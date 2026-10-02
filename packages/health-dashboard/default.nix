{
  pkgs,
  ...
}:
let
  inherit (pkgs) lib;
  manifest = (lib.importTOML ./Cargo.toml).package;
in
pkgs.rustPlatform.buildRustPackage {
  pname = manifest.name;
  inherit (manifest) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  doCheck = false;
  postInstall = ''
    wrapProgram "$out/bin/health-collector" --prefix PATH : ${lib.makeBinPath [ pkgs.curl ]}
    wrapProgram "$out/bin/dashboard" --set-default DASHBOARD_RENDERER "$out/bin/health-dashboard"
  '';

  meta = {
    description = "Homelab laptop health dashboard for the Linux console";
    mainProgram = "health-dashboard";
  };
}
