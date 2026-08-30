{
  config,
  lib,
  pkgs,
  ...
}:

let
  k8sSecrets = {
    operator-oauth = {
      namespace = "tailscale";
      data = {
        client_id = "tailscale_oauth_client_id";
        client_secret = "tailscale_oauth_client_secret";
      };
    };

    kodekamp-secrets = {
      namespace = "kodekamp";
      data = {
        JWT_SECRET = "kodekamp_jwt_secret";
        EMAIL_USER = "kodekamp_email_user";
        EMAIL_PASS = "kodekamp_email_pass";
      };
    };

    cloudflare-tunnel-token = {
      namespace = "cloudflare-tunnel";
      data = {
        TUNNEL_TOKEN = "cloudflare_tunnel_token";
      };
    };

    # htpasswd for the zot registry's "ci" push user (bcrypt line generated
    # from registry_ci_password).
    zot-htpasswd = {
      namespace = "registry";
      data = {
        htpasswd = "registry_htpasswd";
      };
    };

    # docker config.json with the "ci" credential, mounted by the in-cluster
    # BuildKit PreSync Jobs (kubernetes/lib/build-job.nix) to push images.
    changedetection-registry-push = {
      namespace = "changedetection";
      data = {
        "config.json" = "registry_dockerconfig_json";
      };
    };

    kodekamp-registry-push = {
      namespace = "kodekamp";
      data = {
        "config.json" = "registry_dockerconfig_json";
      };
    };

    crafty-secrets = {
      namespace = "crafty";
      data = {
        CLOUDFLARE_API_TOKEN = "cloudflare_api_token";
      };
    };

    longhorn-backup-secret = {
      namespace = "longhorn-system";
      data = {
        AWS_ACCESS_KEY_ID = "hetzner_s3_access_key";
        AWS_SECRET_ACCESS_KEY = "hetzner_s3_secret_key";
      };
      literals = {
        AWS_ENDPOINTS = "https://hel1.your-objectstorage.com";
      };
    };

    paperless-secrets = {
      namespace = "paperless-ngx";
      data = {
        PAPERLESS_SECRET_KEY = "paperless_secret_key";
        PAPERLESS_DBPASS = "paperless_db_password";
        PAPERLESS_ADMIN_PASSWORD = "paperless_admin_password";
      };
    };

    immich-secrets = {
      namespace = "immich";
      data = {
        DB_PASSWORD = "immich_db_password";
      };
    };

    grafana-admin = {
      namespace = "victoria-metrics";
      data = {
        "admin-password" = "grafana_admin_password";
      };
      literals = {
        "admin-user" = "admin";
      };
    };

    # Argo CD reads admin credentials, session signing key, and webhook secret
    # from this secret. The chart's own secret is disabled (createSecret=false)
    # so none of these values end up in the generated manifests.
    argocd-secret = {
      namespace = "argocd";
      data = {
        "admin.password" = "argocd_admin_password_bcrypt";
        "server.secretkey" = "argocd_server_secretkey";
        "webhook.github.secret" = "argocd_github_webhook_secret";
      };
      literals = {
        "admin.passwordMtime" = "2026-08-25T00:00:00Z";
      };
      labels = {
        "app.kubernetes.io/part-of" = "argocd";
      };
    };

    argocd-repo-creds = {
      namespace = "argocd";
      data = {
        sshPrivateKey = "argocd_ssh_private_key";
      };
      literals = {
        type = "git";
        url = "git@github.com:teevik/homelab.git";
      };
      labels = {
        "argocd.argoproj.io/secret-type" = "repository";
      };
    };
  };

  # Collect all SOPS secret names referenced across all k8sSecrets entries
  allSopsKeys = lib.unique (
    lib.concatMap (secret: lib.attrValues secret.data) (lib.attrValues k8sSecrets)
  );

  # Generate a systemd oneshot service for a single K8s secret
  mkSecretService =
    name: secret:
    let
      fromFileArgs = lib.concatStringsSep " \\\n          " (
        lib.mapAttrsToList (
          key: sopsKey: "--from-file=${key}=${config.sops.secrets.${sopsKey}.path}"
        ) secret.data
      );

      fromLiteralArgs = lib.concatStringsSep " \\\n          " (
        lib.mapAttrsToList (key: value: "--from-literal=${key}=${value}") (secret.literals or { })
      );

      allArgs = lib.concatStringsSep " \\\n          " (
        lib.filter (s: s != "") [
          fromFileArgs
          fromLiteralArgs
        ]
      );
    in
    {
      name = "${name}-k8s-secret";
      value = {
        description = "Create '${name}' Kubernetes secret in ${secret.namespace}";
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
        script =
          let
            labelArgs = lib.concatStringsSep " " (
              lib.mapAttrsToList (key: value: "${key}=${value}") (secret.labels or { })
            );
          in
          ''
            until kubectl get ns >/dev/null 2>&1; do sleep 2; done
            kubectl create namespace ${secret.namespace} --dry-run=client -o yaml | kubectl apply -f -
            # Delete first so labels from previous owners (e.g. Helm/Argo CD
            # tracking labels) don't survive and cause Argo CD to prune the secret.
            kubectl delete secret ${name} --namespace ${secret.namespace} --ignore-not-found
            kubectl create secret generic ${name} \
              --namespace ${secret.namespace} \
              ${allArgs} \
              --dry-run=client -o yaml | kubectl apply -f -
          ''
          + lib.optionalString (secret ? labels) ''
            kubectl label secret ${name} \
              --namespace ${secret.namespace} \
              ${labelArgs} \
              --overwrite
          '';
      };
    };
in

{
  config = {
    # Register all SOPS secrets: k3s token (used directly by the service) + all k8sSecrets references
    sops.secrets = {
      k3s_token = { };
    }
    // lib.listToAttrs (map (key: lib.nameValuePair key { }) allSopsKeys);

    # Generate systemd oneshot services for each K8s secret
    systemd.services = lib.listToAttrs (lib.mapAttrsToList mkSecretService k8sSecrets);

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
        # Pin this dual-NIC node to its embedded-etcd peer address.
        "--node-ip=192.168.1.225"
        "--advertise-address=192.168.1.225"
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

    networking.firewall.allowedTCPPorts = [
      30565
    ];
  };
}
