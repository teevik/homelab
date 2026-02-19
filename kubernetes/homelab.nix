{
  # Target repository for generated manifests.
  # Required by nixidy even when using 'nixidy apply' directly.
  nixidy.target.repository = "https://github.com/teevik/homelab.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/homelab";

  # Example application: nginx
  # Remove or replace this with your actual workloads.
  applications.nginx = {
    namespace = "nginx";
    createNamespace = true;

    resources = {
      deployments.nginx.spec = {
        replicas = 1;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec.containers.nginx = {
            image = "nginx:latest";
            ports.http.containerPort = 80;
          };
        };
      };

      services.nginx.spec = {
        selector.app = "nginx";
        ports.http.port = 80;
      };
    };
  };
}
