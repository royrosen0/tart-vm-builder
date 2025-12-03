#!/bin/bash
# =============================================================================
# Cleanup Script for VM Export
# =============================================================================
# This script minimizes disk usage before exporting the VM to ensure
# optimal compression and smaller archive sizes.
# =============================================================================

set -euo pipefail

echo "=============================================="
echo "Starting Cleanup for VM Export"
echo "=============================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ADMIN_USER="admin"
ADMIN_HOME="/Users/admin"

# -----------------------------------------------------------------------------
# Helper function to run commands as admin user
# -----------------------------------------------------------------------------
run_as_admin() {
    sudo -u "$ADMIN_USER" "$@"
}

# -----------------------------------------------------------------------------
# Helper function to safely remove directories/files
# -----------------------------------------------------------------------------
safe_remove() {
    local path="$1"
    if [ -e "$path" ]; then
        echo ">>> Removing: $path"
        rm -rf "$path"
    else
        echo ">>> Skipping (not found): $path"
    fi
}

# -----------------------------------------------------------------------------
# Step 1: Clean Homebrew caches
# -----------------------------------------------------------------------------
echo ""
echo ">>> Cleaning Homebrew..."
run_as_admin /opt/homebrew/bin/brew cleanup --prune=all -s

# Remove Homebrew cache directory
safe_remove "${ADMIN_HOME}/Library/Caches/Homebrew"
safe_remove "/opt/homebrew/Caskroom/.metadata"

# -----------------------------------------------------------------------------
# Step 2: Clean Xcode caches and derived data
# -----------------------------------------------------------------------------
echo ""
echo ">>> Cleaning Xcode caches..."

# Derived Data (build artifacts)
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/DerivedData"

# iOS Device Support (can be large, will be re-downloaded when needed)
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/iOS DeviceSupport"

# watchOS Device Support
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/watchOS DeviceSupport"

# tvOS Device Support
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/tvOS DeviceSupport"

# Xcode Archives (old builds)
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/Archives"

# Xcode Previews cache
safe_remove "${ADMIN_HOME}/Library/Developer/Xcode/UserData/Previews"

# CoreSimulator caches (simulator data)
safe_remove "${ADMIN_HOME}/Library/Developer/CoreSimulator/Caches"

# -----------------------------------------------------------------------------
# Step 3: Clean system caches
# -----------------------------------------------------------------------------
echo ""
echo ">>> Cleaning system caches..."

# User cache directory
safe_remove "${ADMIN_HOME}/Library/Caches/*"

# Log files
safe_remove "${ADMIN_HOME}/Library/Logs/*"
safe_remove "/var/log/*"

# Temporary files
safe_remove "/tmp/*"
safe_remove "/private/var/tmp/*"

# Spotlight index (will be rebuilt on first boot)
# mdutil -E / 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 4: Clean package manager caches
# -----------------------------------------------------------------------------
echo ""
echo ">>> Cleaning package manager caches..."

# npm cache (if npm is installed)
if command -v npm &> /dev/null; then
    run_as_admin npm cache clean --force 2>/dev/null || true
fi

# Gradle cache (Android builds)
safe_remove "${ADMIN_HOME}/.gradle/caches"
safe_remove "${ADMIN_HOME}/.gradle/wrapper/dists"

# CocoaPods cache
safe_remove "${ADMIN_HOME}/Library/Caches/CocoaPods"

# Carthage cache
safe_remove "${ADMIN_HOME}/Library/Caches/org.carthage.CarthageKit"

# -----------------------------------------------------------------------------
# Step 5: Clean Android SDK caches
# -----------------------------------------------------------------------------
echo ""
echo ">>> Cleaning Android SDK caches..."

# Android SDK temporary files
safe_remove "${ADMIN_HOME}/.android/cache"
safe_remove "${ADMIN_HOME}/.android/build-cache"

# AVD (Android Virtual Devices) - remove if not needed
# Uncomment if you don't need pre-configured emulators
# safe_remove "${ADMIN_HOME}/.android/avd"

# -----------------------------------------------------------------------------
# Step 6: Clear bash/zsh history
# -----------------------------------------------------------------------------
echo ""
echo ">>> Clearing shell history..."
safe_remove "${ADMIN_HOME}/.bash_history"
safe_remove "${ADMIN_HOME}/.zsh_history"
safe_remove "${ADMIN_HOME}/.zsh_sessions"

# -----------------------------------------------------------------------------
# Step 7: Flush disk caches
# -----------------------------------------------------------------------------
echo ""
echo ">>> Flushing disk caches..."
sync
purge 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 8: Zero out free space for better compression (optional)
# -----------------------------------------------------------------------------
echo ""
echo ">>> Zeroing free space for better compression..."
echo ">>> This may take a few minutes..."

# Create a file filled with zeros until disk is full, then delete it
# This helps compression by filling free space with zeros
ZERO_FILE="/tmp/zero_fill"
dd if=/dev/zero of="$ZERO_FILE" bs=1m 2>/dev/null || true
sync
rm -f "$ZERO_FILE"

echo ""
echo "=============================================="
echo "Cleanup Complete"
echo "=============================================="

# Report disk usage
echo ""
echo ">>> Current disk usage:"
df -h /

echo ""

