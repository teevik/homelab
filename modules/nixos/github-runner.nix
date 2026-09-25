{
  config,
  flake,
  lib,
  pkgs,
  ...
}:
let
  runner = flake.packages.${pkgs.stdenv.hostPlatform.system}.config-github-runner;
  namespace = "/run/netns/config-ci";
  resolver = pkgs.writeText "config-ci-resolv.conf" "nameserver 1.1.1.1\nnameserver 1.0.0.1\n";
  record = pkgs.writeShellScript "config-ci-record" ''
    exec ${pkgs.python3}/bin/python3 ${../../scripts/runner/record.py}
  '';
  headroom = pkgs.writeShellScript "config-ci-headroom" ''
    exec ${pkgs.python3}/bin/python3 -c 'import os; fs = os.statvfs("/nix/store"); assert fs.f_bavail * fs.f_frsize >= 300 * 1024**3, "CI stopped: less than 300 GiB free"'
  '';
  daemonConfig = pkgs.writeTextDir "nix.conf" ''
    include /etc/nix/nix.conf
    allowed-users = config-runner
    trusted-users = root
    max-jobs = 2
    cores = 4
    sandbox = true
    fallback = true
    post-build-hook = ${record}
    pre-build-hook = ${headroom}
    substituters = http://10.254.254.1:8501 https://cache.nixos.org
    extra-trusted-public-keys = ${lib.concatStringsSep " " config.services.ncps.cache.upstream.publicKeys}
  '';
  hidden = [
    "/root"
    "/home"
    "/run/secrets"
    "/run/secrets.d"
    "/etc/rancher"
    "/var/lib/rancher"
    "/var/lib/kubelet"
    "-/run/k3s"
    "-/run/containerd"
    "-/run/docker.sock"
    "-/run/tailscale"
    "-/run/dbus"
    "-/run/systemd/private"
    "-/run/udev/control"
    "-/etc/nix/netrc"
  ];
  networkUp = pkgs.writeShellScript "config-ci-network-up" ''
    set -euo pipefail
    ${pkgs.iproute2}/bin/ip netns add config-ci
    ${pkgs.iproute2}/bin/ip link add ci-host type veth peer name ci-job
    ${pkgs.iproute2}/bin/ip link set ci-job netns config-ci
    ${pkgs.iproute2}/bin/ip addr add 10.254.254.1/30 dev ci-host
    ${pkgs.iproute2}/bin/ip link set ci-host up
    ${pkgs.iproute2}/bin/ip -n config-ci addr add 10.254.254.2/30 dev ci-job
    ${pkgs.iproute2}/bin/ip -n config-ci link set ci-job up
    ${pkgs.iproute2}/bin/ip -n config-ci link set lo up
    ${pkgs.iproute2}/bin/ip -n config-ci route add default via 10.254.254.1
    ${pkgs.iproute2}/bin/ip netns exec config-ci ${pkgs.procps}/bin/sysctl -qw net.ipv6.conf.all.disable_ipv6=1
    ${pkgs.iptables}/bin/iptables -N CONFIG-CI-INPUT
    ${pkgs.iptables}/bin/iptables -A CONFIG-CI-INPUT -s 10.254.254.2 -d 10.254.254.1 -p tcp --dport 8501 -j ACCEPT
    ${pkgs.iptables}/bin/iptables -A CONFIG-CI-INPUT -j DROP
    ${pkgs.iptables}/bin/iptables -I INPUT 1 -i ci-host -j CONFIG-CI-INPUT
    ${pkgs.iptables}/bin/iptables -N CONFIG-CI-FORWARD
    ${pkgs.iptables}/bin/iptables -A CONFIG-CI-FORWARD ! -s 10.254.254.2 -j DROP
    for range in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
      ${pkgs.iptables}/bin/iptables -A CONFIG-CI-FORWARD -d "$range" -j DROP
    done
    ${pkgs.iptables}/bin/iptables -A CONFIG-CI-FORWARD -j ACCEPT
    ${pkgs.iptables}/bin/iptables -I FORWARD 1 -i ci-host -j CONFIG-CI-FORWARD
    ${pkgs.iptables}/bin/iptables -I FORWARD 1 -o ci-host -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ${pkgs.iptables}/bin/iptables -I FORWARD 2 -o ci-host -j DROP
    ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.254.254.2/32 -j MASQUERADE
  '';
  networkDown = pkgs.writeShellScript "config-ci-network-down" ''
    ${pkgs.iptables}/bin/iptables -D INPUT -i ci-host -j CONFIG-CI-INPUT || true
    ${pkgs.iptables}/bin/iptables -D FORWARD -i ci-host -j CONFIG-CI-FORWARD || true
    ${pkgs.iptables}/bin/iptables -D FORWARD -o ci-host -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
    ${pkgs.iptables}/bin/iptables -D FORWARD -o ci-host -j DROP || true
    ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.254.254.2/32 -j MASQUERADE || true
    ${pkgs.iptables}/bin/iptables -F CONFIG-CI-INPUT || true
    ${pkgs.iptables}/bin/iptables -X CONFIG-CI-INPUT || true
    ${pkgs.iptables}/bin/iptables -F CONFIG-CI-FORWARD || true
    ${pkgs.iptables}/bin/iptables -X CONFIG-CI-FORWARD || true
    ${pkgs.iproute2}/bin/ip link del ci-host || true
    ${pkgs.iproute2}/bin/ip netns del config-ci || true
  '';
  restoreRegistration = pkgs.writeShellScript "config-runner-restore-registration" ''
    set -euo pipefail
    backup=/var/lib/config-runner-registration/state
    state=/var/lib/github-runner/config-nightly
    if [[ -d "$backup" ]]; then
      ${pkgs.findutils}/bin/find "$state" -mindepth 1 -delete
      ${pkgs.coreutils}/bin/cp -a "$backup/." "$state/"
      ${pkgs.coreutils}/bin/chown -R config-runner:config-runner "$state"
      ${pkgs.coreutils}/bin/chown root:root "$state/.current-token"
    fi
  '';
  saveRegistration = pkgs.writeShellScript "config-runner-save-registration" ''
    set -euo pipefail
    backup=/var/lib/config-runner-registration/state
    state=/var/lib/github-runner/config-nightly
    ${pkgs.coreutils}/bin/install -d -m 0700 "$backup"
    for file in .runner .credentials .credentials_rsaparams .current-token .nixos-current-config.json; do
      ${pkgs.coreutils}/bin/cp -L --remove-destination "$state/$file" "$backup/$file"
      ${pkgs.coreutils}/bin/chmod 0600 "$backup/$file"
    done
  '';
