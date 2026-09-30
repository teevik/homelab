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

  nativeBuildInputs = [ pkgs.makeWrapper ];
  # Exercise the real API -> snapshot -> derivation -> frame seam during the package check.
  nativeCheckInputs = [ pkgs.python3 pkgs.curl pkgs.coreutils ];
  postCheck = ''
    cargo build --offline --release --example inspect_snapshot
    python3 ${../../scripts/test-health-collector.py} target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/health-collector target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/examples/inspect_snapshot
    python3 ${../../scripts/test-dashboard-launcher.py} target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/dashboard target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/health-dashboard
  '';
  postInstall = ''
    wrapProgram "$out/bin/health-collector" --prefix PATH : ${lib.makeBinPath [ pkgs.curl ]}
    wrapProgram "$out/bin/dashboard" --set-default DASHBOARD_RENDERER "$out/bin/health-dashboard"
  '';

  meta = {
    description = "Homelab laptop health dashboard for the Linux console";
    mainProgram = "health-dashboard";
  };
}
