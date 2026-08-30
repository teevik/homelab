# Argo CD PreSync hook Job that builds images with rootless BuildKit and
# pushes them to the in-cluster registry (kubernetes/registry.nix).
#
# Argo runs the Job before it applies the rest of the application, so the
# Deployment that references a new tag only rolls once the image exists and
# the old pod keeps serving during the build. Tags are derived from the build
# source at manifest-generation time, so a tag that already exists in the
# registry is skipped in a few seconds and the Job is otherwise idempotent.
#
# Usage (inside an application's `resources`):
#   jobs.build-foo = import ./lib/build-job.nix {
#     name = "build-foo";                      # also the pod's `app` label
#     pushSecret = "foo-registry-push";        # Secret with a docker config.json
#     builds = [ { image = "foo"; tag = "..."; context = "/workspace"; } ];
#     contextConfigMap = "foo-build-context";  # mounted at /workspace (optional)
#   };
#
# `context` is either "/workspace" (files from `contextConfigMap`) or a
# BuildKit git context such as "https://github.com/org/repo.git#<rev>:subdir".
{
  name,
  builds,
  pushSecret,
  contextConfigMap ? null,
  memoryLimit ? "2Gi",
}:
let
  registry = "zot.registry.svc:5000";
  manifestTypes = builtins.concatStringsSep ", " [
    "application/vnd.oci.image.index.v1+json"
    "application/vnd.oci.image.manifest.v1+json"
    "application/vnd.docker.distribution.manifest.list.v2+json"
    "application/vnd.docker.distribution.manifest.v2+json"
  ];

  buildOne =
    {
      image,
      tag,
      context,
    }:
    let
      ref = "${registry}/${image}:${tag}";
      cache = "${registry}/${image}:buildcache";
      contextArgs =
        if context == "/workspace" then
          "--local context=/workspace --local dockerfile=/workspace"
        else
          "--opt context=${context}";
    in
    ''
      if wget -q --spider --header "Accept: ${manifestTypes}" "http://${registry}/v2/${image}/manifests/${tag}"; then
        echo "${ref} is already in the registry; skipping build"
      else
        echo "building ${ref}"
        buildctl-daemonless.sh build --frontend dockerfile.v0 ${contextArgs} \
          --output type=image,name=${ref},push=true,registry.insecure=true \
          --export-cache type=registry,ref=${cache},mode=max,registry.insecure=true \
          --import-cache type=registry,ref=${cache},registry.insecure=true
      fi
    '';

  script = ''
    set -eu
    ${builtins.concatStringsSep "\n" (map buildOne builds)}
  '';
in
{
  metadata.annotations = {
    "argocd.argoproj.io/hook" = "PreSync";
    "argocd.argoproj.io/hook-delete-policy" = "BeforeHookCreation";
    # Anything the Job needs (build-context ConfigMap, NetworkPolicy) must be
    # a PreSync hook in an earlier wave; regular resources sync after hooks.
    "argocd.argoproj.io/sync-wave" = "0";
  };
  spec = {
    backoffLimit = 0;
    # Labelled so namespaces with a default-deny NetworkPolicy can grant the
    # build pod egress (it needs the internet for base images and sources).
    template.metadata.labels.app = name;
    template.spec = {
      restartPolicy = "Never";
      automountServiceAccountToken = false;
      containers.buildkit = {
        image = "docker.io/moby/buildkit:v0.32.2-rootless@sha256:504731e577c20559c00f968f33219f30115e70be29ab96728d1d06e963fc494b";
        command = [
          "sh"
          "-c"
          script
        ];
        env = {
          # Rootless without a separate PID namespace; avoids needing an
          # unmasked /proc (upstream examples/kubernetes/job.rootless.yaml).
          BUILDKITD_FLAGS.value = "--oci-worker-no-process-sandbox";
          DOCKER_CONFIG.value = "/home/user/.docker";
        };
        # Rootless BuildKit needs user namespaces and mount syscalls that the
        # default seccomp profile blocks. This is the one pod in the cluster
        # running unconfined.
        securityContext = {
          seccompProfile.type = "Unconfined";
          appArmorProfile.type = "Unconfined";
          runAsUser = 1000;
          runAsGroup = 1000;
        };
        volumeMounts = {
          "/home/user/.docker" = {
            name = "docker-config";
            readOnly = true;
          };
          "/home/user/.local/share/buildkit".name = "buildkitd";
        }
        // (
          if contextConfigMap != null then
            {
              "/workspace" = {
                name = "workspace";
                readOnly = true;
              };
            }
          else
            { }
        );
        resources = {
          requests = {
            cpu = "500m";
            memory = "512Mi";
          };
          limits.memory = memoryLimit;
        };
      };
      volumes = {
        docker-config.secret.secretName = pushSecret;
        buildkitd.emptyDir = { };
      }
      // (if contextConfigMap != null then { workspace.configMap.name = contextConfigMap; } else { });
    };
  };
}
