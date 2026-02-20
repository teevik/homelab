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
    sops.secrets.cloudflare_api_token = { };

    services.k3s = {
      enable = true;
      role = "server";
      clusterInit = cfg.clusterInit;
      tokenFile = config.sops.secrets.k3s_token.path;
      serverAddr = lib.mkIf (cfg.serverAddr != null) cfg.serverAddr;
      extraFlags = toString [
        "--write-kubeconfig-mode=0644"
        "--disable=traefik" # Manage ingress via nixidy instead
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

    # Create Cloudflare API token secret for cert-manager (initial server only)
    systemd.services.cloudflare-k8s-secret = lib.mkIf cfg.clusterInit {
      description = "Create Cloudflare API token Kubernetes secret for cert-manager";
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
        kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

        # Extract bare token (sops secret is stored as CF_DNS_API_TOKEN=<token>)
        TOKEN=$(${pkgs.gnused}/bin/sed 's/^.*=//' ${config.sops.secrets.cloudflare_api_token.path})
        kubectl create secret generic cloudflare-api-token \
          --namespace cert-manager \
          --from-literal=api-token="$TOKEN" \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };
  };
}
