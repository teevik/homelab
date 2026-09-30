{ ... }:
let
  catalog = import ../catalog-lib.nix { };
  security = {
    allowPrivilegeEscalation = false;
    capabilities.drop = [ "ALL" ];
    readOnlyRootFilesystem = true;
    seccompProfile.type = "RuntimeDefault";
  };
in
{
  applications.victoria-metrics = {
    # Explicit discovery: installed CRDs alone do not start any checks.
    helm.releases.vm.values.vmagent.spec = {
      probeSelector.matchLabels."homelab.teevik.dev/dashboard" = "true";
      probeNamespaceSelector.matchLabels."kubernetes.io/metadata.name" = "victoria-metrics";
    };
    resources = {
      configMaps.dashboard-blackbox.data."blackbox.json" = builtins.toJSON catalog.blackbox;
      deployments.dashboard-blackbox.spec = {
        replicas = 1;
        selector.matchLabels.app = "dashboard-blackbox";
        template = {
          metadata.labels.app = "dashboard-blackbox";
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 65534;
              runAsGroup = 65534;
            };
            containers.blackbox = {
              # renovate: datasource=docker depName=quay.io/prometheus/blackbox-exporter
              image = "quay.io/prometheus/blackbox-exporter:v0.28.0@sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc";
              args = [ "--config.file=/config/blackbox.json" ];
              securityContext = security;
              ports.http.containerPort = 9115;
              volumeMounts."/config" = { name = "config"; readOnly = true; };
              readinessProbe.httpGet = { path = "/-/healthy"; port = "http"; };
              livenessProbe.httpGet = { path = "/-/healthy"; port = "http"; };
              resources = {
                requests = { cpu = "10m"; memory = "32Mi"; };
                limits.memory = "128Mi";
              };
            };
            volumes.config.configMap.name = "dashboard-blackbox";
          };
        };
      };
      services.dashboard-blackbox.spec = {
        selector.app = "dashboard-blackbox";
        ports.http = { port = 9115; targetPort = 9115; };
      };
      # Limit requests to vmagent; the prober requires HTTP/HTTPS, DNS and host routes.
      networkPolicies.dashboard-blackbox.spec = {
        podSelector.matchLabels.app = "dashboard-blackbox";
        policyTypes = [ "Ingress" "Egress" ];
        ingress = [ {
          from = [ { podSelector.matchLabels."app.kubernetes.io/name" = "vmagent"; } ];
          ports = [ { protocol = "TCP"; port = 9115; } ];
        } ];
        egress = [
          {
            to = [ { namespaceSelector = { }; } ];
            # Policies see backend ports after Service DNAT, not just ports 80/443.
            ports = map (port: { protocol = "TCP"; inherit port; }) [ 80 443 2283 3000 5000 5800 8000 8080 8899 ];
          }
          {
            to = [ { ipBlock.cidr = "192.168.1.225/32"; } ];
            ports = map (port: { protocol = "TCP"; inherit port; }) [ 8088 8501 ];
          }
          {
            to = [ { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system"; podSelector.matchLabels."k8s-app" = "kube-dns"; } ];
            ports = [ { protocol = "UDP"; port = 53; } { protocol = "TCP"; port = 53; } ];
          }
        ];
      };
      serviceAccounts.dashboard-collector.automountServiceAccountToken = false;
      roles.dashboard-collector.rules = [ {
        apiGroups = [ "" ];
        resources = [ "services/proxy" ];
        resourceNames = [
          "http:vmsingle-vm-victoria-metrics-k8s-stack:8428"
          "http:vmalertmanager-vm-victoria-metrics-k8s-stack:9093"
        ];
        verbs = [ "get" ];
      } ];
      roleBindings.dashboard-collector = {
        roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "Role"; name = "dashboard-collector"; };
        subjects = [ { kind = "ServiceAccount"; name = "dashboard-collector"; namespace = "victoria-metrics"; } ];
      };
    };
    yamls = map builtins.toJSON catalog.probes;
  };
  applications.kodekamp.resources.networkPolicies.web.spec.ingress = [ {
    from = [ {
      namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "victoria-metrics";
      podSelector.matchLabels.app = "dashboard-blackbox";
    } ];
    ports = [ { protocol = "TCP"; port = 3000; } ];
  } ];
}
