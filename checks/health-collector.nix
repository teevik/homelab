{ pkgs, flake, ... }:
let
  package = flake.packages.${pkgs.stdenv.hostPlatform.system}.health-dashboard;
  panicPackage = package.overrideAttrs (old: {
    pname = "health-dashboard-panic-fixture";
    cargoBuildFlags = (old.cargoBuildFlags or [ ]) ++ [ "--features" "test-panic" ];
    doCheck = false;
  });
in
pkgs.runCommand "health-collection-launcher-check" {
  nativeBuildInputs = [ pkgs.python3 pkgs.curl pkgs.coreutils ];
} ''
  python3 ${../scripts/test-health-collector.py} ${package}/bin/health-collector
  python3 ${../scripts/test-health-scheduling.py} ${package}/bin/health-collector
  python3 ${../scripts/test-dashboard-launcher.py} ${package}/bin/dashboard ${package}/bin/health-dashboard ${panicPackage}/bin/health-dashboard
  touch "$out"
''
