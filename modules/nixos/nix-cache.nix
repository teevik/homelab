{
  config,
  lib,
  pkgs,
  ...
}:
let
  publicKey =
    name: lib.removeSuffix "\n" (builtins.readFile (../../hosts/homelab/cache + "/${name}.pub"));
  rootsDirectory = "/nix/var/nix/gcroots/config-cache";
  settings = pkgs.writeText "nix-cache-publication.json" (
    builtins.toJSON {
      inherit rootsDirectory;
      nix = "${config.nix.package}/bin/nix";
      nixStore = "${config.nix.package}/bin/nix-store";
      storeDirectory = "/nix/store";
      hosts = [
        "desktop"
        "zenbook"
      ];
      keepGenerations = 14;
      minFreeBytes = 300 * 1024 * 1024 * 1024;
      budgetBytes = 500 * 1024 * 1024 * 1024;
      dependencyGroups = [
        "bootstrap"
        "updater"
        "desktop"
        "zenbook"
        "seed"
      ];
      dependencyMaxAgeDays = 14;
      dependencyBudgetBytes = 250 * 1024 * 1024 * 1024;
    }
  );
  command = pkgs.writeShellScript "nix-cache-command" ''
    exec ${pkgs.python3}/bin/python3 ${../../scripts/nix-cache-command.py} ${settings}
  '';
  sshConfig = pkgs.writeText "nix-cache-sshd.conf" ''
    Port 2224
    ListenAddress 0.0.0.0
    HostKey /etc/ssh/ssh_host_ed25519_key
    PidFile /run/nix-cache-sshd/sshd.pid
    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    AllowUsers nix-cache
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitRootLogin no
    UsePAM yes
    DisableForwarding yes
    PermitTTY no
    PermitUserRC no
    X11Forwarding no
    ForceCommand ${command}
    Subsystem sftp internal-sftp
  '';
in
{
  sops.secrets.nix_cache_signing_key = { };
  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ config.sops.secrets.nix_cache_signing_key.path ];
    settings = {
      bind = "127.0.0.1:5000";
      priority = 20;
    };
  };

  # vmagent runs in k3s and cannot reach the host's loopback listener. Expose
  # only metrics on a separate port; the firewall admits the existing trusted
  # CNI/Tailscale interfaces, with no new LAN/public opening.
  services.nginx = {
    enable = true;
    virtualHosts.harmonia-metrics = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 8502;
        }
      ];
      locations."= /metrics".proxyPass = "http://127.0.0.1:5000/metrics";
      locations."/".return = "404";
      extraConfig = "access_log off;";
    };
  };

  # The existing tailnet-only proxy preserves original signatures. Evicting
  # its compressed copy simply fetches the retained closure from Harmonia.
  services.ncps.cache.upstream.urls = lib.mkBefore [ "http://127.0.0.1:5000" ];
  services.ncps.cache.upstream.publicKeys = [ (publicKey "cache") ];
  nix.settings.trusted-public-keys = [
    (publicKey "ci")
    (publicKey "cache")
  ];

  users.groups.nix-cache = { };
  users.users.nix-cache = {
    isSystemUser = true;
    group = "nix-cache";
    home = "/var/lib/nix-cache";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [ "restrict ${publicKey "upload"}" ];
  };
  # This account is deliberately NOT a trusted Nix user. Uploaded paths must
  # carry CI's signature, and the SSH key cannot invoke an arbitrary shell.
  services.openssh.extraConfig = ''
    Match User nix-cache
      ForceCommand ${command}
      DisableForwarding yes
      PermitTTY no
      PermitUserRC no
    Match All
  '';

  # A dedicated port lets tailnet policy grant CI store access without access
  # to the host's normal SSH service. No public/LAN firewall port is opened.
  systemd.services.nix-cache-sshd = {
    description = "Restricted private Nix cache SSH endpoint";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "sshd-keygen.service"
      "nix-daemon.socket"
    ];
    wants = [
      "sshd-keygen.service"
      "nix-daemon.socket"
    ];
    serviceConfig = {
      ExecStartPre = "${pkgs.openssh}/bin/sshd -t -f ${sshConfig}";
      ExecStart = "${pkgs.openssh}/bin/sshd -D -e -f ${sshConfig}";
      Restart = "on-failure";
      RuntimeDirectory = "nix-cache-sshd";
    };
  };
  systemd.tmpfiles.rules = [
    "d ${rootsDirectory} 0700 nix-cache nix-cache -"
    "d ${rootsDirectory}/desktop 0700 nix-cache nix-cache -"
    "d ${rootsDirectory}/zenbook 0700 nix-cache nix-cache -"
    "d ${rootsDirectory}/dependencies 0700 nix-cache nix-cache -"
  ];
  nix.optimise.automatic = true;
  systemd.services.nix-cache-gc = {
    description = "Collect unrooted Nix paths after cache generation pruning";
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.util-linux}/bin/runuser -u nix-cache -- ${pkgs.python3}/bin/python3 ${../../scripts/nix-cache-command.py} ${settings} --prune-dependencies";
      ExecStart = "${config.nix.package}/bin/nix-store --gc";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.nix-cache-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:45:00";
      Persistent = true;
    };
  };
}
