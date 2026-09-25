{ pkgs, ... }:
pkgs.runCommand "native-runner-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  cp -r ${../scripts/runner} runner
  python3 runner/test-cache-local.py
  touch "$out"
''
