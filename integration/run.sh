#!/usr/bin/env bash
# Exercise a Git archive on a fresh, disposable Ubuntu 22.04, 24.04, or 26.04 machine with passwordless sudo.
# DOKKU_PACKAGE_REF selects the tracked Git ref to archive (default: HEAD).
set -euo pipefail
[ "${DOKKU_DISPOSABLE_HOST:-}" = yes ] || { echo 'Refusing to modify host: set DOKKU_DISPOSABLE_HOST=yes only on a disposable Ubuntu VM.' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
  status=$?
  if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "Integration artifacts retained in $work" >&2; fi
}
trap cleanup EXIT
# Consume exactly the tracked source archive and isolate its module cache.
git -C "$root" archive --format=zip -o "$work/module.zip" "${DOKKU_PACKAGE_REF:-HEAD}"
consumer="$work/consumer"
mkdir -p "$consumer"
python3 - "$consumer/main.tf" "$work/module.zip" <<'PYCODE'
import json,pathlib,re,sys,zipfile
path=pathlib.Path(sys.argv[1])
archive=pathlib.Path(sys.argv[2]).resolve()
source=json.dumps(archive.as_uri())
with zipfile.ZipFile(archive) as package:
    fixture=package.read('integration/main.tf').decode()
contents,count=re.subn(r'(?m)^([ \t]*source[ \t]*=[ \t]*)"[.][.]/"[ \t]*$', lambda match: match.group(1)+source, fixture)
if count != 1: raise SystemExit(f'Expected exactly one local module source, found {count}')
path.write_text(contents)
PYCODE
export TF_IN_AUTOMATION=1 TF_DATA_DIR=.terraform TF_VAR_ssh_port="${SSH_PORT:-22}"
ssh-keygen -q -t ed25519 -N '' -f "$work/deploy1"
ssh-keygen -q -t ed25519 -N '' -f "$work/deploy2"
if [ -n "${SSH_HOST:-}" ]; then
  : "${SSH_USER:?}" "${SSH_KEY_PATH:?}" "${SSH_KNOWN_HOSTS_PATH:?}"
  export TF_VAR_ssh_host="$SSH_HOST" TF_VAR_ssh_user="$SSH_USER" TF_VAR_ssh_private_key_path="$SSH_KEY_PATH" TF_VAR_ssh_known_hosts_path="$SSH_KNOWN_HOSTS_PATH"
else
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "$ID" != ubuntu ] || ! [[ $VERSION_ID = 22.04 || $VERSION_ID = 24.04 || $VERSION_ID = 26.04 ]]; then
    echo 'Integration requires Ubuntu 22.04, 24.04, or 26.04.' >&2
    exit 1
  fi
  sudo -n true
  TF_VAR_ssh_user=$(id -un)
  export TF_VAR_ssh_user TF_VAR_ssh_host=127.0.0.1 TF_VAR_ssh_private_key_path="$work/access" TF_VAR_ssh_known_hosts_path="$work/known_hosts"
  ssh-keygen -q -t ed25519 -N '' -f "$work/access"
  sudo apt-get update -qq
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    # Hosted runners come with Docker; remove installed Docker packages only on
    # this explicitly marked disposable runner to exercise a fresh install.
    packages=()
    for package in docker-ce docker-ce-cli containerd.io docker.io containerd docker-buildx-plugin docker-compose-plugin; do
      if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then packages+=("$package"); fi
    done
    if [ "${#packages[@]}" -gt 0 ]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y "${packages[@]}"
    fi
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  cat "$work/access.pub" >> "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  sudo systemctl enable --now ssh
  awk '{print "127.0.0.1 " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub > "$work/known_hosts"
