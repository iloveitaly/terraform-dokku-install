# Dokku Installation Resource
#
# This null_resource performs the Dokku installation on a remote server via SSH.
# 
# Why null_resource?
# - No native Dokku provider exists for OpenTofu/Terraform
# - Dokku installation requires running shell commands on a remote system
# - null_resource provides the perfect abstraction for executing arbitrary commands
# - Allows us to leverage OpenTofu's lifecycle management for what is essentially
#   a one-time installation task
#
# Key Features:
# - Idempotent: Safe to run multiple times (script checks if Dokku already exists)
# - Change Detection: Re-runs when critical parameters or the install script change
# - Resource Management: Properly tracked in OpenTofu state for dependency management
# - SSH-based: Uses standard SSH connection for secure remote execution
#
# Alternatives Considered:
# - local-exec: Would run commands locally, not on target server
# - remote-exec alone: Lacks the resource lifecycle and change detection features
# - Custom provider: Overkill for this simple installation task
# - Configuration management tools: Adds unnecessary complexity for a one-time setup
#

# Local values for dynamic file paths
locals {
  install_script_path = "/tmp/install-${uuid()}.sh"
}

resource "null_resource" "install" {
  # Triggers define when this resource should be recreated/re-executed
  # Adding comprehensive triggers ensures the installation runs when needed
  # If any of these change, the resource will be recreated
  triggers = {
    dokku_version  = var.dokku_version
    dokku_hostname = var.dokku_hostname
    ssh_host       = var.ssh_host
    install_script = filesha256("${path.module}/files/install.sh")
  }

  # SSH connection configuration for remote execution
  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.ssh_host
    private_key = file(pathexpand(var.ssh_private_key_path))
    # Long timeout for slow connections
    timeout = "10m"
  }

  # Upload the installation script to the remote server
  provisioner "file" {
    source      = "${path.module}/files/install.sh"
    destination = local.install_script_path
  }

  # Execute the installation script with proper parameters and cleanup
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.install_script_path}",                                   # Make script executable
      "${local.install_script_path} ${var.dokku_version} ${var.dokku_hostname}", # Run with validated parameters
      "rm -f ${local.install_script_path}"                                       # Clean up temporary file
    ]
  }
}

# Docker Daemon Configuration Module
#
# This module manages Docker daemon configuration separately from the Dokku installation.
# It runs after Docker is installed but before Dokku installation to ensure proper configuration.
#
module "docker_daemon_config" {
  count  = var.docker_daemon_config != null ? 1 : 0
  source = "./modules/docker-daemon-config"

  ssh_host             = var.ssh_host
  ssh_user             = var.ssh_user
  ssh_private_key_path = var.ssh_private_key_path
  docker_daemon_config = var.docker_daemon_config

  # Ensure this runs after Docker is installed but before Dokku
  depends_on = [null_resource.install]
}

# SSH Key Management Resource
#
# This resource adds an SSH public key to Dokku for deployment access.
# It runs after the Dokku installation is complete and only if a public key path is provided.
#
# Why separate resource?
# - Independent lifecycle from installation (key can be changed without reinstalling Dokku)
# - Clear dependency chain (requires Dokku to be installed first)
# - Optional functionality (only runs if public key is provided)
# - Better error isolation (SSH key issues don't affect Dokku installation)
#
resource "null_resource" "ssh_key" {
  count = var.dokku_ssh_public_key_path != null ? 1 : 0

  # This resource depends on the Dokku installation and Docker configuration being complete
  depends_on = [
    null_resource.install,
    module.docker_daemon_config
  ]

  # Triggers for when to update the SSH key
  triggers = {
    ssh_public_key_content = var.dokku_ssh_public_key_path != null ? filesha256(pathexpand(var.dokku_ssh_public_key_path)) : ""
    ssh_key_name           = var.dokku_ssh_key_name
    dokku_installation_id  = null_resource.install.id
  }

  # SSH connection configuration (same as installation)
  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.ssh_host
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "2m"
  }

  # Add the SSH public key to Dokku
  provisioner "remote-exec" {
    inline = [
      # Remove existing key with same name if it exists (idempotent)
      "sudo dokku ssh-keys:remove ${var.dokku_ssh_key_name} 2>/dev/null || true",
      # Add the new public key (read content locally and pipe to remote command)
      "echo '${file(pathexpand(var.dokku_ssh_public_key_path))}' | sudo dokku ssh-keys:add ${var.dokku_ssh_key_name}"
    ]
  }
}
