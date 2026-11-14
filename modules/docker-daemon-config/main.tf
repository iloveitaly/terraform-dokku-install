resource "terraform_data" "docker_daemon_config" {
  triggers_replace = {
    server                  = var.server_identity
    install_id              = var.install_id
    config_hash             = sha256(var.docker_daemon_config)
    allow_storage_migration = var.allow_storage_migration
    runner                  = filesha256(var.runner)
    script                  = filesha256("${path.module}/files/docker-config.sh")
  }
  provisioner "local-exec" {
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = var.runner
      DOKKU_REMOTE_PAYLOAD = jsonencode(merge(var.connection, {
        operation = "configure_docker"
        args      = { config = var.docker_daemon_config, allow_storage_migration = var.allow_storage_migration }
      }))
    }
  }
}
