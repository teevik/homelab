{
  pkgs,
  ...
}:
pkgs.buildGoModule {
  pname = "anime-matrix-stats";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-CDeHiW+wQPSaJDad5rPqAtIJ3wDsdlho/XLwYAn7Cg0=";

  meta = {
    description = "Display Kubernetes cluster stats on ASUS ROG AniMe Matrix";
    mainProgram = "anime-matrix-stats";
  };
}
