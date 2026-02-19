{
  config,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets.k3s_token = { };
  sops.secrets.tailscale_oauth_client_id = { };
  sops.secrets.tailscale_oauth_client_secret = { };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s_token.path;
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

  # Create Tailscale operator OAuth secret from sops-nix
  systemd.services.tailscale-k8s-secret = {
    description = "Create Tailscale operator OAuth Kubernetes secret";
    after = [ "k3s.service" ];
    wants = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
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
}
