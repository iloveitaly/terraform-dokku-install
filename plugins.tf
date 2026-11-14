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

  legacy_plugins = [for plugin in var.dokku_plugins : {
    name     = contains(keys(local.plugin_urls), plugin) ? plugin : trimprefix(trimsuffix(basename(plugin), ".git"), "dokku-")
    url      = lookup(local.plugin_urls, plugin, plugin)
    revision = null
  }]
  explicit_plugins = [for name, plugin in var.dokku_plugin_definitions : {
    name     = name
    url      = plugin.url
    revision = plugin.revision
  }]
  desired_plugins = concat(local.legacy_plugins, local.explicit_plugins)
}

# A single operation serializes mutations of Dokku's global plugin registry.
resource "terraform_data" "plugins" {
  triggers_replace = {
    installation = terraform_data.install.id
    plugins      = local.desired_plugins
    runner       = filesha256(local.runner)
    script       = filesha256("${path.module}/files/plugins.sh")
  }
  lifecycle {
    precondition {
      condition     = length(distinct([for p in local.desired_plugins : p.name])) == length(local.desired_plugins)
      error_message = "Plugin names must be unique after normalizing legacy plugin URLs."
    }
    precondition {
      condition     = alltrue([for p in local.legacy_plugins : can(regex("^https://", p.url)) && can(regex("^[a-z][a-z0-9-]*$", p.name))])
      error_message = "Unknown plugin short name or invalid normalized plugin name; use a supported short name or an explicit plugin definition."
    }
  }
  provisioner "local-exec" {
    command = "python3 \"$DOKKU_RUNNER\""
    environment = {
      DOKKU_RUNNER = local.runner
      DOKKU_REMOTE_PAYLOAD = jsonencode(merge(local.connection, {
        operation = "plugins"
        args      = { plugins = local.desired_plugins, remove_unlisted = false }
      }))
    }
  }
  depends_on = [terraform_data.install]
}
