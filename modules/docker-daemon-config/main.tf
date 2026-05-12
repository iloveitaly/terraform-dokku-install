# Docker Daemon Configuration
#
# Writes /etc/docker/daemon.json and restarts Docker. JSON syntax is validated
# at the variable level (see variables.tf). The file is uploaded to /tmp first
# because the SSH user may not have permission to write to /etc/docker directly;
# `sudo mv` moves it into place.

resource "ssh_resource" "docker_daemon_config" {
  host        = var.ssh_host
  user        = var.ssh_user
  private_key = file(pathexpand(var.ssh_private_key_path))
  timeout     = "5m"

  triggers = {
    ssh_host    = var.ssh_host
    config_hash = sha256(var.docker_daemon_config)
  }

  file {
    content     = var.docker_daemon_config
    destination = "/tmp/dokku-daemon.json"
    permissions = "0644"
  }

  commands = [
    "sudo mkdir -p /etc/docker",
    # Single rotating backup — overwritten each apply so /etc/docker doesn't
    # accumulate timestamped files.
    "if [ -f /etc/docker/daemon.json ]; then sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak; fi",
    "sudo mv /tmp/dokku-daemon.json /etc/docker/daemon.json",
    "sudo chown root:root /etc/docker/daemon.json",
    "echo 'Restarting Docker daemon to apply configuration...'",
    "sudo systemctl restart docker",
    # Poll for readiness instead of a fixed sleep.
    "for i in $(seq 1 30); do sudo systemctl is-active --quiet docker && break; sleep 1; done",
    # Restore from backup on failure.
    "if ! sudo systemctl is-active --quiet docker; then echo 'ERROR: Docker failed to start' >&2; if [ -f /etc/docker/daemon.json.bak ]; then sudo cp /etc/docker/daemon.json.bak /etc/docker/daemon.json; sudo systemctl restart docker; fi; exit 1; fi",
    "echo 'Docker daemon configuration applied successfully'",
  ]
}
