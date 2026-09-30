{ pkgs, flake, ... }:
let
  python = pkgs.python3.withPackages (ps: [ ps.evdev ]);
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
pkgs.testers.runNixOSTest {
  name = "display-policy-recovery";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/nixos/anime-matrix.nix ];
    _module.args.flake = flake;
    users.users.teevik = {
      isNormalUser = true;
      uid = 1000;
    };
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
        date -s '2026-10-01 00:00:00 UTC'
      '';
    };
    environment.systemPackages = [ python ];
    environment.etc."display-hotkeys-test.py".source = ../tests/display-hotkeys.py;
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    import json

    machine.start(allow_reboot=True)
    machine.wait_for_unit("homelab-display-policy.service")
    machine.wait_for_unit("homelab-display-hotkeys.service")
    machine.wait_for_unit("homelab-display-triggerhappy.service")
    def status():
        return json.loads(machine.succeed("cat /run/homelab-display-policy/status.json"))
    def action(name):
        return json.loads(machine.succeed("su -s /bin/sh teevik -c 'display-policy " + name + "'"))
    def applied():
        machine.wait_until_succeeds("grep -q '\"application\": \"applied\"' /run/homelab-display-policy/status.json")
    with subtest("dark boot, fixed authorization, gated producer and console ordering"):
        applied()
        assert not status()["screen_on"] and not status()["anime_on"]
        machine.succeed("grep -q '/dev/tty1 --blank force' /run/display-fixture/console-effects")
        machine.succeed("systemctl start anime-matrix-stats.service")
        machine.fail("systemctl is-active anime-matrix-stats.service")
        machine.fail("su -s /bin/sh nobody -c 'display-policy wake'")
        machine.fail("su -s /bin/sh teevik -c 'display-policy reconcile'")
        machine.fail("display-policy suspend")
    with subtest("same boot recovery preserves remaining wake, latest bedtime wins"):
        bedtime = action("bedtime")["bedtime_until"]
        expiry = action("wake")["wake_until"]
        machine.succeed("systemctl restart homelab-display-policy.service")
        applied()
        assert status()["screen_on"] and status()["wake_until"] == expiry
        assert not status()["anime_on"]
        action("bedtime")
        assert not status()["screen_on"] and status()["wake_until"] is None
        action("wake")
        machine.reboot()
        machine.wait_for_unit("homelab-display-policy.service")
        applied()
        assert not status()["screen_on"] and status()["wake_until"] is None
        assert status()["bedtime_until"] == bedtime
        action("resume-schedule")
        assert not status()["screen_on"]
    with subtest("real chords, ordinary input, independent hotkey and asusd recovery"):
        machine.wait_for_unit("homelab-display-hotkeys.service")
        machine.succeed("python3 /etc/display-hotkeys-test.py")
        machine.succeed("systemctl restart homelab-display-triggerhappy.service")
        machine.succeed("systemctl restart homelab-display-hotkeys.service")
        machine.succeed("systemctl restart asusd.service")
        machine.succeed("python3 /etc/display-hotkeys-test.py")
        assert not status()["screen_on"]
        machine.succeed("echo tty2 > /run/display-fixture/sys/class/tty/tty0/active")
        machine.wait_until_succeeds("grep -q '/dev/tty2 --blank force' /run/display-fixture/console-effects")
    with subtest("device failure is reported and periodic recovery succeeds without wake"):
        machine.succeed("echo disconnected > /run/display-fixture/sys/devices/card2-eDP-2/status")
        machine.wait_until_succeeds("grep -q '\"application\": \"failed\"' /run/homelab-display-policy/status.json")
        machine.succeed("grep -q 'homelab_display_policy_failure 1' /var/lib/homelab-display-metrics/display-policy.prom")
        assert not status()["screen_on"]
        machine.succeed("echo connected > /run/display-fixture/sys/devices/card2-eDP-2/status")
        applied()
    with subtest("morning follows current policy; lid and battery restrictions survive"):
        machine.succeed("date -s '2026-10-01 07:00:00 UTC'; display-policy reconcile")
        assert status()["screen_on"] and status()["anime_on"]
        machine.wait_for_unit("anime-matrix-stats.service")
        machine.succeed("systemctl restart anime-matrix-stats.service")
        machine.wait_until_succeeds("grep -qx true /run/display-fixture/anime-display")
        machine.succeed("systemctl kill -s SIGKILL anime-matrix-stats.service")
        machine.wait_until_succeeds("systemctl is-active anime-matrix-stats.service && grep -qx true /run/display-fixture/anime-display")
        machine.succeed("test $(cat /run/display-fixture/sys/devices/card2-eDP-2/panel/brightness) = 1234")
        machine.succeed("echo 'b true' > /run/display-fixture/lid; display-policy reconcile")
        machine.fail("systemctl is-active anime-matrix-stats.service")
        machine.succeed("echo 'b false' > /run/display-fixture/lid; echo 'b false' > /run/display-fixture/ac; display-policy reconcile")
        machine.fail("systemctl is-active anime-matrix-stats.service")
        machine.succeed("echo 'b true' > /run/display-fixture/ac; display-policy reconcile")
        machine.wait_for_unit("anime-matrix-stats.service")
  '';
}
