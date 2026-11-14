# Compatibility example. New examples live under examples/; automated tests are
# in tests/. This configuration contains no machine-specific credentials.
variable "ssh_host" { type = string }
variable "ssh_user" { type = string }
variable "ssh_known_hosts_path" { type = string }
variable "ssh_private_key_path" {
  type    = string
  default = null
}

module "dokku" {
  source               = "../"
  ssh_host             = var.ssh_host
  ssh_user             = var.ssh_user
  ssh_known_hosts_path = var.ssh_known_hosts_path
  ssh_private_key_path = var.ssh_private_key_path
  dokku_hostname       = "dokku.example.com"
}

output "dokku_info" {
  value = {
    hostname = module.dokku.dokku_hostname
    version  = module.dokku.dokku_version
  }
}
