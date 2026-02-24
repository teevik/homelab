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
    sops.secrets.hetzner_s3_access_key = { };
    sops.secrets.hetzner_s3_secret_key = { };
    sops.secrets.kodekamp_jwt_secret = { };
    sops.secrets.kodekamp_email_user = { };
    sops.secrets.kodekamp_email_pass = { };
    sops.secrets.cloudflare_tunnel_token = { };

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

    # Create KodeKamp application secrets from sops-nix
    systemd.services.kodekamp-k8s-secret = {
      description = "Create KodeKamp Kubernetes secrets";
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
        kubectl create namespace kodekamp --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic kodekamp-secrets \
          --namespace kodekamp \
          --from-file=JWT_SECRET=${config.sops.secrets.kodekamp_jwt_secret.path} \
          --from-file=EMAIL_USER=${config.sops.secrets.kodekamp_email_user.path} \
          --from-file=EMAIL_PASS=${config.sops.secrets.kodekamp_email_pass.path} \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };

    # Create Cloudflare Tunnel token secret from sops-nix
    systemd.services.cloudflare-tunnel-k8s-secret = {
      description = "Create Cloudflare Tunnel token Kubernetes secret";
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
        kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic cloudflare-tunnel-token \
          --namespace cloudflare-tunnel \
          --from-file=TUNNEL_TOKEN=${config.sops.secrets.cloudflare_tunnel_token.path} \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };

    # Create Longhorn S3 backup credentials secret from sops-nix
    systemd.services.longhorn-backup-secret = {
      description = "Create Longhorn S3 backup credentials Kubernetes secret";
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
        until kubectl get ns longhorn-system >/dev/null 2>&1; do sleep 2; done
        kubectl create secret generic longhorn-backup-secret \
          --namespace longhorn-system \
          --from-file=AWS_ACCESS_KEY_ID=${config.sops.secrets.hetzner_s3_access_key.path} \
          --from-file=AWS_SECRET_ACCESS_KEY=${config.sops.secrets.hetzner_s3_secret_key.path} \
          --from-literal=AWS_ENDPOINTS=https://hel1.your-objectstorage.com \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };
  };
}
