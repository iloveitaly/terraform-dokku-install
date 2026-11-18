# Register module version 0.1.0

Both public registries use the same GitHub repository and release. If the release
is still a draft or missing, ask the maintainer to finish publishing it before
submitting either listing. [GitHub release v0.1.0](https://github.com/iloveitaly/terraform-dokku-install/releases/tag/v0.1.0)

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

The repository follows `terraform-<target>-<module>`, with target `dokku` and
module name `install`. Publish the root module. The Docker configuration
submodule ships in the same package and version.

## Register with the Terraform Registry

1. Check that the repository is public and the release has source code and
   release notes. Publish from the existing `v0.1.0` tag on the
   [GitHub release](https://github.com/iloveitaly/terraform-dokku-install/releases/tag/v0.1.0).
2. Open [Terraform Registry module publishing](https://registry.terraform.io/publish/module).
   If the URL redirects or the interface has changed, use the registry's Publish
   or Upload navigation and choose Module.
3. Sign in using the maintainer's authorized account. If prompted for an HCP
   Terraform account, sign in and connect a GitHub account with admin access to
   `iloveitaly/terraform-dokku-install` (normally `iloveitaly`). Authorize GitHub
   access to the public repository and its registry webhook.
4. Select `iloveitaly/terraform-dokku-install` from the repository list. Confirm
   namespace `iloveitaly`, module `install`, and target/provider label `dokku` if
   those fields are displayed. Leave the module directory at the repository root.
5. Click Publish Module. The registry should import version `0.1.0` from the
   existing `v0.1.0` tag.
6. Check that the README renders, the required SSH inputs appear, and
   `dokku_version` defaults to `"latest"`. Confirm that the usage source is
   `iloveitaly/install/dokku`. [Expected module page](https://registry.terraform.io/modules/iloveitaly/install/dokku/0.1.0)
7. If you can't select the repository, check your GitHub account, repository
   authorization, and admin access. If the module page lacks `0.1.0` after the
   initial import finishes, check the tag and choose Resync Module under Manage
   Module.

The registry uses the GitHub repository description for the listing and picks
up later semantic-version tags through its webhook.
[Terraform public module publishing requirements](https://developer.hashicorp.com/terraform/registry/modules/publish)

## Submit to the OpenTofu Registry

1. Sign in to GitHub to submit the public repository path.
2. Open the [new-module issue form](https://github.com/opentofu/registry/issues/new?template=module.yml).
   Choose Submit new Module if GitHub first presents a template chooser.
3. Enter this path in the Module Repository field.

   ```text
   iloveitaly/terraform-dokku-install
   ```

   If the form requires a title and leaves it blank, use
   `Module: iloveitaly/terraform-dokku-install`.
4. Submit through the structured issue form in the browser and save the issue URL.
   OpenTofu's automated validation requires that form.
5. Wait for the registry automation and maintainer review. Follow any validation
   feedback in the issue. Avoid duplicate submissions if the request is pending.
6. After acceptance, open [OpenTofu Registry Search](https://search.opentofu.org/)
   and search for `iloveitaly/install/dokku`. Verify that `0.1.0`, the README, and
   the expected inputs appear.

For submission details, see the [OpenTofu registry repository](https://github.com/opentofu/registry#adding-providers-modules-or-gpg-keys-to-the-opentofu-registry).

## Confirm completion

1. Open both version-list endpoints in a browser and check for `0.1.0`.

   For Terraform, use https://registry.terraform.io/v1/modules/iloveitaly/install/dokku/versions

   For OpenTofu, use https://registry.opentofu.org/v1/modules/iloveitaly/install/dokku/versions

2. Send the maintainer the Terraform listing URL, the OpenTofu submission issue
   URL, the OpenTofu listing URL, and any remaining validation messages. OpenTofu
   registration is complete once the listing appears.
3. Ask the maintainer to run fresh `terraform init` and `tofu init` checks with
   this registry source to confirm both CLIs can fetch the module.

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

Tag each future release with a new immutable semantic version. Both registries
keep using the same repository, so the initial submission covers future releases.
