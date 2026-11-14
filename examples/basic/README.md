# Basic installation

This example installs Dokku with the latest stable package available from its
official apt repository. Existing Dokku installations retain their version until
upgrades are explicitly enabled. Docker logging uses rotation limits.

The module itself is pinned to Git tag `v0.1.0`. Using its Git source allows this
example to run before registration in the Terraform and OpenTofu registries is
complete. After indexing, you can use `source = "iloveitaly/install/dokku"` and
`version = "~> 0.1.0"` instead.

Existing module users should follow the [state migration instructions](../../README.md#migrating-from-the-ssh-provider-implementation)
before applying this example.

1. Prepare an Ubuntu 22.04 or 24.04 server with reachable SSH and passwordless
   sudo. On your macOS or Linux controller, install Terraform or OpenTofu >= 1.10,
   Python >= 3.9, and OpenSSH.
2. Obtain the server host key through a trusted console or provider. Store it in
   a local known_hosts file using the server address you will connect to.
   Compare the fingerprint out of band if you collect the key with `ssh-keyscan`.
3. Load your controller key into an existing SSH agent:

   ```sh
   ssh-add ~/.ssh/id_ed25519
   ```

   The module uses `SSH_AUTH_SOCK`. To use a key file without an agent instead,
   add `ssh_private_key_path = "~/.ssh/id_ed25519"` to the module block in
   `main.tf`. That key must work without an interactive passphrase prompt.
4. From the repository root, enter the example directory and copy the variable
   template:

   ```sh
   cd examples/basic
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars` with your server address, SSH user, known_hosts path,
   and cloud instance ID. Change `dokku_hostname` in `main.tf` to your intended
   hostname. All key paths refer to the controller. Keep `terraform.tfvars` and
   state files out of Git.
5. Initialize and review a saved plan:

   ```sh
   terraform init
   terraform plan -out=dokku.tfplan
   ```

   The plan displays the `latest` selector. The installer resolves its numeric
   version on the server during apply.
6. Apply the reviewed plan:

   ```sh
   terraform apply dokku.tfplan
   terraform output dokku_hostname
   ```

   Check `sudo dokku version` on the server for the installed numeric version.
   You can use `tofu` in place of `terraform` for these commands.

This example does not register a deployment key. To add one, set
`dokku_ssh_public_key_path` in the module block to a public client key on the
controller. See [deploy key management](../../README.md#deploy-keys) for rotation
and revocation behavior.

Destroy removes the Terraform records and revokes a deploy key owned by this
module, if one was configured. Docker, Dokku, plugins, and daemon configuration
remain installed. See [versions and upgrades](../../README.md#versions-and-upgrades)
before updating an existing server.
