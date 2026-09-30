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
      ./tests
      ./examples
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Homelab laptop health dashboard for the Linux console";
    mainProgram = "health-dashboard";
  };
}
