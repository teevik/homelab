"""Production interfaces in a disposable NixOS/k3s VM; no physical acceptance."""
import json
import shlex

machine.start(allow_reboot=True)


def snapshot():
    return json.loads(machine.succeed('cat /run/homelab-health/snapshot.json'))


def policy():
    return json.loads(machine.succeed('cat /run/homelab-display-policy/status.json'))


def wait_snapshot(expression):
    command = "python3 -c " + shlex.quote(
        "import json; s=json.load(open('/run/homelab-health/snapshot.json')); assert " + expression
    )
    try:
        machine.wait_until_succeeds(command, timeout=90)
    except Exception:
        machine.log(machine.succeed('cat /run/homelab-health/snapshot.json'))
        raise


def ui_running():
    machine.wait_until_succeeds('pgrep -u teevik -x health-dashboar')


def shell_command(command):
    machine.send_chars(command + '\n')


with subtest('cold boot starts tty1 and host collection without cluster or credentials'):
    machine.wait_for_unit('homelab-health-collector.service')
    machine.wait_for_unit('getty@tty1.service')
    machine.wait_for_unit('homelab-display-policy.service')
    machine.wait_until_succeeds('test -f /run/homelab-health/snapshot.json')
    addresses = json.loads(machine.succeed('ip -j address'))
    assert not any(interface['addr_info'] for interface in addresses if interface['ifname'] != 'lo')
    machine.fail('systemctl is-active k3s.service')
    machine.fail('test -f /run/homelab-health-credentials/credential.json')
    ui_running()
    wait_snapshot("s['host']['cpu_percent'] is not None and s['host']['root']['total_bytes'] > 0")
    assert snapshot()['sources']['http']['failure'] is not None
    machine.succeed('test $(stat -c %a /var/lib/homelab-health) = 700')
    machine.fail('su -s /bin/sh teevik -c "cat /etc/rancher/k3s/k3s.yaml"')
    machine.fail('su -s /bin/sh teevik -c "cat /run/homelab-health-credentials/credential.json"')
    machine.send_key('ctrl-c')
    machine.wait_until_fails('pgrep -u teevik -x health-dashboar')
    shell_command('stty -a > /tmp/tty1-stty; echo usable-shell > /tmp/tty1-shell')
    machine.wait_until_succeeds('grep -qx usable-shell /tmp/tty1-shell')
    machine.succeed("grep -E '(^|[ ;])echo([ ;]|$)' /tmp/tty1-stty; grep -E '(^|[ ;])icanon([ ;]|$)' /tmp/tty1-stty")
    before = snapshot()['sources']['host']['newest_sample_at']
    wait_snapshot("s['sources']['host']['newest_sample_at'] != " + repr(before))
    assert not policy()['screen_on']

with subtest('real SSH interactive login shell does not launch the dashboard'):
    machine.wait_for_unit('sshd.service')
    machine.succeed("su -s /bin/sh teevik -c 'mkdir -p ~/.ssh; ssh-keygen -q -t ed25519 -N \"\" -f ~/.ssh/id_ed25519; cp ~/.ssh/id_ed25519.pub ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'")
    ssh = "ssh -o StrictHostKeyChecking=no -tt localhost " + shlex.quote("bash -ilc 'echo ssh-shell'")
    machine.succeed('su -s /bin/sh teevik -c ' + shlex.quote(ssh) + ' | grep ssh-shell')
    machine.fail('pgrep -u teevik -x health-dashboar')

with subtest('global fixed requests reach footer inputs and survive shell handoff'):
    machine.succeed('su -s /bin/sh teevik -c "display-policy bedtime"')
    assert not policy()['screen_on']
    machine.succeed('su -s /bin/sh teevik -c "display-policy wake"')
    assert policy()['screen_on'] and not policy()['anime_on']
    machine.wait_until_succeeds("grep -q 'wake_until' /run/homelab-health/night.json")
    shell_command('dashboard')
    ui_running()
    machine.succeed('systemctl stop homelab-display-policy.service')
    machine.wait_until_succeeds('test ! -f /run/homelab-health/night.json', timeout=30)
    machine.send_key('ctrl-c')
    machine.wait_until_fails('pgrep -u teevik -x health-dashboar')
    machine.succeed('systemctl start homelab-display-policy.service')
    machine.wait_until_succeeds('test -f /run/homelab-health/night.json')
    machine.succeed('su -s /bin/sh teevik -c "display-policy resume-schedule"')
    assert not policy()['screen_on']

