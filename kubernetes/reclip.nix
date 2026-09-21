{ reclipSrc, ... }:
let
  rev = reclipSrc.rev;
  imageTag = builtins.substring 0 12 rev;
in
{
  applications.reclip = {
    namespace = "reclip";
    createNamespace = true;

    syncPolicy.retry = {
      limit = 3;
      backoff = {
        duration = "30s";
        factor = 2;
        maxDuration = "3m";
      };
    };

    resources = {
      # The upstream Dockerfile runs Gunicorn with one worker: download jobs
      # live in process memory, so multiple workers/replicas cannot share them.
      jobs.build-reclip = import ./lib/build-job.nix {
        name = "build-reclip";
        pushSecret = "reclip-registry-push";
        builds = [
          {
            image = "reclip";
            tag = imageTag;
            context = "https://github.com/averygan/reclip.git#${rev}";
          }
        ];
      };

      deployments.reclip.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "reclip";
        template = {
          metadata.labels.app = "reclip";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers.reclip = {
              # Built from the flake.lock source; Renovate updates the input.
              image = "registry.tail84b6c.ts.net/reclip:${imageTag}";
              ports.http.containerPort = 8899;
              # Keep upstream's startup yt-dlp update enabled so extractor
              # fixes do not have to wait for a new Reclip commit.
              volumeMounts."/app/downloads".name = "downloads";
              startupProbe = {
                httpGet = {
                  path = "/";
                  port = "http";
                };
                periodSeconds = 10;
                failureThreshold = 30;
                timeoutSeconds = 5;
              };
              readinessProbe = {
                httpGet = {
                  path = "/";
                  port = "http";
                };
                timeoutSeconds = 5;
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
                seccompProfile.type = "RuntimeDefault";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                  ephemeral-storage = "1Gi";
                };
                limits = {
                  memory = "2Gi";
                  ephemeral-storage = "12Gi";
                };
              };
            };
            # Files are staging for browser downloads; job history does not
            # survive a restart. Replacing the pod clears the staged files.
            volumes.downloads.emptyDir.sizeLimit = "10Gi";
          };
        };
      };

      # Reclip has no authentication; expose it only on the tailnet.
      services.reclip-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "reclip";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "reclip";
          ports.http = {
            port = 80;
            targetPort = 8899;
          };
        };
      };
    };
  };
}
