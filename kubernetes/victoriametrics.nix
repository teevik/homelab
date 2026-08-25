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

        # RecordingRulesNoData flags any recording rule with no output for 30m.
        # count:up0 (count of *down* targets) and the bare/Node/Job-owned
        # pod_owner rules are legitimately empty on a healthy single-node
        # cluster, so the alert is a permanent false positive here.
        defaultRules.rules.RecordingRulesNoData.enabled = false;

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

        # --- VictoriaLogs ---
        # vlsingle stores logs; vlagent runs as a DaemonSet (k8sCollector mode,
        # the chart default) tailing /var/log/pods and pushing to vlsingle. The
        # chart adds the Grafana datasource, dashboards, and alert rules itself.
        # Tag only, no digest: the chart copies this value verbatim into the
        # app.kubernetes.io/version label and a digest breaks the 63-char limit
        # (renovate.json5 disables pinDigests for this image accordingly).
        # renovate: datasource=docker depName=victoriametrics/victoria-logs
        vlsingle.spec.image.tag = "v1.52.0";
        # renovate: datasource=docker depName=victoriametrics/victoria-logs
        vlagent.spec.image.tag = "v1.52.0";

        vlsingle.enabled = true;
        vlsingle.spec = {
          retentionPeriod = "30d";
          # Hard cap below the PVC size so retention can never fill the volume
          extraArgs."retention.maxDiskSpaceUsageBytes" = "8GiB";
          storage = {
            storageClassName = "longhorn";
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "10Gi";
          };
          # VictoriaLogs sizes its caches to 60% of the cgroup limit and idles
          # near 800Mi; 1Gi OOM-killed it during vlagent's initial backfill.
          resources = {
            requests = {
              cpu = "100m";
              memory = "512Mi";
            };
            limits.memory = "2Gi";
          };
        };

        # With logs enabled the chart puts an internal vmauth in front of vmalert
        # so LogsQL rules reach vlsingle and PromQL rules reach vmsingle.
        # renovate: datasource=docker depName=victoriametrics/vmauth
        internal.vmauth.spec.image.tag = "v1.150.0@sha256:18501bc13770dbb921fc999b6ae15ddb5054b5147bab027b5d459662855c172d";

        vlagent.enabled = true;
        vlagent.spec.resources = {
          requests = {
            cpu = "50m";
            memory = "128Mi";
          };
          # Headroom for buffered backlog while vlsingle is restarting
          limits.memory = "1Gi";
        };

        # Disable admission webhook to avoid TLS certs being regenerated on every build
        # (Helm's `lookup` function doesn't work with offline rendering)
        victoria-metrics-operator.admissionWebhooks.enabled = false;

        # Required for the victoriametrics-{metrics,logs}-datasource types in Grafana
        grafana.plugins = [
          "victoriametrics-metrics-datasource"
          "victoriametrics-logs-datasource"
        ];

        # Pin the Grafana image like the VM images above; the chart's appVersion
        # is otherwise unpinned and invisible to Renovate.
        # renovate: datasource=docker depName=docker.io/grafana/grafana
        grafana.image.tag = "13.1.1@sha256:7cb8c64c4d57a57e734073f3cc94620adb24a0acb929bd80ba9f14017e3a975b";

        grafana.resources = {
          requests = {
            cpu = "50m";
            memory = "256Mi";
          };
          limits.memory = "1Gi";
        };
        grafana.sidecar.resources = {
          requests = {
            cpu = "10m";
            memory = "64Mi";
          };
          limits.memory = "256Mi";
        };

        # The datasource sidecar writes its file after Grafana has already
        # started, so provisioning relied on a reload POST that fails whenever
        # the admin password in SQLite drifts from the secret. Run the sidecar
        # once as an init container so datasources are present at boot.
        grafana.sidecar.datasources.initDatasources = true;
        # The init container inherits watchMethod; WATCH never exits and wedges
        # the pod in Init. LIST syncs once and exits (datasources only change
        # with the chart, which rolls the pod anyway).
        grafana.sidecar.datasources.watchMethod = "LIST";

        # Dashboards whose ConfigMap carries a `grafana_folder` annotation land
        # in that folder; unannotated ones (the home dashboard) stay at the root.
        grafana.sidecar.dashboards.folderAnnotation = "grafana_folder";
        # Per-service dashboards live in their own namespaces (longhorn, argocd);
        # the sidecar defaults to its own namespace only.
        grafana.sidecar.dashboards.searchNamespace = "ALL";
        grafana.sidecar.dashboards.provider.foldersFromFilesStructure = true;
        defaultDashboards.annotations.grafana_folder = "Cluster";

        # Skip chart dashboards that can't show anything on a single Linux k3s node.
        defaultDashboards.dashboards = {
          k8s-resources-multicluster.enabled = false;
          k8s-resources-windows-cluster.enabled = false;
          k8s-resources-windows-namespace.enabled = false;
          k8s-resources-windows-pod.enabled = false;
          k8s-windows-cluster-rsrc-use.enabled = false;
          k8s-windows-node-rsrc-use.enabled = false;
          nodes-aix.enabled = false;
          nodes-darwin.enabled = false;
          prometheus.enabled = false;
          prometheus-remote-write.enabled = false;
        };

        # Let Grafana-managed alert rules (if any are ever created) flow through
        # the same Alertmanager -> ntfy path instead of Grafana's built-in one.
        defaultDatasources.alertmanager.datasources = [
          {
            name = "Alertmanager";
            access = "proxy";
            uid = "Alertmanager";
            jsonData = {
              implementation = "prometheus";
              handleGrafanaManagedAlerts = true;
            };
          }
        ];

        grafana."grafana.ini" = {
          dashboards.default_home_dashboard_path = "/var/lib/grafana/dashboards/default/homelab-overview.json";
          # Tailnet address; used for share links and alert links.
          server.root_url = "http://grafana.tail84b6c.ts.net";
          # No phoning home from the homelab.
          analytics = {
            reporting_enabled = false;
            check_for_updates = false;
            check_for_plugin_updates = false;
            feedback_links_enabled = false;
          };
          news.news_feed_enabled = false;
        };

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
        # instead of the chart's default blackhole receiver. Silenced:
        #   - Watchdog: always-firing heartbeat
        #   - InfoInhibitor: kube-prometheus's info-severity inhibitor, always firing
        alertmanager.config = {
          route = {
            receiver = "ntfy";
            routes = [
              {
                matchers = [ ''alertname=~"Watchdog|InfoInhibitor"'' ];
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
