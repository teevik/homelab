{
  config,
  flake,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.animeMatrix;
in
{
  options.homelab.animeMatrix = {
    enable = lib.mkEnableOption "AniMe Matrix cluster stats display";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "How often to refresh the cluster stats display (Go duration format).";
    };

    kubeconfig = lib.mkOption {
      type = lib.types.str;
      default = "/etc/rancher/k3s/k3s.yaml";
      description = "Path to the kubeconfig file for accessing the cluster.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd service to run anime-matrix-stats
    systemd.services.anime-matrix-stats = {
      description = "Display Kubernetes cluster stats on AniMe Matrix";
      after = [
        "k3s.service"
        "asusd.service"
      ];
      wants = [
        "k3s.service"
        "asusd.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStopSec = "10s";

        ExecStart = lib.concatStringsSep " " [
          "${flake.packages.${pkgs.system}.anime-matrix-stats}/bin/anime-matrix-stats"
          "--kubeconfig=${cfg.kubeconfig}"
          "--interval=${cfg.interval}"
          "--asusctl=${pkgs.asusctl}/bin/asusctl"
        ];

        # Run as root to access kubeconfig and asusctl
        User = "root";

        # Disable the display on stop
        ExecStopPost = "${pkgs.asusctl}/bin/asusctl anime --enable-display false";
      };
    };
  };
}
