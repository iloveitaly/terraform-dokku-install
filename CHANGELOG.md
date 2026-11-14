# Changelog

## 0.1.0

First tagged release of the Terraform/OpenTofu Dokku installer.

1. Use verified system OpenSSH with SSH-agent or key-file authentication. Private
   key contents are no longer stored in Terraform resource state. The module uses
   built-in `terraform_data` resources without a third-party SSH provider.
2. Default fresh Dokku installations to the latest stable package in the official
   repository. Support exact versions and opt-in upgrades, reject downgrades, and
   reconcile hostname changes. Docker Engine and containerd use explicit versions.
3. Apply Docker daemon configuration before Dokku installation, validate it with
   `dockerd --validate`, and restore the prior configuration after restart failure
   or interruption. Guard storage changes on hosts with containers, images, or
   volumes.
4. Serialize plugin operations, support named repository revisions, and propagate
   failures. Track deploy-key ownership for safe rotation, revocation, and
   destroy-time cleanup while retaining unrelated keys.
5. Resolve the destroy-time runner from the current module location so moving a
   consumer checkout does not break key revocation.
6. Add Terraform/OpenTofu plan tests, isolated Python regression tests, archive
   consumer and relocation checks, opt-in disposable-host integration tests, and
   generated documentation checks.

### Migration and requirements

1. Existing users of the untagged SSH-provider implementation must follow the
   [state migration instructions](README.md#migrating-from-the-ssh-provider-implementation)
   before applying. Resource addresses and the Docker submodule interface changed.
2. The controller requires macOS or Linux, Terraform/OpenTofu >= 1.10, Python >= 3.9,
   and OpenSSH. Targets require Ubuntu 22.04 or 24.04 with reachable SSH and
   passwordless sudo. A verified `ssh_known_hosts_path` is required.
3. Destroy revokes the key owned by this module but retains installed Docker,
   Dokku, plugins, and daemon configuration. Keep the module configuration present
   during destroy, or apply a null deploy-key path to revoke it before removing
   the module block. Refresh does not inspect remote drift.
4. The `dokku_version` output reports the requested selector. Check `dokku version`
   on the server for its resolved numeric release. `dokku_install_stdout` is
   deprecated and returns null; installation output streams during apply.

### Validation

The live Ubuntu 24.04 ARM64 integration run exercised Docker 28.5.2, containerd
1.7.28, and Dokku 0.35.19 to 0.35.20 to the latest available stable package
(0.38.34 at test time). It covered installation, idempotence, upgrades, hostname
changes, pinned plugins, key rotation/revocation, Docker rollback, ownership
replacement, and destroy. The release also includes a packaged-consumer relocation
regression check for both Terraform and OpenTofu.