in
{
  users.groups.config-runner = { };
  users.users.config-runner = {
    isSystemUser = true;
    group = "config-runner";
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/config-ci-work 0700 config-runner config-runner -"
    "d /nix/var/nix/gcroots/config-ci-pending 0770 root nix-cache -"
  ];
  systemd.slices.config-ci.sliceConfig = {
    CPUQuota = "600%";
    CPUWeight = 20;
    MemoryHigh = "14G";
    MemoryMax = "16G";
    MemorySwapMax = 0;
    IOWeight = 20;
  };
  systemd.services.config-ci-network = {
    description = "Isolated CI network with public egress and cache-only host access";
    after = [
      "network-online.target"
      "firewall.service"
    ];
    wants = [ "network-online.target" ];
    before = [
      "github-runner-config-nightly.service"
      "config-ci-nix.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = networkUp;
      ExecStopPost = networkDown;
    };
  };
  systemd.sockets.config-ci-nix = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/config-ci-nix/socket";
      SocketMode = "0600";
      SocketUser = "config-runner";
      DirectoryMode = "0755";
    };
  };
  systemd.services.config-ci-nix = {
    partOf = [ "config-ci-network.service" ];
    requires = [ "config-ci-network.service" ];
    after = [ "config-ci-network.service" ];
    environment.NIX_CONF_DIR = daemonConfig;
    serviceConfig = {
      ExecStart = "${config.nix.package}/bin/nix-daemon";
      Slice = "config-ci.slice";
      Nice = 10;
      IOSchedulingClass = "idle";
      NetworkNamespacePath = namespace;
      BindReadOnlyPaths = [ "${resolver}:/etc/resolv.conf" ];
      # GC needs to resolve existing home-directory roots in the shared store.
      # Build sandboxing isolates builders; the runner itself hides both homes.
      InaccessiblePaths = lib.filter (path: path != "/root" && path != "/home") hidden;
      KillMode = "control-group";
      Restart = "on-failure";
    };
  };
  services.github-runners.config-nightly = {
    enable = true;
    package = runner;
    name = "homelab-config-nightly";
    replace = true;
    url = "https://github.com/teevik/Config";
    tokenFile = "/var/lib/config-runner-registration/token";
    tokenType = "registration";
    noDefaultLabels = true;
    extraLabels = [ "homelab-config-nightly" ];
    user = "config-runner";
    group = "config-runner";
    workDir = "/var/lib/config-ci-work";
    extraPackages = with pkgs; [
      nodejs_24
      python3
      jq
      curl
      findutils
      gnused
      gawk
      xz
      zstd
      unzip
      util-linux
    ];
    extraEnvironment = {
      NIX_REMOTE = "unix:///run/config-ci-nix/socket";
      NIX_CONFIG = "accept-flake-config = true\nmax-jobs = 2\ncores = 4\nsubstituters = http://10.254.254.1:8501 https://cache.nixos.org\n";
      NIX_CACHE_LOCAL_SOCKET = "/run/config-ci-cache.sock";
      NIX_CACHE_URL = "http://10.254.254.1:8501";
    };
  };
  systemd.services.github-runner-config-nightly = {
    partOf = [ "config-ci-network.service" ];
    requires = [
      "config-ci-network.service"
      "config-ci-nix.socket"
      "config-ci-cache.socket"
    ];
    after = [
      "config-ci-network.service"
      "config-ci-nix.socket"
      "config-ci-cache.socket"
    ];
    serviceConfig = {
      # Recycle processes and the workspace after each job, retaining /nix/store.
      ExecStart = lib.mkForce "${runner}/bin/Runner.Listener run --startuptype service --once";
      # Jobs cannot persist altered runner credentials, .env or .path between
      # executions. The backup is root-only and is made before any job starts.
      ExecStartPre = lib.mkMerge [
        (lib.mkBefore [ "+${restoreRegistration}" ])
        (lib.mkAfter [ "+${saveRegistration}" ])
      ];
      Restart = lib.mkForce "always";
      RestartSec = 10;
      LogsDirectoryMode = "0700";
      Slice = "config-ci.slice";
      Nice = 10;
      NetworkNamespacePath = namespace;
      BindReadOnlyPaths = [ "${resolver}:/etc/resolv.conf" ];
      InaccessiblePaths = hidden ++ [ "/nix/var/nix/daemon-socket" ];
      # Use the real unprivileged UID when authenticating to the Nix socket.
      PrivateUsers = lib.mkForce false;
    };
  };
}
