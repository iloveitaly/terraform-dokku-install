#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
if [ "$#" != 3 ] || ! [[ ( $1 = latest || $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ) && $2 =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || ! [[ $3 = true || $3 = false ]]; then
  echo 'Usage: install <version> <hostname> <allow-upgrade>' >&2; exit 1
fi
selector=$1 hostname=$2 allow_upgrade=$3
version=$selector
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
require_supported_ubuntu
current=$(dpkg-query -W -f='${db:Status-Status} ${Version}' dokku 2>/dev/null || true)
if [[ $current = installed\ * ]]; then
  current=${current#installed }
  if [ "$selector" != latest ] && dpkg --compare-versions "$current" gt "$version"; then echo "Dokku downgrade from $current to $version is not supported" >&2; exit 1; fi
  if [ "$selector" != latest ] && dpkg --compare-versions "$current" lt "$version" && [ "$allow_upgrade" != true ]; then echo "Dokku upgrade from $current to $version requires allow_dokku_upgrade" >&2; exit 1; fi
elif command -v dokku >/dev/null; then
  echo 'Existing Dokku is not managed by dpkg; refusing to replace it' >&2; exit 1
else
  current=
fi
# Update the global domain only when it still represents the previous hostname.
old_hostname=$(cat /home/dokku/HOSTNAME 2>/dev/null || true)
if [ -f /home/dokku/VHOST ]; then
  old_domains=$(cat /home/dokku/VHOST)
  if [ -n "$old_domains" ] && [ "$old_domains" != "$hostname" ] && [ "$old_domains" != "$old_hostname" ]; then
    echo 'Global domains were customized; refusing to overwrite them while changing hostname' >&2
    exit 1
  fi
fi
export DEBIAN_FRONTEND=noninteractive
work=$(mktemp -d /root/terraform-dokku.XXXXXXXX)
trap 'rm -rf "$work"' EXIT
install -d -m 0755 /etc/apt/keyrings
curl -fsSL --retry 3 https://packagecloud.io/dokku/dokku/gpgkey -o "$work/dokku.asc"
install -m 0644 "$work/dokku.asc" /etc/apt/keyrings/dokku.asc
printf 'deb [signed-by=/etc/apt/keyrings/dokku.asc] https://packagecloud.io/dokku/dokku/ubuntu/ %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/dokku.list
printf 'dokku dokku/vhost_enable boolean true\ndokku dokku/hostname string %s\ndokku dokku/skip_key_file boolean true\n' "$hostname" | debconf-set-selections
apt-get -o DPkg::Lock::Timeout=600 update
if [ "$selector" = latest ]; then
  if [ -n "$current" ] && [ "$allow_upgrade" = false ]; then
    version=$current
    echo "Keeping installed Dokku $version; upgrades require allow_dokku_upgrade"
  else
    available=$(apt-cache madison dokku)
    version=
    while IFS= read -r candidate; do
      [[ $candidate =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      if [ -z "$version" ] || dpkg --compare-versions "$candidate" gt "$version"; then version=$candidate; fi
    done < <(printf '%s\n' "$available" | awk -F '|' '$3 ~ /https:\/\/packagecloud[.]io\/dokku\/dokku\/ubuntu([\/[:space:]]|$)/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
    [ -n "$version" ] || { echo 'No stable Dokku package version found in the official apt repository' >&2; exit 1; }
    if [ -n "$current" ] && dpkg --compare-versions "$current" gt "$version"; then
      echo "Keeping installed Dokku $current, which is newer than the latest available stable package $version"
      version=$current
    fi
    echo "Selected Dokku $version"
  fi
fi
apt-get -o DPkg::Lock::Timeout=600 install -y "dokku=$version"
[ "$(dpkg-query -W -f='${Version}' dokku)" = "$version" ] || { echo 'Installed Dokku package version does not match' >&2; exit 1; }
dokku plugin:install-dependencies --core
installed=$(dokku version | tr -d '\r')
[[ $installed = "$version" || $installed = "dokku version $version" ]] || { echo "Unexpected Dokku version: $installed" >&2; exit 1; }
dokku domains:set-global "$hostname"
printf '%s\n' "$hostname" > "$work/HOSTNAME"
install -o dokku -g dokku -m 0644 "$work/HOSTNAME" /home/dokku/HOSTNAME
