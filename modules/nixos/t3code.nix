{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.t3code;
  user = config.users.users.${cfg.user};
in
{
  options.homelab.t3code = {
    enable = lib.mkEnableOption "the T3 Code server, published on the tailnet";
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
      description = "T3 Code build; its wrapper puts the agent CLIs on PATH.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "teevik";
      description = "Account the server and its agents run as.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback port Tailscale Serve proxies to.";
    };
  };

  config = lib.mkIf cfg.enable {
    # T3 publishes itself with `tailscale serve`; operators may change serve
    # config without root. The account already has passwordless sudo.
    services.tailscale.extraSetFlags = [ "--operator=${cfg.user}" ];

    # The same agent builds the wrapper uses, so `claude login` and
    # `codex login` work over SSH.
    environment.systemPackages = [
      cfg.package
      pkgs.git
    ]
    ++ cfg.package.providerPackages;

    systemd.services.t3code = {
      description = "T3 Code server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
        "tailscaled-set.service"
      ];
      wants = [ "network-online.target" ];

      # Agents get the same tools as a login shell: system and per-user
      # profiles, setuid wrappers, Nix, git and the Tailscale CLI for Serve.
      path = [
        "/run/wrappers"
        "/etc/profiles/per-user/${cfg.user}"
        "/run/current-system/sw"
        config.nix.package
        config.services.tailscale.package
        pkgs.git
        pkgs.openssh
        pkgs.bashInteractive
        pkgs.coreutils
      ];

      environment = {
        HOME = user.home;
        T3CODE_HOME = "${user.home}/.t3";
        T3CODE_TELEMETRY_ENABLED = "false";
      };

      # A restart kills every running agent, including one deploying this
      # host. Pick up new builds with `sudo systemctl restart t3code`.
      restartIfChanged = false;

      serviceConfig = {
        User = cfg.user;
        Group = user.group;
        WorkingDirectory = user.home;
        ExecStart = lib.escapeShellArgs [
          (lib.getExe cfg.package)
          "serve"
          "--host"
          "127.0.0.1"
          "--port"
          (toString cfg.port)
          "--tailscale-serve"
          user.home
        ];
        # Leave agent processes their own cleanup window on stop.
        KillMode = "mixed";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
