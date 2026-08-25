#!/usr/bin/env bash
# Rotate live credentials to the values stored in secrets.yaml.
#
# The sops secrets are the source of truth; this script pushes them into the
# running services that persist credentials in their own state (Postgres,
# Grafana's SQLite DB, Paperless' Django DB) and restarts consumers.
#
# Run inside `nix develop`, AFTER:
#   1. `just deploy`  (provisions the new k8s secrets on the host)
#   2. Argo CD has synced the updated manifests
set -euo pipefail
cd "$(dirname "$0")/.."

get() { sops -d --extract "[\"$1\"]" secrets.yaml; }

echo "==> Immich: postgres password"
get immich_db_password | kubectl exec -i -n immich deploy/immich-postgresql -- \
  sh -c 'read -r PW; psql -U immich -d immich -v ON_ERROR_STOP=1 -c "ALTER USER immich WITH PASSWORD '\''$PW'\'';"'

echo "==> Paperless: postgres password"
get paperless_db_password | kubectl exec -i -n paperless-ngx deploy/paperless-db -- \
  sh -c 'read -r PW; psql -U paperless -d paperless -v ON_ERROR_STOP=1 -c "ALTER USER paperless WITH PASSWORD '\''$PW'\'';"'

echo "==> Paperless: django admin password"
get paperless_admin_password | kubectl exec -i -n paperless-ngx deploy/paperless -- \
  sh -c 'read -r PW; cd /usr/src/paperless/src && PW="$PW" python3 manage.py shell -c "
import os
from django.contrib.auth import get_user_model
u = get_user_model().objects.get(username=\"admin\")
u.set_password(os.environ[\"PW\"])
u.save()
"'

echo "==> Grafana: admin password"
get grafana_admin_password | kubectl exec -i -n victoria-metrics deploy/vm-grafana -c grafana -- \
  sh -c 'read -r PW; grafana cli --homepath /usr/share/grafana admin reset-admin-password "$PW"'

echo "==> Restarting consumers of rotated credentials"
kubectl rollout restart -n immich deploy/immich-server
kubectl rollout restart -n paperless-ngx deploy/paperless
# Pick up the new server.secretkey (invalidates all existing sessions)
kubectl rollout restart -n argocd deploy/argocd-server

echo "==> Cleaning up superseded secrets"
kubectl delete secret -n argocd argocd-webhook-secret --ignore-not-found

echo "Done. Log in with the new passwords from secrets.yaml:"
echo "  sops -d --extract '[\"argocd_admin_password\"]' secrets.yaml"
echo "  sops -d --extract '[\"grafana_admin_password\"]' secrets.yaml"
echo "  sops -d --extract '[\"paperless_admin_password\"]' secrets.yaml"
