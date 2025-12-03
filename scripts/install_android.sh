#!/bin/bash
# =============================================================================
# Android SDK and Android Studio Installation Script
# =============================================================================
# This script installs:
# - OpenJDK 21 (required for Android development)
# - Android Command Line Tools via Homebrew
# - Android SDK packages (platform-tools, platforms, build-tools)
# - Android Studio
# =============================================================================

set -euo pipefail

echo "=============================================="
echo "Starting Android Development Tools Installation"
echo "=============================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
JAVA_HOME="/opt/homebrew/opt/openjdk@21"
ZSHRC="/Users/admin/.zshrc"

# Switch to admin user for Homebrew operations
ADMIN_USER="admin"

# -----------------------------------------------------------------------------
# Helper function to run commands as admin user
# -----------------------------------------------------------------------------
run_as_admin() {
    sudo -u "$ADMIN_USER" "$@"
}

# -----------------------------------------------------------------------------
# Step 1: Update Homebrew
# -----------------------------------------------------------------------------
echo ""
echo ">>> Updating Homebrew..."
run_as_admin /opt/homebrew/bin/brew update

# -----------------------------------------------------------------------------
# Step 2: Install OpenJDK 21
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing OpenJDK 21..."
run_as_admin /opt/homebrew/bin/brew install openjdk@21

# Verify Java installation
echo ">>> Verifying Java installation..."
"${JAVA_HOME}/bin/java" -version

# -----------------------------------------------------------------------------
# Step 3: Install Android Command Line Tools
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing Android Command Line Tools..."
run_as_admin /opt/homebrew/bin/brew install android-commandlinetools

# -----------------------------------------------------------------------------
# Step 4: Configure Environment Variables
# -----------------------------------------------------------------------------
echo ""
echo ">>> Configuring environment variables..."

# Create or update .zshrc with Android environment variables
cat >> "$ZSHRC" << 'EOF'

# =============================================================================
# Android Development Environment
# =============================================================================
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

# Add Android tools to PATH
export PATH="$JAVA_HOME/bin:$PATH"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export PATH="$ANDROID_HOME/emulator:$PATH"
export PATH="$ANDROID_HOME/build-tools/35.0.0:$PATH"
EOF

# Set ownership of .zshrc
chown "$ADMIN_USER:staff" "$ZSHRC"

# Source the environment for this session
export JAVA_HOME="${JAVA_HOME}"
export ANDROID_HOME="${ANDROID_HOME}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

echo ">>> Environment variables configured and persisted to ${ZSHRC}"

# -----------------------------------------------------------------------------
# Step 5: Accept Android SDK Licenses
# -----------------------------------------------------------------------------
echo ""
echo ">>> Accepting Android SDK licenses..."

# Disable pipefail temporarily for license acceptance
# The 'yes' command will exit with SIGPIPE when sdkmanager stops reading
set +o pipefail
yes 2>/dev/null | run_as_admin "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses || true
set -o pipefail

echo ">>> Licenses accepted"

# -----------------------------------------------------------------------------
# Step 6: Install Android SDK Packages
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing Android SDK packages..."

SDK_PACKAGES=(
    "platform-tools"
    "platforms;android-35"
    "build-tools;35.0.0"
)

for package in "${SDK_PACKAGES[@]}"; do
    echo ">>> Installing: ${package}"
    run_as_admin "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --install "$package"
done

# -----------------------------------------------------------------------------
# Step 7: Install Android Studio
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing Android Studio..."
run_as_admin /opt/homebrew/bin/brew install --cask android-studio

# -----------------------------------------------------------------------------
# Step 8: Verify Installation
# -----------------------------------------------------------------------------
echo ""
echo ">>> Verifying installation..."

echo "Java version:"
"${JAVA_HOME}/bin/java" -version

echo ""
echo "Android SDK Manager:"
run_as_admin "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --version

echo ""
echo "Installed SDK packages:"
run_as_admin "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --list_installed

echo ""
echo "=============================================="
echo "Android Development Tools Installation Complete"
echo "=============================================="
echo ""
echo "ANDROID_HOME: ${ANDROID_HOME}"
echo "JAVA_HOME: ${JAVA_HOME}"
echo ""

