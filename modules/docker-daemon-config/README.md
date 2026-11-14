# Docker daemon configuration

This submodule applies a JSON object after Docker installation and before Dokku
installation. The parent module supplies the verified SSH connection and bundled
OpenSSH runner. Prefer the parent's `docker_daemon_config` input for normal use.

For example, add this input to your Dokku module configuration:

```hcl
docker_daemon_config = jsonencode({
  log-driver = "json-file"
  log-opts   = { max-size = "10m", max-file = "3" }
})
```

The parent module handles installation order and SSH settings. See its
[usage instructions](../../README.md#usage) for a complete configuration.

The remote transaction validates the candidate with `dockerd --validate`, stages
an atomic replacement, restarts Docker, and checks both systemd and `docker info`.
On failure or interruption it restores the previous file, or removes the new file
if none existed, and attempts to restart Docker with the previous configuration.
An existing file is also backed up to `/etc/docker/daemon.json.bak`.

The configuration replaces the entire daemon file. Storage changes are rejected
when images, containers, or volumes exist unless `allow_storage_migration` is
explicitly enabled. That flag permits the operation; it does not migrate Docker
data. Applying `{}` requests default file-based settings, subject to the same
storage checks. Removing the submodule
or setting the parent's input to null leaves the last remote file in place.

Inputs changed from the old SSH-provider version. Existing standalone callers
must supply `connection`, `server_identity`, `runner`, and `install_id` as shown
by the parent module in [main.tf](../../main.tf). `runner` must be the absolute
path to the bundled `scripts/remote.py`; its sibling `files/` and
`modules/docker-daemon-config/files/` directories must remain available. Copying
only this submodule or the runner is insufficient. Connection key paths refer to
files on the Terraform controller. Set `connection.private_key_path` to null to
use its SSH agent. Use `install_id` from the operation that installed Docker to
establish the dependency and rerun configuration after replacement.

Follow the parent's [state migration instructions](../../README.md#migrating-from-the-ssh-provider-implementation)
before applying to an installation managed by the old provider.

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
