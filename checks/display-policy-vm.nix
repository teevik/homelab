{ pkgs, flake, ... }:
pkgs.testers.runNixOSTest {
  name = "display-policy-recovery";
  nodes.machine = import ../tests/nixos/display-fixture.nix { inherit pkgs flake; };

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
        # If the fixture did not initialize RTC before setting night, this
        # registration restores host daytime and the dark-boot assertion fails.
        machine.succeed("modprobe rtc_cmos; display-policy reconcile")
        applied()
        assert not status()["screen_on"] and not status()["anime_on"]
        machine.succeed("grep -q '/dev/tty1 --blank force' /run/display-fixture/console-effects")
        # The gate can skip this forbidden start, or periodic reconciliation can
        # cancel its job. Assert the producer stays inactive in either case.
        machine.execute("systemctl start anime-matrix-stats.service")
        machine.wait_until_succeeds("test $(systemctl show --value --property=ActiveState anime-matrix-stats.service) = inactive")
        machine.fail("su -s /bin/sh nobody -c 'display-policy wake'")
        machine.fail("su -s /bin/sh teevik -c 'display-policy reconcile'")
        machine.fail("display-policy suspend")
    with subtest("same boot recovery preserves remaining wake, latest bedtime wins"):
        bedtime = action("bedtime")["bedtime_until"]
        wake = action("wake")
        expiry = wake["wake_until"]
        deadline = wake["persisted"]["wake_deadline"]
        machine.succeed("systemctl restart homelab-display-policy.service")
        applied()
        recovered = status()
        assert recovered["screen_on"]
        assert recovered["persisted"]["wake_deadline"] == deadline
        # Wall/boot clocks are sampled separately; preserve the exact boot
        # deadline and allow subsecond sampling skew in the displayed expiry.
        assert abs(recovered["wake_until"] - expiry) < 1
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
