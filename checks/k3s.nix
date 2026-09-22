{ pkgs, ... }:
let
  webRoot = pkgs.runCommand "homelab-probe-content" { } ''
    mkdir -p "$out/www"
    echo homelab-service-ok > "$out/www/index.html"
  '';
  probeImage = pkgs.dockerTools.buildLayeredImage {
    name = "test.local/homelab-probe";
    tag = "local";
    contents = [
      pkgs.busybox
      webRoot
    ];
    config.Cmd = [
      "/bin/sleep"
      "infinity"
    ];
  };
  workload = pkgs.writeText "homelab-probe.yaml" ''
    apiVersion: v1
    kind: Pod
    metadata:
      name: probe-server
      labels:
        app: probe-server
    spec:
      containers:
        - name: server
          image: test.local/homelab-probe:local
          imagePullPolicy: Never
          command: ["/bin/httpd", "-f", "-p", "8080", "-h", "/www"]
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: probe
    spec:
      selector:
        app: probe-server
      ports:
        - port: 8080
          targetPort: 8080
    ---
    apiVersion: v1
    kind: Pod
    metadata:
      name: probe-client
    spec:
      containers:
        - name: client
          image: test.local/homelab-probe:local
          imagePullPolicy: Never
  '';
in
pkgs.testers.runNixOSTest {
  name = "homelab-k3s";

  nodes.machine = { config, lib, ... }: {
    imports = [ ../modules/nixos/kubernetes.nix ];

    # Substitute only the SOPS boundary. The real module still declares and
    # provisions every Kubernetes Secret, with disposable plaintext fixtures.
    options.sops.secrets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options.path = lib.mkOption {
              type = lib.types.str;
              default = "/etc/homelab-test/${name}";
            };
          }
        )
      );
    };

    config = {
      environment.etc = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "homelab-test/${name}" {
          text = "fixture-${name}";
          mode = "0600";
        }
      ) config.sops.secrets;
      environment.systemPackages = [ pkgs.kubectl ];
      environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

      # Give the isolated VM the address expected by the production module.
      networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
        {
          address = "192.168.1.225";
          prefixLength = 24;
        }
      ];
      services.k3s.images = [
        config.services.k3s.package.airgap-images
        probeImage
      ];
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        diskSize = 8192;
      };
    };
  };

  testScript = ''
    import base64
    import json

    machine.start(allow_reboot=True)
    machine.wait_for_unit("k3s.service")
    machine.wait_until_succeeds("kubectl get nodes | grep ' Ready '", timeout=180)

    def verify_secrets():
        # Several of these units create the same namespace concurrently.
        for unit in ["amp-secrets", "amp-registry-push", "amp-ddns", "amp-exporter",
                     "argocd-secret", "argocd-repo-creds", "paperless-secrets"]:
            machine.wait_for_unit(unit + "-k8s-secret.service")
        secret = json.loads(machine.succeed("kubectl -n paperless-ngx get secret paperless-secrets -o json"))
        assert base64.b64decode(secret["data"]["PAPERLESS_DBPASS"]).decode() == "fixture-paperless_db_password"
        secret = json.loads(machine.succeed("kubectl -n argocd get secret argocd-repo-creds -o json"))
        assert secret["metadata"]["labels"]["argocd.argoproj.io/secret-type"] == "repository"

    def verify_network():
        machine.succeed("kubectl wait --for=condition=Ready pod/probe-client pod/probe-server --timeout=180s")
        machine.wait_until_succeeds("kubectl exec probe-client -- nslookup probe.default.svc.cluster.local", timeout=120)
        machine.wait_until_succeeds("kubectl exec probe-client -- wget -qO- http://probe.default.svc.cluster.local:8080 | grep -x homelab-service-ok", timeout=120)

    with subtest("secrets, DNS, and Service traffic after boot"):
        verify_secrets()
        machine.wait_until_succeeds("kubectl get serviceaccount default", timeout=120)
        machine.succeed("kubectl create -f ${workload}")
        verify_network()

    with subtest("k3s restart recreates missing secrets and restores connectivity"):
        machine.succeed("kubectl -n paperless-ngx delete secret paperless-secrets")
        machine.succeed("systemctl restart k3s.service")
        verify_secrets()
        verify_network()

    with subtest("reboot retains cluster state and restores services"):
        machine.reboot()
        machine.wait_for_unit("k3s.service")
        verify_secrets()
        verify_network()
  '';
}
