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
    flake.nixosModules.anime-matrix
  ];

  # Disk configuration
  disko.devices = import ./disk-config.nix { disks = [ "/dev/nvme0n1" ]; };

  # Networking
  networking.hostName = "homelab";

  # Ignore lid close so the laptop doesn't sleep
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  # ASUS ROG - disable keyboard LEDs, configure AniMe Matrix
  services.asusd = {
    enable = true;
    asusdConfig = {
      text = ''
        (
            charge_control_end_threshold: 80,
            base_charge_control_end_threshold: 80,
            disable_nvidia_powerd_on_battery: true,
            ac_command: "",
            bat_command: "",
            platform_profile_linked_epp: true,
            platform_profile_on_battery: Quiet,
            change_platform_profile_on_battery: true,
            platform_profile_on_ac: Quiet,
            change_platform_profile_on_ac: true,
            profile_quiet_epp: Power,
            profile_balanced_epp: BalancePower,
            profile_custom_epp: Performance,
            profile_performance_epp: Performance,
            ac_profile_tunings: {},
            dc_profile_tunings: {},
            armoury_settings: {},
        )
      '';
    };
    animeConfig = {
      text = ''
        (
            system: [],
            boot: [],
            wake: [],
            shutdown: [],
            display_enabled: true,
            display_brightness: Med,
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

  # AniMe Matrix stats display
  homelab.animeMatrix.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
