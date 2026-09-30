{ pkgs, flake, ... }:
let
  generated = import ../catalog-lib.nix {
    inherit (pkgs) lib;
    applications = flake.nixidyEnvs.${pkgs.system}.homelab.config.applications;
  };
  variant = import ../catalog-lib.nix {
    applications = flake.nixidyEnvs.${pkgs.system}.homelab.config.applications;
    services = (import ../service-catalog.nix) // {
      fixture = {
        name = "Fixture";
        url = "https://fixture.example";
        target = "http://fixture.fixture.svc";
        icon = "si:nixos";
        app = null;
        order = 16;
        statuses = [ 200 202 ];
        timeout = 4;
      };
    };
  };
in
pkgs.runCommand "health-catalog-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${../scripts/test-health-catalog.py} ${pkgs.writeText "catalog-consumers.json" (builtins.toJSON (generated // { inherit variant; }))}
  touch "$out"
''
