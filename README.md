# Install Dokku with Terraform

This OpenTofu/Terraform module installs Docker, Dokku, and Dokku plugins on a server over SSH using the official package repositories.

You can manage apps, services, and links on the installed instance with any of
these Dokku providers.

- [`aliksend/dokku`](https://registry.opentofu.org/providers/aliksend/dokku) (v1.0.24+)
- [`dimmkirr/dokku`](https://registry.opentofu.org/providers/dimmkirr/dokku) (v1.2.0+)
- [`aaronstillwell/dokku`](https://github.com/aaronstillwell/terraform-provider-dokku)

The providers' `dokku_plugin` resource checks whether a plugin is installed.
This module handles installation, which requires root access.

If you're upgrading from the SSH-provider implementation, follow the
[state migration steps](#migrating-from-the-ssh-provider-implementation) before applying.

## Install the released module

Use `iloveitaly/install/dokku` as the registry source. A constraint such as
`~> 0.1.0` selects the module version. The `dokku_version` input selects the
Dokku package on the server.

Maintainers register the module once using the [publishing guide](PUBLISHING.md).
While registry indexing is pending, use the tagged Git source.

```hcl
source = "git::https://github.com/iloveitaly/terraform-dokku-install.git?ref=v0.1.0"
```

Omit the `version` argument with the Git source because the tag selects the
version. The [basic example](examples/basic/README.md) uses the tagged source.

## Usage

On macOS or Linux, install Terraform or OpenTofu >= 1.10, Python >= 3.9, and
OpenSSH. The module uses the built-in `terraform_data` resource, so you need no
third-party Terraform providers.

The server needs Ubuntu 22.04, 24.04, or 26.04 with systemd, SSH, and passwordless
sudo. Make sure SSH is reachable before applying. The installer waits for
cloud-init after it connects.

Get the server's SSH host key through your cloud console or another trusted
source and save it in a dedicated known_hosts file. If you collect the key with
`ssh-keyscan`, verify its fingerprint against the trusted source before applying.
For a nonstandard port, use `[hostname]:port` in known_hosts. The runner skips
your normal SSH configuration.

```hcl
module "dokku" {
  source  = "iloveitaly/install/dokku"
  version = "~> 0.1.0"

  ssh_host             = "192.0.2.10"
  ssh_user             = "ubuntu"
  ssh_known_hosts_path = "~/.ssh/dokku_known_hosts"
  dokku_hostname       = "dokku.example.com"
  dokku_version        = "latest"

  # Optional. Pass the instance ID to detect replacement at the same SSH address.
  # server_id = "your-cloud-instance-id"

  # Optional. Omit ssh_private_key_path to use your local SSH agent.
  # ssh_private_key_path = "~/.ssh/id_ed25519"

  docker_daemon_config = jsonencode({
    log-driver = "json-file"
    log-opts   = { max-size = "10m", max-file = "3" }
  })

  dokku_plugin_definitions = {
    redis = {
      url      = "https://github.com/dokku/dokku-redis.git"
      revision = "e9df51c60fc5e14a486fab6e740e35f110a00995"
    }
  }
}
```

`dokku_hostname` sets Dokku's global domain. With the value above, an app named
`api` gets `api.dokku.example.com` by default. Set custom domains for individual
apps with `dokku domains:set`. [Dokku domain documentation](https://dokku.com/docs/configuration/domains/)

The [basic example](examples/basic/README.md) walks through loading an SSH agent,
entering server details, and applying a saved plan. For a shorter configuration,
see `test/main.tf`. Automated tests are in `tests/`.

SSH paths point to files on the machine running Terraform.

| Input | Purpose | When needed |
| --- | --- | --- |
| `ssh_known_hosts_path` | Verified SSH host keys for the server | Every remote operation, including destroy |
| `ssh_private_key_path` | Controller key used to connect to `ssh_user` | Optional. Defaults to `null`, which uses the SSH agent. |
| `dokku_ssh_public_key_path` | Public client key to authorize for Dokku deployments | Plan and apply when configuring a deploy key |

Omit `ssh_private_key_path` or set it to `null` to use the SSH agent through
`SSH_AUTH_SOCK`. Load passphrase-protected keys into the agent before applying.
The runner uses noninteractive SSH.

## Execution and lifecycle

The module installs Docker and applies any daemon configuration before installing
Dokku and setting its hostname. It then configures plugins and the deploy key.
All changes share one lock on the server. Each operation has an `ssh_timeout`
in seconds. A failed command stops the apply on the first attempt. Output goes
to the Terraform console. The deprecated `dokku_install_stdout` output returns
null.

OpenSSH reads the private key directly from the supplied path or uses the local
agent. It verifies the host key and disables agent forwarding. Terraform stores
configuration, public key hashes, and local paths in state. The private key
contents stay with OpenSSH or the agent. Protect the state file as you normally
would.

Use `server_id` to identify a server that might be replaced while keeping the
same IP address or DNS name. If Terraform creates the server, reference the
cloud resource's instance ID. If you enter the ID by hand, update it when you
replace the server. Omit `server_id` to use `ssh_host` as the ID. Change
`server_revision` after a rebuild that keeps both the address and the ID.

Changing the effective server ID or `server_revision` reruns setup on the next
apply and replaces deploy-key ownership. Terraform runs the revocation hook with
the previous SSH connection details before configuring the key again.

Terraform refresh reads the installation records in state. To reapply the Dokku
configuration, replace the installation resource using the
[upgrade steps](#versions-and-upgrades).

Check for manual changes on the server with `sudo dokku version`,
`sudo dokku domains:report --global`, `sudo dokku plugin:list`,
`sudo dokku ssh-keys:list`, and `sudo docker info`. Compare these with the desired
inputs and `/etc/docker/daemon.json` before rerunning setup.

Destroy leaves Docker, Dokku, plugins, and daemon configuration on the server and
revokes the deploy key recorded under this module's `management_id`. Use a unique
`management_id` for each independently managed installation on a host. Keep the
server and local key files accessible until revocation finishes. If the server
is already gone, check whether any live host still needs the key revoked before
removing its obsolete ownership resource from state.

Keep the module block in place when you run `terraform destroy` so Terraform
can run the revocation hook. If you plan to delete the block, first apply
`dokku_ssh_public_key_path = null` to revoke the key.
[Destroy-time provisioner behavior](https://developer.hashicorp.com/terraform/language/provisioners#remove-a-resource-block-containing-a-destroy-time-provisioner)

An SSH timeout closes the connection, and package operations may still be running
on the server. Check the server before retrying. The lock prevents simultaneous
configuration changes.

## Versions and upgrades

On a fresh server, the default `dokku_version = "latest"` installs the highest
stable numeric release in Dokku's official apt repository. Set an exact version
such as `"0.38.34"` for repeatable installs. Docker Engine and containerd use
fixed defaults for each Ubuntu release.

| Target | Docker Engine | containerd.io |
| --- | --- | --- |
| Ubuntu 22.04 / 24.04 | 28.5.2 | 1.7.28 |
| Ubuntu 26.04 | 29.4.3 | 2.2.5 |

Leave `docker_version` and `containerd_version` unset or null for these defaults.
To override either pin, choose a numeric version available for the target OS.
Ubuntu 26.04 lacks the older Docker and containerd defaults and may lack older
Dokku versions. On 26.04, `latest` selects a stable package from that release's
official repository.

An upgrade from module 0.1.0 reruns setup once because the installer scripts
changed. This applies to pinned versions too. The default Docker and containerd
inputs change to null. On Ubuntu 22.04 and 24.04, those defaults still resolve to
the same package versions.

For Docker and containerd, the installer maps upstream versions to distribution
packages, installs and verifies them, then pins them so unrelated apt upgrades
skip them. It installs Dokku at an exact package version. Availability depends
on the upstream repositories. Manage OS upgrades and other packages separately.

The installer evaluates the Dokku selector when it runs.

| Server state | Selector | Result |
| --- | --- | --- |
| Dokku is absent | `latest` | Install the highest stable numeric version available from the official repository |
| Dokku is installed | `latest`, upgrades disabled | Retain the installed version and reconcile the hostname |
| Dokku is installed | `latest`, `allow_dokku_upgrade = true` | Upgrade to the latest available stable version, retaining an installed version if it is newer |
| Dokku is installed | Exact version | Require opt-in for upgrades and reject downgrades |

The installer resolves package versions on the server during apply. A new
upstream release alone produces no plan changes. For a module named `dokku`
in the root configuration, upgrade to the latest version with a saved plan.

1. Set its `dokku_version` input to `"latest"` and `allow_dokku_upgrade` to `true`.
   Read the applicable Dokku migration guides and back up applications first.
2. Create and review a plan that reruns the installation resource.

   ```sh
   terraform plan -replace='module.dokku.terraform_data.install' -out=dokku-upgrade.tfplan
   ```

   Use the resource's full address if your module is nested or named differently.
   The apply also reconciles plugins and the deploy key after installation.
3. Apply the reviewed plan and check `sudo dokku version` on the server.

   ```sh
   terraform apply dokku-upgrade.tfplan
   ```

4. Set `allow_dokku_upgrade` back to `false` and apply to restore the upgrade guard.

The `dokku_version` output reports the requested selector, such as `"latest"`.
Use `sudo dokku version` for the installed numeric release.

Changing the hostname also updates the global domain. The installer stops if
the change would overwrite global domains you configured separately.

## Plugins

Give each explicit plugin a stable name and an HTTPS repository URL. To pin its
revision, use a full commit SHA because branches and tags can move. The module
applies revision changes and verifies them against the repository. If you change
a source URL, the module stops and reports the change. Replace that plugin
manually.

The legacy `dokku_plugins` list accepts plugin short names and URLs, normalizes
`dokku-` prefixes, and rejects duplicate names. On first install, legacy entries
and explicit entries without a revision get whatever revision is current in the
repository at that time. Removing a plugin from the inputs leaves it installed.
Check its services and data before uninstalling it manually.

## Docker daemon configuration

Pass a JSON object to `docker_daemon_config`. The module ignores formatting-only
changes. When the configuration changes, it runs `dockerd --validate`, backs up
any existing file to `/etc/docker/daemon.json.bak`, and replaces the entire
`/etc/docker/daemon.json` file. It restarts Docker and checks that it is ready.
If the operation fails or is interrupted, the module restores the previous file
or removes the new file if none existed. It then tries to restart Docker with
the previous settings.

The module configures Docker before installing Dokku. On a host with images,
containers, or volumes, set `allow_storage_migration = true` to permit changes to
the storage driver, containerd snapshotter, storage options, or data root. Plan
the data migration separately. Switching image stores can hide existing images
and containers.

Set the input back to null to keep the last configuration on the server.
Apply `{}` to request Docker defaults, subject to the same storage checks.
Schedule configuration changes around workloads that a Docker restart could interrupt.

## Deploy keys

Set `dokku_ssh_public_key_path` to register one deploy key. The module validates
the replacement before editing authorized_keys. When you rotate or rename a key,
the module backs up the old authorization and restores it if the change fails.
It tracks the exact key line for each `management_id` in a root-owned ledger
under `/var/lib/terraform-dokku/keys/`. Setting the path to null or destroying
the module revokes the recorded key and leaves other keys in place.

The module refuses to take over an existing key with the requested name. During
migration, choose a new key name and test deployment access before revoking
the old key. Keep a separate credential for the controller's SSH access.

## Migrating from the SSH-provider implementation

Review the migration plan before applying to an existing server. This release
changes resource types in state and the inputs to the Docker submodule. Set
`ssh_known_hosts_path` for host verification. The controller uses the SSH agent
by default.

1. Set `umask 077` and back up Terraform state with
   `terraform state pull > /secure/path/dokku-state-backup.json`, choosing an
   existing directory outside the repository. Record the installed versions,
   deploy keys, plugin names and URLs, and daemon configuration.
2. Add a verified known_hosts file. Set `server_id` to the cloud instance ID if
   available. Set `ssh_private_key_path` if you connect with a key file. Match
   the installed Docker, containerd, and Dokku versions to avoid an unintended
   upgrade or a rejected downgrade. Choose a new deploy-key name so the module
   can record ownership.
3. Run `terraform state list` and remove only the old `ssh_resource` addresses
   belonging to this installation with `terraform state rm '<exact-address>'`.
   Look for install, install_plugin instances, ssh_key, and the daemon submodule
   resource. Nested modules add prefixes to these addresses. Review older
   `null_resource` addresses the same way. Remove the records from state to leave
   the remote software and keys intact. Skip any intermediate destroy plan.
4. Initialize and review the new plan. Terraform creates new resource records
   and runs the setup scripts against the existing server. Check plugin names
   before normalizing legacy URLs. Dokku treats `dokku-postgres` and `postgres`
   as separate plugins, so reconcile them manually. Removing the old name from
   Terraform leaves that plugin and its services on the server.
5. Apply and verify the version, hostname, plugins, Docker readiness, and
   deployment access. Then revoke the old unmanaged deploy key. Previous state
   backups may contain controller private keys. Keep or dispose of those backups
   securely according to your state retention policy.

## Validation and integration tests

Both installers use `files/ubuntu.sh` to select Ubuntu packages and repositories.
The SSH runner bundles the helper with each installer. Terraform tracks changes
to the helper when planning replacements.

```sh
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
python3 -m unittest discover -s tests -v
python3 scripts/check_package.py --ref HEAD --cli terraform
python3 scripts/check_package.py --ref HEAD --cli tofu
shellcheck files/*.sh modules/docker-daemon-config/files/*.sh integration/run.sh
```

Run the same configuration tests in OpenTofu with `tofu test`. CI tests Terraform
1.10.5 and 1.17.2 and OpenTofu 1.10.0 and 1.13.9. The Python tests exercise failure
paths with isolated files and fake services.

The package checks unpack a Git archive into a separate consuming configuration
and apply it with a fake SSH command. They move the consumer and its module cache
before destroying from the new path. Commit the files under test so `git archive`
includes them.

`integration/run.sh` exercises installation, a no-change second plan, pinned and
latest upgrades, plugin failures, hostname changes, key rotation and revocation,
host-key rejection, Docker rollback, ownership replacement, and destroy-time key
revocation. It requires Terraform, Python, OpenSSH, and a fresh disposable Ubuntu
22.04, 24.04, or 26.04 target. The script creates temporary controller keys and
state. It tests a Git archive of `HEAD` by default, or the ref in
`DOKKU_PACKAGE_REF`. It moves the consumer and module cache before destroy to
check key revocation from the new path.

For a VM you created separately, supply all four connection variables.

```sh
DOKKU_DISPOSABLE_HOST=yes SSH_HOST=192.0.2.10 SSH_USER=ubuntu \
  SSH_KEY_PATH=/path/to/controller-key \
  SSH_KNOWN_HOSTS_PATH=/path/to/verified-known-hosts \
  bash integration/run.sh
```

`SSH_PORT` defaults to 22. Use key paths that exist on the controller and a
known_hosts entry that matches the host and port used by the test.

On 22.04 and 24.04 the test installs Dokku 0.35.19, upgrades to 0.35.20, then
selects `latest`. On 26.04 it starts with `latest` and skips the distinct-version
upgrade by default. To test an upgrade between exact versions, set
`DOKKU_TEST_INITIAL_VERSION` and `DOKKU_TEST_UPGRADE_VERSION` to available numeric
releases. The 26.04 live run used 0.38.33 and 0.38.34.

Leave `SSH_HOST` unset only on a disposable Ubuntu 22.04, 24.04, or 26.04 runner.
In that mode the script installs packages locally, configures localhost SSH, and
appends a temporary key to the current user's `authorized_keys`. To run the
test on the Ubuntu 24.04 GitHub Actions runner, start the `Validate` workflow
manually and enable the `integration` input, which defaults to off.

The script creates and destroys the Terraform resource records. Installed
software and other test-host changes stay in place. You create and delete the
disposable VM yourself. Inspect the results before deleting it. On success, the
script removes temporary controller files. On failure, it keeps them and prints
their location.

CI checks the minimum and current CLI versions separately from live installation.

| Target | Docker / containerd | Dokku | Verification |
| --- | --- | --- | --- |
| Ubuntu 26.04, ARM64 (OrbStack) | 29.4.3 / 2.2.5 | 0.38.33 → 0.38.34 (`latest` at test time) | Live installation, no-op plan, upgrades, hostname, plugins, keys, rollback through systemd restart limits, and relocated destroy |
| Ubuntu 24.04, ARM64 | 28.5.2 / 1.7.28 | 0.35.19 → 0.35.20 → 0.38.34 (`latest` at test time) | Live installation, no-op plan, upgrades, hostname, plugins, keys, rollback, and destroy |
| Ubuntu 22.04 | Configurable | Configurable | Installer accepts this release. It was outside the live test run. |

Use terraform-docs 0.25.1 to regenerate the reference tables.

```sh
terraform-docs .
terraform-docs -c .terraform-docs.yml modules/docker-daemon-config
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| docker\_daemon\_config | ./modules/docker-daemon-config | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allow\_dokku\_upgrade | Allow changing an already installed Dokku version. | `bool` | `false` | no |
| allow\_storage\_migration | Allow changes to Docker storage configuration on an existing Docker installation. | `bool` | `false` | no |
| containerd\_version | containerd.io version to install. Null selects 1.7.28 on Ubuntu 22.04/24.04 or 2.2.5 on Ubuntu 26.04. | `string` | `null` | no |
| docker\_daemon\_config | Optional JSON object to write to /etc/docker/daemon.json. | `string` | `null` | no |
| docker\_version | Docker Engine version to install. Null selects 28.5.2 on Ubuntu 22.04/24.04 or 29.4.3 on Ubuntu 26.04. | `string` | `null` | no |
| dokku\_hostname | Dokku's global domain for default app subdomains. For example, an app named api under dokku.example.com gets api.dokku.example.com. | `string` | `"dokku.yourhost.com"` | no |
| dokku\_plugin\_definitions | Map of Dokku plugin names to HTTPS Git URLs and optional revisions. | <pre>map(object({<br/>    url      = string<br/>    revision = optional(string)<br/>  }))</pre> | `{}` | no |
| dokku\_plugins | Legacy list of known plugin short names or HTTPS Git repository URLs. | `list(string)` | `[]` | no |
| dokku\_ssh\_key\_name | Name for the deploy SSH key in Dokku. | `string` | `"admin"` | no |
| dokku\_ssh\_public\_key\_path | Optional path to the public SSH key Dokku should authorize for deployments. | `string` | `null` | no |
| dokku\_version | Use latest for the latest stable release on a fresh install, or specify an exact numeric version. | `string` | `"latest"` | no |
| management\_id | Unique ID this module uses to track deploy-key ownership on the server. | `string` | `"terraform-dokku"` | no |
| server\_id | Optional server instance ID, such as the cloud instance ID. Changing it reruns setup even at the same SSH address. If omitted, the ID is ssh\_host. | `string` | `null` | no |
| server\_revision | Change this value after a rebuild that keeps the same SSH address and server ID. | `string` | `""` | no |
| ssh\_host | SSH host | `string` | n/a | yes |
| ssh\_known\_hosts\_path | Path to an existing known\_hosts file with the verified server host key. | `string` | n/a | yes |
| ssh\_port | SSH port of the server. | `number` | `22` | no |
| ssh\_private\_key\_path | Optional path to a local SSH private key. Leave unset or set to null to use the SSH agent. | `string` | `null` | no |
| ssh\_timeout | Maximum duration in seconds for each remote operation. | `number` | `1800` | no |
| ssh\_user | SSH user | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| docker\_daemon\_config\_applied | Whether the module applied custom Docker daemon configuration. |
| docker\_daemon\_config\_hash | Hash of the applied Docker daemon configuration, if any. |
| dokku\_hostname | Dokku's global domain for default app subdomains. |
| dokku\_install\_stdout | Deprecated. Installation output goes to the Terraform console and stays out of state. |
| dokku\_installation\_id | Identifier of the Dokku installation resource. |
| dokku\_plugin\_definitions | Configured plugins keyed by name, including legacy plugin entries. |
| dokku\_plugins | Legacy plugin list configured for installation. |
| dokku\_ssh\_key\_configured | Whether the module configured an SSH public key for Dokku deployments. |
| dokku\_ssh\_key\_name | The name of the configured deploy key, if any. |
| dokku\_version | Requested Dokku version. When set to latest, the installer resolves the numeric version during apply. |
| ssh\_host | The SSH host where Dokku is installed. |
<!-- END_TF_DOCS -->

## Related projects

- [Dokku Terraform Install Script](https://github.com/dhinus/dokku-terraform/blob/master/scripts/install-dokku.sh)
- I got the idea for this module from the [Original Terraform Dokku Project](https://github.com/brotandgames/terraform-dokku).
