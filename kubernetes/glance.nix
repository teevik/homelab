{ ... }:
let
  glanceConfig = builtins.toJSON {
    pages = [
      # Home tab - News and content
      {
        name = "Home";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "custom-api";
                title = "Homelab Status";
                cache = "2m";
                url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(kube_node_status_condition{condition=%22Ready%22,status=%22true%22})";
                subrequests = {
                  nodesTotal = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(kube_node_info)";
                  };
                  podsRunning = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(kube_pod_status_phase{phase=%22Running%22})";
                  };
                  alertsFiring = {
                    url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093/api/v2/alerts?active=true&silenced=false&inhibited=false";
                    skip-json-validation = true;
                  };
                  storageUsage = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=avg(node_filesystem_size_bytes%20/%20node_filesystem_size_bytes%20*%20100)";
                  };
                };
                template = ''
                  <div class="flex flex-col gap-8">
                    {{ $nodesRunning := .JSON.String "data.result.0.value.1" }}
                    {{ $nodesTotalReq := .Subrequest "nodesTotal" }}
                    {{ $nodesTotal := $nodesTotalReq.JSON.String "data.result.0.value.1" }}
                    {{ $podsRunningReq := .Subrequest "podsRunning" }}
                    {{ $podsRunning := $podsRunningReq.JSON.String "data.result.0.value.1" }}
                    {{ $alertsReq := .Subrequest "alertsFiring" }}
                    {{ $alerts := len ($alertsReq.JSON.Array ".") }}
                    {{ $storageReq := .Subrequest "storageUsage" }}
                    {{ $storage := $storageReq.JSON.String "data.result.0.value.1" }}
                    
                    <div class="flex justify-between items-center">
                      <span class="size-h6 color-paragraph">Nodes</span>
                      <span class="size-h4 color-highlight">{{ $nodesRunning }}</span>
                    </div>
                    
                    <div class="flex justify-between items-center">
                      <span class="size-h6 color-paragraph">Pods Running</span>
                      <span class="size-h4 color-highlight">{{ $podsRunning }}</span>
                    </div>
                    
                    <div class="flex justify-between items-center">
                      <span class="size-h6 color-paragraph">Alerts</span>
                      <span class="size-h4 {{ if eq $alerts 0 }}color-positive{{ else }}color-negative{{ end }}">
                        {{ if eq $alerts 0 }}None{{ else }}{{ $alerts }} firing{{ end }}
                      </span>
                    </div>
                    
                    <div class="flex justify-between items-center">
                      <span class="size-h6 color-paragraph">Storage Usage</span>
                      <span class="size-h4 color-highlight">
                        {{ if $storage }}{{ $storage }}%{{ else }}--{{ end }}
                      </span>
                    </div>
                    
                    <div class="flex justify-center mt-2">
                      <a href="/homelab" class="color-highlight size-h6">View Details →</a>
                    </div>
                  </div>
                '';
              }

              {
                type = "calendar";
                first-day-of-week = "monday";
              }

              {
                type = "weather";
                location = "Oslo, Norway";
                units = "metric";
                hour-format = "24h";
              }

              {
                type = "rss";
                title = "News & Blogs";
                limit = 10;
                collapse-after = 3;
                cache = "12h";
                feeds = [
                  {
                    url = "https://selfh.st/rss/";
                    title = "selfh.st";
                    limit = 4;
                  }
                  { url = "https://blog.syndtr.com/feed.xml"; }
                  { url = "https://samwho.dev/rss.xml"; }
                  { url = "https://ciechanow.ski/atom.xml"; }
                  {
                    url = "https://www.joshwcomeau.com/rss.xml";
                    title = "Josh Comeau";
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              {
                type = "group";
                widgets = [
                  { type = "hacker-news"; }
                  { type = "lobsters"; }
                ];
              }

              {
                type = "videos";
                channels = [
                  "UCR-DXc1voovS8nhAvccRZhg" # Jeff Geerling
                  "UCsBjURrPoezykLs9EqgamOA" # Fireship
                  "UCXuqSBlHAE6Xw-yeJA0Tunw" # Linus Tech Tips
                  "UCHnyfMqiRRG1u-2MsSQLbXA" # Veritasium
                ];
              }

              {
                type = "group";
                widgets = [
                  {
                    type = "reddit";
                    subreddit = "selfhosted";
                    show-thumbnails = true;
                  }
                  {
                    type = "reddit";
                    subreddit = "homelab";
                    show-thumbnails = true;
                  }
                ];
              }
            ];
          }

          {
            size = "small";
            widgets = [
              {
                type = "bookmarks";
                groups = [
                  {
                    title = "Homelab";
                    color = "10 70 50";
                    links = [
                      {
                        title = "Longhorn";
                        url = "https://longhorn.local";
                      }
                      {
                        title = "ArgoCD";
                        url = "https://argocd.local";
                      }
                    ];
                  }
                  {
                    title = "General";
                    color = "200 50 50";
                    links = [
                      {
                        title = "GitHub";
                        url = "https://github.com";
                      }
                      {
                        title = "Wikipedia";
                        url = "https://en.wikipedia.org";
                      }
                    ];
                  }
                ];
              }

              {
                type = "markets";
                markets = [
                  {
                    symbol = "SPY";
                    name = "S&P 500";
                  }
                  {
                    symbol = "BTC-USD";
                    name = "Bitcoin";
                  }
                  {
                    symbol = "ETH-USD";
                    name = "Ethereum";
                  }
                  {
                    symbol = "NVDA";
                    name = "NVIDIA";
                  }
                ];
              }

              {
                type = "releases";
                cache = "1d";
                repositories = [
                  "glanceapp/glance"
                  "longhorn/longhorn"
                  "k3s-io/k3s"
                  "NixOS/nixpkgs"
                ];
              }
            ];
          }
        ];
      }

      # Homelab tab - Service health front and center + node stats
      {
        name = "Homelab";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "monitor";
                title = "Service Health";
                cache = "1m";
                sites = [
                  {
                    title = "Glance";
                    url = "http://glance.glance.svc";
                    icon = "si:glance";
                  }
                  {
                    title = "Grafana";
                    url = "http://victoria-metrics-k8s-stack-grafana.monitoring.svc:80";
                    icon = "si:grafana";
                  }
                  {
                    title = "VictoriaMetrics";
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428";
                    icon = "si:victoriametrics";
                  }
                  {
                    title = "Alertmanager";
                    url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093";
                    icon = "si:prometheus";
                  }
                  {
                    title = "VMAgent";
                    url = "http://vmagent-victoria-metrics-k8s-stack.monitoring.svc:8429";
                    icon = "si:victoriametrics";
                  }
                  {
                    title = "Longhorn UI";
                    url = "http://longhorn-frontend.longhorn-system.svc:80";
                    icon = "si:longhorn";
                  }
                  {
                    title = "Nginx";
                    url = "http://nginx.nginx.svc:80";
                    icon = "si:nginx";
                  }
                ];
              }

              {
                type = "custom-api";
                title = "Active Alerts";
                cache = "1m";
                url = "http://vmalertmanager-victoria-metrics-k8s-stack.monitoring.svc:9093/api/v2/alerts?active=true&silenced=false&inhibited=false";
                template = ''
                  {{ $alerts := .JSON.Array "." }}
                  {{ if eq ($alerts | len) 0 }}
                    <div class="flex justify-center">
                      <span class="color-positive size-h3">No active alerts</span>
                    </div>
                  {{ else }}
                    <ul class="list list-gap-8">
                    {{ range $alerts }}
                      <li class="flex flex-col gap-4">
                        <div class="flex items-center gap-8">
                          <span class="color-negative size-h4">{{ .String "labels.alertname" }}</span>
                          <span class="size-h5 color-paragraph">{{ .String "labels.severity" }}</span>
                        </div>
                        <div class="size-h6 color-paragraph">{{ .String "annotations.summary" }}</div>
                      </li>
                    {{ end }}
                    </ul>
                  {{ end }}
                '';
              }

              {
                type = "bookmarks";
                title = "Quick Links";
                groups = [
                  {
                    title = "Observability";
                    color = "30 80 50";
                    links = [
                      {
                        title = "Grafana";
                        url = "http://grafana";
                        icon = "si:grafana";
                      }
                    ];
                  }
                  {
                    title = "Infrastructure";
                    color = "10 70 50";
                    links = [
                      {
                        title = "Longhorn";
                        url = "https://longhorn.local";
                        icon = "si:longhorn";
                      }
                      {
                        title = "ArgoCD";
                        url = "https://argocd.local";
                        icon = "si:argo";
                      }
                    ];
                  }
                ];
              }
            ];
          }

          {
            size = "full";
            widgets = [
              # All 3 nodes side by side
              {
                type = "split-column";
                widgets = [
                  {
                    type = "server-stats";
                    title = "homelab-1";
                    servers = [
                      {
                        type = "remote";
                        name = "homelab-1";
                        url = "http://homelab-1:27973";
                      }
                    ];
                  }
                  {
                    type = "server-stats";
                    title = "homelab-2";
                    servers = [
                      {
                        type = "remote";
                        name = "homelab-2";
                        url = "http://homelab-2:27973";
                      }
                    ];
                  }
                  {
                    type = "server-stats";
                    title = "homelab-3";
                    servers = [
                      {
                        type = "remote";
                        name = "homelab-3";
                        url = "http://homelab-3:27973";
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
      }
    ];
  };

  configHash = builtins.hashString "sha256" glanceConfig;
in
{
  applications.glance = {
    namespace = "glance";
    createNamespace = true;

    resources = {
      configMaps.glance-config.data."glance.yml" = glanceConfig;

      deployments.glance.spec = {
        replicas = 1;
        selector.matchLabels.app = "glance";
        template = {
          metadata = {
            labels.app = "glance";
            annotations."checksum/config" = configHash;
          };
          spec = {
            containers.glance = {
              image = "glanceapp/glance:latest";
              ports.http.containerPort = 8080;
              volumeMounts."/app/config/glance.yml" = {
                name = "config";
                subPath = "glance.yml";
              };
            };
            volumes.config.configMap.name = "glance-config";
          };
        };
      };

      services.glance = {
        metadata.annotations = {
          "tailscale.com/proxy-group" = "ingress";
          "tailscale.com/hostname" = "glance";
        };
        spec = {
          type = "LoadBalancer";
          loadBalancerClass = "tailscale";
          selector.app = "glance";
          ports.http = {
            port = 80;
            targetPort = 8080;
          };
        };
      };
    };
  };
}
