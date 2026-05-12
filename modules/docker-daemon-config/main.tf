# Docker Daemon Configuration Module
#
# This module manages Docker daemon configuration by:
# - Writing JSON configuration to /etc/docker/daemon.json
# - Restarting Docker daemon when configuration changes
# - Validating configuration before applying
#
# Why separate module?
# - Independent lifecycle from Dokku installation
# - Reusable for other Docker hosts
# - Better error isolation
# - Clear separation of concerns

locals {
  # Generate a unique filename for the temporary config file
  temp_config_file = "/tmp/daemon-config-${uuid()}.json"
}

resource "null_resource" "docker_daemon_config" {
  # Triggers ensure this resource runs when configuration changes
  triggers = {
    docker_daemon_config = var.docker_daemon_config
    ssh_host             = var.ssh_host
    config_hash          = sha256(var.docker_daemon_config)
  }

  # SSH connection configuration
  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.ssh_host
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # Apply Docker daemon configuration
  provisioner "remote-exec" {
    inline = [
      # Create /etc/docker directory if it doesn't exist
      "sudo mkdir -p /etc/docker",

      # Write the configuration directly using echo and base64 decode
      "echo '${base64encode(var.docker_daemon_config)}' | base64 -d | sudo tee ${local.temp_config_file} > /dev/null",

      # Validate JSON syntax before applying
      "if ! python3 -m json.tool ${local.temp_config_file} > /dev/null 2>&1; then",
      "  echo 'ERROR: Invalid JSON in Docker daemon configuration' >&2",
      "  rm -f ${local.temp_config_file}",
      "  exit 1",
      "fi",

      # Backup existing configuration if it exists
      "if [ -f /etc/docker/daemon.json ]; then",
      "  sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)",
      "fi",

      # Move new configuration into place
      "sudo mv ${local.temp_config_file} /etc/docker/daemon.json",

      # Set proper permissions
      "sudo chmod 644 /etc/docker/daemon.json",
      "sudo chown root:root /etc/docker/daemon.json",

      # Restart Docker daemon to apply configuration
      "echo 'Restarting Docker daemon to apply configuration...'",
      "sudo systemctl restart docker",

      # Wait for Docker to be ready
      "sleep 5",

      # Verify Docker is running
      "if ! sudo systemctl is-active --quiet docker; then",
      "  echo 'ERROR: Docker failed to start with new configuration' >&2",
      "  if [ -f /etc/docker/daemon.json.backup.* ]; then",
      "    echo 'Attempting to restore backup configuration...'",
      "    sudo cp /etc/docker/daemon.json.backup.* /etc/docker/daemon.json",
      "    sudo systemctl restart docker",
      "  fi",
      "  exit 1",
      "fi",

      "echo 'Docker daemon configuration applied successfully'"
    ]
  }
}
