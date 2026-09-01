{ charts, ... }:
{
  applications.argocd = {
    namespace = "argocd";
    createNamespace = true;

    # Server-side apply avoids the 262144 byte annotation limit,
    # allowing large CRDs like applicationsets.argoproj.io.
    syncPolicy.syncOptions.serverSideApply = true;

    helm.releases.argocd = {
      chart = charts.argoproj.argo-cd;

      values = {

        # Single-node homelab: minimal HA, disable unused components
        dex.enabled = false;
        notifications.enabled = false;

        # TLS terminated by Tailscale, run insecure
        server.extraArgs = [ "--insecure" ];

        # argocd-secret (admin password, server.secretkey, webhook secret) is
        # provisioned from sops on the host (modules/nixos/kubernetes.nix)
        # instead of being rendered into the git-tracked manifests.
        configs.secret.createSecret = false;

        # GitHub push payloads are small; constrain the unauthenticated public endpoint.
        configs.cm."webhook.maxPayloadSizeMB" = "1";

        # Expose Prometheus metrics for the VMServiceScrape below
        controller.metrics.enabled = true;
        server.metrics.enabled = true;
        repoServer.metrics.enabled = true;
        applicationSet.metrics.enabled = true;

        # Grant admin user full permissions
        configs.rbac."policy.csv" = "g, admin, role:admin";
      };
    };

    # Enable orphaned resources monitoring on the default project
    resources.appProjects.default.spec = {
      sourceRepos = [ "*" ];
      destinations = [
        {
          server = "*";
          namespace = "*";
        }
      ];
      clusterResourceWhitelist = [
        {
          group = "*";
          kind = "*";
        }
      ];
      orphanedResources.warn = true;
    };

    # Scrape the Argo CD *-metrics Services. Written as a VMServiceScrape
    # directly: the chart's ServiceMonitor templates are gated on the
    # monitoring.coreos.com CRD, which is not installed.
    yamls = [
      ''
        apiVersion: operator.victoriametrics.com/v1beta1
        kind: VMServiceScrape
        metadata:
          name: argocd-metrics
          namespace: argocd
        spec:
          selector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - argocd-metrics
                  - argocd-server-metrics
                  - argocd-repo-server-metrics
          endpoints:
            - port: http-metrics
      ''

      # Guard against applying the rendered tree by hand. `nixidy apply` (or
      # `kubectl apply -f manifests/...`) bypasses Argo CD and, on 2026-08-30,
      # created Helm pre-delete hook Jobs that Argo itself never runs; one of
      # them wiped every VictoriaMetrics CR and the VictoriaLogs volume.
      #
      # Only non-system callers (you, via the Tailscale proxy) are evaluated;
      # Argo CD, controllers and the host's system:admin are untouched. Denied:
      # creating an object with a kubectl last-applied-configuration
      # annotation, or changing that annotation on update — i.e. client-side
      # `kubectl apply`. Still allowed: `kubectl create`/`edit`/`patch`/`scale`/
      # `rollout restart`/`delete`, and Secrets (so the ad-hoc `kubectl create
      # secret ... | kubectl apply -f -` habit keeps working; the one
      # chart-rendered Secret in manifests/ is harmless). `--server-side` is
      # caught too: the API server rewrites the annotation for manager `kubectl`.
      #
      # Deliberate bypass (e.g. `nixidy bootstrap`): name the field manager —
      #   kubectl apply --field-manager=gitops-bypass -f ...
      # (impersonation groups don't survive the Tailscale API proxy.)
      ''
        apiVersion: admissionregistration.k8s.io/v1
        kind: ValidatingAdmissionPolicy
        metadata:
          name: no-manual-apply
        spec:
          failurePolicy: Fail
          matchConstraints:
            resourceRules:
              - apiGroups: ["*"]
                apiVersions: ["*"]
                operations: ["CREATE", "UPDATE"]
                resources: ["*"]
          matchConditions:
            - name: human-caller
              expression: "!request.userInfo.username.startsWith('system:')"
            - name: not-a-secret
              expression: '!(request.resource.group == "" && request.resource.resource == "secrets")'
          variables:
            - name: key
              expression: "'kubectl.kubernetes.io/last-applied-configuration'"
            - name: clientSideApply
              expression: >-
                has(object.metadata.annotations)
                && variables.key in object.metadata.annotations
                && !(
                  request.operation == 'UPDATE'
                  && has(oldObject.metadata.annotations)
                  && variables.key in oldObject.metadata.annotations
                  && oldObject.metadata.annotations[variables.key]
                     == object.metadata.annotations[variables.key]
                )
            - name: bypass
              expression: "has(request.options.fieldManager) && request.options.fieldManager == 'gitops-bypass'"
          validations:
            - expression: variables.bypass || !variables.clientSideApply
              reason: Forbidden
              message: >-
                Client-side kubectl apply is disabled: this cluster is managed by
                Argo CD from git. Commit and push instead of `nixidy apply` /
                `kubectl apply -f manifests`, or pass --field-manager=gitops-bypass
                if this is deliberate.
      ''
      ''
        apiVersion: admissionregistration.k8s.io/v1
        kind: ValidatingAdmissionPolicyBinding
        metadata:
          name: no-manual-apply
        spec:
          policyName: no-manual-apply
          validationActions: ["Deny"]
      ''
    ];

    # Argo CD dashboard (grafana.com/dashboards/14584), picked up by the
    # Grafana sidecar from any namespace via the grafana_dashboard label.
    resources.configMaps.argocd-dashboard = {
      metadata.labels.grafana_dashboard = "1";
      metadata.annotations.grafana_folder = "Cluster";
      data."argocd.json" = builtins.readFile ./dashboards/argocd.json;
    };

    # Expose only the webhook route publicly; keep the Argo CD UI tailnet-private.
    resources.ingresses.argocd-webhook = {
      metadata.annotations = {
        "tailscale.com/funnel" = "true";
      };
      spec = {
        ingressClassName = "tailscale";
        rules = [
          {
            http.paths = [
              {
                path = "/api/webhook";
                pathType = "Prefix";
                backend.service = {
                  name = "argocd-server";
                  port.number = 80;
                };
              }
            ];
          }
        ];
        tls = [
          {
            hosts = [ "argocd-webhook" ];
          }
        ];
      };
    };

    # Tailscale LoadBalancer to expose ArgoCD UI
    resources.services.argocd-tailscale = {
      metadata.annotations = {
        "tailscale.com/proxy-group" = "ingress";
        "tailscale.com/hostname" = "argocd";
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        selector = {
          "app.kubernetes.io/name" = "argocd-server";
          "app.kubernetes.io/instance" = "argocd";
        };
        ports.http = {
          port = 80;
          targetPort = 8080;
        };
      };
    };
  };
}
