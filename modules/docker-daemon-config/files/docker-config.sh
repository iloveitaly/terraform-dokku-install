#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
if [ "$#" != 2 ] || ! [[ $2 = true || $2 = false ]]; then
  echo 'Usage: configure <base64-json> <allow-storage-migration>' >&2; exit 1
fi
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
umask 077
work=$(mktemp -d /root/terraform-dokku.XXXXXXXX)
pending=false
had_config=false
staged=
ready() {
  for _ in {1..30}; do systemctl is-active --quiet docker && docker info >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [ "$pending" = true ]; then
    echo 'Docker configuration change failed or was interrupted; restoring previous configuration' >&2
    if [ "$had_config" = true ]; then
      if ! cp -p "$work/old.json" "$staged" || ! mv -f "$staged" "$config"; then
        echo "Could not restore Docker configuration; backup is at /etc/docker/daemon.json.bak" >&2
      fi
    else
      rm -f "$config" || echo 'Could not remove the newly created Docker configuration' >&2
    fi
    if ! systemctl restart docker || ! ready; then echo 'Rollback restart failed; investigate Docker manually' >&2; fi
    [ "$status" -ne 0 ] || status=1
  fi
  [ -z "$staged" ] || rm -f "$staged"
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s' "$1" | base64 -d > "$work/candidate.json"
python3 - "$work/candidate.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: data=json.load(f)
if not isinstance(data,dict): raise SystemExit('Docker configuration must be a JSON object')
PY
dockerd --validate --config-file "$work/candidate.json"
install -d -m 0755 /etc/docker
config=/etc/docker/daemon.json
if [ -L "$config" ] || { [ -e "$config" ] && [ ! -f "$config" ]; }; then
  echo 'Docker config must be a regular file' >&2; exit 1
fi
if [ -f "$config" ] && cmp -s "$config" "$work/candidate.json"; then exit 0; fi
if [ "$2" = false ]; then
  python3 - "$config" "$work/candidate.json" <<'PY' || { echo 'Storage backend change requires allow_storage_migration when Docker has images, containers, or volumes' >&2; exit 1; }
import json,os,subprocess,sys
old={}
if os.path.exists(sys.argv[1]):
    with open(sys.argv[1]) as f: old=json.load(f)
with open(sys.argv[2]) as f: new=json.load(f)
keys=('storage-driver','storage-opts','data-root')
changed=any(old.get(k) != new.get(k) for k in keys)
changed |= old.get('features',{}).get('containerd-snapshotter') != new.get('features',{}).get('containerd-snapshotter')
if new.get('storage-driver') and not old.get('storage-driver'):
    active=subprocess.check_output(['docker','info','--format','{{.Driver}}'],text=True).strip()
    changed |= active != new['storage-driver']
if changed:
    for command in (['docker','ps','-aq'], ['docker','images','-aq'], ['docker','volume','ls','-q']):
        if subprocess.check_output(command, text=True).strip(): sys.exit(1)
PY
fi
if [ -e "$config" ]; then
  if [ ! -f "$config" ] || [ -L "$config" ]; then
    echo 'Docker config must be a regular file' >&2; exit 1
  fi
  cp -p "$config" "$work/old.json"
  cp -p "$config" /etc/docker/daemon.json.bak
  had_config=true
fi
staged=$(mktemp /etc/docker/.daemon.json.terraform.XXXXXXXX)
install -m 0644 "$work/candidate.json" "$staged"
# Set this before the atomic rename so an interrupt cannot leave an untracked change.
pending=true
mv -f "$staged" "$config"
if ! systemctl restart docker || ! ready; then
  echo 'Docker failed to start with the candidate configuration' >&2
  exit 1
fi
pending=false
