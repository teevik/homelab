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

  # Disk configuration
  disko.devices = import ./disk-config.nix { disks = [ "/dev/nvme0n1" ]; };

  # Networking
  networking.hostName = "homelab-3";

  # Ignore lid close so the laptop doesn't sleep
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  # ASUS ROG - disable keyboard LEDs and AniMe Matrix
  services.asusd = {
    enable = true;
    animeConfig = {
      text = ''
        (
            system: [],
            boot: [],
            wake: [],
            shutdown: [],
            display_enabled: false,
            display_brightness: Off,
            builtin_anims_enabled: false,
            off_when_unplugged: true,
            off_when_suspended: true,
            off_when_lid_closed: true,
            brightness_on_battery: Off,
            builtin_anims: (
                boot: GlitchConstruction,
                awake: BinaryBannerScroll,
                sleep: BannerSwipe,
                shutdown: GlitchOut,
            ),
        )
      '';
    };
  };

  # Turn off keyboard backlight via sysfs at boot
  systemd.tmpfiles.rules = [
    "w /sys/class/leds/asus::kbd_backlight/brightness - - - - 0"
  ];

  # Join existing HA cluster
  homelab.kubernetes.serverAddr = "https://homelab-1:6443";

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
