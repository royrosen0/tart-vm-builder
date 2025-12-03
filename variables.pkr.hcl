# =============================================================================
# Variables for Tart VM Builder
# =============================================================================

variable "base_image" {
  type        = string
  default     = "ghcr.io/cirruslabs/macos-tahoe-xcode:latest"
  description = "Base macOS image to clone from"
}

variable "vm_name" {
  type        = string
  default     = "tahoe-full-stack"
  description = "Name for the output VM image"
}

variable "cpu_count" {
  type        = number
  default     = 4
  description = "Number of CPUs to allocate to the build VM"
}

variable "memory_gb" {
  type        = number
  default     = 8
  description = "Amount of RAM in GB to allocate to the build VM"
}

variable "disk_size_gb" {
  type        = number
  default     = 100
  description = "Disk size in GB for the VM"
}

variable "ssh_username" {
  type        = string
  default     = "admin"
  description = "SSH username for connecting to the VM"
}

variable "ssh_password" {
  type        = string
  default     = "admin"
  sensitive   = true
  description = "SSH password for connecting to the VM"
}

variable "ssh_timeout" {
  type        = string
  default     = "120s"
  description = "SSH connection timeout"
}

