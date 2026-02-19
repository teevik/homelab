{
  flake,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix

    inputs.disko.nixosModules.disko
    flake.nixosModules.standard
  ];

  # Disk configuration
  disko.devices = import ./disk-config.nix { disks = [ "/dev/sda" ]; };

  # Networking
  networking.hostName = "homelab-1";

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
