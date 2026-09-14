{ ... }:
let
  context = {
    Dockerfile = builtins.readFile ../images/amp/Dockerfile;
    "entrypoint.py" = builtins.readFile ../images/amp/entrypoint.py;
  };
  upstreamVersion = builtins.head (
    builtins.match ".*amp-dockerized:([^@[:space:]]+)@.*" context.Dockerfile
  );
  imageTag = "${upstreamVersion}-${
    builtins.substring 0 8 (builtins.hashString "sha256" (builtins.toJSON context))
  }";
  containerSecurity = {
    allowPrivilegeEscalation = false;
    capabilities.drop = [ "ALL" ];
    seccompProfile.type = "RuntimeDefault";
  };
  # Cloudflare terminates HTTPS. AMP needs its scheme header, WebSocket
  # upgrade headers, and a local trusted reverse proxy for instance UIs.
  proxyConfig = ''
    map $http_upgrade $connection_upgrade {
      default upgrade;
      "" close;
    }
    map $http_x_forwarded_proto $amp_scheme {
      default $scheme;
      https https;
    }
    server {
      listen 8088;
      server_name _;
      client_max_body_size 1024m;
      location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-AMP-Scheme $amp_scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
      }
    }
  '';
  httpCheck = [
    "python3"
    "-c"
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=3)"
  ];
