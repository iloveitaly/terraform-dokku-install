# Docker Daemon Configuration Module

This module manages Docker daemon configuration by writing a JSON configuration file to `/etc/docker/daemon.json` and restarting the Docker daemon when changes are detected.

## Features

- ✅ Validates JSON configuration before applying
- ✅ Creates backup of existing configuration
- ✅ Restarts Docker daemon when configuration changes
- ✅ Rollback on failure
- ✅ Proper error handling and validation

## Usage

```hcl
module "docker_daemon_config" {
  source = "./modules/docker-daemon-config"

  ssh_host             = "192.168.1.100"
  ssh_user             = "root"
  ssh_private_key_path = "~/.ssh/id_rsa"

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
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| null | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| null | >= 3.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| docker\_daemon\_config | Docker daemon configuration as JSON string | `string` | yes |
| ssh\_host | SSH host where configuration should be applied | `string` | yes |
| ssh\_private\_key\_path | Path to SSH private key for authentication | `string` | yes |
| ssh\_user | SSH user for connecting to the host | `string` | yes |
| depends\_on\_resources | List of resources this module should depend on | `list(string)` | no |

## Outputs

| Name | Description |
|------|-------------|
| configuration\_applied | Whether the Docker daemon configuration was successfully applied |
| configuration\_hash | Hash of the applied Docker daemon configuration |
| resource\_id | Unique identifier for this configuration resource |
