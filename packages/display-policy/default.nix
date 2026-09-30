{ pkgs, ... }:
let
  lib = pkgs.lib;
  python = pkgs.python3.withPackages (ps: [ ps.evdev ]);
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "display-policy";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    mkdir -p $out/lib/display-policy $out/bin
    cp policy.py devices.py daemon.py hotkeys.py $out/lib/display-policy/
    makeWrapper ${python}/bin/python3 $out/bin/display-policy \
      --add-flags "$out/lib/display-policy/daemon.py" \
      --set PYTHONTZPATH ${pkgs.tzdata}/share/zoneinfo
    makeWrapper ${python}/bin/python3 $out/bin/display-hotkeys \
      --add-flags "$out/lib/display-policy/hotkeys.py"
  '';
  meta = {
    description = "Independent homelab screen and AniMe night policy";
    mainProgram = "display-policy";
    platforms = lib.platforms.linux;
  };
}
