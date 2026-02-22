{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.kubernetes;
in
{
  options.homelab.kubernetes = {
    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Initialize the HA cluster with embedded etcd. Only set on the first server.";
    };

    serverAddr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Address of an existing server to join (e.g. https://homelab-1:6443). Leave null for the initial server.";
    };
  };

  config = {
    sops.secrets.k3s_token = { };
    sops.secrets.tailscale_oauth_client_id = { };
    sops.secrets.tailscale_oauth_client_secret = { };

    # Ensure k3s starts after Tailscale is connected, so that MagicDNS
    # names (e.g. homelab-1) are resolvable when joining the cluster.
    # Without this, flannel may fail to initialize on joining nodes.
    systemd.services.k3s = {
      after = [ "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled-autoconnect.service" ];
    };

    services.k3s = {
      enable = true;
      role = "server";
      clusterInit = cfg.clusterInit;
      tokenFile = config.sops.secrets.k3s_token.path;
      serverAddr = lib.mkIf (cfg.serverAddr != null) cfg.serverAddr;
      extraFlags = toString [
        "--write-kubeconfig-mode=0644"
        "--disable=traefik" # Use Tailscale ingress instead
        "--disable=local-storage" # Use Longhorn instead
        "--disable=servicelb" # Use MetalLB instead
      ];
    };

    # Longhorn requires binaries at standard FHS paths
    systemd.tmpfiles.rules = [
      "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
    ];

    # Longhorn prerequisites
    services.openiscsi = {
      enable = true;
      name = "${config.networking.hostName}-initiatorhost";
    };

    environment.systemPackages = with pkgs; [
      nfs-utils
    ];

    # Create Tailscale operator OAuth secret from sops-nix (initial server only)
    systemd.services.tailscale-k8s-secret = lib.mkIf cfg.clusterInit {
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
