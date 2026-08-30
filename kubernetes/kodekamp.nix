{ kodekampSrc, ... }:
let
  # KodeKamp's source is a (non-flake) flake input pinned in flake.lock;
  # Renovate bumps it. Both images are built from that exact commit by the
  # PreSync Job below and tagged with it.
  rev = kodekampSrc.rev;
  imageTag = builtins.substring 0 12 rev;
  gitContext = "https://github.com/teevik/KodeKamp.git#${rev}";
  registry = "registry.tail84b6c.ts.net";
in
{
  applications.kodekamp = {
    namespace = "kodekamp";
    createNamespace = true;

    # The PreSync build Job fails if the registry is not up yet (fresh cluster,
    # zot restarting); let Argo CD retry the sync instead of stalling on it.
    # Kept short: while an operation is retrying, Argo CD does not start a
    # sync to a newer commit, so a long retry loop would delay a fix.
    syncPolicy.retry = {
      limit = 3;
      backoff = {
        duration = "30s";
        factor = 2;
        maxDuration = "3m";
      };
    };

    resources = {
      # Builds kodekamp-web (repo root) and kodekamp-code-runner (code-runner/)
      # from the pinned KodeKamp commit before Argo CD rolls the Deployments.
      # The Rust build is the heavy one, hence the memory limit.
      jobs.build-kodekamp = import ./lib/build-job.nix {
        name = "build-kodekamp";
        pushSecret = "kodekamp-registry-push";
        memoryLimit = "6Gi";
        builds = [
          {
            image = "kodekamp-web";
            tag = imageTag;
            context = gitContext;
          }
          {
            image = "kodekamp-code-runner";
            tag = imageTag;
            context = "${gitContext}:code-runner";
          }
        ];
      };

      # MongoDB persistent storage
      persistentVolumeClaims.kodekamp-db-data.spec = {
        storageClassName = "longhorn";
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
      };

      # MongoDB deployment
      deployments.kodekamp-db.spec = {
        replicas = 1;
        strategy.type = "Recreate"; # Required for RWO PVC - can't have two pods mounting it
        selector.matchLabels.app = "kodekamp-db";
        template = {
          metadata.labels.app = "kodekamp-db";
          spec = {
            automountServiceAccountToken = false;
            containers.mongodb = {
              # Last 4.4.x patch release; same feature-compatibility version as
              # 4.4.6 so it's a drop-in upgrade. 5.0+ needs a stepped migration.
              image = "mongo:4.4.29@sha256:52c42cbab240b3c5b1748582cc13ef46d521ddacae002bbbda645cebed270ec0";
              ports.mongodb.containerPort = 27017;
              volumeMounts."/data/db" = {
                name = "data";
              };
            };
            volumes.data.persistentVolumeClaim.claimName = "kodekamp-db-data";
          };
        };
      };

      # MongoDB service
      services.kodekamp-db.spec = {
        selector.app = "kodekamp-db";
        ports.mongodb = {
          port = 27017;
          targetPort = 27017;
        };
      };

      # Code runner deployment (3 replicas for parallel code execution).
      # Executes untrusted user code, so it gets the tightest settings in the
      # cluster: no privilege escalation, no capabilities, no service account
      # token, hard resource limits, and (below) a NetworkPolicy that only
      # allows traffic from the web app and DNS egress.
      deployments.kodekamp-code-runner.spec = {
        replicas = 3;
        selector.matchLabels.app = "kodekamp-code-runner";
        template = {
          metadata.labels.app = "kodekamp-code-runner";
          spec = {
            automountServiceAccountToken = false;
            containers.code-runner = {
              # Built from teevik/KodeKamp @ flake.lock by build-kodekamp below.
              image = "${registry}/kodekamp-code-runner:${imageTag}";
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "1";
                  memory = "1Gi";
                };
              };
            };
          };
        };
      };

      # Code runner service
      services.kodekamp-code-runner.spec = {
        selector.app = "kodekamp-code-runner";
        ports.http = {
          port = 3000;
          targetPort = 3000;
        };
      };

      # Web application deployment
      deployments.kodekamp-web.spec = {
        replicas = 1;
        selector.matchLabels.app = "kodekamp-web";
        template = {
          metadata.labels.app = "kodekamp-web";
          spec = {
            automountServiceAccountToken = false;
            containers.web = {
              # Built from teevik/KodeKamp @ flake.lock by build-kodekamp below.
              image = "${registry}/kodekamp-web:${imageTag}";
              ports.http.containerPort = 3000;
              env = {
                NODE_ENV.value = "production";
                PORT.value = "3000";
                SERVER_URL.value = "https://kodekamp.teevik.no";
                DATABASE_URL.value = "mongodb://kodekamp-db:27017/kode-kamp";
                CODE_RUNNER_URL.value = "http://kodekamp-code-runner:3000";
                JWT_SECRET.valueFrom.secretKeyRef = {
                  name = "kodekamp-secrets";
                  key = "JWT_SECRET";
                };
                EMAIL_USER.valueFrom.secretKeyRef = {
                  name = "kodekamp-secrets";
                  key = "EMAIL_USER";
                };
                EMAIL_PASS.valueFrom.secretKeyRef = {
                  name = "kodekamp-secrets";
                  key = "EMAIL_PASS";
                };
              };
            };
          };
        };
      };

      # Web service (internal ClusterIP, accessed by cloudflare tunnel)
      services.kodekamp-web.spec = {
        selector.app = "kodekamp-web";
        ports.http = {
          port = 3000;
          targetPort = 3000;
        };
      };

      # --- NetworkPolicies ---
      # KodeKamp runs untrusted user code and fronts the public internet via
      # Cloudflare, so the namespace is default-deny with explicit allows.
      # Enforced by k3s's embedded network policy controller.

      networkPolicies.default-deny.spec = {
        podSelector = { };
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };

      # The build Job clones KodeKamp from GitHub, pulls base images and
      # pushes to the registry, so it gets unrestricted egress; it serves
      # nothing, so the default deny keeps all ingress closed.
      networkPolicies.build = {
        metadata.annotations = {
          # Applied as a PreSync hook one wave before the build Job: regular
          # resources are only synced after hooks, so the Job could never see it.
          "argocd.argoproj.io/hook" = "PreSync";
          "argocd.argoproj.io/hook-delete-policy" = "BeforeHookCreation";
          "argocd.argoproj.io/sync-wave" = "-1";
        };
        spec = {
          podSelector.matchLabels.app = "build-kodekamp";
          policyTypes = [ "Egress" ];
          egress = [ { } ];
        };
      };

      networkPolicies.web.spec = {
        podSelector.matchLabels.app = "kodekamp-web";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        # Reachable only from the Cloudflare tunnel, Tailscale ingress proxies,
        # and Glance (dashboard health check)
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "cloudflare-tunnel"; }
              { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "tailscale"; }
              { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "glance"; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
        ];
        egress = [
          # MongoDB
          {
            to = [ { podSelector.matchLabels.app = "kodekamp-db"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 27017;
              }
            ];
          }
          # Code runner
          {
            to = [ { podSelector.matchLabels.app = "kodekamp-code-runner"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
          # Cluster DNS
          {
            to = [
              {
                namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
          # Internet egress for outgoing email; never cluster or LAN ranges
          {
            to = [
              {
                ipBlock = {
                  cidr = "0.0.0.0/0";
                  except = [
                    "10.0.0.0/8"
                    "172.16.0.0/12"
                    "192.168.0.0/16"
                  ];
                };
              }
            ];
          }
        ];
      };

      networkPolicies.code-runner.spec = {
        podSelector.matchLabels.app = "kodekamp-code-runner";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        # Only the web app may submit code
        ingress = [
          {
            from = [ { podSelector.matchLabels.app = "kodekamp-web"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
        ];
        # Untrusted code gets no network beyond cluster DNS
        egress = [
          {
            to = [
              {
                namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };

      networkPolicies.db.spec = {
        podSelector.matchLabels.app = "kodekamp-db";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        # Only the web app may talk to MongoDB; the database dials nothing
        ingress = [
          {
            from = [ { podSelector.matchLabels.app = "kodekamp-web"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 27017;
              }
            ];
          }
        ];
      };

      # Tailscale service for internal access via MagicDNS
      services.kodekamp-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "kodekamp";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "kodekamp-web";
          ports.http = {
            port = 80;
            targetPort = 3000;
          };
        };
      };
    };
  };
}
