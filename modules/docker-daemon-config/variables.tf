variable "ssh_host" {
  description = "SSH host where Docker daemon configuration should be applied"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for connecting to the host"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for authentication"
  type        = string
}

variable "docker_daemon_config" {
  description = "Docker daemon configuration as JSON string to be written to /etc/docker/daemon.json"
  type        = string

  validation {
    condition     = can(jsondecode(var.docker_daemon_config))
    error_message = "The docker_daemon_config must be a valid JSON string."
  }
}

