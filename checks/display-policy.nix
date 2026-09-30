{ pkgs, ... }:
pkgs.runCommand "display-policy-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.evdev
        ps.mypy
      ]))
    ];
    PYTHONTZPATH = "${pkgs.tzdata}/share/zoneinfo";
  }
  ''
    cp -r ${../packages/display-policy} source
    chmod -R u+w source
    cd source
    mypy --check-untyped-defs --ignore-missing-imports policy.py devices.py daemon.py hotkeys.py
    python3 -m unittest discover -v
    touch $out
  ''
