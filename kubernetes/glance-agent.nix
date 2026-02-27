# Glance Agent - Lightweight system metrics exporter
# https://github.com/glanceapp/agent
# Deploys on all nodes to expose host metrics for Glance's server-stats widget

{ ... }:
{
  applications.glance-agent = {
    namespace = "glance";
    createNamespace = false;

    resources = {
      daemonSets.glance-agent.spec = {
        selector.matchLabels.app = "glance-agent";
        template = {
          metadata.labels.app = "glance-agent";
          spec = {
            hostNetwork = true;
            containers.glance-agent = {
              image = "glanceapp/agent:v0.1.0@sha256:f57ee10cd2f23e66ae6a8325fb6106e12878e1f985a88aaa914687d14489017c";
              ports.http.containerPort = 27973;
              env = {
                HIDE_MOUNTPOINTS_BY_DEFAULT.value = "true";
                MOUNTPOINTS.value = "/:Root";
              };
            };
          };
        };
      };
    };
  };
}
