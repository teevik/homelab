{ pkgs, ... }:
pkgs.runCommand "amp-supervisor-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${../scripts/test-amp.py} ${../images/amp/entrypoint.py}
  touch "$out"
''
