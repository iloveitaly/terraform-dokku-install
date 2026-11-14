variables {
  ssh_host             = "example.test"
  ssh_user             = "ubuntu"
  ssh_private_key_path = null
  ssh_known_hosts_path = "tests/fixtures/known_hosts"
}

run "valid_defaults" {
  command = plan
  assert {
    condition     = output.dokku_hostname == "dokku.yourhost.com" && output.dokku_version == "latest"
    error_message = "Default outputs must reflect the requested Dokku configuration."
  }
  assert {
    condition     = output.dokku_ssh_key_configured == false && output.docker_daemon_config_applied == false
    error_message = "Optional resources must be disabled by default."
  }
  assert {
    condition     = terraform_data.install.triggers_replace.version == "latest" && terraform_data.install.triggers_replace.hostname == "dokku.yourhost.com"
    error_message = "The install resource must track the requested version and hostname."
  }
  assert {
    condition     = terraform_data.install_docker.triggers_replace.ubuntu_helper == filesha256("${path.module}/files/ubuntu.sh") && terraform_data.install.triggers_replace.ubuntu_helper == filesha256("${path.module}/files/ubuntu.sh")
    error_message = "Both installation resources must track changes to the shared Ubuntu policy."
  }
}

run "reject_version" {
  command = plan
  variables { dokku_version = "0.35.20;touch /tmp/pwned" }
  expect_failures = [var.dokku_version]
}

run "reject_hostname" {
  command = plan
  variables { dokku_hostname = "host..example.com" }
  expect_failures = [var.dokku_hostname]
}

run "reject_key_name" {
  command = plan
  variables { dokku_ssh_key_name = "-oProxyCommand=bad" }
  expect_failures = [var.dokku_ssh_key_name]
}

run "reject_plugin_url" {
  command = plan
  variables { dokku_plugins = ["https://example.com/a/b;bad"] }
  expect_failures = [var.dokku_plugins]
}

run "reject_invalid_plugin_definition" {
  command = plan
  variables { dokku_plugin_definitions = { evil = { url = "https://example.com/a/b.git", revision = "main;bad" } } }
  expect_failures = [var.dokku_plugin_definitions]
}

run "reject_non_json" {
  command = plan
  variables { docker_daemon_config = "not-json" }
  expect_failures = [var.docker_daemon_config]
}

run "reject_json_array" {
  command = plan
  variables { docker_daemon_config = "[]" }
  expect_failures = [var.docker_daemon_config]
}

run "reject_json_null" {
  command = plan
  variables { docker_daemon_config = "null" }
  expect_failures = [var.docker_daemon_config]
}

run "reject_json_string" {
  command = plan
  variables { docker_daemon_config = "\"text\"" }
  expect_failures = [var.docker_daemon_config]
}

run "reject_duplicate_normalized_plugins" {
  command = plan
  variables {
    dokku_plugins = ["postgres", "https://github.com/dokku/dokku-postgres.git"]
  }
  expect_failures = [terraform_data.plugins]
}

run "reject_invalid_dns_label" {
  command = plan
  variables { dokku_hostname = "bad-.example.test" }
  expect_failures = [var.dokku_hostname]
}

run "reject_invalid_plugin_revision" {
  command = plan
  variables { dokku_plugin_definitions = { redis = { url = "https://github.com/dokku/dokku-redis.git", revision = "refs/heads/../main" } } }
  expect_failures = [var.dokku_plugin_definitions]
}

run "valid_pinned_version" {
  command = plan
  variables { dokku_version = "0.35.20" }
  assert {
    condition     = output.dokku_version == "0.35.20"
    error_message = "An explicit pinned version must be preserved in the output."
  }
}

run "automatic_docker_package_defaults" {
  command = plan
  variables {
    docker_version     = null
    containerd_version = null
  }
  assert {
    condition     = terraform_data.install_docker.triggers_replace.docker_version == null && terraform_data.install_docker.triggers_replace.containerd_version == null
    error_message = "Null Docker and containerd versions must select automatic defaults."
  }
}

run "explicit_docker_package_versions" {
  command = plan
  variables {
    docker_version     = "29.4.3"
    containerd_version = "2.2.5"
  }
  assert {
    condition     = terraform_data.install_docker.triggers_replace.docker_version == "29.4.3" && terraform_data.install_docker.triggers_replace.containerd_version == "2.2.5"
    error_message = "Explicit Docker and containerd versions must be retained."
  }
}

run "reject_invalid_docker_version" {
  command = plan
  variables { docker_version = "29.4.3;bad" }
  expect_failures = [var.docker_version]
}

run "reject_invalid_containerd_version" {
  command = plan
  variables { containerd_version = "2.2.5;bad" }
  expect_failures = [var.containerd_version]
}
