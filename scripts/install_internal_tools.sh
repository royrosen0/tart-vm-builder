#!/bin/bash
# =============================================================================
# Additional Development Tools Installation Script
# =============================================================================
# This script installs additional development and CI/CD tools:
# - SonarScanner (code quality analysis)
# - ktlint (Kotlin linter)
# - SwiftLint (Swift linter)
# - Fastlane (iOS/Android automation)
# =============================================================================

set -euo pipefail

echo "=============================================="
echo "Starting Additional Tools Installation"
echo "=============================================="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ADMIN_USER="admin"
ADMIN_HOME="/Users/admin"
ZSHRC="${ADMIN_HOME}/.zshrc"

# -----------------------------------------------------------------------------
# Helper function to run commands as admin user
# -----------------------------------------------------------------------------
run_as_admin() {
    sudo -u "$ADMIN_USER" "$@"
}

# -----------------------------------------------------------------------------
# Step 1: Install SonarScanner
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing SonarScanner..."
run_as_admin /opt/homebrew/bin/brew install sonar-scanner

# Verify installation
echo ">>> SonarScanner version:"
/opt/homebrew/bin/sonar-scanner --version || true

# -----------------------------------------------------------------------------
# Step 2: Install ktlint (Kotlin linter)
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing ktlint..."
run_as_admin /opt/homebrew/bin/brew install ktlint

# Verify installation
echo ">>> ktlint version:"
/opt/homebrew/bin/ktlint --version || true

# -----------------------------------------------------------------------------
# Step 3: Install SwiftLint
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing SwiftLint..."
run_as_admin /opt/homebrew/bin/brew install swiftlint

# Verify installation
echo ">>> SwiftLint version:"
/opt/homebrew/bin/swiftlint version || true

# -----------------------------------------------------------------------------
# Step 4: Install Fastlane
# -----------------------------------------------------------------------------
echo ""
echo ">>> Installing Fastlane..."
run_as_admin /opt/homebrew/bin/brew install fastlane

# Add Fastlane to PATH in .zshrc
cat >> "$ZSHRC" << 'EOF'

# =============================================================================
# Fastlane Configuration
# =============================================================================
export PATH="$HOME/.fastlane/bin:$PATH"
# Disable Fastlane crash reporting and usage analytics for CI
export FASTLANE_OPT_OUT_CRASH_REPORTING=1
export FASTLANE_OPT_OUT_USAGE=1
EOF

chown "$ADMIN_USER:staff" "$ZSHRC"

# Verify installation
echo ">>> Fastlane version:"
/opt/homebrew/bin/fastlane --version || true

# -----------------------------------------------------------------------------
# Step 5: Install Ruby (dependency for some Fastlane plugins)
# -----------------------------------------------------------------------------
echo ""
echo ">>> Ensuring Ruby is available for Fastlane plugins..."
# Ruby comes with macOS, but we ensure bundler is available
run_as_admin /opt/homebrew/bin/gem install bundler --no-document 2>/dev/null || true

# -----------------------------------------------------------------------------
# Verification Summary
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "Additional Tools Installation Complete"
echo "=============================================="
echo ""
echo "Installed tools:"
echo "  - sonar-scanner: $(/opt/homebrew/bin/sonar-scanner --version 2>&1 | head -1 || echo 'installed')"
echo "  - ktlint:        $(/opt/homebrew/bin/ktlint --version 2>&1 || echo 'installed')"
echo "  - swiftlint:     $(/opt/homebrew/bin/swiftlint version 2>&1 || echo 'installed')"
echo "  - fastlane:      $(/opt/homebrew/bin/fastlane --version 2>&1 | head -1 || echo 'installed')"
echo ""