with subtest('real scoped service proxies, atomic renewal, collector restart and API return'):
    machine.succeed('ip address add 10.0.2.15/24 dev eth0; ip link set eth0 up; ip route add default via 10.0.2.2')
    machine.succeed('ip address add 192.168.1.225/24 dev eth1; ip link set eth1 up')
    machine.succeed('touch /run/start-k3s; systemctl start k3s.service health-fixture.service')
    machine.wait_until_succeeds("kubectl get nodes | grep ' Ready '", timeout=180)
    machine.succeed('python3 /etc/health-vm-install.py', timeout=180)
    machine.succeed('systemctl start homelab-health-credential.service')
    machine.wait_until_succeeds('python3 /etc/health-proxy.py', timeout=90)
    wait_snapshot("all(s['sources'][name]['failure'] is None and s['sources'][name]['newest_sample_at'] for name in ['http', 'argo', 'alerts'])")
    machine.succeed('echo failure > /run/health-fixture-mode')
    wait_snapshot("s['endpoints']['glance']['result'] == 'fail'")
    onset = snapshot()['endpoints']['glance']['since']
    machine.succeed('echo offline > /run/health-fixture-mode')
    wait_snapshot("s['sources']['http']['failure'] is not None")
    assert snapshot()['endpoints']['glance']['since'] == onset
    assert not snapshot()['recoveries']
    before = snapshot()['sources']['host']['newest_sample_at']
    wait_snapshot("s['sources']['host']['newest_sample_at'] != " + repr(before))
    machine.succeed('systemctl restart homelab-health-collector.service')
    wait_snapshot("s['endpoints']['glance']['since'] == " + repr(onset))
    machine.succeed('rm /run/homelab-health-credentials/credential.json; echo healthy > /run/health-fixture-mode')
    wait_snapshot("'credential unavailable' in (s['sources']['http']['failure'] or {}).get('reason', '')")
    machine.succeed('systemctl start homelab-health-credential.service')
    wait_snapshot("s['sources']['http']['failure'] is None and bool(s['recoveries'])")
    assert snapshot()['recoveries'][0]['service'] == 'glance'
    # A genuinely expired, signed service-account JWT, without waiting ten minutes.
    machine.succeed("kubectl -n victoria-metrics create token dashboard-collector --duration=10m > /run/short-token")
    machine.succeed("python3 -c 'import json; p=\"/run/homelab-health-credentials/credential.json\"; d=json.load(open(p)); d[\"token\"]=open(\"/run/short-token\").read().strip(); json.dump(d,open(p,\"w\"))'")
    machine.succeed("date -s '+11 minutes'")
    wait_snapshot("'401' in (s['sources']['http']['failure'] or {}).get('reason', '')")
    machine.succeed('systemctl start homelab-health-credential.service')
    wait_snapshot("s['sources']['http']['failure'] is None")
    previous = snapshot()['sources']['alerts']['newest_sample_at']
    machine.succeed('echo frozen-evaluator > /run/health-fixture-mode')
    wait_snapshot("s['sources']['alerts']['newest_sample_at'] != " + repr(previous))
    machine.succeed("date -s '+4 minutes'")
    wait_snapshot("'old evaluator progress' in (s['sources']['alerts']['failure'] or {}).get('reason', '')")
    machine.succeed('echo healthy > /run/health-fixture-mode')
    wait_snapshot("s['sources']['alerts']['failure'] is None")
    machine.succeed("date -s '+2 hours'; systemctl start homelab-health-credential.service")
    wait_snapshot("not s['recoveries'] and len(s['host']['temperature_history']['celsius']) == 90")

