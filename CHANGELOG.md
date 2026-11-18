# Changelog

## Unreleased

1. Support Ubuntu 26.04 in both installers using the official `resolute` package
   repositories. Dokku continues to default to the latest stable package.
2. When Docker and containerd inputs are unset or null, use 28.5.2 and 1.7.28 on
   Ubuntu 22.04 and 24.04, or 29.4.3 and 2.2.5 on Ubuntu 26.04. Explicit numeric
   versions are strict pins.
3. Run disposable-host integration tests on all three supported Ubuntu releases.
   Set the Dokku versions to test an upgrade. Regression tests cover supported
   OS versions, repository selection, defaults, and overrides.
4. During configuration rollback, clear Docker's systemd service and socket
   failure states so restart limits can't block recovery.
5. Share Ubuntu package rules between installers. Use one Docker package list
   for downgrade checks, apt preferences, installation, and verification.
   Terraform replacement triggers and archive checks track the bundled helper.

An upgrade from 0.1.0 reruns provisioning because the installer script hashes
changed. On Ubuntu 22.04 and 24.04, the new defaults resolve to the same packages
as 0.1.0.

The integration test ran on a fresh Ubuntu 26.04 ARM64 OrbStack guest with Docker
29.4.3 and containerd 2.2.5. It upgraded Dokku from 0.38.33 to 0.38.34 and checked
installation, idempotence, plugins, hostname changes, key rotation and
revocation, configuration rollback, ownership replacement, and destroy after
moving the consuming configuration. All 45 Python tests and 18 plan tests
passed, along with the package checks for Terraform and OpenTofu.

## 0.1.0

First tagged release of the Terraform/OpenTofu Dokku installer.

1. Use system OpenSSH with host key verification and either an SSH agent or a
   key file. Private key contents stay with OpenSSH or the agent. Built-in
   `terraform_data` resources replace the third-party SSH provider.
2. Default fresh Dokku installations to the latest stable package in the official
   repository. Support exact versions and opt-in upgrades, reject downgrades, and
   reconcile hostname changes. Docker Engine and containerd use explicit versions.
3. Validate the Docker daemon configuration with `dockerd --validate` and apply
   it before installing Dokku. Restore the previous configuration after a failed
   restart or interruption. Guard storage changes on hosts with containers,
   images, or volumes.
4. Serialize plugin operations, support named repository revisions, and propagate
   failures. Track deploy-key ownership for safe rotation, revocation, and
   destroy-time cleanup while retaining unrelated keys.
5. Find the destroy-time runner at the current module path so key revocation
   works after moving the consuming checkout.
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
3. Destroy revokes the deploy key owned by the module and leaves Docker, Dokku,
   plugins, and daemon configuration on the server. Keep the module block in
   place for destroy. To remove the block directly, apply a null deploy-key path
   first. Check for manual server changes separately from Terraform refresh.
4. The `dokku_version` output reports the requested selector. Run `dokku version`
   on the server for the installed version. Installation output streams during
   apply. The deprecated `dokku_install_stdout` output returns null.

### Validation

The integration test ran on Ubuntu 24.04 ARM64 with Docker 28.5.2 and containerd
1.7.28. It installed Dokku 0.35.19, upgraded to 0.35.20, then installed the latest
stable package (0.38.34 at test time). It checked idempotence, hostname changes,
pinned plugins, key rotation and revocation, Docker rollback, ownership
replacement, and destroy. The package tests also check that destroy works after
moving the consuming configuration in Terraform and OpenTofu.
