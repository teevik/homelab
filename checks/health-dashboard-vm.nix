{ pkgs, flake, ... }:
let
  python = pkgs.python3.withPackages (ps: [ ps.evdev ps.pyyaml ]);
  # Import exactly the deployed upstream artifacts into the isolated airgap.
  images = map pkgs.dockerTools.pullImage [
    {
      imageName = "victoriametrics/operator";
      imageDigest = "sha256:7310c4a80b94f530c5f0b1fcf6d6eaf933f39cc5704e983900d9cfd6b31f9dc1";
      hash = "sha256-RMP0wudfZ1C9U5P+uMPFPJYXUJdCH917zm+ABf0I7kw=";
      finalImageTag = "v0.74.1";
    }
    {
      imageName = "victoriametrics/operator";
      imageDigest = "sha256:0909fff9dde819f9a5847779855ebc030e4f00d61751352945a309e6ce80310c";
      hash = "sha256-tHcjnT29loEMhHWlO9i50Jso/P6wGj7juLH22ISi2BM=";
      finalImageTag = "config-reloader-v0.74.1";
    }
    {
      imageName = "victoriametrics/vmagent";
      imageDigest = "sha256:3eff5874d59292714878dcb6aee14f048bf19b7312b727860ba5e7d29e2e0c07";
      hash = "sha256-agQzqtONOJgHEYM6c/ynJ5w5bEXL55vHsho6ERfNUHU=";
      finalImageTag = "v1.150.0";
    }
    {
      imageName = "quay.io/prometheus/blackbox-exporter";
      imageDigest = "sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc";
      hash = "sha256-sCyWOhQjOYsnaGt+MAzHkPVAHz7JPvmpdx0Og39g6BA=";
      finalImageTag = "v0.28.0";
    }
  ];
  fixtureImage = pkgs.dockerTools.buildLayeredImage {
    name = "test.local/health-client";
    tag = "local";
    contents = [ pkgs.busybox ];
    config.Cmd = [ "/bin/sleep" "infinity" ];
  };
  production = flake.nixidyEnvs.${pkgs.system}.homelab.environmentPackage;
in
(import ./k3s.nix { inherit pkgs; }).extend {
  modules = [ ({ lib, ... }: {
    name = lib.mkForce "integrated-health-dashboard";
    nodes.machine = { lib, ... }: {
      imports = [
        (import ../tests/nixos/display-fixture.nix { inherit pkgs flake python; })
        ../modules/nixos/health-dashboard.nix
      ];
      homelab.healthDashboard.enable = true;
      # No non-loopback IP exists at boot. Restore the node address from the
      # driver only after tty1/collector/controller have started successfully.
      networking.useDHCP = lib.mkForce false;
      networking.enableIPv6 = lib.mkForce false;
      networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 10 [ ];
      users.users.teevik = {
        shell = pkgs.bashInteractive;
        # Only this disposable VM uses a known password.
        password = "dashboard-fixture";
      };
      services.openssh.enable = true;
      services.k3s.images = images ++ [ fixtureImage ];
      # Observe cold tty1/host startup before any Kubernetes or credential exists.
      systemd.services.k3s.wantedBy = lib.mkForce [ ];
      systemd.services.k3s.unitConfig.ConditionPathExists = "/run/start-k3s";
      systemd.timers.homelab-health-credential.wantedBy = lib.mkForce [ ];
      virtualisation.memorySize = lib.mkForce 4096;
      environment.systemPackages = [
        pkgs.curl pkgs.procps python
      ];
      environment.etc = {
        "health-vm-api.py".source = ../tests/health-vm-api.py;
        "health-vm-install.py".source = ../tests/health-vm-install.py;
        "health-proxy.py".source = ../tests/health-proxy.py;
        "health-production".source = production;
      };
      systemd.services.health-fixture = {
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 /etc/health-vm-api.py";
        preStart = "echo healthy > /run/health-fixture-mode";
      };
      networking.firewall.allowedTCPPorts = [ 8428 8088 8501 ];
    };
    testScript = lib.mkForce (builtins.readFile ../tests/health-dashboard-vm.py);
  }) ];
}
