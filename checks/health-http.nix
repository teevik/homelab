{ pkgs, ... }:
let
  catalog = import ../catalog-lib.nix { };
  config = pkgs.writeText "health-http-consumers.json" (builtins.toJSON catalog);
in
assert pkgs.prometheus-blackbox-exporter.version == "0.28.0";
assert pkgs.glance.version == "0.8.5";
pkgs.runCommand "health-http-check" {
  nativeBuildInputs = [ pkgs.python3 pkgs.openssl ];
} ''
  python3 ${../scripts/test-health-http.py} ${pkgs.glance}/bin/glance ${pkgs.prometheus-blackbox-exporter}/bin/blackbox_exporter ${config}
  touch "$out"
''
