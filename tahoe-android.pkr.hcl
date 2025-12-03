# =============================================================================
# Packer Template for macOS Tahoe with Android Development Tools
# =============================================================================
# This template creates a layered VM image by:
# 1. Cloning a base macOS Tahoe + Xcode image
# 2. Installing Android SDK, Android Studio, and related tools
# 3. Cleaning up to minimize disk usage for export
# =============================================================================

packer {
  required_plugins {
    tart = {
      version = ">= 1.14.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# =============================================================================
# Source: Tart VM from base image
# =============================================================================
source "tart-cli" "tahoe-android" {
  # Clone from the base macOS image with Xcode pre-installed
  from_oci       = var.base_image
  vm_name        = var.vm_name
  
  # Resource allocation for faster builds
  cpu_count      = var.cpu_count
  memory_gb      = var.memory_gb
  disk_size_gb   = var.disk_size_gb
  
  # SSH configuration
  ssh_username   = var.ssh_username
  ssh_password   = var.ssh_password
  ssh_timeout    = var.ssh_timeout
  
  # Disable VNC as we don't need graphical access during build
  headless       = true
  
  # Run the VM during provisioning
  run_packer_tag = "packer-build"
}

# =============================================================================
# Build definition
# =============================================================================
build {
  name    = "tahoe-android-build"
  sources = ["source.tart-cli.tahoe-android"]

  # -------------------------------------------------------------------------
  # Step 1: Install Android SDK and Android Studio
  # -------------------------------------------------------------------------
  provisioner "shell" {
    script = "${path.root}/scripts/install_android.sh"
    
    # Use sudo to handle operations that need elevated privileges
    execute_command = "chmod +x {{ .Path }}; sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
    
    # Pass the password for sudo
    environment_vars = [
      "SUDO_PASS=${var.ssh_password}"
    ]
    
    # Increase timeout for SDK downloads
    timeout = "60m"
  }

  # -------------------------------------------------------------------------
  # Step 2: Install internal/custom tools (placeholder)
  # -------------------------------------------------------------------------
  provisioner "shell" {
    script = "${path.root}/scripts/install_internal_tools.sh"
    
    execute_command = "chmod +x {{ .Path }}; sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
    
    environment_vars = [
      "SUDO_PASS=${var.ssh_password}"
    ]
    
    timeout = "30m"
  }

  # -------------------------------------------------------------------------
  # Step 3: Cleanup to minimize disk usage before export
  # -------------------------------------------------------------------------
  provisioner "shell" {
    script = "${path.root}/scripts/cleanup.sh"
    
    execute_command = "chmod +x {{ .Path }}; sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
    
    environment_vars = [
      "SUDO_PASS=${var.ssh_password}"
    ]
    
    timeout = "30m"
  }

  # -------------------------------------------------------------------------
  # Post-processor: Print build information
  # -------------------------------------------------------------------------
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}

