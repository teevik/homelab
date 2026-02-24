{
  pkgs,
  ...
}:
pkgs.buildGoModule {
  pname = "anime-matrix-stats";
  version = "0.1.0";

  src = ./.;

  vendorHash = null;

  meta = {
    description = "Display server CPU, memory and disk stats on ASUS ROG AniMe Matrix";
    mainProgram = "anime-matrix-stats";
  };
}
