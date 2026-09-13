{ ... }:
let
  backupLabels = {
    "recurring-job.longhorn.io/source" = "enabled";
    "recurring-job-group.longhorn.io/backup" = "enabled";
    "recurring-job-group.longhorn.io/snapshot" = "enabled";
  };

  mkPvc = storage: {
    metadata.annotations."argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
    spec = {
      storageClassName = "longhorn";
      accessModes = [ "ReadWriteOnce" ];
      resources.requests.storage = storage;
    };
  };

  mkBackedUpPvc =
    storage:
    let
      pvc = mkPvc storage;
    in
    pvc // { metadata = pvc.metadata // { labels = backupLabels; }; };
in
{
  # Crafty is retired in favour of AMP. Keep the existing application and
  # namespace so Argo CD prunes its workloads while retaining all five data
  # volumes for migration. Remove these claims only after the data is migrated.
  applications.crafty = {
    namespace = "crafty";
    createNamespace = true;

    resources = {
      persistentVolumeClaims.crafty-config = mkPvc "2Gi";
      persistentVolumeClaims.crafty-servers = mkBackedUpPvc "80Gi";
      persistentVolumeClaims.crafty-backups = mkBackedUpPvc "50Gi";
      persistentVolumeClaims.crafty-logs = mkPvc "5Gi";
      persistentVolumeClaims.crafty-import = mkPvc "10Gi";
    };
  };
}
