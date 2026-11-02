# T3 Code server

`modules/nixos/t3code.nix` runs `t3 serve` as a NixOS service under `teevik`,
so agents see the normal home directory, Nix daemon, git and the system
profile. The default package comes from `llm-agents.nix`, whose wrapper adds
Claude Code, Codex, Cursor Agent, Grok and OpenCode to the server's PATH.
`just deploy` builds this host through
[teevik/Config](https://github.com/teevik/Config), which replaces it with the
desktop's T3 Code nightly, so the server and its agent CLIs match the desktop.

The server listens on `127.0.0.1:3773`. On start it publishes itself with
Tailscale Serve at <https://homelab.tail84b6c.ts.net>, so it is tailnet-only and
has real HTTPS. `teevik` is a Tailscale operator for that reason. State lives in
`~/.t3`.

## Pairing a device

Every browser or desktop client needs a one-time token:

```sh
ssh homelab t3 pair --tailscale --label phone
```

`--tailscale` makes it print the tailnet URL instead of the loopback one. Open
it (or scan the QR code) on the device. Tokens expire after five minutes;
`--ttl` changes that. A token works once: opening the URL in a browser spends
it, so give a desktop app a fresh token instead of one already clicked.

## Provider logins

Agent CLIs keep their credentials in `~/.claude`, `~/.codex` and so on. Log in
once from a T3 terminal on the homelab, or over SSH with the same binaries.

## GitHub access

`githubTokenSecret` names a SOPS secret, here `t3code_github_token`: a
fine-grained token for `teevik/Config` only, with read and write access to
contents and pull requests. It reaches the server's environment as `GH_TOKEN`,
not login shells, and git pushes over HTTPS authenticate through `gh`. Agents
commit as `teevik`. Rotate it with `sops secrets.yaml`, then deploy and restart
the service.

## Updates

Config's `flake.lock` pins T3 Code and the bundled agents: update Config, then
run `just deploy` here or `just deploy-homelab` in Config. The service
has `restartIfChanged = false`, because a restart kills running agents, including
one that is deploying this host. After `just deploy`, run
`sudo systemctl restart t3code` when no agent is busy.
