{ charts, ... }:
{
  applications.victoria-metrics = {
    namespace = "victoria-metrics";
    createNamespace = true;

    # Server-side apply avoids the 262144 byte annotation limit,
    # allowing large resources like the node-exporter-full dashboard.
    syncPolicy.syncOptions.serverSideApply = true;

    helm.releases.vm = {
      chart = charts.victoriametrics.victoria-metrics-k8s-stack;

      values = {
        # Pin VictoriaMetrics image version
        # renovate: datasource=docker depName=victoriametrics/victoria-metrics
        vmsingle.spec.image.tag = "v1.150.0@sha256:54467c7764a3e6579199af1914bb779f01ce32265cd552eb5ae0d4f8a2b80a97";
        # renovate: datasource=docker depName=victoriametrics/vmagent
        vmagent.spec.image.tag = "v1.150.0@sha256:3eff5874d59292714878dcb6aee14f048bf19b7312b727860ba5e7d29e2e0c07";
        # renovate: datasource=docker depName=victoriametrics/vmalert
        vmalert.spec.image.tag = "v1.150.0@sha256:c6e6c1ef6e43c09510dd0aff264bf0ea319c1bdfced1ccc79dad1545950a7989";

        # k3s bundles controller-manager, scheduler, and etcd into the main
        # k3s process — there are no separate pods to scrape, so disable these
        # to avoid KubeControllerManagerDown, KubeSchedulerDown,
        # ScrapePoolHasNoTargets, and RecordingRulesNoData alerts.
        kubeControllerManager.enabled = false;
        kubeScheduler.enabled = false;
        kubeEtcd.enabled = false;

        # The sync job manages rules independently of scrape components.
        # Keep rules for absent k3s control-plane targets disabled as well.
        defaultRules.groups = {
          "kube-scheduler.rules".enabled = false;
          "kubernetes-system-controller-manager".enabled = false;
          "kubernetes-system-scheduler".enabled = false;
        };

        # Give vmagent enough CPU headroom to avoid CPUThrottlingHigh alerts
        vmagent.spec.resources = {
          requests = {
            cpu = "100m";
            memory = "200Mi";
          };
          limits = {
            cpu = "500m";
            memory = "500Mi";
          };
        };

        # Single-node VMSingle with Longhorn storage
        vmsingle.spec = {
          retentionPeriod = "3";
          storage = {
            storageClassName = "longhorn";
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "20Gi";
          };
        };

        # Disable admission webhook to avoid TLS certs being regenerated on every build
        # (Helm's `lookup` function doesn't work with offline rendering)
        victoria-metrics-operator.admissionWebhooks.enabled = false;

        # Required for the victoriametrics-metrics-datasource type in Grafana
        grafana.plugins = [ "victoriametrics-metrics-datasource" ];

        grafana."grafana.ini".dashboards.default_home_dashboard_path =
          "/var/lib/grafana/dashboards/default/homelab-overview.json";

        # Persist Grafana's SQLite database so sessions and settings survive pod restarts
        grafana.persistence = {
          enabled = true;
          storageClassName = "longhorn";
          size = "1Gi";
        };

        # Admin credentials come from the sops-provisioned grafana-admin secret
        # (modules/nixos/kubernetes.nix) instead of a value in git.
        grafana.admin = {
          existingSecret = "grafana-admin";
          userKey = "admin-user";
          passwordKey = "admin-password";
        };

        # Route alerts to ntfy (via the alertmanager-ntfy forwarder below)
        # instead of the chart's default blackhole receiver. Watchdog is the
        # always-firing heartbeat alert and stays silenced.
        alertmanager.config = {
          route = {
            receiver = "ntfy";
            routes = [
              {
                matchers = [ ''alertname="Watchdog"'' ];
                receiver = "blackhole";
              }
            ];
          };
          receivers = [
            {
              name = "ntfy";
              webhook_configs = [
                {
                  url = "http://alertmanager-ntfy:8000/hook";
                  send_resolved = true;
                }
              ];
            }
            { name = "blackhole"; }
          ];
        };
      };
    };

    # Forwards Alertmanager webhook payloads to ntfy as readable notifications
    resources.configMaps.alertmanager-ntfy.data."config.yml" = ''
      ntfy:
        baseurl: http://ntfy.ntfy.svc.cluster.local
        notification:
          topic: alerts
          priority: |
            status == "firing" ? "high" : "default"
          tags:
            - tag: rotating_light
              condition: status == "firing"
            - tag: white_check_mark
              condition: status == "resolved"
          templates:
            title: |
              {{ if eq .Status "resolved" }}Resolved: {{ end }}{{ index .Annotations "summary" }}
            description: |
              {{ index .Annotations "description" }}
    '';

    resources.deployments.alertmanager-ntfy.spec = {
      replicas = 1;
      selector.matchLabels.app = "alertmanager-ntfy";
      template = {
        metadata.labels.app = "alertmanager-ntfy";
        spec = {
          automountServiceAccountToken = false;
          containers.alertmanager-ntfy = {
            # renovate: datasource=docker depName=ghcr.io/alexbakker/alertmanager-ntfy
            image = "ghcr.io/alexbakker/alertmanager-ntfy:1.2.1@sha256:2a862f23c8fb67f777824979487c06a417b2f9bbbc2eb45a974a1fb45b9bbff3";
            args = [
              "--configs"
              "/etc/alertmanager-ntfy/config.yml"
            ];
            ports.http.containerPort = 8000;
            volumeMounts."/etc/alertmanager-ntfy".name = "config";
            securityContext = {
              runAsUser = 1000;
              runAsGroup = 1000;
              runAsNonRoot = true;
              allowPrivilegeEscalation = false;
              capabilities.drop = [ "ALL" ];
              seccompProfile.type = "RuntimeDefault";
            };
            resources = {
              requests = {
                cpu = "10m";
                memory = "32Mi";
              };
              limits.memory = "128Mi";
            };
          };
          volumes.config.configMap.name = "alertmanager-ntfy";
        };
      };
    };

    resources.services.alertmanager-ntfy.spec = {
      selector.app = "alertmanager-ntfy";
      ports.http = {
        port = 8000;
        targetPort = 8000;
      };
    };

    # Custom homelab overview dashboard
    resources.configMaps.homelab-overview = {
      metadata.labels.grafana_dashboard = "1";
      data."homelab-overview.json" = builtins.readFile ./dashboards/homelab-overview.json;
    };

    # Tailscale LoadBalancer to expose Grafana
    resources.services.grafana-tailscale = {
      metadata.annotations = {
        "tailscale.com/proxy-group" = "ingress";
        "tailscale.com/hostname" = "grafana";
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        selector = {
          "app.kubernetes.io/name" = "grafana";
          "app.kubernetes.io/instance" = "vm";
        };
        ports.http = {
          port = 80;
          targetPort = 3000;
        };
      };
    };
  };
}