in
{
  applications.amp = {
    namespace = "amp";
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
      configMaps.amp-build-context = {
        metadata.annotations = {
          "argocd.argoproj.io/hook" = "PreSync";
          "argocd.argoproj.io/hook-delete-policy" = "BeforeHookCreation";
          "argocd.argoproj.io/sync-wave" = "-1";
        };
        data = context;
      };
      jobs.build-amp = import ./lib/build-job.nix {
        name = "build-amp";
        pushSecret = "amp-registry-push";
        contextConfigMap = "amp-build-context";
        builds = [
          {
            image = "amp";
            tag = imageTag;
            context = "/workspace";
          }
        ];
      };

      persistentVolumeClaims.amp-data = {
        metadata.labels = {
          "recurring-job.longhorn.io/source" = "enabled";
          "recurring-job-group.longhorn.io/backup" = "enabled";
          "recurring-job-group.longhorn.io/snapshot" = "enabled";
        };
        spec = {
          storageClassName = "longhorn";
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "150Gi";
        };
      };

      configMaps.amp-proxy.data."default.conf" = proxyConfig;

      deployments.amp.spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "amp";
        template = {
          metadata.labels.app = "amp";
          metadata.annotations."checksum/proxy" = builtins.hashString "sha256" proxyConfig;
          spec = {
            # AMP's licence is tied to host identity. The stable node network
            # also lets new game instances bind their assigned ports directly.
            # Host firewall + router forwarding control public game exposure.
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            nodeSelector."kubernetes.io/hostname" = "homelab";
            automountServiceAccountToken = false;
            terminationGracePeriodSeconds = 360;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
              fsGroupChangePolicy = "OnRootMismatch";
            };
            containers = {
              amp = {
                image = "registry.tail84b6c.ts.net/amp:${imageTag}";
                env.TZ.value = "Europe/Oslo";
                securityContext = containerSecurity;
                volumeMounts = {
                  "/home/amp".name = "data";
                  "/run/secrets/amp" = {
                    name = "secrets";
                    readOnly = true;
                  };
                };
                startupProbe = {
                  exec.command = [
                    "test"
                    "-f"
                    "/tmp/amp-ready"
                  ];
                  periodSeconds = 10;
                  failureThreshold = 120;
                };
                readinessProbe = {
                  exec.command = httpCheck;
                  periodSeconds = 15;
                  timeoutSeconds = 5;
                };
                # Allow five minutes for an AMP self-update before recovering
                # an unresponsive controller. Game backup duration is separate.
                livenessProbe = {
                  exec.command = httpCheck;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    cpu = "1";
                    memory = "2Gi";
                  };
                  limits.memory = "10Gi";
                };
              };
              proxy = {
                image = "nginxinc/nginx-unprivileged:1.31.5-alpine@sha256:1905fed0833f52c25fdda4d37e17740615f44e9520b62782a0affcfa8448cb96";
                securityContext = containerSecurity;
                ports.http.containerPort = 8088;
                volumeMounts."/etc/nginx/conf.d" = {
                  name = "proxy-config";
                  readOnly = true;
                };
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits.memory = "128Mi";
                };
              };
            };
            volumes = {
              data.persistentVolumeClaim.claimName = "amp-data";
              secrets.secret = {
                secretName = "amp-secrets";
                defaultMode = 288;
              };
              proxy-config.configMap.name = "amp-proxy";
            };
          };
        };
      };

      # Published route in the existing Cloudflare Tunnel: HTTP amp.amp.svc:80.
      services.amp.spec = {
        selector.app = "amp";
        ports.http = {
          port = 80;
          targetPort = 8088;
        };
      };
      services.amp-tailscale = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "amp";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "amp";
          ports.http = {
            port = 80;
            targetPort = 8088;
          };
        };
      };

      # A separate pod collects through ADS, including instances created later.
      # The common Metrics Reader role grants only Instances.*.Manage; it has
      # no application control, console, file, or role-management permissions.
      deployments.amp-exporter.spec = {
        replicas = 1;
        selector.matchLabels.app = "amp-exporter";
        template = {
          metadata.labels.app = "amp-exporter";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 65532;
              runAsGroup = 65532;
            };
            containers.exporter = {
              # renovate: datasource=docker depName=ghcr.io/soynx/amp-cubecoders-exporter
              image = "ghcr.io/soynx/amp-cubecoders-exporter:0.1.0@sha256:69154b351258608e9830ff5c4e54230ff4cd66ccc77cc2ad8cb36db691ef6ed2";
              securityContext = containerSecurity // {
                readOnlyRootFilesystem = true;
              };
              env = {
                AMP_URL.value = "http://amp.amp.svc:80";
                AMP_USERNAME.value = "amp-metrics";
                AMP_PASSWORD.valueFrom.secretKeyRef = {
                  name = "amp-exporter";
                  key = "AMP_PASSWORD";
                };
              };
              ports.metrics.containerPort = 9822;
              readinessProbe.httpGet = {
                path = "/healthz";
                port = "metrics";
              };
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = "metrics";
                };
                initialDelaySeconds = 10;
                periodSeconds = 30;
              };
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "32Mi";
                };
                limits.memory = "128Mi";
              };
            };
          };
        };
      };

      services.amp-exporter = {
        metadata.labels.app = "amp-exporter";
        spec = {
          selector.app = "amp-exporter";
          ports.metrics = {
            port = 9822;
            targetPort = "metrics";
          };
        };
      };

      networkPolicies.amp-exporter.spec = {
        podSelector.matchLabels.app = "amp-exporter";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "victoria-metrics"; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 9822;
              }
            ];
          }
        ];
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
          {
            # AMP uses hostNetwork; its Service routes to the node's proxy.
            to = [ { ipBlock.cidr = "192.168.1.225/32"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 8088;
              }
            ];
          }
        ];
      };

      configMaps.amp-dashboard = {
        metadata.labels.grafana_dashboard = "1";
        metadata.annotations.grafana_folder = "Games";
        data."amp.json" = builtins.readFile ./dashboards/amp.json;
      };

      deployments.amp-cloudflare-ddns.spec = {
        replicas = 1;
        selector.matchLabels.app = "amp-cloudflare-ddns";
        template = {
          metadata.labels.app = "amp-cloudflare-ddns";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
            };
            containers.ddns = {
              image = "favonia/cloudflare-ddns:1.17.0@sha256:61013368c8f95981c0bb8bf56d962078d8b4e95724a554fa2dabb20d6e478097";
              securityContext = containerSecurity;
              env = {
                CLOUDFLARE_API_TOKEN.valueFrom.secretKeyRef = {
                  name = "amp-ddns";
                  key = "CLOUDFLARE_API_TOKEN";
                };
                IP4_DOMAINS.value = "games.teevik.no";
                IP6_PROVIDER.value = "none";
                PROXIED.value = "false";
              };
              resources = {
                requests = {
                  cpu = "10m";
                  memory = "32Mi";
                };
                limits.memory = "128Mi";
              };
            };
          };
        };
      };
    };

    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: amp-exporter
          namespace: amp
        spec:
          jobLabel: app
          selector:
            matchLabels:
              app: amp-exporter
          endpoints:
            - port: metrics
              path: /metrics
              interval: 30s
              scrapeTimeout: 20s
              metricRelabelConfigs:
                # ADS is the controller, not a game; its app metrics are not
                # meaningful. amp_up still reports controller connectivity.
                - sourceLabels: [module]
                  regex: ADS
                  action: drop
      ''
    ];
  };
}
