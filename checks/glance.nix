{ pkgs, ... }:
let
  glance = (import ../kubernetes/glance.nix { }).applications.glance;
  config = pkgs.writeText "glance.json" glance.resources.configMaps.glance-config.data."glance.yml";
in
assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix ":v${pkgs.glance.version}@" glance.resources.deployments.glance.spec.template.spec.containers.glance.image)
  "Run Glance widget checks with the version deployed in the cluster";
pkgs.runCommand "glance-widgets-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${../scripts/test-glance.py} ${pkgs.glance}/bin/glance ${config}
  touch "$out"
''
