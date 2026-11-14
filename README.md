# Install Dokku with Terraform

This OpenTofu/Terraform module installs Docker, Dokku, and Dokku plugins on a server over SSH using the official package repositories.

Use a downstream Dokku provider to manage apps, services, and links on the
installed instance. Active options on the OpenTofu registry:

- [`aliksend/dokku`](https://registry.opentofu.org/providers/aliksend/dokku) (v1.0.24+)
- [`dimmkirr/dokku`](https://registry.opentofu.org/providers/dimmkirr/dokku) (v1.2.0+)
- [`aaronstillwell/dokku`](https://github.com/aaronstillwell/terraform-provider-dokku)

Their `dokku_plugin` resources only verify that a plugin is installed.
Installing plugins requires root access, so this module manages plugin installation.

If you already use an earlier version of this module, follow the
[state migration steps](#migrating-from-the-ssh-provider-implementation) before
applying this version.

## Install the released module

The registry address for this module is `iloveitaly/install/dokku`. Use a module
version constraint such as `~> 0.1.0`; this is separate from the Dokku version
installed on the server.

Registry registration is a one-time step described in the
[browser handoff](PUBLISHING.md). If the module is not indexed yet, use the
tagged Git source instead:

```hcl
source = "git::https://github.com/iloveitaly/terraform-dokku-install.git?ref=v0.1.0"
```

When using the Git source, omit the `version` argument. The tag selects the module
version. The [basic example](examples/basic/README.md) uses this source so it works
before registry indexing is complete.

## Usage

Run Terraform from macOS or Linux with Terraform or OpenTofu >= 1.10,
Python >= 3.9, and OpenSSH installed.
The target must run Ubuntu 22.04 or 24.04 with systemd, SSH, and passwordless sudo.
SSH must be reachable before applying; the installer waits for cloud-init once
connected.
The module uses Terraform's built-in `terraform_data` resource and requires no
third-party Terraform providers.

Obtain the server's SSH host key through your cloud console or another trusted
channel. Put the verified key in a dedicated known_hosts file. `ssh-keyscan`
can collect a key, but does not authenticate it; compare its fingerprint with
that trusted source before applying. For a nonstandard port, known_hosts uses
`[hostname]:port`. Your normal SSH configuration is deliberately bypassed.

```hcl
module "dokku" {
  source  = "iloveitaly/install/dokku"
  version = "~> 0.1.0"

  ssh_host             = "192.0.2.10"
  ssh_user             = "ubuntu"
  ssh_known_hosts_path = "~/.ssh/dokku_known_hosts"
  server_id            = "your-cloud-instance-id"
  dokku_hostname       = "dokku.example.com"
  dokku_version        = "latest"

  # Default: use SSH_AUTH_SOCK from your local SSH agent.
  # Alternatively: ssh_private_key_path = "~/.ssh/id_ed25519"

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

For a complete setup sequence, use [the basic example](examples/basic/README.md).
It covers loading an SSH agent, supplying server details, and reviewing a saved
plan before applying. `test/main.tf` is another minimal example; automated tests
are in `tests/`.

All SSH paths refer to files on the machine running Terraform:

| Input | Purpose | When needed |
| --- | --- | --- |
| `ssh_known_hosts_path` | Verified SSH host keys for the server | Every remote operation, including destroy |
| `ssh_private_key_path` | Controller key used to connect to `ssh_user` | Every remote operation when using a key file instead of the agent |
| `dokku_ssh_public_key_path` | Public client key to authorize for Dokku deployments | Plan and apply when configuring a deploy key |

The SSH agent must be available through `SSH_AUTH_SOCK`. Load passphrase-protected
controller keys into the agent before applying; the runner cannot prompt for a
passphrase. The server host key and the deploy public key have different purposes.

## Execution and lifecycle

Operations run in this order: Docker installation, optional daemon configuration,
Dokku installation and hostname reconciliation, plugin reconciliation, and deploy
key reconciliation. All remote mutations share a host lock. Each operation has a
configurable `ssh_timeout` in seconds. Failed commands stop the apply without
being silently retried. Output streams to the Terraform console;
`dokku_install_stdout` is deprecated and returns null.

Private key contents never enter Terraform resource attributes or state.
OpenSSH reads a supplied key path, or authenticates with the local agent. Host
key verification is required, and agent forwarding is disabled. State still
contains configuration, public key hashes, and local paths; protect it normally.

Terraform refresh does not inspect the server for manual changes. Set `server_id`
to the cloud instance ID. If a server is rebuilt at the same address without a new
ID, change `server_revision`. Both inputs represent server replacement and also
replace key ownership, revoking the previous managed deploy key before adding it
again. For a routine Dokku reconciliation, replace only the installation resource
as shown in [the upgrade steps](#versions-and-upgrades).

Read-only checks on the server include `sudo dokku version`,
`sudo dokku domains:report --global`, `sudo dokku plugin:list`,
`sudo dokku ssh-keys:list`, and `sudo docker info`. Compare these with the desired
inputs and `/etc/docker/daemon.json` before forcing a reconciliation.

Destroy retains Docker, Dokku, plugins, and daemon configuration. It revokes only
the deploy key recorded under this module's `management_id`. Each independently
managed installation on a host needs a unique `management_id`. Revocation needs
the server and controller key paths to remain reachable during destroy. For an
already destroyed server, remove only its obsolete ownership resource from state
after confirming there is no live host on which that key still needs revocation.

Run `terraform destroy` while the module block is still present. If you want to
delete the module block instead, first set `dokku_ssh_public_key_path = null` and
apply to revoke the owned key. Terraform cannot run this module's destroy-time
hook after its configuration has been removed. See
[destroy-time provisioner behavior](https://developer.hashicorp.com/terraform/language/provisioners#remove-a-resource-block-containing-a-destroy-time-provisioner).

A timeout disconnects SSH but cannot guarantee that a remote package operation
stopped. Inspect the server before retrying; the remote lock prevents overlapping
reconciliation attempts.

## Versions and upgrades

Dokku defaults to `dokku_version = "latest"`, which resolves the highest stable
numeric release available from the official Dokku apt repository during a fresh
installation. Set an exact version such as `"0.35.20"` for reproducible installs.
The Docker Engine and containerd defaults remain 28.5.2 and 1.7.28.
Docker and containerd inputs select upstream versions; the installer resolves and
installs matching distribution packages, verifies them, and pins them against
unrelated apt upgrades. Dokku installs an exact package version. Package availability
still depends on the upstream repositories. OS upgrades and unrelated package
maintenance remain the caller's responsibility.

The selector is evaluated when the installation operation runs:

| Server state | Selector | Result |
| --- | --- | --- |
| Dokku is absent | `latest` | Install the highest stable numeric version available from the official repository |
| Dokku is installed | `latest`, upgrades disabled | Retain the installed version and reconcile the hostname |
| Dokku is installed | `latest`, `allow_dokku_upgrade = true` | Upgrade to the latest available stable version, retaining an installed version if it is newer |
| Dokku is installed | Exact version | Require opt-in for an upgrade; reject a downgrade |

New upstream releases do not cause a Terraform diff. To request a latest-version
upgrade for a module named `dokku` in your root configuration:

1. Set its `dokku_version` input to `"latest"` and `allow_dokku_upgrade` to `true`.
   Read the applicable Dokku migration guides and back up applications first.
2. Create and review a plan that reruns the installation resource:

   ```sh
   terraform plan -replace='module.dokku.terraform_data.install' -out=dokku-upgrade.tfplan
   ```

   Use the resource's full address if your module is nested or named differently.
   This also reruns plugin and deploy-key reconciliation after installation.
3. Apply the reviewed plan and check `sudo dokku version` on the server:

   ```sh
   terraform apply dokku-upgrade.tfplan
   ```

4. Set `allow_dokku_upgrade` back to `false` and apply to restore the upgrade guard.

The `dokku_version` output reports the requested selector, such as `"latest"`.
Use `sudo dokku version` for the installed numeric release.

Hostname changes also update the global domain. If global domains have been
customized independently, reconciliation fails if it would overwrite that custom
configuration.

## Plugins

Explicit plugin definitions provide a stable name, HTTPS repository URL, and
optional revision. Prefer full commit SHAs; tags and branches can move. Revision
changes are reconciled and checked against the repository. A source URL change
fails with a clear error and requires an explicit manual plugin replacement.
The legacy `dokku_plugins` shortname/URL list still works, normalizes `dokku-`
prefixes consistently, and rejects duplicate names. Legacy entries and explicit
entries without revisions install the repository's current revision on first use;
they do not provide reproducible version selection. Removing a plugin from the
inputs retains it on the server. Uninstall plugins explicitly after checking their
services and data; there is no automatic removal of unlisted plugins.

## Docker daemon configuration

`docker_daemon_config` must be a JSON object. The module canonicalizes it to avoid
restarts caused only by formatting, validates it with `dockerd --validate`, and
replaces the entire `/etc/docker/daemon.json` file. Docker is restarted and checked
for readiness. Failure or interruption restores the previous file, or removes the
new file if none existed, and attempts to restart the previous configuration.
An existing file is also backed up to `/etc/docker/daemon.json.bak`.

The configuration is applied before Dokku installation. Changing storage driver,
containerd snapshotter, storage options, or data root on a host with images,
containers, or volumes is rejected unless `allow_storage_migration = true`.
That flag only permits the change; it does not migrate data. Switching image stores
can hide existing images and containers. Plan a separate data migration for existing
hosts.

Setting the input back to null retains the last remote daemon configuration.
To request Docker defaults, explicitly apply `{}` first; storage checks still
apply. Restarting Docker may interrupt workloads, so schedule configuration changes
appropriately.

## Deploy keys

Set `dokku_ssh_public_key_path` to register one deployment key. The replacement is
validated before touching authorized_keys. Rotation and renaming preserve a backup
and restore the previous authorization on failure. A root-owned ledger records the
exact key line owned by `management_id`; unrelated keys are preserved. Setting the
path to null revokes the recorded key. Destroy also revokes that key. The ledger
is stored under `/var/lib/terraform-dokku/keys/` on the server.

Existing keys with the requested name are not silently adopted. During migration,
use a new key name, validate deployment access, then explicitly revoke the old
unmanaged key. Do not use the deploy key as the sole controller credential.

## Migrating from the SSH-provider implementation

This release changes the state resource types, requires `ssh_known_hosts_path`,
and defaults controller authentication to the SSH agent. The Docker submodule's
interface also changed. Plan the migration before applying to an existing server.

1. Set `umask 077` and back up Terraform state with
   `terraform state pull > /secure/path/dokku-state-backup.json`, choosing an
   existing directory outside the repository. Record installed versions, deploy keys,
   plugin names and URLs, and daemon configuration.
2. Add a verified known_hosts file and an immutable `server_id`. Set an explicit
   `ssh_private_key_path` if you do not use an SSH agent. Match the currently
   installed Docker/containerd/Dokku versions to avoid an unintended upgrade or
   a rejected downgrade. Configure a new deploy-key name for ledger ownership.
3. Run `terraform state list` and remove only the old `ssh_resource` addresses
   belonging to this installation with `terraform state rm '<exact-address>'`.
   These include install, install_plugin instances, ssh_key, and the daemon
   submodule resource. Prefixes vary when this module is nested. State removal
   leaves remote software and keys intact. Do not apply an intermediate destroy
   plan. Older `null_resource` versions require the same address-by-address review.
4. Initialize and review the new plan. It creates bootstrap resource records;
   scripts reconcile the existing host. Confirm legacy URL plugin names before
   normalizing them: an old `dokku-postgres` name and new `postgres` name are
   separate server plugins and must be reconciled manually. Removing the old name
   from configuration leaves that plugin and its services on the server.
5. Apply, verify version, hostname, plugins, Docker readiness and deployment
   access, then revoke the former unmanaged deployment key explicitly. Previous
   state backups may contain controller private keys; retain them securely or
   dispose of them according to your state retention policy.

## Validation and integration tests

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

OpenTofu can run the same Terraform configuration tests with `tofu test`. CI covers
Terraform 1.10.5 and 1.17.1 and OpenTofu 1.10.0 and 1.13.9. Python tests use isolated
files and fake services to exercise failure paths without modifying your host.
The package checks download a Git archive into an external consumer, apply with a
fake SSH command, relocate the consumer and module cache, and destroy from the new
path. They require a commit containing the files under test; uncommitted files are
not part of `git archive`.

`integration/run.sh` exercises installation, a no-change second plan, pinned and
latest upgrades, plugin failures, hostname changes, key rotation and revocation,
host-key rejection, Docker rollback, ownership replacement, and destroy-time key
revocation. It requires Terraform, Python, OpenSSH, and a fresh disposable Ubuntu
24.04 target. The script creates temporary controller keys and state for the test.
It consumes a tracked Git archive of `HEAD`, or the ref supplied through
`DOKKU_PACKAGE_REF`, and moves its consumer and module cache before destroy to
check that revocation works from a new checkout path.

To use a VM you created separately, provide all four connection variables:

```sh
DOKKU_DISPOSABLE_HOST=yes SSH_HOST=192.0.2.10 SSH_USER=ubuntu \
  SSH_KEY_PATH=/path/to/controller-key \
  SSH_KNOWN_HOSTS_PATH=/path/to/verified-known-hosts \
  bash integration/run.sh
```

`SSH_PORT` is optional and defaults to 22. The key paths must exist on the
controller, and known_hosts must match the host and port used by the test.

When `SSH_HOST` is unset, the script modifies the machine on which it runs. That
mode installs packages, configures localhost SSH access, and appends a temporary
key to the current user's `authorized_keys`. Use it only on a disposable Ubuntu
24.04 runner. In GitHub Actions, run the `Validate` workflow manually with the
`integration` input enabled; the default is disabled.

The script creates and destroys Terraform resource records, but leaves installed
software and test-host changes in place. It does not create or delete a VM. Delete
your disposable VM after inspecting the results. Successful runs remove temporary
controller files; failed runs print their retained artifact directory for diagnosis.

Ubuntu 22.04 is accepted by the installer; the live integration fixture targets
24.04. Minimum and current CLI versions are checked separately in CI.

| Target | Docker / containerd | Dokku | Verification |
| --- | --- | --- | --- |
| Ubuntu 24.04, ARM64 | 28.5.2 / 1.7.28 | 0.35.19 → 0.35.20 → 0.38.34 (`latest` at test time) | Live installation, no-op plan, upgrades, hostname, plugins, keys, rollback, and destroy |
| Ubuntu 22.04 | Configurable | Configurable | Accepted by the installer; not live-tested in this run |

Regenerate the reference tables with terraform-docs 0.20.0:

```sh
terraform-docs .
terraform-docs -c .terraform-docs.yml modules/docker-daemon-config
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.10 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| docker\_daemon\_config | ./modules/docker-daemon-config | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allow\_dokku\_upgrade | Allow changing an already installed Dokku version. | `bool` | `false` | no |
| allow\_storage\_migration | Allow changes to Docker storage configuration on an existing Docker installation. | `bool` | `false` | no |
| containerd\_version | containerd.io version to install. | `string` | `"1.7.28"` | no |
| docker\_daemon\_config | Optional JSON object to write to /etc/docker/daemon.json. | `string` | `null` | no |
| docker\_version | Docker Engine version to install. | `string` | `"28.5.2"` | no |
| dokku\_hostname | Dokku hostname | `string` | `"dokku.yourhost.com"` | no |
| dokku\_plugin\_definitions | Explicit plugins keyed by Dokku plugin name, each with an HTTPS Git URL and optional revision. | <pre>map(object({<br/>    url      = string<br/>    revision = optional(string)<br/>  }))</pre> | `{}` | no |
| dokku\_plugins | Legacy list of known plugin short names or HTTPS Git repository URLs. | `list(string)` | `[]` | no |
| dokku\_ssh\_key\_name | Name for the deploy SSH key in Dokku. | `string` | `"admin"` | no |
| dokku\_ssh\_public\_key\_path | Path to an SSH public key file to add to Dokku for deployments (optional). | `string` | `null` | no |
| dokku\_version | Dokku version selector: latest stable for new installs, or an exact numeric version. | `string` | `"latest"` | no |
| management\_id | Unique ownership identifier for deploy keys managed by this module on the server. | `string` | `"terraform-dokku"` | no |
| server\_id | Stable identity of the server, preferably the cloud instance ID. Defaults to the SSH host. | `string` | `null` | no |
| server\_revision | Change this value when the server is replaced at the same SSH address. | `string` | `""` | no |
| ssh\_host | SSH host | `string` | n/a | yes |
| ssh\_known\_hosts\_path | Path to an existing known\_hosts file containing the verified server host key. | `string` | n/a | yes |
| ssh\_port | SSH port of the server. | `number` | `22` | no |
| ssh\_private\_key\_path | Path to the SSH private key. Set to null to use the SSH agent. | `string` | `null` | no |
| ssh\_timeout | Maximum duration in seconds for each remote operation. | `number` | `1800` | no |
| ssh\_user | SSH user | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| docker\_daemon\_config\_applied | Whether custom Docker daemon configuration was applied. |
| docker\_daemon\_config\_hash | Hash of the applied Docker daemon configuration, if any. |
| dokku\_hostname | The hostname configured for Dokku. |
| dokku\_install\_stdout | Deprecated: installation output is streamed to the Terraform console and is not stored in state. |
| dokku\_installation\_id | Identifier of the Dokku installation resource. |
| dokku\_plugin\_definitions | Configured plugins keyed by name, including legacy plugin entries. |
| dokku\_plugins | Legacy plugin list configured for installation. |
| dokku\_ssh\_key\_configured | Whether an SSH public key was configured for Dokku deployments. |
| dokku\_ssh\_key\_name | The name of the configured deploy key, if any. |
| dokku\_version | Requested Dokku version selector. With latest, the installed numeric version is resolved on the server during apply. |
| ssh\_host | The SSH host where Dokku is installed. |
<!-- END_TF_DOCS -->

## Related projects

- [Dokku Terraform Install Script](https://github.com/dhinus/dokku-terraform/blob/master/scripts/install-dokku.sh)
- [Original Terraform Dokku Project](https://github.com/brotandgames/terraform-dokku) - this project was my original inspiration
