#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run as root' >&2; exit 1; }
[ "$#" = 2 ] && [[ $1 =~ ^[0-9a-zA-Z.+:~_-]+$ && $2 =~ ^[0-9a-zA-Z.+:~_-]+$ ]] || { echo 'Usage: install-docker <docker-ce upstream version> <containerd.io upstream version>' >&2; exit 1; }
exec 9>/run/lock/terraform-dokku.lock
flock -w 600 9 || { echo 'Timed out waiting for Dokku provisioning lock' >&2; exit 1; }
if command -v cloud-init >/dev/null; then timeout 600 cloud-init status --wait || { echo 'cloud-init did not finish successfully' >&2; exit 1; }; fi
# shellcheck disable=SC1091
. /etc/os-release
[ "$ID" = ubuntu ] && [[ $VERSION_ID = 22.04 || $VERSION_ID = 24.04 ]] || { echo 'Only Ubuntu 22.04 and 24.04 are supported' >&2; exit 1; }
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
docker_version=$(resolve_version docker-ce "$1")
cli_version=$(resolve_version docker-ce-cli "$1")
containerd_version=$(resolve_version containerd.io "$2")
# Never let a requested version silently downgrade an existing engine or runtime.
for entry in "docker-ce=$docker_version" "docker-ce-cli=$cli_version" "containerd.io=$containerd_version"; do
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
cat > "$work/docker.pref" <<PREF
Package: docker-ce
Pin: version $docker_version
Pin-Priority: 990

Package: docker-ce-cli
Pin: version $cli_version
Pin-Priority: 990

Package: containerd.io
Pin: version $containerd_version
Pin-Priority: 990
PREF
install -m 0644 "$work/docker.pref" /etc/apt/preferences.d/terraform-dokku-docker
apt-get -o DPkg::Lock::Timeout=600 install -y "docker-ce=$docker_version" "docker-ce-cli=$cli_version" "containerd.io=$containerd_version"
[ "$(dpkg-query -W -f='${Version}' docker-ce)" = "$docker_version" ] && [ "$(dpkg-query -W -f='${Version}' docker-ce-cli)" = "$cli_version" ] && [ "$(dpkg-query -W -f='${Version}' containerd.io)" = "$containerd_version" ] || { echo 'Installed Docker package versions do not match' >&2; exit 1; }
systemctl enable --now docker
docker info >/dev/null
