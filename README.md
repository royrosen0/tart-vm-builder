# Tart VM Builder - macOS Tahoe with Android Development Tools

This project uses HashiCorp Packer with the Tart plugin to create a layered macOS VM image containing Xcode and Android development tools.

## Overview

The build process:
1. Clones a base macOS Tahoe image with Xcode pre-installed
2. Installs Android SDK, Android Studio, and Java 17
3. Cleans up caches to minimize disk usage
4. Exports to a compressed `.aar` archive for airgapped transfer

## Prerequisites

### Host Machine Requirements
- Apple Silicon Mac (M1/M2/M3/M4)
- macOS Sonoma or later
- At least 100GB free disk space
- Tart installed: `brew install cirruslabs/cli/tart`
- Packer installed: `brew install hashicorp/tap/packer`

### Install Tart Plugin for Packer
```bash
packer plugins install github.com/cirruslabs/tart
```

## Project Structure

```
tart-vm-builder/
├── README.md                      # This file
├── tahoe-android.pkr.hcl          # Main Packer template
├── variables.pkr.hcl              # Variable definitions
├── verify_export.sh               # Host-side export script
└── scripts/
    ├── install_android.sh         # Android SDK installation
    ├── install_internal_tools.sh  # Placeholder for custom tools
    └── cleanup.sh                 # Disk cleanup for export
```

## Quick Start

### 1. Initialize Packer

```bash
cd tart-vm-builder
packer init .
```

### 2. Validate the Configuration

```bash
packer validate .
```

### 3. Build the VM

```bash
packer build .
```

This will:
- Pull the base macOS Tahoe + Xcode image (~30GB download on first run)
- Install Android development tools (~5-10GB)
- Clean up caches
- Save the VM as `tahoe-full-stack`

**Estimated build time:** 30-60 minutes (depending on network speed)

### 4. Export for Airgapped Transfer

```bash
chmod +x verify_export.sh
./verify_export.sh
```

This creates:
- `tahoe-full-stack.aar` - Compressed VM archive
- `tahoe-full-stack.aar.sha256` - Checksum file for verification

### 5. Import on Target Machine

On the airgapped machine:

```bash
# Verify integrity
shasum -a 256 -c tahoe-full-stack.aar.sha256

# Import the VM
tart import tahoe-full-stack tahoe-full-stack.aar

# Start the VM
tart run tahoe-full-stack
```

## Configuration

### Customize Variables

You can override defaults via command line:

```bash
packer build \
  -var 'cpu_count=8' \
  -var 'memory_gb=16' \
  -var 'vm_name=my-custom-vm' \
  .
```

Or create a `variables.auto.pkrvars.hcl` file:

```hcl
cpu_count  = 8
memory_gb  = 16
vm_name    = "my-custom-vm"
```

### Available Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `base_image` | `ghcr.io/cirruslabs/macos-tahoe-xcode:latest` | Base image to clone |
| `vm_name` | `tahoe-full-stack` | Output VM name |
| `cpu_count` | `4` | CPUs for build VM |
| `memory_gb` | `8` | RAM for build VM |
| `disk_size_gb` | `100` | Disk size |
| `ssh_username` | `admin` | SSH user |
| `ssh_password` | `admin` | SSH password |

## What's Installed

### Base Image (from Cirrus Labs)
- macOS Tahoe
- Xcode (latest)
- Command Line Tools
- Homebrew

### Added by This Build
- **Java:** OpenJDK 21
- **Android SDK:**
  - Command Line Tools
  - Platform Tools (adb, fastboot)
  - Build Tools 35.0.0
  - Android Platform 35
- **Android Studio** (latest)
- **Code Quality & Linting:**
  - SonarScanner (code quality analysis)
  - ktlint (Kotlin linter)
  - SwiftLint (Swift linter)
- **CI/CD:**
  - Fastlane (iOS/Android automation)

### Environment Variables (in `~/.zshrc`)
```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

## Customization

### Adding Internal Tools

Edit `scripts/install_internal_tools.sh` to add your organization's tools:

```bash
# Example: Install custom packages
run_as_admin /opt/homebrew/bin/brew install your-package

# Example: Install from private tap
run_as_admin /opt/homebrew/bin/brew tap your-org/tools
run_as_admin /opt/homebrew/bin/brew install your-internal-tool
```

### Adding More Android SDK Packages

Edit `scripts/install_android.sh` and add to the `SDK_PACKAGES` array:

```bash
SDK_PACKAGES=(
    "platform-tools"
    "platforms;android-35"
    "platforms;android-34"
    "build-tools;35.0.0"
    "build-tools;34.0.0"
    "ndk;26.1.10909125"
    "cmake;3.22.1"
)
```

## Troubleshooting

### Build Fails at SSH Connection
The base image may take time to boot. Try increasing `ssh_timeout`:
```bash
packer build -var 'ssh_timeout=300s' .
```

### Disk Space Issues
Increase disk size or reduce installed packages:
```bash
packer build -var 'disk_size_gb=150' .
```

### SDK License Acceptance Fails
If license acceptance hangs, the script handles this gracefully, but you can manually accept licenses after the build:
```bash
tart run tahoe-full-stack
# Inside VM:
sdkmanager --licenses
```

### Export Takes Too Long
Large VMs take time to compress. Consider:
- Running cleanup script manually to free more space
- Using a faster SSD
- Reducing installed tools

## License

This project configuration is provided as-is. The software installed (macOS, Xcode, Android SDK, etc.) is subject to their respective licenses.

