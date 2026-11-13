# Install Dokku with Terraform

This OpenTofu/Terraform module installs Docker, Dokku, and Dokku plugins on a server over SSH using the official Dokku bootstrap script.

Use a downstream Dokku provider to manage apps, services, and links on the
installed instance. Active options on the OpenTofu registry:

- [`aliksend/dokku`](https://registry.opentofu.org/providers/aliksend/dokku) (v1.0.24+)
- [`dimmkirr/dokku`](https://registry.opentofu.org/providers/dimmkirr/dokku) (v1.2.0+)
- [`aaronstillwell/dokku`](https://github.com/aaronstillwell/terraform-provider-dokku)

Their `dokku_plugin` resources only verify that a plugin is installed.
Installing plugins requires root access, so this module manages plugin installation.

## Features

- Uses the official Dokku bootstrap script
- Idempotent installation (safe to run multiple times)
- Supports Ubuntu 20.04, 22.04, and 24.04
- Supports latest Dokku versions (0.35.x)
- Improved error handling and logging
- Declarative plugin management
- Supports both shortnames and full URLs for plugins
- Modular Docker daemon configuration with automatic restart
- Configuration validation and backup/rollback on failure

## Architecture

The main module installs Dokku and its plugins and manages SSH keys. A separate
submodule (`./modules/docker-daemon-config`) configures the Docker daemon after
Docker is installed and before Dokku is installed. The submodule:

- Validates the JSON configuration before applying it
- Backs up the existing configuration
- Restarts the Docker daemon when the configuration changes
- Automatically rolls back on failure
- Provides detailed error handling

## Requirements

- OpenTofu / Terraform >= 1.10
- `loafoe/ssh` provider ~> 2.7 (auto-installed)
- SSH access to target server
- Ubuntu 20.04+ (recommended)

## Usage

See `test/main.tf` for an example.

### Example

```hcl
module "dokku" {
  source = "path/to/this/module"

  ssh_host             = "192.168.1.100"
  ssh_user             = "root"
  ssh_private_key_path = "~/.ssh/id_rsa"
  
  dokku_version  = "0.35.20"
  dokku_hostname = "dokku.example.com"

  dokku_plugins = [
    "postgres",
    "redis",
    "mysql"
  ]
}
```

### Example with Docker daemon configuration

```hcl
module "dokku" {
  source = "path/to/this/module"

  ssh_host             = "192.168.1.100"
  ssh_user             = "root"
  ssh_private_key_path = "~/.ssh/id_rsa"
  
  dokku_version  = "0.35.20"
  dokku_hostname = "dokku.example.com"

  # Enable containerd snapshotter for modern image storage
  docker_daemon_config = jsonencode({
    features = {
      containerd-snapshotter = true
    }
    log-driver = "json-file"
    log-opts = {
      max-size = "10m"
      max-file = "3"
    }
  })

  dokku_plugins = [
    "postgres",
    "redis"
  ]
}
```

## Docker daemon configuration

Set `docker_daemon_config` to a JSON configuration to customize Docker's behavior.
The module writes it to `/etc/docker/daemon.json`.

### Common use cases

Enable the containerd snapshotter (recommended for better performance and compatibility):

```hcl
docker_daemon_config = jsonencode({
  features = {
    containerd-snapshotter = true
  }
})
```

Configure logging drivers and rotation:

```hcl
docker_daemon_config = jsonencode({
  log-driver = "json-file"
  log-opts = {
    max-size = "10m"
    max-file = "3"
  }
})
```

Set registry mirrors:

```hcl
docker_daemon_config = jsonencode({
  registry-mirrors = [
    "https://mirror.gcr.io"
  ]
})
```

Configure the storage driver:

```hcl
docker_daemon_config = jsonencode({
  storage-driver = "overlay2"
  storage-opts = [
    "overlay2.override_kernel_check=true"
  ]
})
```

Combine several settings:

```hcl
docker_daemon_config = jsonencode({
  features = {
    containerd-snapshotter = true
  }
  log-driver = "json-file"
  log-opts = {
    max-size = "10m"
    max-file = "3"
  }
  registry-mirrors = [
    "https://mirror.gcr.io"
  ]
})
```

The module validates the JSON before applying it, then restarts the Docker daemon
automatically.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| dokku\_hostname | Dokku hostname | string | `"dokku.yourhost.com"` | no |
| dokku\_plugins | List of Dokku plugins to install. Can be shortnames (postgres, redis, mysql, clickhouse) or full URLs | list(string) | `[]` | no |
| dokku\_ssh\_key\_name | Name for the SSH key in Dokku (used with ssh-keys:add command) | string | `"admin"` | no |
| dokku\_ssh\_public\_key\_path | Path to SSH public key file to add to Dokku for deployments (optional) | string | `null` | no |
| dokku\_version | Dokku version | string | `"0.35.20"` | no |
| docker\_daemon\_config | Custom Docker daemon configuration as JSON string to be written to /etc/docker/daemon.json | string | `null` | no |
| remove\_unlisted\_plugins | Whether to remove plugins that are installed but not listed in dokku\_plugins | bool | `false` | no |
| ssh\_host | SSH host | string | `null` | yes |
| ssh\_private\_key\_path | SSH private key path, for connecting to the server | string | `"~/.ssh/id_rsa"` | no |
| ssh\_user | SSH user | string | `null` | yes |

## Outputs

| Name | Description |
|------|-------------|
| docker\_daemon\_config\_applied | Whether custom Docker daemon configuration was applied |
| docker\_daemon\_config\_hash | Hash of the applied Docker daemon configuration (if any) |
| dokku\_hostname | The hostname configured for Dokku |
| dokku\_installation\_id | Unique identifier for this Dokku installation resource. Changes when the installation is re-triggered. |
| dokku\_plugins | List of Dokku plugins that were configured for installation |
| dokku\_ssh\_key\_configured | Whether an SSH public key was configured for Dokku deployments |
| dokku\_ssh\_key\_name | The name of the SSH key configured in Dokku (if any) |
| dokku\_version | The version of Dokku installed |
| ssh\_host | The SSH host where Dokku is installed |

## Related projects

- [Dokku Terraform Install Script](https://github.com/dhinus/dokku-terraform/blob/master/scripts/install-dokku.sh)
- [Original Terraform Dokku Project](https://github.com/brotandgames/terraform-dokku) - this project was my original inspiration
