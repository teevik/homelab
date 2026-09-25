{ ... }:
{
  # AMD GPU device plugin: advertises amd.com/gpu and injects /dev/kfd +
  # /dev/dri into requesting containers with proper device-cgroup access,
  # so GPU workloads (Immich ML) don't need privileged hostPath mounts.
  applications.amd-device-plugin = {
    namespace = "kube-system";

    resources.daemonSets.amdgpu-device-plugin.spec = {
      selector.matchLabels.name = "amdgpu-device-plugin";
      template = {
        metadata.labels.name = "amdgpu-device-plugin";
        spec = {
          priorityClassName = "system-node-critical";
          automountServiceAccountToken = false;
          tolerations = [
            {
              key = "CriticalAddonsOnly";
              operator = "Exists";
            }
          ];
          containers.amdgpu = {
            # renovate: datasource=docker depName=rocm/k8s-device-plugin
            image = "rocm/k8s-device-plugin:1.31.0.11@sha256:e4df5dc9a7fa34e2344852256dcc5762171a6d68f1f9a34026ce26786ae335e2";
            securityContext = {
              allowPrivilegeEscalation = false;
              capabilities.drop = [ "ALL" ];
            };
            volumeMounts = {
              "/var/lib/kubelet/device-plugins".name = "device-plugins";
              "/sys".name = "sys";
            };
          };
          volumes = {
            device-plugins.hostPath.path = "/var/lib/kubelet/device-plugins";
            sys.hostPath.path = "/sys";
          };
        };
      };
    };
  };
}
