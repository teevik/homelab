{ pkgs, flake, ... }:
let
  config = flake.nixosConfigurations.homelab.config;
  collector = config.systemd.services.homelab-health-collector;
  consumers = {
    shell = toString config.users.users.teevik.shell;
    bash = toString pkgs.bashInteractive;
    font = config.console.font;
    inherit (config.services.getty) autologinUser autologinOnce;
    after = collector.after;
    requires = collector.requires;
    service = collector.serviceConfig;
    settings = builtins.fromJSON config.environment.etc."homelab/health-collector.json".text;
    catalog = builtins.fromJSON config.environment.etc."homelab/health-catalog.json".text;
    role = flake.nixidyEnvs.${pkgs.stdenv.hostPlatform.system}.homelab.config.applications.victoria-metrics.resources.roles.dashboard-collector;
  };
in
pkgs.runCommand "health-host-wiring-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${pkgs.writeText "health-host.json" (builtins.toJSON consumers)} <<'PY'
  import gzip,json,struct,sys
  from pathlib import Path
  host=json.loads(Path(sys.argv[1]).read_text())
  assert host["shell"] == host["bash"]
  font=gzip.open(host["font"],"rb").read()
  if font[:2]==bytes([0x36,0x04]):
    assert font[2] & 1 == 0 and font[3] == 64, "256 glyphs at 16x32"
  else:
    magic,version,header,flags,glyphs,size,height,width=struct.unpack("<8I",font[:32])
    assert magic==0x864ab572 and (glyphs,height,width)==(256,32,16)
  assert host["autologinUser"] == "teevik" and host["autologinOnce"] is True
  assert not host["after"] and not host["requires"], "host sampling cannot await cluster/network/UI"
  assert host["service"]["User"] == "health-collector"
  assert host["service"]["RuntimeDirectoryMode"] == "0755"
  assert host["service"]["StateDirectoryMode"] == "0700"
  assert "credential" not in host["catalog"]
  assert len(host["catalog"]["endpoints"]) == 16
  assert len(host["catalog"]["apps"]) == 18
  rules=host["role"]["rules"]
  assert len(rules)==1
  assert rules[0]["verbs"]==["get"]
  assert rules[0]["resources"]==["services/proxy"]
  assert set(rules[0]["resourceNames"])=={
    "http:vmsingle-vm-victoria-metrics-k8s-stack:8428",
    "http:vmalertmanager-vm-victoria-metrics-k8s-stack:9093",
  }
  print("evaluated host: Bash, once-per-boot tty1, independent service and scoped access passed")
  PY
  touch "$out"
''
