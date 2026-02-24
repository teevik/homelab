{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = {
    sops.secrets.k3s_token = { };
    sops.secrets.tailscale_oauth_client_id = { };
    sops.secrets.tailscale_oauth_client_secret = { };

    # Longhorn requires binaries at standard FHS paths (iscsiadm, mount, etc.)
    systemd.tmpfiles.rules = [
      "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
    ];

    # Longhorn v1 engine requires open-iscsi on the host
    services.openiscsi = {
      enable = true;
      name = "iqn.2016-04.io.longhorn:homelab";
    };

    # nfs-utils needed for Longhorn NFS backup targets and RWX volumes
    environment.systemPackages = with pkgs; [
      nfs-utils
    ];

    services.k3s = {
      enable = true;
      role = "server";
      clusterInit = true;
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = toString [
        "--write-kubeconfig-mode=0644"
        "--disable=traefik" # Use Tailscale ingress instead
        "--disable=servicelb" # Not needed with Tailscale
        "--disable=local-storage" # Use Longhorn instead of local-path provisioner
      ];
    };

    # Allow traffic on CNI and flannel interfaces
    # Fixes DNS and service IP issues on NixOS with k3s
    # See: https://github.com/NixOS/nixpkgs/issues/98766
    networking.firewall.trustedInterfaces = [
      "cni+"
      "flannel.+"
    ];

    # Create Tailscale operator OAuth secret from sops-nix
    systemd.services.tailscale-k8s-secret = {
      description = "Create Tailscale operator OAuth Kubernetes secret";
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      partOf = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
      };
      path = [ pkgs.kubectl ];
      script = ''
        until kubectl get ns >/dev/null 2>&1; do sleep 2; done
        kubectl create namespace tailscale --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic operator-oauth \
          --namespace tailscale \
          --from-file=client_id=${config.sops.secrets.tailscale_oauth_client_id.path} \
          --from-file=client_secret=${config.sops.secrets.tailscale_oauth_client_secret.path} \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };

  };
}
