# Install Dokku with Terraform

OpenTofu/Terraform Module to install Docker, Dokku, and Dokku plugins on a server with SSH access using the official Dokku bootstrap script.

## Features

- ✅ Uses official Dokku bootstrap installation method
- ✅ Idempotent installation (safe to run multiple times)
- ✅ Modern Ubuntu support (20.04, 22.04, 24.04)
- ✅ Supports latest Dokku versions (0.35.x)
- ✅ Improved error handling and logging
- ✅ Declarative plugin management
- ✅ Supports both shortnames and full URLs for plugins

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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| dokku\_hostname | Dokku hostname | string | `"dokku.yourhost.com"` | no |
| dokku\_ssh\_key\_name | Name for the SSH key in Dokku (used with ssh-keys:add command) | string | `"admin"` | no |
| dokku\_ssh\_public\_key\_path | Path to SSH public key file to add to Dokku for deployments (optional) | string | `null` | no |
| dokku\_version | Dokku version | string | `"0.35.20"` | no |
| ssh\_host | SSH host | string | `"192.168.0.100"` | no |
| ssh\_private\_key\_path | SSH private key path | string | `"~/.ssh/id_rsa"` | no |
| ssh\_user | SSH user | string | `"root"` | no |

## Outputs

| Name | Description |
|------|-------------|
| dokku\_hostname | The hostname configured for Dokku |
| dokku\_version | The version of Dokku installed |
| installation\_id | Unique identifier for this Dokku installation |
| ssh\_host | The SSH host where Dokku is installed |
| ssh\_key\_configured | Whether an SSH public key was configured for Dokku deployments |
| ssh\_key\_name | The name of the SSH key configured in Dokku (if any) |

## Related Projects

* https://github.com/dhinus/dokku-terraform/blob/master/scripts/install-dokku.sh
* https://github.com/brotandgames/terraform-dokku this project was my original inspiration