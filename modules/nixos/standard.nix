{
  pkgs,
  lib,
  config,
  ...
}:
let
  initialHashedPassword = "$6$X19Q8OhBkw8xUegs$prAFssd1NxBR1qrdMUhqZX4Xqy02bTeNfCZw24YCMClQhp8Pox65w6PF5w7hV2foKfGytsXTwCB5pQ7FLwF7o/";
  sshKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3/B6lqoz+fG6QqerYS4kMCtrgl+hCvN6OhuXgcG9yCf0QhRfPFuPGqq/X5DgmyZsLAheH5YgaXxmtPnfO3+t4k9JEFgDRr8SB3dDxzfoQJfHi7SGk1dyjJ9CGgTzrc9Kgs1Zvp76NAug3VkPHv+J92oytprFEiBRzLg0HV8NWtFkDiR0TtjLbxt28UAHyD1v0VjjC9WRuzRPiiQonye5Tk3fz6Z9PGItWht+3Jhnvhb6CHxHcio8582w9xRpP9Ho+yFYINgipQDfU2MDcZxIaqnM4tWS0ExTdneIWqWcmP28EyWWQo0DayY/lxp2WIL/AbQ94bjCSzlgy29KVAU13T2ct/m70VGo8xqB3cBhd/bhIQlamGc5D8pS2XipRmPXrdMGW4tkr9k4La0SOkS1kb47solf5K1AXtMgslFh7844+mQbMfYVRbnAtjOMtZjsOmzOwxtVaZLdmYLPSgTZO0a92UXyZRd8/apx+erg+Oak9pHHfp4rZi86/sUue8d8= teemu@DESKTOP-J8H46CI"
  ];
in
{
  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Autologin
  services.getty.autologinUser = lib.mkForce "teevik";

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Networking
  networking = {
    networkmanager.enable = true;
    firewall.enable = false;

    firewall.trustedInterfaces = [ "tailscale0" ];
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets.tailscale_key.path;
    extraUpFlags = [ "--operator=teevik" ];
  };

  # Sops secrets
  sops.defaultSopsFile = ../../secrets.yaml;
  sops.age.keyFile = "/home/teevik/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ ];

  sops.secrets.tailscale_key = { };

  # System user
  users.users.root = {
    inherit initialHashedPassword;
    openssh.authorizedKeys.keys = sshKeys;
  };

  users.users.teevik = {
    isNormalUser = true;
    inherit initialHashedPassword;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = sshKeys;
  };

  # Nix settings
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