fi
remote() { ssh -F /dev/null -p "$TF_VAR_ssh_port" -o IdentitiesOnly=yes -o ForwardAgent=no -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$TF_VAR_ssh_known_hosts_path" -i "$TF_VAR_ssh_private_key_path" "$TF_VAR_ssh_user@$TF_VAR_ssh_host" "$@"; }
# shellcheck disable=SC2016
target_os=$(remote 'sudo -n true && . /etc/os-release && printf "%s %s\n" "$ID" "$VERSION_ID"')
case "$target_os" in
  'ubuntu 22.04'|'ubuntu 24.04')
    initial_version=${DOKKU_TEST_INITIAL_VERSION:-0.35.19}
    upgrade_version=${DOKKU_TEST_UPGRADE_VERSION:-0.35.20}
    ;;
  'ubuntu 26.04')
    # Older packages need not exist for a new Ubuntu release. Use latest by
    # default; explicit versions enable a distinct-version upgrade test.
    initial_version=${DOKKU_TEST_INITIAL_VERSION:-latest}
    upgrade_version=${DOKKU_TEST_UPGRADE_VERSION:-}
    ;;
  *) echo "Unsupported integration target: $target_os" >&2; exit 1 ;;
esac
export TF_VAR_dokku_version="$initial_version"
# A known but incorrect host key must fail before installation.
known_name=$TF_VAR_ssh_host
if [ "$TF_VAR_ssh_port" != 22 ]; then known_name="[$known_name]:$TF_VAR_ssh_port"; fi
awk -v host="$known_name" '{print host " " $1 " " $2}' "$work/deploy1.pub" > "$work/unknown_hosts"
if ssh -F /dev/null -p "$TF_VAR_ssh_port" -o IdentitiesOnly=yes -o ForwardAgent=no -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$work/unknown_hosts" -o GlobalKnownHostsFile=/dev/null -i "$TF_VAR_ssh_private_key_path" "$TF_VAR_ssh_user@$TF_VAR_ssh_host" true; then
  echo 'Unexpectedly accepted a mismatched host key' >&2; exit 1
fi
export TF_VAR_dokku_ssh_public_key_path="$work/deploy1.pub"
export TF_VAR_dokku_plugin_definitions='{"redis":{"url":"https://github.com/dokku/dokku-redis.git","revision":"e9df51c60fc5e14a486fab6e740e35f110a00995"}}'
tf() { terraform -chdir="$consumer" "$@"; }
apply() { tf apply -input=false -auto-approve; }
tf init -input=false -backend-config="path=$work/terraform.tfstate"
apply
initial_installed=$(remote "dpkg-query -W -f='\${Version}' dokku")
if [ "$initial_version" != latest ] && [ "$initial_installed" != "$initial_version" ]; then
  echo "Expected Dokku $initial_version; installed $initial_installed" >&2; exit 1
fi
remote sudo dokku version | grep -F "$initial_installed"
remote sudo dokku ssh-keys:list | grep -F integration
remote sudo dokku plugin:installed redis
remote sudo git -C /var/lib/dokku/plugins/available/redis rev-parse HEAD | grep -Fx e9df51c60fc5e14a486fab6e740e35f110a00995
set +e
tf plan -input=false -detailed-exitcode > "$work/second-plan" 2>&1
status=$?
set -e
[ "$status" = 0 ] || { cat "$work/second-plan"; echo 'Second plan was not a no-op' >&2; exit 1; }
if [ -n "$upgrade_version" ]; then
  export TF_VAR_dokku_version="$upgrade_version" TF_VAR_allow_dokku_upgrade=true
  apply
  remote sudo dokku version | grep -F "$upgrade_version"
else
  echo 'Skipping distinct-version upgrade: set DOKKU_TEST_INITIAL_VERSION and DOKKU_TEST_UPGRADE_VERSION to available releases to exercise it.'
