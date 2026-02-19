{
  flake,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix

    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    flake.nixosModules.standard
    flake.nixosModules.kubernetes
  ];

  homelab.kubernetes.enable = true;

  # Disk configuration
  disko.devices = import ./disk-config.nix { disks = [ "/dev/nvme0n1" ]; };

  # Networking
  networking.hostName = "homelab-1";

  # Ignore lid close so the laptop doesn't sleep
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
