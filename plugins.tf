# Dokku Plugin Management
#
# This file contains all Dokku plugin-related resources and logic.
# It provides declarative plugin management by:
# 1. Reading current plugin state from Dokku
# 2. Installing desired plugins using native dokku commands
# 3. Optionally removing unlisted plugins
#
# Uses native `dokku plugin:install` and `dokku plugin:uninstall` commands directly
# for maximum transparency and minimal abstraction.

# Get current plugin state from Dokku server
data "external" "dokku_plugins" {
  depends_on = [null_resource.install]

  # NOTE I hate this, but I couldn't find a better way to load remote server state :/
  program = [
    "ssh",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", pathexpand(var.ssh_private_key_path),
    "${var.ssh_user}@${var.ssh_host}",
    "dokku plugin:list | python3 -c \"import sys, json; plugins = {}; [plugins.update({l.split()[0]: l.split()[2]}) for l in sys.stdin if l.strip() and len(l.split()) >= 3]; print(json.dumps(plugins))\""
  ]
}

locals {
  # Parse current plugins from server (now a flat map of plugin_name -> status)
  current_plugins = keys(data.external.dokku_plugins.result)

  # Core plugins that should never be removed 
  # Note: We can't easily detect core plugins from just the flat status map,
  # so we'll use a predefined list of known core plugins
  core_plugins = [
    "buildpacks",
    "certs",
    "checks",
    "config",
    "docker-options",
    "domains",
    "enter",
    "git",
    "logs",
    "network",
    "plugin",
    "proxy",
    "ps",
    "repo",
    "resource",
    "run",
    "scheduler",
    "shell",
    "storage",
    "tags",
    "tar",
    "trace"
  ]

  # Plugin URL mapping for shortnames
  # TODO this is not comprehensive, consider expanding
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

  # Convert desired plugins to standardized format
  desired_plugins = [for plugin in var.dokku_plugins : {
    name = contains(keys(local.plugin_urls), plugin) ? plugin : regex("[^/]+(?=\\.git$|$)", replace(plugin, "^.*/", ""))
    url  = contains(keys(local.plugin_urls), plugin) ? local.plugin_urls[plugin] : plugin
  }]

  # Plugins to install (desired but not currently installed)
  plugins_to_install = [for plugin in local.desired_plugins :
    plugin if !contains(local.current_plugins, plugin.name)
  ]

  # Plugins to remove (installed but not desired, excluding core plugins)
  plugins_to_remove = var.remove_unlisted_plugins ? [for plugin in local.current_plugins :
    plugin if !contains([for p in local.desired_plugins : p.name], plugin) &&
    !contains(local.core_plugins, plugin)
  ] : []
}

# Install missing plugins using native dokku commands
resource "null_resource" "install_plugin" {
  for_each = { for plugin in local.desired_plugins : plugin.name => plugin }

  depends_on = [null_resource.install]

  triggers = {
    plugin_name = each.value.name
    plugin_url  = each.value.url
    # NOTE this isn't ideal: you'll get a state changes that you need to confirm
    # after the initial install. I couldn't think of a great way around this:
    # - handle server plugin state changes
    # - avoid using plugins_to_install to avoid terraform state changes
    plugin_missing = !contains(local.current_plugins, each.value.name)

  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.ssh_host
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "10m" # Plugin installation can take time
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Installing Dokku plugin: ${each.value.name} from ${each.value.url}'",
      "sudo dokku plugin:install ${each.value.url} --name ${each.value.name}",
      "echo 'Successfully installed plugin: ${each.value.name}'"
    ]
  }
}

# Remove unwanted plugins (if enabled) using native dokku commands
resource "null_resource" "remove_plugin" {
  for_each = toset(local.plugins_to_remove)

  depends_on = [null_resource.install]

  triggers = {
    plugin_name    = each.value
    remove_enabled = var.remove_unlisted_plugins
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.ssh_host
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Removing Dokku plugin: ${each.value}'",
      "sudo dokku plugin:uninstall ${each.value}",
      "echo 'Successfully removed plugin: ${each.value}'"
    ]
  }
}
