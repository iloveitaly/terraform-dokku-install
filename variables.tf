variable "ssh_private_key_path" {
  description = "SSH private key path, for connecting to the server"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = null
}

variable "ssh_host" {
  description = "SSH host"
  type        = string
  default     = null
}

variable "dokku_version" {
  description = "Dokku version"
  type        = string
  default     = "0.35.20"
}

variable "dokku_hostname" {
  description = "Dokku hostname"
  type        = string
  default     = "dokku.yourhost.com"
}

variable "dokku_ssh_public_key_path" {
  description = "Path to SSH public key file to add to Dokku for deployments (optional)"
  type        = string
  default     = null
}

variable "dokku_ssh_key_name" {
  description = "Name for the SSH key in Dokku (used with ssh-keys:add command)"
  type        = string
  default     = "admin"
}

variable "dokku_plugins" {
  description = "List of Dokku plugins to install. Can be shortnames (postgres, redis, mysql, clickhouse) or full URLs"
  type        = list(string)
  default     = []
}

variable "remove_unlisted_plugins" {
  description = "Whether to remove plugins that are installed but not listed in dokku_plugins"
  type        = bool
  default     = false
}

variable "docker_daemon_config" {
  description = "Custom Docker daemon configuration as JSON string to be written to /etc/docker/daemon.json. Examples: enable containerd snapshotter, configure logging drivers, set storage drivers, etc."
  type        = string
  default     = null

  validation {
    condition     = var.docker_daemon_config == null || can(jsondecode(var.docker_daemon_config))
    error_message = "The docker_daemon_config must be a valid JSON string."
  }
}
