{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.kubernetes;
in
{
  options.homelab.kubernetes = {
    enable = lib.mkEnableOption "Kubernetes via k3s";
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = "server";
      extraFlags = toString [
        "--disable=traefik" # Manage ingress via nixidy instead
      ];
    };

    networking.firewall.allowedTCPPorts = [
      6443 # Kubernetes API
    ];
  };
}
