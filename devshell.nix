{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem.nixidy.default
    pkgs.kubernetes-helm
    (pkgs.python3.withPackages (p: [ p.pyyaml ]))
    pkgs.kubectl
    pkgs.argocd
    pkgs.sops
    pkgs.age
  ];
}
