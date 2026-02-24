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
    enable = lib.mkEnableOption "AniMe Matrix server stats display";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "How often to refresh the server stats display (Go duration format).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd service to run anime-matrix-stats
    systemd.services.anime-matrix-stats = {
      description = "Display server CPU, memory and disk stats on AniMe Matrix";
      after = [ "asusd.service" ];
      wants = [ "asusd.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStopSec = "10s";

        ExecStart = lib.concatStringsSep " " [
          "${flake.packages.${pkgs.system}.anime-matrix-stats}/bin/anime-matrix-stats"
          "--interval=${cfg.interval}"
          "--asusctl=${pkgs.asusctl}/bin/asusctl"
        ];

        # Run as root to access asusctl
        User = "root";

        # Disable the display on stop
        ExecStopPost = "${pkgs.asusctl}/bin/asusctl anime --enable-display false";
      };
    };
  };
}
