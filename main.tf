locals {
  runner = abspath("${path.module}/scripts/remote.py")
  connection = {
    host              = var.ssh_host
    user              = var.ssh_user
    port              = var.ssh_port
    known_hosts_path  = var.ssh_known_hosts_path
    private_key_path  = var.ssh_private_key_path
    operation_timeout = var.ssh_timeout
  }
  server_identity = {
    id       = coalesce(var.server_id, var.ssh_host)
    revision = var.server_revision
    host     = var.ssh_host
    user     = var.ssh_user
    port     = var.ssh_port
  }
}

resource "terraform_data" "install_docker" {
  triggers_replace = {
    server             = local.server_identity
    docker_version     = var.docker_version
    containerd_version = var.containerd_version
    runner             = filesha256(local.runner)
    script             = filesha256("${path.module}/files/install-docker.sh")
    ubuntu_helper      = filesha256("${path.module}/files/ubuntu.sh")
  }
  provisioner "local-exec" {
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = local.runner
      DOKKU_REMOTE_PAYLOAD = jsonencode(merge(local.connection, {
        operation = "install_docker"
        args      = { docker_version = coalesce(var.docker_version, "auto"), containerd_version = coalesce(var.containerd_version, "auto") }
      }))
    }
  }
}

module "docker_daemon_config" {
  count  = var.docker_daemon_config != null ? 1 : 0
  source = "./modules/docker-daemon-config"

  connection              = local.connection
  server_identity         = local.server_identity
  runner                  = local.runner
  docker_daemon_config    = var.docker_daemon_config == null ? null : jsonencode(jsondecode(var.docker_daemon_config))
  allow_storage_migration = var.allow_storage_migration
  install_id              = terraform_data.install_docker.id
  depends_on              = [terraform_data.install_docker]
}

resource "terraform_data" "install" {
  triggers_replace = {
    server              = local.server_identity
    docker_install_id   = terraform_data.install_docker.id
    daemon_config_id    = one(module.docker_daemon_config[*].resource_id)
    version             = var.dokku_version
    hostname            = var.dokku_hostname
    allow_dokku_upgrade = var.allow_dokku_upgrade
    runner              = filesha256(local.runner)
    script              = filesha256("${path.module}/files/install.sh")
    ubuntu_helper       = filesha256("${path.module}/files/ubuntu.sh")
  }
  provisioner "local-exec" {
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = local.runner
      DOKKU_REMOTE_PAYLOAD = jsonencode(merge(local.connection, {
        operation = "install_dokku"
        args      = { version = var.dokku_version, hostname = var.dokku_hostname, allow_upgrade = var.allow_dokku_upgrade }
      }))
    }
  }
  depends_on = [module.docker_daemon_config]
}

# The owner remains stable across key rotations. Its destroy hook revokes keys
# tracked under this module's management ID, including after key renames.
resource "terraform_data" "key_ownership" {
  input = merge(local.connection, {
    management_id = var.management_id
  })
  triggers_replace = {
    server        = local.server_identity
    management_id = var.management_id
  }
  provisioner "local-exec" {
    when    = destroy
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = abspath("${path.module}/scripts/remote.py")
      DOKKU_REMOTE_PAYLOAD = jsonencode({
        host              = self.input.host
        user              = self.input.user
        port              = self.input.port
        known_hosts_path  = self.input.known_hosts_path
        private_key_path  = self.input.private_key_path
        operation_timeout = self.input.operation_timeout
        operation         = "ssh_key_revoke"
        args              = { management_id = self.input.management_id }
      })
    }
  }
}

resource "terraform_data" "ssh_key" {
  triggers_replace = {
    owner_id        = terraform_data.key_ownership.id
    installation    = terraform_data.install.id
    plugins         = terraform_data.plugins.id
    key_name        = var.dokku_ssh_key_name
    public_key      = var.dokku_ssh_public_key_path == null ? null : filesha256(pathexpand(var.dokku_ssh_public_key_path))
    public_key_path = var.dokku_ssh_public_key_path
    runner          = filesha256(local.runner)
    script          = filesha256("${path.module}/files/ssh-key.sh")
  }
  provisioner "local-exec" {
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = local.runner
      DOKKU_REMOTE_PAYLOAD = jsonencode(merge(local.connection, {
        operation = "ssh_key"
        args = {
          management_id   = var.management_id
          name            = var.dokku_ssh_key_name
          public_key_path = var.dokku_ssh_public_key_path
        }
      }))
    }
  }
  depends_on = [terraform_data.plugins]
}
