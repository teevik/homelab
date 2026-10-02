{
  config,
  flake,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.displayPolicy;
  package = flake.packages.${pkgs.system}.display-policy;
  triggerhappy = flake.packages.${pkgs.system}.display-triggerhappy;
  command = "${package}/bin/display-policy";
  settings = {
    state_dir = "/var/lib/homelab-display-policy";
    run_dir = "/run/homelab-display-policy";
    metrics_dir = "/var/lib/homelab-display-metrics";
    authorized_user = "teevik";
    initial_brightness = 3122; # Read-only observation of this laptop; saved daytime level wins.
    asusctl = "${config.services.asusd.package}/bin/asusctl";
    busctl = "${pkgs.systemd}/bin/busctl";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    setterm = "${pkgs.util-linux}/bin/setterm";
  }
  // cfg.settings;
  triggers = pkgs.writeText "display-actions.conf" ''
    KEY_PROG1 1 ${command} away
    KEY_PROG2 1 ${command} wake
    KEY_PROG3 1 ${command} resume-schedule
  '';
  thSocket = "/run/homelab-display-triggerhappy/control.sock";
in
{
  options.homelab.displayPolicy = {
    enable = lib.mkEnableOption "independent screen and AniMe night control";
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Device adapter settings; overrides are for isolated simulated-device acceptance.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.animeMatrix.enable && config.services.asusd.enable;
        message = "Display policy requires asusd and the gated AniMe producer.";
      }
    ];
    environment.systemPackages = [ package ];
    environment.etc."homelab/display-policy.json".text = builtins.toJSON settings;
    boot.kernelModules = [ "uinput" ];
    # No uncontrolled restoration during boot or driver re-registration.
    systemd.services."systemd-backlight@".enable = false;
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", ATTR{bl_power}="4", ATTR{brightness}="0"
      ACTION=="change", SUBSYSTEM=="power_supply", RUN+="${pkgs.systemd}/bin/systemctl --no-block start homelab-display-reconcile.service"
      ACTION=="add|change", SUBSYSTEM=="drm", RUN+="${pkgs.systemd}/bin/systemctl --no-block start homelab-display-reconcile.service"
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.systemd}/bin/systemctl --no-block start homelab-display-reconcile.service"
    '';
    systemd.tmpfiles.rules = [
      "d ${settings.metrics_dir} 0755 root root -"
    ];
    systemd.services.homelab-display-policy = {
      description = "Serialized Oslo screen and AniMe policy";
      wantedBy = [ "multi-user.target" ];
      after = [
        "asusd.service"
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "asusd.service" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        ExecStart = "${command} serve";
        Restart = "always";
        RestartSec = "1s";
        StateDirectory = "homelab-display-policy";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "homelab-display-policy";
        RuntimeDirectoryMode = "0755";
        # Same-boot restart keeps the status/socket directory; policy is on persistent storage.
        RuntimeDirectoryPreserve = "restart";
        TimeoutStopSec = "10s";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "full";
      };
    };
    systemd.services.homelab-display-reconcile = {
      description = "Request current display policy after host events";
      requires = [ "homelab-display-policy.service" ];
      after = [ "homelab-display-policy.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${command} reconcile";
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };
    systemd.timers.homelab-display-reconcile = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = [
          "*-*-* 23:00:00 Europe/Oslo"
          "*-*-* 08:00:00 Europe/Oslo"
        ];
        OnClockChange = true;
        OnTimezoneChange = true;
        OnBootSec = "5s";
        OnUnitActiveSec = "30s";
        AccuracySec = "1s";
        Persistent = true;
      };
    };
    systemd.services.asusd.postStart = ''
      ${pkgs.systemd}/bin/systemctl --no-block start homelab-display-reconcile.service
    '';
    systemd.services."getty@".postStart = ''
      ${pkgs.systemd}/bin/systemctl --no-block start homelab-display-reconcile.service
    '';
    systemd.services.homelab-display-triggerhappy = {
      description = "Fixed display actions on press (serialized triggerhappy)";
      wantedBy = [ "multi-user.target" ];
      postStart = ''
        while [ ! -S ${thSocket} ]; do ${pkgs.coreutils}/bin/sleep 0.1; done
        chmod 0600 ${thSocket}
      '';
      serviceConfig = {
        ExecStart = "${triggerhappy}/bin/thd --socket ${thSocket} --triggers ${triggers}";
        RuntimeDirectory = "homelab-display-triggerhappy";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "1s";
        TimeoutStartSec = "10s";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
    systemd.services.homelab-display-hotkeys = {
      description = "Reserve display chords and relay ordinary keyboard input";
      wantedBy = [ "multi-user.target" ];
      after = [ "homelab-display-triggerhappy.service" ];
      wants = [ "homelab-display-triggerhappy.service" ];
      serviceConfig = {
        ExecStart = "${package}/bin/display-hotkeys --th-cmd ${triggerhappy}/bin/th-cmd --socket ${thSocket}";
        Restart = "always";
        RestartSec = "1s";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
