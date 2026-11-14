#!/usr/bin/env bash
# Shared by the Docker and Dokku installers; the runner prepends this helper.
require_supported_ubuntu() {
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) return 0 ;;
    *) echo 'Only Ubuntu 22.04, 24.04, and 26.04 are supported' >&2; return 1 ;;
  esac
}
