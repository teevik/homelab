{
  config,
  flake,
  inputs,
  lib,
  pkgs,
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

  sops.secrets.tailscale_key = { };
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_key.path;
    extraUpFlags = [
      "--reset"
      "--hostname=homelab"
    ];
  };

  # Share one pull-through Nix cache across the tailnet. Clients validate the
  # original upstream signatures, so ncps intentionally does not re-sign them.
  services.ncps = {
    enable = true;
    package = inputs.ncps.packages.${pkgs.stdenv.hostPlatform.system}.default;
    analytics.reporting.enable = false;
    logLevel = "warn";
    prometheus.enable = true;

    server.addr = ":8501";

    cache = {
      allowDeleteVerb = false;
      allowPutVerb = false;
      cdc.enabled = false;
      hostName = "homelab";
      maxSize = "200G";
      signNarinfo = false;
      storage.local = "/var/lib/ncps";
      tempPath = "/var/lib/ncps/tmp";

      database.pool = {
        maxOpenConns = 1;
        maxIdleConns = 1;
      };

      lru = {
        schedule = "15 4 * * *";
        scheduleTimeZone = "Europe/Oslo";
      };

      upstream = {
        dialerTimeout = "1s";
        responseHeaderTimeout = "1s";
        urls = [
          "https://cache.nixos.org"
          "https://teevik.cachix.org"
          "https://hyprland.cachix.org"
          "https://install.determinate.systems"
          "https://nyx-cache.chaotic.cx"
          "https://cache.numtide.com"
        ];
        publicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "teevik.cachix.org-1:lh2jXPvLIaTNsL8e8gvrI2abYe83tKhV0PmxQOGlitQ="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
          "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
          "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
          "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
          "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
          "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
          "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
          "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
          "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ];
      };
    };
  };

  # The pinned nixpkgs module still calls the removed dbmate-ncps binary.
  # Clear the old 0.9.4 cache once before upgrading; see docs/research/ncps.md.
  systemd.services.ncps.preStart = lib.mkForce ''
    ${lib.getExe config.services.ncps.package} migrate up \
      --cache-database-url=${lib.escapeShellArg config.services.ncps.cache.databaseURL}
  '';

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

  # Enable GPU driver/firmware support (needed for ROCm in containers)
  hardware.graphics.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";
}
