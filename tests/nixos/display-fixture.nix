{ pkgs, flake, python ? pkgs.python3.withPackages (ps: [ ps.evdev ]), ... }:
let
  fakeAsus = pkgs.writeShellScriptBin "asusctl" ''
    echo "$*" >> /run/display-fixture/asus-effects
    case "$*" in
      "anime --enable-display false"|"anime --brightness off") echo false > /run/display-fixture/anime-display ;;
      "anime --enable-display true") echo true > /run/display-fixture/anime-display ;;
    esac
  '';
  fakeBus = pkgs.writeShellScript "busctl" ''
    if [ "''${@: -1}" = LidClosed ]; then
      cat /run/display-fixture/lid
    else
      cat /run/display-fixture/ac
    fi
  '';
  fakeConsole = pkgs.writeShellScript "setterm" ''
    test "$(cat /run/display-fixture/sys/devices/card2-eDP-2/panel/bl_power)" = 4
    test "$(cat /run/display-fixture/sys/devices/card2-eDP-2/panel/brightness)" = 0
    echo "$(readlink /proc/self/fd/0) $*" >> /run/display-fixture/console-effects
  '';
in
{ lib, ... }: {
    imports = [ ../../modules/nixos/anime-matrix.nix ];
    _module.args.flake = flake;
    users.users.teevik = {
      isNormalUser = true;
      uid = 1000;
    };
    # Force the late RTC registration that reset the fixture clock in CI.
    # An explicit modprobe still works; udev must not win this ordering race.
    boot.blacklistedKernelModules = [ "rtc_cmos" ];
    services.asusd.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "ignore";
    # Stub only device/time boundaries; controller, producer gate and hotkeys are real.
    systemd.services.asusd.serviceConfig = {
      Type = lib.mkForce "simple";
      BusName = lib.mkForce "";
      ExecStartPre = lib.mkForce [ "" ];
      ExecStart = lib.mkForce [
        ""
        "${pkgs.coreutils}/bin/sleep infinity"
      ];
    };
    homelab.animeMatrix.enable = true;
    homelab.displayPolicy = {
      enable = true;
      settings = {
        sys = "/run/display-fixture/sys";
        proc = "/run/display-fixture/proc";
        asusctl = "${fakeAsus}/bin/asusctl";
        busctl = toString fakeBus;
        setterm = toString fakeConsole;
      };
    };
    # Make socket initialization lag behind exec so readiness ordering is tested
    # deterministically, including after controller restart and reboot.
    systemd.services.homelab-display-policy.serviceConfig.ExecStart = lib.mkForce (
      pkgs.writeShellScript "delayed-display-policy" ''
        ${pkgs.coreutils}/bin/sleep 3
        exec ${flake.packages.${pkgs.system}.display-policy}/bin/display-policy serve
      ''
    );
    # Preserve the actual service/gate, swapping only the external device command.
    systemd.services.anime-matrix-stats.serviceConfig.ExecStart = lib.mkForce "${
      flake.packages.${pkgs.system}.anime-matrix-stats
    }/bin/anime-matrix-stats --interval=1s --asusctl=${fakeAsus}/bin/asusctl";
    systemd.services.anime-matrix-stats.serviceConfig.ExecStopPost =
      lib.mkForce "${fakeAsus}/bin/asusctl anime --enable-display false";
    systemd.services.display-fixture = {
      before = [ "homelab-display-policy.service" ];
      requiredBy = [ "homelab-display-policy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/display-fixture/sys/{devices/card2-eDP-2/panel,class/backlight,class/tty/tty0}
        echo connected > /run/display-fixture/sys/devices/card2-eDP-2/status
        echo 1234 > /run/display-fixture/sys/devices/card2-eDP-2/panel/brightness
        echo 65535 > /run/display-fixture/sys/devices/card2-eDP-2/panel/max_brightness
        echo 0 > /run/display-fixture/sys/devices/card2-eDP-2/panel/bl_power
        ln -s /run/display-fixture/sys/devices/card2-eDP-2/panel /run/display-fixture/sys/class/backlight/panel
        echo tty1 > /run/display-fixture/sys/class/tty/tty0/active
        echo 'b false' > /run/display-fixture/lid
        echo 'b true' > /run/display-fixture/ac
        # RTC registration calls rtc_hctosys and can overwrite an earlier date.
        # Complete it before installing the deterministic night clock.
        ${pkgs.kmod}/bin/modprobe rtc_cmos
        date -s '2026-10-01 00:00:00 UTC'
      '';
    };
    environment.systemPackages = [ python ];
    environment.etc."display-hotkeys-test.py".source = ../display-hotkeys.py;
    virtualisation.memorySize = 1024;
  }
