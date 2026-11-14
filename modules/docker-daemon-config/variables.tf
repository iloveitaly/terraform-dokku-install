variable "connection" {
  description = "SSH connection settings."
  type = object({
    host              = string
    user              = string
    port              = number
    known_hosts_path  = string
    private_key_path  = string
    operation_timeout = number
  })
}
variable "server_identity" {
  description = "Identity of the server being configured."
  type = object({
    id       = string
    revision = string
    host     = string
    user     = string
    port     = number
  })
}
variable "runner" {
  description = "Absolute path to the SSH runner."
  type        = string
}
variable "install_id" {
  description = "Docker installation resource ID."
  type        = string
}
variable "allow_storage_migration" {
  description = "Allow changes to Docker storage configuration."
  type        = bool
  default     = false
}
variable "docker_daemon_config" {
  description = "JSON object to write to /etc/docker/daemon.json."
  type        = string
  validation {
    condition     = can(keys(jsondecode(var.docker_daemon_config)))
    error_message = "docker_daemon_config must be a JSON object."
  }
}
