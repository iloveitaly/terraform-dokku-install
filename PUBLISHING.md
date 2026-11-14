# Browser handoff: register module version 0.1.0

This handoff registers the same GitHub repository and release in the public
Terraform and OpenTofu registries. It does not deploy a server.

Start when [GitHub release v0.1.0](https://github.com/iloveitaly/terraform-dokku-install/releases/tag/v0.1.0)
is visible as a published release. The release, repository metadata, code, and
terminal checks are prepared separately. If the release is missing, ask the
maintainer to finish the terminal release work before submitting either listing.

## Values to use

| Field | Value |
| --- | --- |
| GitHub owner / namespace | `iloveitaly` |
| Repository | `terraform-dokku-install` |
| Full repository path | `iloveitaly/terraform-dokku-install` |
| Repository URL | https://github.com/iloveitaly/terraform-dokku-install |
| Git tag | `v0.1.0` |
| Registry version | `0.1.0` |
| Module name | `install` |
| Provider / target-system label | `dokku` |
| Module address | `iloveitaly/install/dokku` |
| Description | Install Docker, Dokku, and plugins on Ubuntu over verified SSH with Terraform or OpenTofu. |

The name follows `terraform-<target>-<module>`, so the module name is `install` and
the target is `dokku`. Publish the root module; the Docker configuration submodule
ships in the same package and version.

## Register with the Terraform Registry

1. Open the [GitHub release](https://github.com/iloveitaly/terraform-dokku-install/releases/tag/v0.1.0)
   and verify that tag `v0.1.0`, source code, and release notes are present. The
   repository must remain public. Do not create a replacement tag in the browser.
2. Open [Terraform Registry module publishing](https://registry.terraform.io/publish/module).
   If the URL redirects or the interface has changed, use the registry's Publish
   or Upload navigation and choose Module.
3. Sign in using the maintainer's authorized account. If prompted for an HCP
   Terraform account, sign in there and connect the GitHub account with admin
   access to `iloveitaly/terraform-dokku-install` (normally `iloveitaly`). Complete
   the GitHub authorization needed to read the public repository and manage its
   registry webhook.
4. Select `iloveitaly/terraform-dokku-install` from the repository list. Confirm
   namespace `iloveitaly`, module `install`, and target/provider label `dokku` if
   those fields are displayed. Leave the module directory at the repository root.
5. Click Publish Module. The registry should import version `0.1.0` from the
   existing `v0.1.0` tag.
6. Open the [expected module page](https://registry.terraform.io/modules/iloveitaly/install/dokku/0.1.0).
   Verify that the README renders, the required SSH inputs are listed, and
   `dokku_version` defaults to `"latest"`. The usage source must be
   `iloveitaly/install/dokku`.
7. If the repository is absent from the selection list, check the signed-in
   GitHub account, repository authorization, and admin access. If the module
   exists but `0.1.0` is missing, check the tag and use Manage Module → Resync
   Module after allowing the initial import to finish.

These steps follow the [Terraform public module publishing requirements](https://developer.hashicorp.com/terraform/registry/modules/publish).
The GitHub repository description supplies the listing description, and subsequent
semantic-version tags are delivered through the registry webhook.

## Submit to the OpenTofu Registry

1. Sign in to GitHub. OpenTofu accepts module submissions from GitHub users; the
   form asks for the public repository path.
2. Open the [new-module issue form](https://github.com/opentofu/registry/issues/new?template=module.yml).
   Choose Submit new Module if GitHub first presents a template chooser.
3. In the Module Repository field, enter exactly:

   ```text
   iloveitaly/terraform-dokku-install
   ```

   This field takes the repository path, not the registry address or a full URL.
   If a title is required and not filled automatically, use
   `Module: iloveitaly/terraform-dokku-install`.
4. Submit the form and save the resulting issue URL. Use the structured issue-form
   UI: OpenTofu explicitly requires it for automated validation. Do not substitute
   a plain issue, API call, CLI-created issue, or metadata pull request.
5. Wait for the registry automation and maintainer review. Follow any validation
   feedback in the issue. Avoid duplicate submissions if the request is pending.
6. After acceptance, open [OpenTofu Registry Search](https://search.opentofu.org/)
   and search for `iloveitaly/install/dokku`. Verify that `0.1.0`, the README, and
   the expected inputs appear.

The submission process and issue-form requirement are documented in the
[OpenTofu registry repository](https://github.com/opentofu/registry#adding-providers-modules-or-gpg-keys-to-the-opentofu-registry).

## Confirm completion

1. In a browser, check both version-list endpoints and confirm each includes
   version `0.1.0`:

   Terraform: https://registry.terraform.io/v1/modules/iloveitaly/install/dokku/versions

   OpenTofu: https://registry.opentofu.org/v1/modules/iloveitaly/install/dokku/versions

2. Send the maintainer the Terraform listing URL, the OpenTofu submission issue
   URL, the OpenTofu listing URL, and any remaining validation messages. A pending
   OpenTofu submission is not yet a completed registration.
3. Ask the maintainer to run fresh `terraform init` and `tofu init` checks using
   the registry source below. Browser listing checks do not execute the installer.

   ```hcl
   module "dokku" {
     source  = "iloveitaly/install/dokku"
     version = "~> 0.1.0"

     ssh_host             = "192.0.2.10"
     ssh_user             = "ubuntu"
     ssh_known_hosts_path = "~/.ssh/dokku_known_hosts"
     dokku_hostname       = "dokku.example.com"
   }
   ```

Future releases use new immutable semantic-version tags. Both registries continue
to reference this repository; routine releases do not need another initial module
submission.
