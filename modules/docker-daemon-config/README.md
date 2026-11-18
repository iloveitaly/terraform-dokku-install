# Docker daemon configuration

For most setups, set `docker_daemon_config` in the parent Dokku module. The
parent supplies the verified SSH connection and bundled OpenSSH runner. It
installs Docker first, applies the JSON through this submodule, then installs
Dokku.

```hcl
docker_daemon_config = jsonencode({
  log-driver = "json-file"
  log-opts   = { max-size = "10m", max-file = "3" }
})
```

See a complete module configuration in the [usage instructions](../../README.md#usage).

The submodule checks the new configuration with `dockerd --validate`, replaces
the whole file atomically, then restarts Docker and checks systemd and
`docker info`. It backs up an existing file to `/etc/docker/daemon.json.bak`.
On failure or interruption, it restores the previous file or removes the new
file if none existed, then tries to restart Docker with the previous settings.

If the host has images, containers, or volumes, enable `allow_storage_migration`
to permit storage changes. Migrate Docker data separately. Apply `{}` to request
Docker's default file-based settings, subject to the same storage checks.
Removing the submodule or setting the parent's input to null keeps the last
file on the server.

If you call the submodule directly, supply `connection`, `server_identity`,
`runner`, and `install_id`. See how the parent module calls it in [main.tf](../../main.tf).

Set `runner` to the absolute path to the bundled `scripts/remote.py`. If you copy
the runner or submodule elsewhere, keep the `files/` and
`modules/docker-daemon-config/files/` directories in the same relative locations.
SSH key paths point to files on the Terraform controller. Set
`connection.private_key_path` to null to use the controller's SSH agent. Pass
`install_id` from the Docker installation operation so configuration waits for
Docker and runs again when Terraform replaces that operation.

The inputs changed after the move away from the SSH provider. If you're migrating
an existing installation, follow the parent's
[state migration instructions](../../README.md#migrating-from-the-ssh-provider-implementation) before applying.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.10 |



## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allow\_storage\_migration | Allow changes to Docker storage configuration. | `bool` | `false` | no |
| connection | SSH connection settings. | <pre>object({<br/>    host              = string<br/>    user              = string<br/>    port              = number<br/>    known_hosts_path  = string<br/>    private_key_path  = string<br/>    operation_timeout = number<br/>  })</pre> | n/a | yes |
| docker\_daemon\_config | JSON object to write to /etc/docker/daemon.json. | `string` | n/a | yes |
| install\_id | Docker installation resource ID. | `string` | n/a | yes |
| runner | Absolute path to the SSH runner. | `string` | n/a | yes |
| server\_identity | Identity of the server being configured. | <pre>object({<br/>    id       = string<br/>    revision = string<br/>    host     = string<br/>    user     = string<br/>    port     = number<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| configuration\_applied | Whether Docker daemon configuration completed. |
| configuration\_hash | Hash of the applied Docker daemon configuration. |
| resource\_id | Identifier of the configuration resource. |
<!-- END_TF_DOCS -->
