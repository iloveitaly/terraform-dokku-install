# Dokku Installation
#
# Uses loafoe/ssh's ssh_resource so the install is a properly-modeled resource
# instead of a `terraform_data` + provisioner escape hatch. HashiCorp officially
# discourages provisioners; this provider is the standard alternative when no
# native provider exists for the target system.

locals {
  ssh_private_key = file(pathexpand(var.ssh_private_key_path))
}

resource "ssh_resource" "install" {
  host        = var.ssh_host
  user        = var.ssh_user
  private_key = local.ssh_private_key

  timeout     = "10m"
  retry_delay = "5s"

  triggers = {
    dokku_version  = var.dokku_version
    dokku_hostname = var.dokku_hostname
    install_script = filesha256("${path.module}/files/install.sh")
  }

  file {
    source      = "${path.module}/files/install.sh"
    destination = "/tmp/dokku-install.sh"
    permissions = "0755"
  }

  commands = [
    "/tmp/dokku-install.sh ${var.dokku_version} ${var.dokku_hostname}",
    "rm -f /tmp/dokku-install.sh",
  ]
}

module "docker_daemon_config" {
  count  = var.docker_daemon_config != null ? 1 : 0
  source = "./modules/docker-daemon-config"

  ssh_host             = var.ssh_host
  ssh_user             = var.ssh_user
  ssh_private_key_path = var.ssh_private_key_path
  docker_daemon_config = var.docker_daemon_config

  depends_on = [ssh_resource.install]
}

# SSH Key — registered with Dokku for deploys. Separate from the install so it
# can be rotated independently.
resource "ssh_resource" "ssh_key" {
  count = var.dokku_ssh_public_key_path != null ? 1 : 0

  host        = var.ssh_host
  user        = var.ssh_user
  private_key = local.ssh_private_key
  timeout     = "2m"

  triggers = {
    ssh_public_key_content = filesha256(pathexpand(var.dokku_ssh_public_key_path))
    ssh_key_name           = var.dokku_ssh_key_name
    dokku_installation_id  = ssh_resource.install.id
  }

  # Upload the pubkey rather than interpolating it into a shell command —
  # keeps the key out of Terraform state and avoids quoting hazards.
  file {
    source      = pathexpand(var.dokku_ssh_public_key_path)
    destination = "/tmp/dokku-key.pub"
    permissions = "0600"
  }

  commands = [
    "sudo dokku ssh-keys:remove ${var.dokku_ssh_key_name} 2>/dev/null || true",
    "cat /tmp/dokku-key.pub | sudo dokku ssh-keys:add ${var.dokku_ssh_key_name}",
    "rm -f /tmp/dokku-key.pub",
  ]

  depends_on = [module.docker_daemon_config]
}
