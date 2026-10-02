# Laptop health dashboard

The laptop automatically logs in as `teevik` on tty1 once per boot and opens the
dashboard. Later authenticated tty1 logins also open it. Press **Ctrl+C** to
return to the shell; `q` is ignored. Run `dashboard` to open it again. SSH
sessions and other consoles do not launch it automatically.

**ALL CLEAR** means every source is current, with no signals or coverage gaps.
**ATTENTION** means at least one signal is known. **UNKNOWN** means there are no
known signals, but data is missing or unavailable. Losing data retains known
signals. Recoveries stay visible for 15 minutes.

Host readings update every five seconds; HTTP checks, apps and alerts update
every 30 seconds. The collector and display controller keep running when the
dashboard exits. Neither suspends the laptop.

For an illustrative preview, run `dashboard demo normal`, `dashboard demo mixed`
or `dashboard demo monitoring-down`. Ctrl+C returns to the shell.

## Display controls

These shortcuts work from the dashboard, shell or login prompt. The keyboard's
Fn combination may be needed for Home, End or Insert.

| Shortcut | Action |
| --- | --- |
| Ctrl+Alt+Home | Away mode: panel and AniMe display off until explicitly resumed |
| Ctrl+Alt+End | Wake the panel for ten minutes, leaving AniMe off during darkness |
| Ctrl+Alt+Insert | Clear overrides and resume the current schedule |

Away mode survives mornings, controller restarts and reboots. Ordinary typing
does not cancel it. After a temporary wake, both displays return to darkness
while away mode is active. A reboot cancels the temporary wake.

The normal schedule is dark from **23:00 to 08:00, Europe/Oslo**. Resuming during
those hours leaves the displays dark. AniMe also requires external power and
an open lid.

The same actions are available locally or over SSH as `teevik`:

```sh
display-policy away
display-policy wake
display-policy resume-schedule
display-policy bedtime          # off until the next 08:00; does not clear away
```

To set this laptop's panel to about 50%, while the schedule permits it to be on:

```sh
echo 32768 | sudo tee /sys/class/backlight/amdgpu_bl2/brightness
```

The controller saves the nonzero brightness when turning the panel off and
restores it when permitted. Changing brightness does not cancel away mode.

## Troubleshooting

```sh
systemctl status homelab-health-collector homelab-display-policy homelab-display-hotkeys
journalctl -u homelab-health-collector -u homelab-health-credential -u homelab-display-policy --since '1 hour ago'
cat /run/homelab-display-policy/status.json
```

The dashboard reads `/etc/homelab/health-catalog.json` and the collector's
`snapshot.json` and `night.json` under `/run/homelab-health`. Credential renewal
runs every 15 minutes; credentials under `/run/homelab-health-credentials` are
private to root and the collector. The renderer has no credentials or device
control.

Away state is stored in `/var/lib/homelab-display-policy/policy.json`.
Before downgrading to a controller without away support, decide whether to clear
away mode, stop the controller, back up that file, and atomically remove only its
`away` key while preserving root ownership and mode 0600. Older controllers
reject that key even when false; resuming alone does not remove it. Switch to
the older configuration only after conversion, then verify its display policy.
