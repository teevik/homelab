{ pkgs, ... }:
pkgs.runCommand "private-nix-cache-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    mkdir scripts
    cp ${../scripts/nix-cache-command.py} scripts/nix-cache-command.py
    cp ${../scripts/test-nix-cache.py} scripts/test-nix-cache.py
    python3 scripts/test-nix-cache.py
    touch "$out"
  ''
