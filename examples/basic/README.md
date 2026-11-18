# Basic installation

On a fresh server, this example installs the latest stable Dokku package from
the official apt repository. If Dokku is already installed, it keeps that version
until you enable upgrades. The example also sets Docker log rotation limits.

The example uses Git tag `v0.1.0` so it works before the Terraform and OpenTofu
registries finish indexing it. Once the module appears in the registry, you can
use `source = "iloveitaly/install/dokku"` with `version = "~> 0.1.0"`.

If you're upgrading from the SSH-provider version, follow the
[state migration instructions](../../README.md#migrating-from-the-ssh-provider-implementation) before applying.

1. Prepare an Ubuntu 22.04 or 24.04 server with reachable SSH and passwordless
   sudo. On your macOS or Linux controller, install Terraform or OpenTofu >= 1.10,
   Python >= 3.9, and OpenSSH.
2. Get the server host key through a trusted console or provider. Save it in a
   local known_hosts file under the server address you'll connect to. If you
   collect the key with `ssh-keyscan`, verify its fingerprint through a separate
   trusted channel.
3. Load your controller key into your SSH agent.

   ```sh
   ssh-add ~/.ssh/id_ed25519
   ```

   The module uses the agent through `SSH_AUTH_SOCK` when you omit
   `ssh_private_key_path`. To use a key file, add
   `ssh_private_key_path = "~/.ssh/id_ed25519"` to the module block in `main.tf`.
   Choose a key that works without a passphrase prompt.
4. From the repository root, open the example directory and copy the variable
   template.

   ```sh
   cd examples/basic
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars` with your server address, SSH user, and known_hosts
   path. Use your cloud instance ID for `server_id` and update it if you replace
   the server. Use `server_id = null` to identify the server by its SSH address.
   In `main.tf`, set `dokku_hostname` to the base domain for your apps. With
   `dokku.example.com`, an app named `api` gets `api.dokku.example.com` by
   default. Key paths point to files on the controller. Keep `terraform.tfvars`
   and state files out of Git.
5. Initialize, save the plan, and review it.

   ```sh
   terraform init
   terraform plan -out=dokku.tfplan
   ```

   The plan shows `latest`. During apply, the installer resolves the numeric
   version on the server.
6. Apply the reviewed plan.

   ```sh
   terraform apply dokku.tfplan
   terraform output dokku_hostname
   ```

   Check `sudo dokku version` on the server for the installed numeric version.
   You can use `tofu` in place of `terraform` for these commands.

To register a deploy key, set `dokku_ssh_public_key_path` in the module block
to a public client key on the controller. Rotation and revocation are covered
under [deploy key management](../../README.md#deploy-keys).

Read [versions and upgrades](../../README.md#versions-and-upgrades) before
updating an existing server.

Keep the module block in place when you run `terraform destroy`. Terraform
removes its records and revokes the deploy key if you registered one. Docker,
Dokku, plugins, and daemon configuration stay on the server. If you plan to
delete the module block, first set `dokku_ssh_public_key_path` to null and apply
while the revocation hook is still available.
