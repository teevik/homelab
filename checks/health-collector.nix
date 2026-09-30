{ pkgs, flake, ... }:
let
  package = flake.packages.${pkgs.stdenv.hostPlatform.system}.health-dashboard;
in
pkgs.runCommand "health-collection-launcher-check" {
  nativeBuildInputs = [ pkgs.python3 pkgs.curl pkgs.coreutils ];
} ''
  python3 ${../scripts/test-health-collector.py} ${package}/bin/health-collector
  python3 ${../scripts/test-dashboard-launcher.py} ${package}/bin/dashboard ${package}/bin/health-dashboard
  touch "$out"
''