with subtest('operator discovers every production VMProbe and real policies allow synthetic host/app routes'):
    machine.succeed('kubectl -n victoria-metrics rollout status deployment/dashboard-blackbox --timeout=180s', timeout=200)
    machine.succeed('kubectl -n victoria-metrics rollout status deployment/vm-victoria-metrics-operator --timeout=180s', timeout=200)
    machine.wait_until_succeeds('kubectl -n victoria-metrics get pods -l app.kubernetes.io/name=vmagent | grep Running', timeout=180)
    machine.succeed('kubectl -n victoria-metrics wait --for=condition=Ready pod/allowed pod/denied --timeout=180s', timeout=200)
    probe = 'http://dashboard-blackbox.victoria-metrics.svc:9115/probe?module=kodekamp&target=http://kodekamp-web.kodekamp.svc:3000'
    machine.wait_until_succeeds('kubectl -n victoria-metrics exec allowed -- wget -qO- ' + shlex.quote(probe) + " | grep -x 'probe_success 1'", timeout=90)
    machine.fail('kubectl -n victoria-metrics exec denied -- wget -T 3 -qO- ' + shlex.quote(probe))
    machine.fail('kubectl -n victoria-metrics exec denied -- wget -T 3 -qO- http://kodekamp-web.kodekamp.svc:3000')
    for module, target in [('amp', 'http://amp.amp.svc'), ('nix-cache', 'http://192.168.1.225:8501/nix-cache-info')]:
        url = 'http://dashboard-blackbox.victoria-metrics.svc:9115/probe?module=' + module + '&target=' + target
        machine.wait_until_succeeds('kubectl -n victoria-metrics exec allowed -- wget -qO- ' + shlex.quote(url) + " | grep -x 'probe_success 1'", timeout=90)
    # Read actual operator-generated vmagent targets, not a reconstructed config.
    target_url = 'http://vmagent-vm-victoria-metrics-k8s-stack.victoria-metrics.svc:8429/api/v1/targets'
    target_command = 'kubectl -n victoria-metrics exec allowed -- wget -qO- ' + shlex.quote(target_url) + ' > /run/health-targets.json'
    machine.wait_until_succeeds(target_command + "; python3 -c 'import json; t=json.load(open(\"/run/health-targets.json\"))[\"data\"][\"activeTargets\"]; assert len(t)==16 and all(x[\"health\"]==\"up\" for x in t)'", timeout=180)
    targets = json.loads(machine.succeed('cat /run/health-targets.json'))['data']['activeTargets']
    catalog = json.loads(machine.succeed('cat /etc/homelab/health-catalog.json'))
    assert {t['labels']['service_id'] for t in targets} == {e['id'] for e in catalog['endpoints']}

with subtest('full logout authenticates; later tty1 login launches; other VT, SSH and nested shells do not'):
    shell_command('bash')
    shell_command('echo nested-shell > /tmp/nested; exit')
    machine.wait_until_succeeds('grep -qx nested-shell /tmp/nested')
    machine.fail('pgrep -u teevik -x health-dashboar')
    shell_command('exit')
    machine.wait_until_succeeds("grep -a -q 'login:' /dev/vcs1")
    machine.fail('pgrep -u teevik -x dashboard')
    machine.send_chars('teevik\n')
    machine.wait_until_succeeds("grep -a -q 'Password:' /dev/vcs1")
    machine.send_chars('dashboard-fixture\n')
    ui_running()
    machine.send_key('ctrl-c')
    machine.wait_until_fails('pgrep -u teevik -x health-dashboar')
    machine.send_key('ctrl-alt-f2')
    machine.wait_until_succeeds("grep -a -q 'login:' /dev/vcs2")
    machine.send_chars('teevik\n')
    machine.wait_until_succeeds("grep -a -q 'Password:' /dev/vcs2")
    machine.send_chars('dashboard-fixture\n')
    shell_command('echo other-vt > /tmp/other-vt')
    machine.wait_until_succeeds('grep -qx other-vt /tmp/other-vt')
    machine.fail('pgrep -u teevik -x health-dashboar')
    machine.reboot()
    ui_running()
    machine.wait_for_unit('homelab-health-collector.service')
    machine.wait_until_succeeds('test -f /run/homelab-display-policy/status.json')
    assert not policy()['screen_on'] and policy()['wake_until'] is None
