# T3 Code server

`modules/nixos/t3code.nix` runs `t3 serve` as a NixOS service under `teevik`,
so agents see the normal home directory, Nix daemon, git and the system
profile. The package comes from `llm-agents.nix`, whose wrapper adds Claude
Code, Codex, Cursor Agent, Grok and OpenCode to the server's PATH.

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
`--ttl` changes that.

## Provider logins

Agent CLIs keep their credentials in `~/.claude`, `~/.codex` and so on. Log in
once from a T3 terminal on the homelab, or over SSH with the same binaries.

## Updates

`nix flake update llm-agents` bumps T3 Code and the bundled agents. The service
has `restartIfChanged = false`, because a restart kills running agents, including
one that is deploying this host. After `just deploy`, run
`sudo systemctl restart t3code` when no agent is busy.
