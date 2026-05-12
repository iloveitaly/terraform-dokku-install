# Dokku Plugin Management
#
# `dokku plugin:install` is idempotent server-side, so we only need triggers
# keyed on name+url — no remote-state discovery required.

locals {
  plugin_urls = {
    postgres      = "https://github.com/dokku/dokku-postgres.git"
    redis         = "https://github.com/dokku/dokku-redis.git"
    mysql         = "https://github.com/dokku/dokku-mysql.git"
    clickhouse    = "https://github.com/dokku/dokku-clickhouse.git"
    mariadb       = "https://github.com/dokku/dokku-mariadb.git"
    mongo         = "https://github.com/dokku/dokku-mongo.git"
    elasticsearch = "https://github.com/dokku/dokku-elasticsearch.git"
    memcached     = "https://github.com/dokku/dokku-memcached.git"
    rabbitmq      = "https://github.com/dokku/dokku-rabbitmq.git"
    letsencrypt   = "https://github.com/dokku/dokku-letsencrypt.git"
    typesense     = "https://github.com/dokku/dokku-typesense.git"
  }

  desired_plugins = [for plugin in var.dokku_plugins : {
    name = contains(keys(local.plugin_urls), plugin) ? plugin : trimsuffix(basename(plugin), ".git")
    url  = contains(keys(local.plugin_urls), plugin) ? local.plugin_urls[plugin] : plugin
  }]
}

resource "ssh_resource" "install_plugin" {
  for_each = { for plugin in local.desired_plugins : plugin.name => plugin }

  host        = var.ssh_host
  user        = var.ssh_user
  private_key = local.ssh_private_key
  timeout     = "10m"

  triggers = {
    plugin_name = each.value.name
    plugin_url  = each.value.url
  }

  commands = [
    "echo 'Installing Dokku plugin: ${each.value.name} from ${each.value.url}'",
    # `dokku plugin:install` is a no-op if already installed at the same URL.
    "sudo dokku plugin:install ${each.value.url} --name ${each.value.name} || true",
    "echo 'Plugin ready: ${each.value.name}'",
  ]

  depends_on = [ssh_resource.install]
}
