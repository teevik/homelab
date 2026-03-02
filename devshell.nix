{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem.nixidy.default
    pkgs.kubectl
    pkgs.argocd
    pkgs.sops
    pkgs.age
  ];
}
