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
                };
                template = ''
                  {{ $nodesRunning := .JSON.String "data.result.0.value.1" }}
                  {{ $nodesTotalReq := .Subrequest "nodesTotal" }}
                  {{ $nodesTotal := $nodesTotalReq.JSON.String "data.result.0.value.1" }}
                  {{ $podsRunningReq := .Subrequest "podsRunning" }}
                  {{ $podsRunning := $podsRunningReq.JSON.String "data.result.0.value.1" }}
                  {{ $alertsReq := .Subrequest "alertsFiring" }}
                  {{ $alerts := len ($alertsReq.JSON.Array ".") }}

                  <a href="/homelab" class="block text-decoration-none">
                    <div class="grid grid-cols-3 gap-15 margin-top-10 margin-bottom-10">
                      <!-- Nodes Card -->
                      <div class="flex flex-col items-center gap-10 padding-10">
                        <span class="size-h2">🖥️</span>
                        <span class="size-h1 color-highlight">{{ $nodesRunning }}</span>
                        <span class="size-h6 color-paragraph">Nodes Ready</span>
                      </div>

                      <!-- Pods Card -->
                      <div class="flex flex-col items-center gap-10 padding-10">
                        <span class="size-h2">📦</span>
                        <span class="size-h1 color-highlight">{{ $podsRunning }}</span>
                        <span class="size-h6 color-paragraph">Pods Running</span>
                      </div>

                      <!-- Alerts Card -->
                      <div class="flex flex-col items-center gap-10 padding-10">
                        <span class="size-h2">{{ if eq $alerts 0 }}✅{{ else }}⚠️{{ end }}</span>
                        <span class="size-h1 {{ if eq $alerts 0 }}color-positive{{ else }}color-negative{{ end }}">
                          {{ if eq $alerts 0 }}OK{{ else }}{{ $alerts }}{{ end }}
                        </span>
                        <span class="size-h6 color-paragraph">{{ if eq $alerts 0 }}No Alerts{{ else }}Alerts{{ end }}</span>
                      </div>
                    </div>

                    <div class="flex justify-center margin-top-10">
                      <span class="color-highlight size-h5">View Details →</span>
                    </div>
                  </a>
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
                        url = "http://longhorn";
                      }
                      {
                        title = "ArgoCD";
                        url = "http://argocd";
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
                    icon = "auto-invert https://raw.githubusercontent.com/cncf/artwork/main/projects/longhorn/icon/black/longhorn-icon-black.svg";
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
                type = "custom-api";
                title = "Longhorn Storage";
                cache = "2m";
                url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(longhorn_volume_capacity_bytes)";
                subrequests = {
                  attachedVolumes = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(longhorn_volume_state%7Bstate%3D%22attached%22%7D)";
                  };
                  detachedVolumes = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(longhorn_volume_state%7Bstate%3D%22detached%22%7D)";
                  };
                  totalCapacity = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=sum(longhorn_volume_capacity_bytes)";
                  };
                  usedCapacity = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=sum(longhorn_volume_actual_size_bytes)";
                  };
                  healthyNodes = {
                    url = "http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/query?query=count(longhorn_node_status%7Bcondition%3D%22ready%22%7D)";
                  };
                };
                template = ''
                  <div style="display: flex; flex-direction: column; gap: 1rem;">
                    <div>
                      {{ $totalVolumes := .JSON.String "data.result.0.value.1" }}
                      {{ $attachedReq := .Subrequest "attachedVolumes" }}
                      {{ $attached := $attachedReq.JSON.String "data.result.0.value.1" }}
                      {{ $detachedReq := .Subrequest "detachedVolumes" }}
                      {{ $detached := $detachedReq.JSON.String "data.result.0.value.1" }}
                      <p class="color-subdue size-h6">Volumes</p>
                      <p class="color-highlight size-h3">{{ $totalVolumes }} total</p>
                      <p class="size-h6"><span class="color-positive">{{ $attached }} attached</span> &middot; {{ $detached }} detached</p>
                    </div>
                    <div>
                      {{ $totalCapReq := .Subrequest "totalCapacity" }}
                      {{ $totalCapBytes := $totalCapReq.JSON.Float "data.result.0.value.1" }}
                      {{ $usedCapReq := .Subrequest "usedCapacity" }}
                      {{ $usedCapBytes := $usedCapReq.JSON.Float "data.result.0.value.1" }}
                      {{ $totalGB := div $totalCapBytes 1073741824 }}
                      {{ $usedGB := div $usedCapBytes 1073741824 }}
                      {{ $usagePercent := 0.0 }}
                      {{ if gt $totalGB 0.0 }}{{ $usagePercent = mul (div $usedGB $totalGB) 100 }}{{ end }}
                      <p class="color-subdue size-h6">Storage</p>
                      <p class="color-highlight size-h3">{{ printf "%.1f" $usedGB }} / {{ printf "%.1f" $totalGB }} GB</p>
                      <div class="progress-bar progress-bar-combined" style="margin-top: 0.4rem;">
                        <div class="progress-value" style="--percent: {{ printf "%.0f" $usagePercent }}"></div>
                      </div>
                      <p class="size-h6" style="margin-top: 0.25rem;">{{ printf "%.1f" $usagePercent }}% used</p>
                    </div>
                    <div>
                      {{ $nodesReq := .Subrequest "healthyNodes" }}
                      {{ $nodes := $nodesReq.JSON.String "data.result.0.value.1" }}
                      <p class="color-subdue size-h6">Storage Nodes</p>
                      <p class="color-highlight size-h3">{{ $nodes }} ready</p>
                    </div>
                    <a href="http://longhorn" class="color-highlight size-h6" style="text-decoration: none;">Open Longhorn UI →</a>
                  </div>
                '';
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
