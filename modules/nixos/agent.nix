{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.agent;

  agentGh = pkgs.writeShellApplication {
    name = "gh";
    text = ''
      export GH_TOKEN
      GH_TOKEN="$(< ${config.sops.secrets.agent_github_token.path})"
      exec ${lib.getExe pkgs.gh} "$@"
    '';
  };

  gitConfig = pkgs.writeText "agent-gitconfig" ''
    [user]
      name = teevik
      email = teemu.vikoren@gmail.com
    [credential "https://github.com"]
      helper = !${lib.getExe agentGh} auth git-credential
  '';

  claudeApiKeyHelper = pkgs.writeShellScript "agent-claude-api-key-helper" ''
    exec ${lib.getExe' pkgs.coreutils "cat"} ${config.sops.secrets.agent_anthropic_api_key.path}
  '';

  claudeSettings = pkgs.writeText "agent-claude-settings.json" (
    builtins.toJSON { apiKeyHelper = claudeApiKeyHelper; }
  );

  agentSecret = {
    owner = "agent";
    group = "agent";
    mode = "0400";
  };
in
{
  options.homelab.agent.enable = lib.mkEnableOption "Background Agent account and workspace";

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "claude-code";

    users.groups.agent = { };

    users.users.agent = {
      isSystemUser = true;
      group = "agent";
      home = "/var/lib/agent";
      createHome = true;
      shell = pkgs.bashInteractive;
      packages = [
        pkgs.git
        agentGh
        pkgs.claude-code
      ];
    };

    sops.secrets = {
      agent_github_token = agentSecret;
      agent_anthropic_api_key = agentSecret;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/agent/Workspace 0700 agent agent -"
      "d /var/lib/agent/.claude 0700 agent agent -"
      "L+ /var/lib/agent/.gitconfig - - - - ${gitConfig}"
      "L+ /var/lib/agent/.claude/settings.json - - - - ${claudeSettings}"
    ];

    security.sudo.extraRules = [
      {
        users = [ "teevik" ];
        runAs = "agent";
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
