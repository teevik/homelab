{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem.nixidy.default
    pkgs.kubectl
  ];
}
