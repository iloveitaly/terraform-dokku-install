variable "ssh_private_key_path" {
  description = "Optional path to a local SSH private key. Leave unset or set to null to use the SSH agent."
  type        = string
  default     = null
  validation {
    condition     = var.ssh_private_key_path == null ? true : trimspace(var.ssh_private_key_path) != ""
    error_message = "ssh_private_key_path must be a nonempty path or null to use an SSH agent."
  }
}

variable "ssh_known_hosts_path" {
  description = "Path to an existing known_hosts file with the verified server host key."
  type        = string
  nullable    = false
  validation {
    condition     = trimspace(var.ssh_known_hosts_path) != ""
    error_message = "ssh_known_hosts_path must be nonempty."
  }
}

variable "ssh_port" {
  description = "SSH port of the server."
  type        = number
  default     = 22
  nullable    = false
  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535 && floor(var.ssh_port) == var.ssh_port
    error_message = "ssh_port must be an integer between 1 and 65535."
  }
}

variable "server_revision" {
  description = "Change this value after a rebuild that keeps the same SSH address and server ID."
  type        = string
  default     = ""
  nullable    = false
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*[$]?$", var.ssh_user))
    error_message = "ssh_user must be a valid lowercase Unix username."
  }
}

variable "ssh_host" {
  description = "SSH host"
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrhost("${var.ssh_host}/128", 0)) || (length(var.ssh_host) <= 253 && alltrue([for label in split(".", var.ssh_host) : length(label) <= 63 && can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))]))
    error_message = "ssh_host must be a hostname or IP address without a port or whitespace."
  }
}

variable "dokku_version" {
  description = "Use latest for the latest stable release on a fresh install, or specify an exact numeric version."
  type        = string
  default     = "latest"
  nullable    = false
  validation {
    condition     = var.dokku_version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.dokku_version))
    error_message = "dokku_version must be latest or a numeric version such as 0.35.20."
  }
}

variable "dokku_hostname" {
  description = "Dokku's global domain for default app subdomains. For example, an app named api under dokku.example.com gets api.dokku.example.com."
  type        = string
  default     = "dokku.yourhost.com"
  nullable    = false
  validation {
    condition     = length(var.dokku_hostname) <= 253 && can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.dokku_hostname)) && alltrue([for label in split(".", var.dokku_hostname) : length(label) <= 63 && can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))])
    error_message = "dokku_hostname must be a valid DNS hostname."
  }
}

variable "dokku_ssh_public_key" {
  description = "Optional public SSH key content Dokku should authorize for deployments."
  type        = string
  default     = null
  validation {
    condition     = var.dokku_ssh_public_key == null ? true : trimspace(var.dokku_ssh_public_key) != "" && !strcontains(trimspace(var.dokku_ssh_public_key), "\n") && !strcontains(var.dokku_ssh_public_key, "\r")
    error_message = "dokku_ssh_public_key must be a single nonempty SSH public key line or null."
  }
}

variable "dokku_ssh_public_key_path" {
  description = "Optional path to the public SSH key Dokku should authorize for deployments."
  type        = string
  default     = null
  validation {
    condition     = var.dokku_ssh_public_key_path == null ? true : trimspace(var.dokku_ssh_public_key_path) != ""
    error_message = "dokku_ssh_public_key_path must be a nonempty path or null."
  }
}

variable "dokku_ssh_key_name" {
  description = "Name for the deploy SSH key in Dokku."
  type        = string
  default     = "admin"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.dokku_ssh_key_name))
    error_message = "dokku_ssh_key_name must contain only letters, digits, underscores, dots, and hyphens, and start with a letter or digit."
  }
}

variable "dokku_plugins" {
  description = "Legacy list of known plugin short names or HTTPS Git repository URLs."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for p in var.dokku_plugins : can(regex("^[a-z][a-z0-9-]*$", p)) || can(regex("^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", p))])
    error_message = "Each plugin must be a short name or an HTTPS Git repository URL."
  }
}

variable "dokku_plugin_definitions" {
  description = "Map of Dokku plugin names to HTTPS Git URLs and optional revisions."
  type = map(object({
    url      = string
    revision = optional(string)
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([for name, p in var.dokku_plugin_definitions :
      can(regex("^[a-z][a-z0-9-]*$", name)) && can(regex("^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", p.url)) && (p.revision == null ? true : can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", p.revision)) && !strcontains(p.revision, "..") && !strcontains(p.revision, "//") && !endswith(p.revision, "/"))
    ])
    error_message = "Plugin names, HTTPS repository URLs, and optional revisions must be valid and contain no shell metacharacters."
  }
}

variable "docker_daemon_config" {
  description = "Optional JSON object to write to /etc/docker/daemon.json."
  type        = string
  default     = null
  validation {
    condition     = var.docker_daemon_config == null ? true : can(keys(jsondecode(var.docker_daemon_config)))
    error_message = "docker_daemon_config must be a JSON object."
  }
}

variable "server_id" {
  description = "Optional server instance ID, such as the cloud instance ID. Changing it reruns setup even at the same SSH address. If omitted, the ID is ssh_host."
  type        = string
  default     = null
  validation {
    condition     = var.server_id == null ? true : trimspace(var.server_id) != ""
    error_message = "server_id must be nonempty when provided."
  }
}

variable "management_id" {
  description = "Unique ID this module uses to track deploy-key ownership on the server."
  type        = string
  default     = "terraform-dokku"
  nullable    = false
  validation {
    condition     = length(var.management_id) <= 200 && can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.management_id))
    error_message = "management_id must be at most 200 characters, start with a letter or digit, and contain only letters, digits, underscores, dots, and hyphens."
  }
}

variable "docker_version" {
  description = "Docker Engine version to install. Null selects 28.5.2 on Ubuntu 22.04/24.04 or 29.4.3 on Ubuntu 26.04."
  type        = string
  default     = null
  validation {
    condition     = var.docker_version == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.docker_version))
    error_message = "docker_version must be null or a numeric version such as 28.5.2."
  }
}

variable "containerd_version" {
  description = "containerd.io version to install. Null selects 1.7.28 on Ubuntu 22.04/24.04 or 2.2.5 on Ubuntu 26.04."
  type        = string
  default     = null
  validation {
    condition     = var.containerd_version == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.containerd_version))
    error_message = "containerd_version must be null or a numeric version such as 1.7.28."
  }
}

variable "allow_dokku_upgrade" {
  description = "Allow changing an already installed Dokku version."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_storage_migration" {
  description = "Allow changes to Docker storage configuration on an existing Docker installation."
  type        = bool
  default     = false
  nullable    = false
}

variable "ssh_timeout" {
  description = "Maximum duration in seconds for each remote operation."
  type        = number
  default     = 1800
  nullable    = false
  validation {
    condition     = var.ssh_timeout >= 60 && var.ssh_timeout <= 7200 && floor(var.ssh_timeout) == var.ssh_timeout
    error_message = "ssh_timeout must be an integer between 60 and 7200 seconds."
  }
}
