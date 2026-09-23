let
  metricsURL = "http://vmsingle-vm-victoria-metrics-k8s-stack.victoria-metrics.svc:8428/api/v1/query";
  query = expression: {
    url = metricsURL;
    parameters.query = expression;
  };

  # Check every required exporter, including sample age. An empty result from
  # a broken scrape must not turn into a healthy zero on the dashboard.
  widget =
    {
      title,
      link,
      sources,
      queries,
      requiredResults ? [ ],
      requests ? { },
      template,
    }:
    let
      selector = ''up{job=~"${builtins.concatStringsSep "|" sources}"}'';
    in
    {
      type = "custom-api";
      inherit title;
      title-url = link;
      cache = "1m";
      css-class = "homelab-metrics";
      subrequests = builtins.mapAttrs (_: query) queries // requests;
      url = metricsURL;
      parameters.query = "min by(job) (${selector} * (timestamp(${selector}) > bool time() - 180))";
      template = ''
        {{ $ok := and (eq .Response.StatusCode 200) (eq (.JSON.String "status") "success") (eq (len (.JSON.Array "data.result")) ${toString (builtins.length sources)}) }}
        {{ range .JSON.Array "data.result" }}
          {{ if ne (.Float "value.1") 1.0 }}{{ $ok = false }}{{ end }}
        {{ end }}
        ${builtins.concatStringsSep "\n" (
          builtins.map (name: ''
            {{ ${"$" + name} := .Subrequest "${name}" }}
            {{ if not (and (eq ${"$" + name}.Response.StatusCode 200) (eq (${"$" + name}.JSON.String "status") "success") (eq (${"$" + name}.JSON.String "data.resultType") "vector")) }}{{ $ok = false }}{{ end }}
          '') (builtins.attrNames queries)
        )}
        ${builtins.concatStringsSep "\n" (
          builtins.map (name: ''
            {{ if eq (len (${"$" + name}.JSON.Array "data.result")) 0 }}{{ $ok = false }}{{ end }}
          '') requiredResults
        )}
        <div class="homelab-unavailable">
          <p class="color-negative">Update unavailable</p>
          <p class="size-h5 margin-top-5">Could not refresh this card. Open its title for details.</p>
        </div>
        <div class="homelab-current">
          ${builtins.readFile template}
          <p class="size-h6 color-subdue margin-top-15">Checked <span {{ now | toRelativeTime }}></span> ago · refresh to update</p>
        </div>
      '';
    };

  protectedVolumes = ''max by(pvc, pvc_namespace) (label_replace(label_replace(kube_persistentvolumeclaim_labels{label_recurring_job_group_longhorn_io_backup="enabled"}, "pvc", "$1", "persistentvolumeclaim", "(.*)"), "pvc_namespace", "$1", "namespace", "(.*)"))'';
  lastBackup = "max by(pvc, pvc_namespace) (longhorn_volume_last_backup_at)";
in
{
  attention = widget {
    title = "Needs attention";
    link = "http://grafana/d/homelab-overview";
    sources = [
      "kube-state-metrics"
      "argocd-application-controller-metrics"
      "vmalert-vm-victoria-metrics-k8s-stack"
    ];
    queries = {
      apps = "max by(name, health_status, sync_status) (argocd_app_info)";
      inventory = "count(kube_pod_info)";
      pods = ''max by(namespace, pod) (kube_pod_status_phase{phase=~"Pending|Failed|Unknown"} == 1 or kube_pod_status_ready{condition="false"} == 1) unless on(namespace, pod) (kube_pod_status_phase{phase="Succeeded"} == 1)'';
      restarts = "sort_desc(sum by(namespace, pod) (round(increase_prometheus(kube_pod_container_status_restarts_total[1h]))) > 0)";
    };
    requiredResults = [
      "apps"
      "inventory"
    ];
    requests.alerts = {
      url = "http://vmalertmanager-vm-victoria-metrics-k8s-stack.victoria-metrics.svc:9093/api/v2/alerts";
      parameters = {
        active = "true";
        silenced = "false";
        inhibited = "false";
        filter = ''alertname!~"Watchdog|InfoInhibitor"'';
      };
    };
    template = ./attention.html;
  };

  backups = widget {
    title = "Backups";
    link = "http://longhorn/#/backup";
    sources = [
      "kube-state-metrics"
      "longhorn-backend"
    ];
    queries = {
      # Keep every opted-in PVC. -1 means missing telemetry; 0 means that
      # Longhorn reports no successful backup. They are different states.
      volumes = "sort((${lastBackup} and on(pvc, pvc_namespace) ${protectedVolumes}) or on(pvc, pvc_namespace) (${protectedVolumes} * -1))";
      failures = "(count by(volume) (longhorn_backup_state == 4) * on(volume) group_left(pvc, pvc_namespace) max by(volume, pvc, pvc_namespace) (longhorn_volume_last_backup_at * 0 + 1)) and on(pvc, pvc_namespace) ${protectedVolumes}";
    };
    template = ./backups.html;
  };

  resources = widget {
    title = "Resource consumers";
    link = "http://grafana/d/homelab-overview";
    sources = [
      "node-exporter"
      "kubelet"
    ];
    queries = {
      cpu = ''100 * (1 - avg(rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))'';
      memory = ''100 * (1 - sum(node_memory_MemAvailable_bytes{job="node-exporter"}) / sum(node_memory_MemTotal_bytes{job="node-exporter"}))'';
      topCPU = ''sort_desc(topk(3, sum by(namespace) (rate(container_cpu_usage_seconds_total{container!="",container!="POD",pod!="",job="kubelet",metrics_path="/metrics/cadvisor"}[5m]))))'';
      topMemory = ''sort_desc(topk(3, sum by(namespace) (container_memory_working_set_bytes{container!="",container!="POD",pod!="",job="kubelet",metrics_path="/metrics/cadvisor"})))'';
    };
    requiredResults = [
      "cpu"
      "memory"
      "topCPU"
      "topMemory"
    ];
    template = ./resources.html;
  };
}
