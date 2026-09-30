# Independent laptop display policy

Implementation of [#75](https://github.com/teevik/homelab/issues/75), following
[#72](https://github.com/teevik/homelab/issues/72). This prepares configuration and
isolated tests; it does not authorize deployment, reboot, or display-power changes
on the production laptop. Actual-laptop acceptance belongs to the validation
ticket. Simulated writes and a passing VM are not physical darkness evidence.

## Ownership and commands

`homelab-display-policy.service` owns panel and AniMe policy independently of the
renderer, collector, login session and Kubernetes. It never suspends the host.
The existing logind lid-ignore configuration and unrelated ASUS controls remain.

From an authorized SSH session as `teevik` (or root):

```sh
display-policy bedtime
display-policy wake
display-policy resume-schedule
```

The kernel authenticates each socket peer UID. Only root and the account resolved
as `teevik` may submit those three fixed requests; no command, path or device
argument is accepted. Root-only `reconcile` is used by host event hooks and timers.
The account retains its pre-existing administrative sudo access. These commands
do not claim isolation from the owner or from root.

Reserved chords, available at the UI, shell and login prompt:

| Chord | Request |
| --- | --- |
| Ctrl+Alt+Home | Bedtime until the next local 08:00 |
| Ctrl+Alt+End | Ten-minute screen-only wake |
| Ctrl+Alt+Insert | Clear both overrides and resume the current schedule |

Either Ctrl/Alt side works. The laptop's Fn combination may be needed to generate
Home, End or Insert. Confirm the actual keys during physical acceptance.
`homelab-display-hotkeys.service` exclusively grabs keyboard devices with normal
letter/modifier capabilities and relays ordinary events through uinput. It
consumes the reserved key from press through repeat/release, while forwarding the
modifiers and all other keys, including Ctrl+C and Ctrl+Alt+Fn VT switching.
Pointing devices and separate power-button devices are not grabbed.
Triggerhappy exclusively reads a separate virtual fixed-action device. Only
press (`1`) has bindings; hold (`2`) does not renew wake. Its small reproducible
patch runs commands synchronously so successive chords cannot reorder forked
clients. Only these host services open input devices; the renderer needs none.

Both hotkey services restart independently. The relay reattaches its action
device when triggerhappy's socket is replaced. On relay exit the kernel releases
its grabs and removes its synthetic keyboard; ordinary physical input remains
available. A new relay mirrors already-held ordinary keys without synthesizing
a bedtime/wake action. Overflow/hot-unplug rebuilds the affected keyboard.

## Time, state and recovery

Darkness is 23:00 inclusive–08:00 exclusive, **Europe/Oslo**. Bedtime expires at
the next local 08:00, calculated with IANA timezone data across both DST changes.
New bedtime cancels wake. Wake during applicable darkness illuminates only the
panel and resets a ten-minute **CLOCK_BOOTTIME** deadline. The boot identity and
deadline survive controller recovery; actual reboot discards wake. Wall-clock
corrections recompute the reported wake expiry without extending its duration.
Resume at 02:00 stays dark. At wake expiry after 08:00, current daytime policy
wins. Requests and effects run on one serialized loop, guarded against a second
controller process.

Overrides are atomically persisted and fsynced in
`/var/lib/homelab-display-policy/policy.json` before device application. Intended
daytime brightness is saved separately. Corrupt policy fails closed and remains
reported as a failure until an administrator repairs the state and restarts the
controller; it is not silently erased by a reboot or request.

Calendar, clock/timezone changes, udev power/display events and asusd/getty startup
request reconciliation, rather than unconditional switching. The controller
also observes active VT, AC and lid state every half-second and reconciles every
five seconds as recovery for missed events. Expired overrides and schedule
changes are checked on each loop. Nothing treats ordinary input, shell output,
alerts, refreshes or UI exit as a wake request.

## Device application and baseline

Read-only inspection on 2026-09-30 found a connected `card2-eDP-2` on amdgpu,
backlight `amdgpu_bl2`, `bl_power=0`, brightness `3122`, actual brightness `3084`,
and maximum `65535`, running kernel `6.18.44`. Runtime discovery resolves the
backlight's connected eDP parent; it rejects absent or ambiguous devices rather
than guessing a card number. This establishes an interface, **not** effective
panel-off behavior. Initial daytime brightness is 3122; a saved nonzero daytime
level takes precedence.

Udev starts backlights with power 4 and brightness 0; uncontrolled systemd
backlight restoration is masked. The controller saves a nonzero brightness,
applies both `bl_power=4` and brightness 0, and verifies control readback before
calling `setterm --blank force` on the explicitly discovered active `/dev/ttyN`.
Console transitions, including permitted unblanking, happen while the backlight
is off. Only permitted policy restores the saved brightness and power 0.
Readback failure is reported; no black image substitutes for power control.

The effective root nixpkgs is `e5bdc4a41d4c072fe1e3787eaa0320a384741d44` and its
asusctl is **6.3.8**, corroborated by the booted executable's store path. This is
the corrected baseline from [#64](https://github.com/teevik/homelab/issues/64#issuecomment-5911553019).
In [6.3.8's AniMe handlers](https://github.com/OpenGamingCollective/asusctl/blob/6.3.8/asusd/src/aura_anime/trait_impls.rs),
lid-open/AC callbacks can enable display without checking `display_enabled`, and
reload can enable before applying disabled state. The Off setter sends a zero
brightness packet and disables display. Therefore startup defaults are Off plus
disabled, and runtime darkness separately requests `--brightness off`, then
`--enable-display false`. This remains a candidate defense needing physical
verification. Unrelated asusd functions are retained.

The stats producer no longer enables display at startup. It has no boot target
when policy is enabled. Before darkness the controller revokes the permission,
stops the producer and applies Off plus disabled. Its `ExecCondition` rechecks
current time, boot identity, overrides, recent permission and logind lid/AC state,
so independent starts/restarts cannot bypass night policy. Daytime restoration
grants producer permission only on external power with the lid open, waits for
producer startup, then uses Med plus enabled. Reconciliation compares systemd
state and invocation identities for both producer and asusd; independent
restart/crash recovery invalidates cached AniMe state. Restoration follows the
old producer’s stop hooks so they cannot disable a just-restored display. Lid/battery restrictions are preserved.
Failed stop/AniMe operations do not prevent independent panel-off attempts.

## Frontend contract and monitoring

Read `/run/homelab-display-policy/status.json` without privileges. It is atomic,
versioned (`version: 1`), and contains:

- `observed_at` (Unix wall timestamp), `boot_id`;
- `mode`: `schedule`, `bedtime` or `wake`;
- `scheduled_dark`, `schedule_until`, `bedtime_until`, `wake_until` (Unix timestamps or null);
- `screen_on`, `anime_on`: **intended policy**, not physical observations;
- `application`: `applied` (commands/readbacks succeeded) or `failed`;
- `failures`: reasons, including policy storage and device application failures.

The `persisted` member is diagnostic state, not a renderer write API. The frontend
must check the current boot and sample age; absent/disconnected or older-than-15s
state is unavailable, never a successful current application. Format expiries in
Europe/Oslo and label temporary wake screen-only. `schedule_until` is the next
scheduled 23:00 or 08:00 boundary. `applied` is not a claim of
physical darkness. Daytime `anime_on` remains subject to lid/AC restrictions.

State changes/failures go to the journal and atomic node-exporter textfile metrics
in `/var/lib/homelab-display-metrics`. Existing VictoriaMetrics node-exporter reads
them through its read-only host-root mount. `HomelabDisplayControlFailed` reports
known failures; `HomelabDisplayControllerUnavailable` reports missing/old
reconciliation. Reporting invokes no display operation. Use SSH/journal/status to
investigate without illuminating the laptop.

## Automated checks

```sh
nix build --no-link .#checks.x86_64-linux.display-policy
nix build --no-link .#checks.x86_64-linux.display-policy-vm
just check
```

The approved deterministic policy/recording-device seam checks Oslo edges/DST,
expiry, renewal, cancellation, missed/clock events, same-boot/reboot state,
persistence before effects, producer gating and off-before-console ordering.
The disposable NixOS VM runs the real module, controller, producer gate, relay
and triggerhappy against simulated panel/ASUS/time boundaries. It verifies
fixed-command authorization, reboot/recovery, keyboard consumption/ordinary
input, hotkey/asusd/VT recovery and failure reporting. It contains no renderer or
collector dependency and uses no production secrets.

## Actual-laptop acceptance procedure (not executed)

Obtain separate rollout/power-action authorization through the validation ticket.
Record the booted configuration, kernel, asusctl version, eDP/backlight interfaces,
observer, local time, physical conditions and result for every case below. Observe
the panel/backlight and AniMe directly in a dark room; successful sysfs/asusctl
writes, black pixels, polling/retries and simulated evidence do not pass.

1. Observe normal daytime brightness/producer on AC with lid open. Establish the
   intended brightness and check it restores after darkness and device recovery.
2. Test just before/at 23:00 and just before/at 08:00 Oslo, plus early bedtime and
   bedtime after 08:00. Confirm services, collection and monitoring continue.
3. While dark, type/move the mouse, refresh/induce an alert, Ctrl+C to the shell,
   print text, switch all text VTs and return to tty1. Confirm continuous physical
   panel/AniMe darkness, with no visible flash during transitions.
4. Use all three **real chords** at the dashboard, usable shell and authenticated
   login prompt; confirm no chord key leaks escape sequences or actions into the
   shell, repeats do not invoke requests, and ordinary input/Ctrl+C/VT switching
   still work. Repeat all three SSH requests. Verify actual Home/End/Insert Fn keys.
5. Wake during darkness: screen-only for ten minutes, repeat press renews, bedtime
   cancels, resume at night stays dark. Cover wake expiry across 08:00. Recover the
   controller in the same boot, then reboot while bedtime plus wake are active:
   remaining wake survives only same boot and bedtime survives reboot.
6. During scheduled darkness and bedtime, open/close the lid, unplug/replug AC,
   restart/reload asusd, attempt producer restart, recover the controller and both
   hotkey services, restart getty, reconnect/reinitialize the display and boot at
   night. Observe **no panel or AniMe flash once OS controls are available**.
   Record firmware/early-boot illumination separately within the approved boundary.
7. During daytime, repeat lid/battery events and confirm AniMe remains restricted
   and returns only when permitted. Verify screen-only wake never turns AniMe on
   while darkness applies. Verify intended daytime brightness after all events.
8. Simulate/observe unsupported device control and controller/producer faults
   under controlled validation conditions. Confirm failure/status/monitoring
   evidence without an intentional panel wake, and independent service recovery.

Unsupported effective panel control **fails acceptance**. Visible AniMe flashes
with Off plus disabled **fail acceptance and require a policy-aware asusd fix**
before the full system is accepted. Do not accept delayed correction by polling.
Record resource/soak measurements for the added controller/relay/triggerhappy stack
as part of whole-dashboard validation; there is no invented numeric budget.
