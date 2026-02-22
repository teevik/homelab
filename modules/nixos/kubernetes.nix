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
      description = "Address of an existing server to join (e.g. https://192.168.1.114:6443). Leave null for the initial server.";
    };
  };

  config = {
    sops.secrets.k3s_token = { };
    sops.secrets.tailscale_oauth_client_id = { };
    sops.secrets.tailscale_oauth_client_secret = { };

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

    # Allow traffic on CNI and flannel interfaces for cross-node networking
    # Fixes DNS and service IP issues on NixOS with k3s
    # See: https://github.com/NixOS/nixpkgs/issues/98766
    networking.firewall.trustedInterfaces = [
      "cni+"
      "flannel.+"
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
