{ pkgs, flake, ... }:
let
  cfg = flake.nixosConfigurations.homelab.config;
in
pkgs.runCommand "native-client-trust-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      cfg.nix.package
    ];
    NIX_CONFIG =
      cfg.systemd.services.github-runner-config-nightly.environment.NIX_CONFIG
      + "\nextra-experimental-features = nix-command\n";
  }
  ''
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export NIX_CONF_DIR="$TMPDIR/nix-conf"
    mkdir -p "$NIX_CONF_DIR"
    cp -r ${../scripts/runner} runner
    python3 runner/test-client-trust.py
    touch "$out"
  ''
