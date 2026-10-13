#!/usr/bin/env python3
"""Verify Minecraft world persistence across a real, isolated AMP image restart."""

import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import uuid


def inside(action, version):
    sys.path.insert(0, '/opt/homelab')
    import entrypoint as amp

    def wait_for(check, description, timeout=900):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(1)
        raise RuntimeError(f'Timed out waiting for {description}')

    wait_for(lambda: amp.READY.exists(), 'AMP startup')
    wait_for(lambda: (amp.STATE / 'licensed').exists(), 'AMP activation and instance licence defaults')

    def login_ready(api):
        try:
            api.login()
            return True
        except (OSError, ValueError, RuntimeError):
            return False

    controller = amp.API()
    wait_for(lambda: login_ready(controller), 'controller HTTP readiness')
    if action == 'setup':
        target = controller.call('ADSModule/GetInstances', ForceIncludeSelf=True)[0]['AvailableInstances'][0]['InstanceID']
        controller.call(
            'ADSModule/CreateInstance', TargetADSInstance=target, NewInstanceId=str(uuid.uuid4()),
            Module='Minecraft', InstanceName='ShutdownTest', FriendlyName='Disposable shutdown test',
            IPBinding='127.0.0.1', PortNumber=8081, AdminUsername='admin',
            AdminPassword=amp.secret('AMP_ADMIN_PASSWORD'), ProvisionSettings={},
            AutoConfigure=False, PostCreate=0, StartOnBoot=True,
            DisplayImageSource='', TargetDatastore=-1, Group='',
        )

    child = amp.API(base='http://127.0.0.1:8081/')
    wait_for(lambda: login_ready(child), 'Minecraft AMP instance')
    if action == 'setup':
        child.settings({
            'MinecraftModule.Minecraft.ServerType': '10',
            'MinecraftModule.Minecraft.SpecificVersion': version,
            'MinecraftModule.Java.JavaVersion': '/usr/lib/jvm/temurin-21-jdk-amd64/bin/java',
            'MinecraftModule.Java.MaxHeapSizeMB': '1024',
            'MinecraftModule.Limits.StopTimeout': '300',
            'Core.AMP.AppStartupMode': '2',
            'Core.Privacy.AutoReportFatalExceptions': False,
            'Core.Privacy.AllowAnalytics': False,
        })
        child.call('MinecraftModule/AcceptEULA')
        child.call('Core/UpdateApplication')
        wait_for(lambda: not child.call('Core/GetTasks'), 'Minecraft download')
        child.call('Core/Start')
    wait_for(lambda: child.call('Core/GetStatus')['State'] == 20, 'Minecraft ready')

    def console_contains(marker):
        return any(marker in entry.get('Contents', '') and entry.get('Source', '').startswith('Server thread/')
                   for entry in child.call('Core/GetUpdates').get('ConsoleEntries', []))

    if action == 'setup':
        # Disable autosaves so an abrupt exit cannot pass just because the next
        # autosave happened to finish. The supervisor must allow stop to save.
        for command in ['save-off', 'forceload add 0 0', 'setblock 0 70 0 minecraft:diamond_block',
                        'execute if block 0 70 0 minecraft:diamond_block run say BEFORE_RESTART_CONFIRMED']:
            child.call('Core/SendConsoleMessage', message=command)
        wait_for(lambda: console_contains('BEFORE_RESTART_CONFIRMED'), 'in-memory test block')
    else:
        child.call('Core/SendConsoleMessage', message='forceload add 0 0')
        child.call('Core/SendConsoleMessage', message='execute if block 0 70 0 minecraft:diamond_block run say SHUTDOWN_SAVE_PASSED')
        wait_for(lambda: console_contains('SHUTDOWN_SAVE_PASSED'), 'saved test block after restart', timeout=60)
        marker = amp.STATE / 'ads-shutdown-fixes'
        if not marker.exists():
            raise RuntimeError('First-rollout ADS upgrade did not complete')
        print('PASS: Minecraft test block survived SIGTERM/restart; ADS migration completed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True, help='Locally built AMP image')
    parser.add_argument('--license-file', required=True, type=Path, help='AMP licence; never printed')
    parser.add_argument('--minecraft-version', default='1.21.11')
    args = parser.parse_args()
    if os.getuid() != 1000:
        parser.error('Run as UID 1000, matching the AMP image and bind-mounted fixture data')
    name = 'homelab-amp-test-' + uuid.uuid4().hex[:12]

    def docker(*arguments, **kwargs):
        try:
            return subprocess.run(['docker', *arguments], check=True, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
        except subprocess.CalledProcessError as error:
            for line in error.stderr.splitlines():
                if line.startswith('AMP_TEST_FAILURE: '):
                    raise RuntimeError(line.removeprefix('AMP_TEST_FAILURE: ')) from None
            raise RuntimeError(f'Docker {arguments[0]} failed with exit code {error.returncode}') from None

    with tempfile.TemporaryDirectory(prefix='amp-minecraft-') as directory:
        root = Path(directory)
        (root / 'data').mkdir()
        (root / 'secrets').mkdir(mode=0o700)
        for field, value in [('AMP_ADMIN_PASSWORD', secrets.token_urlsafe(32)),
                             ('AMP_LICENSE_KEY', args.license_file.read_text().strip())]:
            path = root / 'secrets' / field
            path.write_text(value)
            path.chmod(0o600)
        try:
            docker('run', '-d', '--name', name, '--log-driver=json-file', '--memory=4g', '--cpus=2',
                   '--mac-address', '02:42:ac:12:00:02',
                   '--mount', f'type=bind,src={root}/data,dst=/home/amp',
                   '--mount', f'type=bind,src={root}/secrets,dst=/run/secrets/amp,readonly',
                   '--mount', f'type=bind,src={Path(__file__).resolve()},dst=/opt/test-amp-minecraft.py,readonly',
                   args.image)
            # No ports are published and no host networking or production data
            # is used. The licence is mounted only inside this disposable pod.
            print('Started isolated AMP/Minecraft fixture.', flush=True)
            docker('exec', name, 'python3', '/opt/test-amp-minecraft.py', 'inside', 'setup', args.minecraft_version,
                   timeout=1500)
            # Exercise the existing-controller migration on the next boot too.
            (root / 'data' / '.homelab' / 'ads-shutdown-fixes').unlink()
            print('Terminating the image through Tini/SIGTERM with an unsaved test block.', flush=True)
            docker('stop', '--time', '720', name, timeout=750)
            state = json.loads(docker('inspect', name).stdout)[0]['State']
            logs = docker('logs', name).stdout
            if state['ExitCode'] != 0 or 'no instance processes remain' not in logs:
                raise RuntimeError('AMP did not report a complete graceful shutdown')
            docker('start', name)
            result = docker('exec', name, 'python3', '/opt/test-amp-minecraft.py', 'inside', 'verify', args.minecraft_version,
                            timeout=1200)
            print(result.stdout.strip(), flush=True)
            docker('stop', '--time', '720', name, timeout=750)
        finally:
            subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    try:
        if len(sys.argv) > 1 and sys.argv[1] == 'inside':
            inside(sys.argv[2], sys.argv[3])
        else:
            main()
    except Exception as error:
        # API bodies, manager arguments and Docker output can contain secrets.
        print('AMP_TEST_FAILURE: ' + (str(error) if type(error) is RuntimeError else type(error).__name__),
              file=sys.stderr)
        sys.exit(1)
