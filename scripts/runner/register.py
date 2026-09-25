"""Install a short-lived repository runner registration token without logging it."""

import json
import subprocess

response = json.loads(subprocess.check_output([
    "gh", "api", "--method", "POST",
    "repos/teevik/Config/actions/runners/registration-token",
]))
subprocess.run([
    "ssh", "homelab",
    "sudo install -d -m 0700 /var/lib/config-runner-registration && "
    "sudo sh -c 'umask 077; cat > /var/lib/config-runner-registration/token.new && "
    "mv /var/lib/config-runner-registration/token.new /var/lib/config-runner-registration/token'",
], input=(response["token"] + "\n").encode(), check=True)
print("Installed a short-lived registration token on homelab (root only).")
