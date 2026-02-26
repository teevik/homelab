{ ... }:
{
  applications.kodekamp = {
    namespace = "kodekamp";
    createNamespace = true;

    resources = {
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
            containers.mongodb = {
              image = "mongo:4.4.6";
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

      # Code runner deployment (3 replicas for parallel code execution)
      deployments.kodekamp-code-runner.spec = {
        replicas = 3;
        selector.matchLabels.app = "kodekamp-code-runner";
        template = {
          metadata.labels.app = "kodekamp-code-runner";
          spec = {
            containers.code-runner = {
              image = "ghcr.io/teevik/kodekamp-code-runner:latest";
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
            containers.web = {
              image = "ghcr.io/teevik/kodekamp-web:latest";
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
