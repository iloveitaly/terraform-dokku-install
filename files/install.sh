#!/usr/bin/env bash
#
# id: bash_install_dokku
# description: Install Dokku using official bootstrap script in an idempotent way
#
# Resources
# - Dokku Official Installation Guide
#   https://dokku.com/docs/getting-started/installation/
#

set -euo pipefail

self=${0##*/}
log() {
  echo "== $self $1"
}

DOKKU_VERSION="$1"
DOKKU_HOSTNAME="$2"

# Validate required parameters
if [ -z "$DOKKU_VERSION" ]; then
    echo "ERROR: DOKKU_VERSION (first argument) is required but not provided" >&2
    echo "Usage: $0 <dokku_version> <dokku_hostname>" >&2
    echo "Example: $0 0.35.20 dokku.example.com" >&2
    exit 1
fi

if [ -z "$DOKKU_HOSTNAME" ]; then
    echo "ERROR: DOKKU_HOSTNAME (second argument) is required but not provided" >&2
    echo "Usage: $0 <dokku_version> <dokku_hostname>" >&2
    echo "Example: $0 0.35.20 dokku.example.com" >&2
    exit 1
fi

log "DOKKU_VERSION=$DOKKU_VERSION"
log "DOKKU_HOSTNAME=$DOKKU_HOSTNAME"

log "Waiting for 20 seconds for cloud-init to finish ..."
sleep 20

log "Update package list ..."
sudo apt-get update -qq >/dev/null

log "Install prerequisites ..."
sudo apt-get install -qq -y apt-transport-https ca-certificates curl gnupg lsb-release

log "Install docker using official script ..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable docker
    sudo systemctl start docker
else
    log "Docker already installed, skipping..."
fi

log "Install dokku using official bootstrap script ..."
if ! command -v dokku &> /dev/null; then
    # Set environment variables for unattended installation
    export DOKKU_TAG="$DOKKU_VERSION"
    export DOKKU_VHOST_ENABLE=true
    export DOKKU_WEB_CONFIG=false
    export DOKKU_HOSTNAME="$DOKKU_HOSTNAME"
    export DOKKU_SKIP_KEY_FILE=true
    
    # Download and run the bootstrap script
    log "Downloading Dokku bootstrap script for version ${DOKKU_VERSION}..."
    if ! curl -fsSL "https://dokku.com/install/v${DOKKU_VERSION}/bootstrap.sh" -o bootstrap.sh; then
      echo "Download of dokku install script failed!" >&2
      exit 1
    fi
    
    log "Running bootstrap.sh..."
    sudo DOKKU_TAG="$DOKKU_VERSION" bash bootstrap.sh
    
    log "Cleaning up bootstrap.sh..."
    rm -f bootstrap.sh
else
    log "Dokku already installed, skipping..."
fi

log "Dokku installation completed successfully!"