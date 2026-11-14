terraform {
  backend "local" {}
}

variable "ssh_host" { type = string }
variable "ssh_user" { type = string }
variable "ssh_port" {
  type    = number
  default = 22
}
variable "ssh_private_key_path" { type = string }
variable "ssh_known_hosts_path" { type = string }
variable "dokku_ssh_public_key_path" {
  type    = string
  default = null
}
variable "dokku_ssh_key_name" {
  type    = string
  default = "integration"
}
variable "management_id" {
  type    = string
  default = "integration-test"
}
variable "dokku_hostname" {
  type    = string
  default = "dokku.example.test"
}
variable "dokku_version" {
  type    = string
  default = "0.35.19"
}
variable "allow_dokku_upgrade" {
  type    = bool
  default = false
}
variable "docker_daemon_config" {
  type    = string
  default = null
}
variable "dokku_plugin_definitions" {
  type = map(object({
    url      = string
    revision = optional(string)
  }))
  default = {}
}
module "dokku" {
  source                    = "../"
  ssh_host                  = var.ssh_host
  ssh_user                  = var.ssh_user
  ssh_port                  = var.ssh_port
  ssh_private_key_path      = var.ssh_private_key_path
  ssh_known_hosts_path      = var.ssh_known_hosts_path
  dokku_ssh_public_key_path = var.dokku_ssh_public_key_path
  dokku_ssh_key_name        = var.dokku_ssh_key_name
  dokku_version             = var.dokku_version
  allow_dokku_upgrade       = var.allow_dokku_upgrade
  docker_daemon_config      = var.docker_daemon_config
  dokku_plugin_definitions  = var.dokku_plugin_definitions
  dokku_hostname            = var.dokku_hostname
  management_id             = var.management_id
}
