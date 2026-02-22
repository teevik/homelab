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
              image = "glanceapp/agent:latest";
              ports.http.containerPort = 27973;
              env = {
                HIDE_MOUNTPOINTS_BY_DEFAULT.value = "true";
              };
            };
          };
        };
      };
    };
  };
}