fi
export TF_VAR_dokku_version=latest TF_VAR_allow_dokku_upgrade=true
apply
expected_latest=$(remote apt-cache madison dokku | python3 -c 'import re,sys
versions=[]
for line in sys.stdin:
    fields=line.split("|")
    if len(fields)>=3 and re.search(r"https://packagecloud[.]io/dokku/dokku/ubuntu(?:/|\s|$)", fields[2]):
        version=fields[1].strip()
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",version): versions.append(version)
if not versions: sys.exit("No stable official Dokku versions found")
print(max(versions,key=lambda x: tuple(map(int,x.split(".")))))')
actual_latest=$(remote "dpkg-query -W -f='\${Version}' dokku")
[ "$actual_latest" = "$expected_latest" ] || { echo "Expected latest $expected_latest; got $actual_latest" >&2; exit 1; }
export TF_VAR_allow_dokku_upgrade=false
apply
[ "$(remote "dpkg-query -W -f='\${Version}' dokku")" = "$actual_latest" ] || { echo 'Latest unexpectedly changed without upgrade permission' >&2; exit 1; }
export TF_VAR_dokku_hostname=changed.example.test
apply
remote sudo dokku domains:report --global | grep -F changed.example.test
export TF_VAR_dokku_ssh_public_key_path="$work/deploy2.pub" TF_VAR_dokku_ssh_key_name=integration-rotated
apply
remote sudo dokku ssh-keys:list | grep -F integration-rotated
if remote sudo dokku ssh-keys:list | grep -E 'integration($|[[:space:]])'; then echo 'Old key remains after rotation' >&2; exit 1; fi
unset TF_VAR_dokku_ssh_public_key_path
apply
if remote sudo dokku ssh-keys:list | grep -F integration-rotated; then echo 'Key remains after revocation' >&2; exit 1; fi
export TF_VAR_dokku_plugin_definitions='{"redis":{"url":"https://github.com/dokku/dokku-redis.git","revision":"e9df51c60fc5e14a486fab6e740e35f110a00995"},"integrationbroken":{"url":"https://github.com/dokku/nonexistent-integration-plugin.git"}}'
if apply; then echo 'A failed plugin install unexpectedly succeeded' >&2; exit 1; fi
export TF_VAR_dokku_plugin_definitions='{"redis":{"url":"https://github.com/dokku/dokku-redis.git","revision":"e9df51c60fc5e14a486fab6e740e35f110a00995"}}'
apply
# systemd starts dockerd with -H fd://, so an additional hosts setting validates
# as JSON but prevents the service starting. The transaction must restore the file.
if remote sudo test -e /etc/docker/daemon.json; then remote sudo cat /etc/docker/daemon.json > "$work/daemon.before"; else touch "$work/no-daemon-before"; fi
export TF_VAR_docker_daemon_config='{"hosts":["tcp://127.0.0.1:2375"]}'
if apply; then echo 'Expected Docker restart failure' >&2; exit 1; fi
remote sudo systemctl is-active --quiet docker
if [ -e "$work/no-daemon-before" ]; then remote sudo test ! -e /etc/docker/daemon.json; else remote sudo cat /etc/docker/daemon.json > "$work/daemon.after"; cmp "$work/daemon.after" "$work/daemon.before"; fi
# Recover from the failed apply and exercise ownership replacement and destroy.
unset TF_VAR_docker_daemon_config
export TF_VAR_dokku_ssh_public_key_path="$work/deploy1.pub" TF_VAR_dokku_ssh_key_name=integration-destroy
apply
remote sudo dokku ssh-keys:list | grep -F integration-destroy
export TF_VAR_management_id=integration-test-replaced
export TF_VAR_dokku_ssh_key_name=integration-owner-replaced
apply
remote sudo dokku ssh-keys:list | grep -F integration-owner-replaced
if remote sudo dokku ssh-keys:list | grep -F integration-destroy; then echo 'Old owner key remains after replacement' >&2; exit 1; fi
# Move both consumer and module cache so destroy cannot use the old module path.
mv "$consumer" "$work/relocated-consumer"
consumer="$work/relocated-consumer"
tf destroy -input=false -auto-approve
if remote sudo dokku ssh-keys:list | grep -F integration-owner-replaced; then echo 'Key remains after destroy' >&2; exit 1; fi
remote sudo systemctl is-active --quiet docker
echo 'Disposable integration checks passed.'
