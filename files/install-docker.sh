#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
if [ "$#" != 2 ] || ! [[ ( $1 = auto || $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ) && ( $2 = auto || $2 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ) ]]; then
  echo 'Usage: install-docker <auto|docker-ce upstream version> <auto|containerd.io upstream version>' >&2; exit 1
fi
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
if command -v cloud-init >/dev/null; then timeout 600 cloud-init status --wait || { echo 'cloud-init did not finish successfully' >&2; exit 1; }; fi
require_supported_ubuntu
docker_requested=$1
containerd_requested=$2
if [ "$VERSION_ID" = 26.04 ]; then
  default_docker=29.4.3
  default_containerd=2.2.5
else
  default_docker=28.5.2
  default_containerd=1.7.28
fi
if [ "$docker_requested" = auto ]; then docker_requested=$default_docker; fi
if [ "$containerd_requested" = auto ]; then containerd_requested=$default_containerd; fi
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install -y ca-certificates curl python3 util-linux
install -d -m 0755 /etc/apt/keyrings
work=$(mktemp -d /root/terraform-dokku.XXXXXXXX)
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg -o "$work/docker.asc"
install -m 0644 "$work/docker.asc" /etc/apt/keyrings/docker.asc
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' "$(dpkg --print-architecture)" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list
apt-get -o DPkg::Lock::Timeout=600 update
resolve_version() {
  local package=$1 wanted=$2 version
  version=$(apt-cache madison "$package" | awk -F '|' -v wanted="$wanted" '{gsub(/^[ \t]+|[ \t]+$/, "", $2); v=$2; sub(/^[0-9]+:/, "", v); if (index(v, wanted "-") == 1) {print $2; exit}}')
  [ -n "$version" ] || { echo "No $package package for upstream version $wanted" >&2; return 1; }
  printf '%s' "$version"
}
docker_version=$(resolve_version docker-ce "$docker_requested")
cli_version=$(resolve_version docker-ce-cli "$docker_requested")
containerd_version=$(resolve_version containerd.io "$containerd_requested")
packages=("docker-ce=$docker_version" "docker-ce-cli=$cli_version" "containerd.io=$containerd_version")
# Never let a requested version silently downgrade an existing engine or runtime.
for entry in "${packages[@]}"; do
  package=${entry%%=*} desired=${entry#*=}
  installed=$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$package" 2>/dev/null || true)
  if [[ $installed = installed\ * ]]; then
    installed=${installed#installed }
    if dpkg --compare-versions "$installed" gt "$desired"; then
      echo "Downgrade of $package from $installed to $desired is not supported" >&2
      exit 1
    fi
  fi
done
# Keep later apt operations, including Dokku dependencies, on these versions.
for entry in "${packages[@]}"; do
  printf 'Package: %s\nPin: version %s\nPin-Priority: 990\n\n' "${entry%%=*}" "${entry#*=}"
done > "$work/docker.pref"
install -m 0644 "$work/docker.pref" /etc/apt/preferences.d/terraform-dokku-docker
apt-get -o DPkg::Lock::Timeout=600 install -y "${packages[@]}"
for entry in "${packages[@]}"; do
  package=${entry%%=*} desired=${entry#*=}
  if [ "$(dpkg-query -W -f='${Version}' "$package")" != "$desired" ]; then
    echo 'Installed Docker package versions do not match' >&2; exit 1
  fi
done
systemctl enable --now docker
docker info >/dev/null
