terraform {
  required_version = ">= 1.10"

  required_providers {
    ssh = {
      source  = "loafoe/ssh"
      version = "~> 2.7"
    }
  }
}
