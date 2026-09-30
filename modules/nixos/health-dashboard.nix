{ config, flake, lib, pkgs, ... }:
let
  cfg = config.homelab.healthDashboard;
  package = flake.packages.${pkgs.stdenv.hostPlatform.system}.health-dashboard;
  catalog = import ../../catalog-lib.nix {
    applications = flake.nixidyEnvs.${pkgs.stdenv.hostPlatform.system}.homelab.config.applications;
  };
  credentialDirectory = "/run/homelab-health-credentials";
  settings = {
    catalog = "/etc/homelab/health-catalog.json";
    snapshot = "/run/homelab-health/snapshot.json";
    state = "/var/lib/homelab-health/state.json";
    credential = "${credentialDirectory}/credential.json";
    controller_report = "/run/homelab-display-policy/status.json";
    night = "/run/homelab-health/night.json";
    inherit (catalog) namespaces;
  };
  renew = pkgs.writeShellApplication {
    name = "renew-health-credential";
    runtimeInputs = [ pkgs.kubectl pkgs.python3 pkgs.coreutils ];
    text = ''
      umask 027
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      temporary=$(mktemp ${credentialDirectory}/credential.XXXXXX)
      trap 'rm -f "$temporary"' EXIT
      kubectl --request-timeout=5s -n victoria-metrics create token dashboard-collector --duration=1h \
        | python3 -c 'import json,sys; json.dump({"token":sys.stdin.read().strip(),"ca":"${credentialDirectory}/ca.crt"},sys.stdout)' > "$temporary"
      test -s "$temporary"
      install -m 0640 -o root -g health-collector /var/lib/rancher/k3s/server/tls/server-ca.crt ${credentialDirectory}/ca.new
      mv ${credentialDirectory}/ca.new ${credentialDirectory}/ca.crt
      chown root:health-collector "$temporary"
      chmod 0640 "$temporary"
      mv "$temporary" ${credentialDirectory}/credential.json
    '';
  };
in
{
  options.homelab.healthDashboard.enable = lib.mkEnableOption "production health collection and tty1 dashboard";
  config = lib.mkIf cfg.enable {
    assertions = [ {
      assertion = config.users.users.teevik.shell == pkgs.bashInteractive;
      message = "The dashboard login hook is for the evaluated teevik Bash shell; update it if that shell changes.";
    } ];
    users.groups.health-collector = { };
    users.users.health-collector = { isSystemUser = true; group = "health-collector"; };
    environment.systemPackages = [ package ];
    environment.etc."homelab/health-catalog.json".text = builtins.toJSON catalog.dashboard;
    environment.etc."homelab/health-collector.json".text = builtins.toJSON settings;
    systemd.tmpfiles.rules = [ "d ${credentialDirectory} 0750 root health-collector -" ];
    systemd.services.homelab-health-collector = {
      description = "Independent host and scoped cluster health collector";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${package}/bin/health-collector --config /etc/homelab/health-collector.json";
        User = "health-collector";
        Group = "health-collector";
        Restart = "always";
        RestartSec = "2s";
        RuntimeDirectory = "homelab-health";
        RuntimeDirectoryMode = "0755";
        StateDirectory = "homelab-health";
        StateDirectoryMode = "0700";
        UMask = "0022";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };
    };
    systemd.services.homelab-health-credential = {
      description = "Atomically renew the namespace-scoped service-proxy credential";
      after = [ "k3s.service" "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe renew;
        TimeoutStartSec = "15s";
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "60s";
      };
    };
    systemd.timers.homelab-health-credential = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "5s"; OnUnitActiveSec = "15m"; AccuracySec = "1s"; };
    };
    services.getty = { autologinUser = "teevik"; autologinOnce = true; };
    # NixOS implements autologinOnce using a per-boot marker; other VTs remain authenticated.
    programs.bash.interactiveShellInit = ''
      if shopt -q login_shell && [[ $(${pkgs.coreutils}/bin/id -un) == teevik && -z ''${SSH_CONNECTION-} && -z ''${SSH_TTY-} && -z ''${HOMELAB_DASHBOARD_SESSION-} ]] \
          && [[ $(${pkgs.coreutils}/bin/tty) == /dev/tty1 ]]; then
        export HOMELAB_DASHBOARD_SESSION=1
        ${package}/bin/dashboard
      fi
    '';
    console = {
      # Pinned CP437 16x32 Terminus, 256 glyphs: preserves sixteen foreground slots.
      font = "${pkgs.terminus_font}/share/consolefonts/ter-i32b.psf.gz";
      colors = [
        "45475a" "f38ba8" "a6e3a1" "f9e2af" "89b4fa" "f5c2e7" "94e2d5" "bac2de"
        "585b70" "f38ba8" "a6e3a1" "f9e2af" "89b4fa" "f5c2e7" "94e2d5" "a6adc8"
      ];
    };
  };
}
