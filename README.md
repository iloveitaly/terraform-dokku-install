# Install Dokku with Terraform

OpenTofu/Terraform Module to install Docker, Dokku, and Dokku plugins on a server with SSH access using the official Dokku bootstrap script.

This pairs really well with this [other dokku terraform module](https://github.com/aaronstillwell/terraform-provider-dokku) which is focused
on configuring an already-installed Dokku instance.

## Features

- ✅ Uses official Dokku bootstrap installation method
- ✅ Idempotent installation (safe to run multiple times)
- ✅ Modern Ubuntu support (20.04, 22.04, 24.04)
- ✅ Supports latest Dokku versions (0.35.x)
- ✅ Improved error handling and logging
- ✅ Declarative plugin management
- ✅ Supports both shortnames and full URLs for plugins
- ✅ Modular Docker daemon configuration with automatic restart
- ✅ Configuration validation and backup/rollback on failure

## Architecture

This module follows a modular design:

- **Main Module**: Handles Dokku installation, SSH key management, and plugin installation
- **Docker Daemon Config Module**: Separately manages Docker daemon configuration with automatic restart
- **Clean Dependencies**: Docker config is applied after Docker installation but before Dokku installation

The Docker daemon configuration is handled by a separate sub-module (`./modules/docker-daemon-config`) that:

- Validates JSON configuration before applying
- Creates backups of existing configuration
- Restarts Docker daemon when configuration changes
- Automatically rolls back on failure
- Provides detailed error handling

## Requirements

- OpenTofu >= 1.6 or Terraform >= 1.5
- SSH access to target server
- Ubuntu 20.04+ (recommended)

## Usage

See `test/main.tf` for example usage of the module.

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

### Example with Docker Daemon Configuration

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

## Docker Daemon Configuration

The `docker_daemon_config` variable allows you to customize Docker's behavior by providing a JSON configuration that will be written to `/etc/docker/daemon.json`. This is useful for:

### Common Use Cases

**Enable containerd snapshotter** (recommended for better performance and compatibility):

```hcl
docker_daemon_config = jsonencode({
  features = {
    containerd-snapshotter = true
  }
})
```

**Configure logging drivers and rotation**:

```hcl
docker_daemon_config = jsonencode({
  log-driver = "json-file"
  log-opts = {
    max-size = "10m"
    max-file = "3"
  }
})
```

**Set registry mirrors**:

```hcl
docker_daemon_config = jsonencode({
  registry-mirrors = [
    "https://mirror.gcr.io"
  ]
})
```

**Configure storage driver**:

```hcl
docker_daemon_config = jsonencode({
  storage-driver = "overlay2"
  storage-opts = [
    "overlay2.override_kernel_check=true"
  ]
})
```

**Multiple configurations combined**:

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

> **Note**: Docker daemon will be restarted automatically after applying the configuration. The JSON configuration is validated before being applied.

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

## Related Projects

- [Dokku Terraform Install Script](https://github.com/dhinus/dokku-terraform/blob/master/scripts/install-dokku.sh)
- [Original Terraform Dokku Project](https://github.com/brotandgames/terraform-dokku) - this project was my original inspiration