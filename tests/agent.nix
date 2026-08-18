{
  hostConfig,
  lib,
  pkgs,
}:
let
  agent = hostConfig.users.users.agent;
  packageNames = map lib.getName agent.packages;
  gitConfigRule =
    lib.findFirst (lib.hasPrefix "L+ /var/lib/agent/.gitconfig ") null
      hostConfig.systemd.tmpfiles.rules;
  gitConfigPath = lib.last (lib.splitString " " gitConfigRule);
  gitConfig = builtins.readFile gitConfigPath;
  claudeSettingsRule =
    lib.findFirst (lib.hasPrefix "L+ /var/lib/agent/.claude/settings.json ") null
      hostConfig.systemd.tmpfiles.rules;
  claudeSettingsPath = lib.last (lib.splitString " " claudeSettingsRule);
  claudeSettings = builtins.fromJSON (
    builtins.unsafeDiscardStringContext (builtins.readFile claudeSettingsPath)
  );
  ownerCanBecomeAgent = lib.any (
    rule:
    builtins.elem "teevik" rule.users
    && rule.runAs == "agent"
    && lib.any (
      command: command.command == "ALL" && builtins.elem "NOPASSWD" command.options
    ) rule.commands
  ) hostConfig.security.sudo.extraRules;
in
assert agent.isSystemUser;
assert agent.createHome;
assert agent.home == "/var/lib/agent";
assert agent.group == "agent";
assert hostConfig.users.groups ? agent;
assert builtins.elem "d /var/lib/agent/Workspace 0700 agent agent -"
  hostConfig.systemd.tmpfiles.rules;
assert builtins.elem "git" packageNames;
assert builtins.elem "gh" packageNames;
assert lib.hasInfix "name = teevik" gitConfig;
assert lib.hasInfix "email = teemu.vikoren@gmail.com" gitConfig;
assert lib.hasInfix "helper = !" gitConfig;
assert lib.hasInfix "gh auth git-credential" gitConfig;
assert builtins.elem "claude-code" packageNames;
assert hostConfig.nixpkgs.config.allowUnfreePredicate pkgs.claude-code;
assert claudeSettings ? apiKeyHelper;
assert hostConfig.sops.secrets.agent_github_token.owner == "agent";
assert hostConfig.sops.secrets.agent_github_token.group == "agent";
assert hostConfig.sops.secrets.agent_github_token.mode == "0400";
assert hostConfig.sops.secrets.agent_anthropic_api_key.owner == "agent";
assert hostConfig.sops.secrets.agent_anthropic_api_key.group == "agent";
assert hostConfig.sops.secrets.agent_anthropic_api_key.mode == "0400";
assert ownerCanBecomeAgent;
pkgs.runCommand "agent-configuration" { } ''
  touch "$out"
''
