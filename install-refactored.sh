#!/bin/bash
# macOS Development Environment Setup Script
# Version: 2.0.0
# Description: Automated setup for iOS/Android development environment on macOS
# Author: Refactored version

set -euo pipefail

# ============================================================================
# CONFIGURATION SECTION
# ============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Paths and directories
readonly ANDROID_SDK_ROOT="/Users/Shared/dev/sdk"
readonly ANDROID_HOME="$ANDROID_SDK_ROOT"
readonly NPM_PREFIX="$HOME/.npm-global"
readonly SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
readonly DOCK_BACKUP_DIR="$HOME"

# Network configuration
readonly SSH_PORT="20022"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SERVICES_FILE="/etc/services"

# Installation options
# REMOVED 'readonly' to allow command line arguments to override these
INSTALL_ANDROID="${INSTALL_ANDROID:-true}"
INSTALL_XCODE="${INSTALL_XCODE:-true}"
INSTALL_APPIUM="${INSTALL_APPIUM:-true}"
CONFIGURE_SSH="${CONFIGURE_SSH:-true}"
CONFIGURE_POWER="${CONFIGURE_POWER:-true}"

# Logging configuration
readonly LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME%.sh}.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

# ============================================================================
# LOGGING SYSTEM
# ============================================================================

# Color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_GRAY='\033[0;90m'

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Logging functions
log_debug() {
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [DEBUG] $msg" >> "$LOG_FILE"
    [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "${COLOR_GRAY}[DEBUG] $msg${COLOR_RESET}" >&2
}

log_info() {
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [INFO] $msg" >> "$LOG_FILE"
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $msg"
}

log_success() {
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [SUCCESS] $msg" >> "$LOG_FILE"
    echo -e "${COLOR_GREEN}[✓]${COLOR_RESET} $msg"
}

log_warn() {
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [WARN] $msg" >> "$LOG_FILE"
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $msg" >&2
}

log_error() {
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [ERROR] $msg" >> "$LOG_FILE"
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $msg" >&2
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Stack trace on error
error_handler() {
    local line_no=$1
    local exit_code=$2
    log_error "Script failed at line $line_no with exit code $exit_code"
    log_error "Call stack:"
    local frame=0
    while caller $frame; do
        ((frame++))
    done
    exit "$exit_code"
}

trap 'error_handler $LINENO $?' ERR

# Cleanup handler
cleanup() {
    local exit_code=$?
    if [[ -n "${KEEPALIVE_PID:-}" ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [[ $exit_code -eq 0 ]]; then
        log_success "Script completed successfully"
    else
        log_error "Script failed with exit code $exit_code"
    fi
    log_info "Log file: $LOG_FILE"
}

trap cleanup EXIT

# ============================================================================
# VALIDATION AND PREREQUISITES
# ============================================================================

validate_system() {
    log_info "Validating system requirements..."
    
    # Check macOS version
    local macos_version
    macos_version="$(sw_vers -productVersion)"
    log_info "macOS version: $macos_version"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
    
    # Check disk space (require at least 50GB free)
    local free_space
    free_space=$(df -g / | awk 'NR==2 {print $4}')
    if [[ $free_space -lt 50 ]]; then
        log_warn "Low disk space: ${free_space}GB free (recommended: 50GB+)"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 -t 2 8.8.8.8 &>/dev/null; then
        log_warn "No internet connection detected - some features may not work"
    fi
    
    log_success "System validation complete"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Brew formula check
brew_formula_installed() {
    brew list --versions "$1" >/dev/null 2>&1
}

# Brew cask check
brew_cask_installed() {
    brew list --cask --versions "$1" >/dev/null 2>&1
}

# Safe brew install with retry
brew_install_safe() {
    local package="$1"
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if brew install "$package" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Installed: $package"
            return 0
        fi
        ((retry++))
        log_warn "Installation failed for $package, retry $retry/$max_retries"
        sleep 2
    done
    
    log_error "Failed to install $package after $max_retries attempts"
    return 1
}

# Ensure brew packages
brew_ensure() {
    local packages=("$@")
    for package in "${packages[@]}"; do
        if brew_formula_installed "$package"; then
            log_info "Already installed: $package"
        else
            log_info "Installing: $package"
            brew_install_safe "$package" || log_warn "Failed to install $package"
        fi
    done
}

# Ensure brew casks
brew_cask_ensure() {
    local packages=("$@")
    for package in "${packages[@]}"; do
        if brew_cask_installed "$package"; then
            log_info "Already installed (cask): $package"
        else
            log_info "Installing (cask): $package"
            brew install --cask "$package" || log_warn "Failed to install cask $package"
        fi
    done
}

# ============================================================================
# SUDO MANAGEMENT
# ============================================================================

setup_sudo_keepalive() {
    log_info "Setting up sudo keepalive..."
    sudo -v
    ( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
    log_debug "Sudo keepalive PID: $KEEPALIVE_PID"
}

# ============================================================================
# HOMEBREW SETUP
# ============================================================================

setup_homebrew() {
    log_info "Setting up Homebrew..."
    
    if ! command_exists brew; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Setup brew environment
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    log_info "Updating Homebrew..."
    brew update || log_warn "Failed to update Homebrew"
    
    log_success "Homebrew setup complete"
}

# ============================================================================
# CORE TOOLS INSTALLATION
# ============================================================================

install_core_tools() {
    log_info "Installing core development tools..."
    
    local core_formulas=(
        jq
        node
        xcodes
        bash
        autoconf
        coreutils
        fastlane
        htop
        maven
        nvm
        python
        tree
        aria2
        sshpass
        rsync
        ktlint
        swiftlint
    )
    
    local core_casks=(
        android-studio
        android-commandlinetools
    )
    
    brew_ensure "${core_formulas[@]}"
    brew_cask_ensure "${core_casks[@]}"
    
    log_success "Core tools installation complete"
}

# ============================================================================
# JAVA SETUP
# ============================================================================

setup_java() {
    log_info "Setting up Java environment..."
    
    if ! command_exists java; then
        brew_ensure openjdk@17
    fi
    
    # Set JAVA_HOME
    if [[ -d "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    elif [[ -d "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
        export JAVA_HOME="/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    elif /usr/libexec/java_home -V >/dev/null 2>&1; then
        export JAVA_HOME="$(/usr/libexec/java_home -v '17+')"
    fi
    
    export PATH="$JAVA_HOME/bin:$PATH"
    log_success "Java setup complete: $JAVA_HOME"
}

# ============================================================================
# NPM SETUP
# ============================================================================

setup_npm() {
    log_info "Setting up NPM environment..."
    
    local current_prefix
    current_prefix="$(npm config get prefix 2>/dev/null || echo "")"
    
    if [[ "$current_prefix" != "$NPM_PREFIX" ]]; then
        log_info "Setting NPM prefix to $NPM_PREFIX"
        mkdir -p "$NPM_PREFIX"/{lib,node_modules,bin}
        npm config set prefix "$NPM_PREFIX"
    fi
    
    export PATH="$NPM_PREFIX/bin:$PATH"
    log_success "NPM setup complete"
}

# ============================================================================
# RUBY SETUP
# ============================================================================

setup_ruby() {
    log_info "Setting up Ruby environment..."
    
    local gem_user_bin
    gem_user_bin="$(ruby -rrubygems -e 'print Gem.user_dir' 2>/dev/null)/bin" || true
    
    if [[ -z "${gem_user_bin:-}" ]]; then
        gem_user_bin="$HOME/.gem/bin"
    fi
    
    export PATH="$gem_user_bin:$PATH"
    
    # Install xcpretty
    if ! command_exists xcpretty; then
        log_info "Installing xcpretty..."
        gem install --user-install xcpretty --no-document || {
            log_warn "Failed with system Ruby, trying Homebrew Ruby..."
            brew_ensure ruby
            export PATH="$(brew --prefix)/opt/ruby/bin:$PATH"
            gem install --user-install xcpretty --no-document
        }
    fi
    
    log_success "Ruby setup complete"
}

# ============================================================================
# ANDROID SDK SETUP
# ============================================================================

setup_android_sdk() {
    [[ "$INSTALL_ANDROID" != "true" ]] && return 0
    
    log_info "Setting up Android SDK..."
    
    # Create SDK directory with proper permissions
    sudo mkdir -p "$ANDROID_SDK_ROOT"
    sudo chown -R "$(whoami)":staff "$ANDROID_SDK_ROOT"
    sudo chmod -R 2775 "$ANDROID_SDK_ROOT"
    
    # Create symlink for Android Studio
    mkdir -p "$HOME/Library/Android"
    ln -snf "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk"
    
    # Copy command line tools
    local cmd_tools_src="$(brew --prefix)/share/android-commandlinetools"
    if [[ -d "$cmd_tools_src" ]]; then
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        rsync -a "$cmd_tools_src/" "$ANDROID_SDK_ROOT/cmdline-tools/latest/" 2>/dev/null || \
            cp -R "$cmd_tools_src/." "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
    fi
    
    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
    
    # Install SDK components
    log_info "Installing Android SDK components..."
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --update 2>&1 | tee -a "$LOG_FILE" || true
    
    local sdk_packages=(
        "platform-tools"
        "emulator"
    )
    
    for package in "${sdk_packages[@]}"; do
        log_info "Installing SDK package: $package"
        yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "$package" 2>&1 | tee -a "$LOG_FILE" || true
    done
    
    # Accept licenses
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
    
    log_success "Android SDK setup complete"
}

# ============================================================================
# XCODE SETUP
# ============================================================================

setup_xcode() {
    [[ "$INSTALL_XCODE" != "true" ]] && return 0
    
    log_info "Setting up Xcode..."
    
    # Get stable Xcode versions
    local versions
    versions=$(xcodes list | awk '!/beta|Beta|RC|candidate/ && /^[0-9]+\.[0-9]+/ {print $1}' | sort -V | uniq | tail -n 3 || true)
    
    if [[ -n "${versions// /}" ]]; then
        while IFS= read -r version; do
            [[ -n "$version" ]] || continue
            
            if xcodes installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$version"; then
                log_info "Xcode $version already installed"
            else
                log_info "Installing Xcode $version..."
                sudo xcodes install "$version" --experimental-unxip || log_warn "Failed to install Xcode $version"
            fi
        done <<< "$versions"
    fi
    
    # Select latest Xcode
    local latest_xcode
    latest_xcode=$(ls -1d /Applications/Xcode*.app 2>/dev/null | grep -vi beta | sort -V | tail -n 1 || true)
    
    if [[ -n "${latest_xcode:-}" ]]; then
        log_info "Selecting Xcode: $latest_xcode"
        sudo xcode-select -s "$latest_xcode/Contents/Developer"
        export DEVELOPER_DIR="$latest_xcode/Contents/Developer"
        sudo xcodebuild -license accept >/dev/null 2>&1 || true
        sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
    fi
    
    # Create versioned symlinks
    log_info "Creating Xcode version symlinks..."
    for app in /Applications/Xcode*.app; do
        [[ -d "$app" ]] || continue
        
        local version
        version="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
        [[ -n "$version" ]] || continue
        
        local target_dir="/Applications/Xcode $version"
        local symlink_path="$target_dir/Xcode.app"
        
        sudo mkdir -p "$target_dir"
        if [[ ! -L "$symlink_path" ]]; then
            sudo ln -sfn "$app" "$symlink_path"
            log_info "Created symlink: $symlink_path -> $app"
        fi
    done
    
    log_success "Xcode setup complete"
}

# ============================================================================
# APPIUM SETUP
# ============================================================================

setup_appium() {
    [[ "$INSTALL_APPIUM" != "true" ]] && return 0
    
    log_info "Setting up Appium..."
    
    setup_npm
    
    if ! command_exists appium; then
        log_info "Installing Appium and Appium Doctor..."
        npm install -g appium appium-doctor
    else
        log_info "Updating Appium..."
        npm update -g appium appium-doctor
    fi
    
    # Install drivers
    if ! appium driver list --installed 2>/dev/null | grep -q '\bxcuitest\b'; then
        log_info "Installing xcuitest driver..."
        appium driver install xcuitest
    fi
    
    if ! appium driver list --installed 2>/dev/null | grep -q '\buiautomator2\b'; then
        log_info "Installing uiautomator2 driver..."
        appium driver install uiautomator2
    fi
    
    # Install ios-deploy
    if ! command_exists ios-deploy; then
        brew_ensure ios-deploy
    fi
    
    # Run diagnostics
    log_info "Running Appium diagnostics..."
    appium-doctor --ios 2>&1 | tee -a "$LOG_FILE" || true
    appium-doctor --android 2>&1 | tee -a "$LOG_FILE" || true
    
    log_success "Appium setup complete"
}

# ============================================================================
# SSH CONFIGURATION
# ============================================================================

configure_ssh() {
    [[ "$CONFIGURE_SSH" != "true" ]] && return 0
    
    log_info "Configuring SSH..."
    
    # Update /etc/services
    if grep -qE '^ssh[[:space:]]+22/' "$SERVICES_FILE"; then
        log_info "Updating SSH port in $SERVICES_FILE..."
        sudo sed -i.bak -E "s/^(ssh[[:space:]]+)22\//\1${SSH_PORT}\//" "$SERVICES_FILE"
    fi
    
    # Update sshd_config
    local sshd_config="$SSH_CONFIG"
    if ! sudo grep -qE "^[#]*[[:space:]]*Port[[:space:]]+${SSH_PORT}\b" "$sshd_config"; then
        log_info "Setting SSH port to $SSH_PORT..."
        if sudo grep -qE '^[#]*[[:space:]]*Port[[:space:]]+[0-9]+' "$sshd_config"; then
            sudo sed -i.bak -E "s/^[#]*[[:space:]]*Port[[:space:]]+[0-9]+/Port ${SSH_PORT}/" "$sshd_config"
        else
            echo "Port ${SSH_PORT}" | sudo tee -a "$sshd_config" >/dev/null
        fi
    fi
    
    # Enable remote login
    sudo systemsetup -setremotelogin on >/dev/null 2>&1 || true
    sudo launchctl enable system/com.openssh.sshd >/dev/null 2>&1 || true
    sudo launchctl kickstart -k system/com.openssh.sshd >/dev/null 2>&1 || true
    
    # Generate SSH key
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_info "Generating SSH key..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "$(whoami)@$(hostname)" -N ""
        log_info "SSH public key:"
        cat "${SSH_KEY_PATH}.pub"
    fi
    
    log_success "SSH configuration complete (port $SSH_PORT)"
}

# ============================================================================
# POWER MANAGEMENT
# ============================================================================

configure_power_management() {
    [[ "$CONFIGURE_POWER" != "true" ]] && return 0
    
    log_info "Configuring power management for server use..."
    
    # Disable all sleep modes
    sudo pmset -a sleep 0
    sudo pmset -a displaysleep 0
    sudo pmset -a disksleep 0
    sudo pmset -a powernap 0 2>/dev/null || true
    sudo pmset -a standby 0 2>/dev/null || true
    sudo pmset -a autopoweroff 0 2>/dev/null || true
    
    # Legacy commands for compatibility
    sudo systemsetup -setcomputersleep Never >/dev/null 2>&1 || true
    sudo systemsetup -setdisplaysleep Never >/dev/null 2>&1 || true
    sudo systemsetup -setharddisksleep Never >/dev/null 2>&1 || true
    
    # Disable screensaver
    defaults -currentHost write com.apple.screensaver idleTime -int 0
    
    log_info "Current power settings:"
    pmset -g | sed 's/^/  /' | tee -a "$LOG_FILE"
    
    log_success "Power management configured"
}

# ============================================================================
# REMOTE MANAGEMENT
# ============================================================================

configure_remote_management() {
    log_info "Configuring Apple Remote Desktop..."
    
    local kickstart="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
    
    if [[ -x "$kickstart" ]]; then
        sudo "$kickstart" -activate -configure -access -on -allowAccessFor -allUsers -privs -all || true
        sudo "$kickstart" -restart -agent || true
        log_success "Remote management enabled"
    else
        log_warn "ARD kickstart tool not found"
    fi
}

# ============================================================================
# DOCK CONFIGURATION
# ============================================================================

configure_dock() {
    log_info "Configuring Dock..."
    
    # Backup current dock
    local backup_file="$DOCK_BACKUP_DIR/dock-backup-$(date +%Y%m%d-%H%M%S).plist"
    defaults export com.apple.dock - > "$backup_file" 2>/dev/null || true
    log_info "Dock backup saved to: $backup_file"
    
    # Clear and configure dock
    defaults write com.apple.dock persistent-apps -array
    defaults write com.apple.dock persistent-others -array
    defaults write com.apple.dock show-recents -bool false
    
    # Add essential apps
    local apps=(
        "/System/Applications/Utilities/Terminal.app"
        "/Applications/Safari.app"
        "/System/Applications/System Settings.app"
    )
    
    for app in "${apps[@]}"; do
        if [[ -d "$app" ]]; then
            defaults write com.apple.dock persistent-apps -array-add \
                "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        fi
    done
    
    killall Dock >/dev/null 2>&1 || true
    log_success "Dock configured"
}

# ============================================================================
# SHELL ENVIRONMENT CONFIGURATION
# ============================================================================

configure_shell_environment() {
    log_info "Configuring shell environment..."
    
    local zshrc="$HOME/.zshrc"
    local zprofile="$HOME/.zprofile"
    
    # Ensure files exist
    touch "$zshrc" "$zprofile"
    
    # Create configuration blocks
    local android_block="# --- Android SDK (managed by ${SCRIPT_NAME}) ---
export ANDROID_SDK_ROOT=\"$ANDROID_SDK_ROOT\"
export ANDROID_HOME=\"\$ANDROID_SDK_ROOT\"
path_add() { case \":\$PATH:\" in *:\"\$1\":*) ;; *) PATH=\"\$1:\$PATH\";; esac }
path_add \"\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin\"
path_add \"\$ANDROID_SDK_ROOT/platform-tools\"
unset -f path_add
# --- end Android ---"
    
    local npm_block="# --- NPM user bin (managed by ${SCRIPT_NAME}) ---
export PATH=\"$NPM_PREFIX/bin:\$PATH\"
# --- end npm ---"
    
    local ruby_block="# --- Ruby gems user bin (managed by ${SCRIPT_NAME}) ---
_ruby_user_bin=\"\$(
  /usr/bin/env ruby -rrubygems -e 'print Gem.user_dir' 2>/dev/null || printf \"\$HOME/.gem\"
)/bin\"
case \":\$PATH:\" in *:\"\$_ruby_user_bin\":*) ;; *) PATH=\"\$_ruby_user_bin:\$PATH\";; esac
unset _ruby_user_bin
# --- end ruby ---"
    
    local nvm_block="# --- NVM (managed by ${SCRIPT_NAME}) ---
export NVM_DIR=\"\$HOME/.nvm\"
if [ -s \"/opt/homebrew/opt/nvm/nvm.sh\" ]; then . \"/opt/homebrew/opt/nvm/nvm.sh\"; fi
if [ -s \"/usr/local/opt/nvm/nvm.sh\" ]; then . \"/usr/local/opt/nvm/nvm.sh\"; fi
# --- end NVM ---"
    
    # Add blocks to .zshrc if not present
    if ! grep -q 'ANDROID_SDK_ROOT' "$zshrc"; then
        echo "$android_block" >> "$zshrc"
        log_info "Added Android configuration to .zshrc"
    fi
    
    if ! grep -q 'NPM user bin' "$zshrc"; then
        echo "$npm_block" >> "$zshrc"
        log_info "Added NPM configuration to .zshrc"
    fi
    
    if ! grep -q 'Ruby gems user bin' "$zshrc"; then
        echo "$ruby_block" >> "$zshrc"
        log_info "Added Ruby configuration to .zshrc"
    fi
    
    if ! grep -q 'NVM.*managed' "$zshrc"; then
        echo "$nvm_block" >> "$zshrc"
        log_info "Added NVM configuration to .zshrc"
    fi
    
    # Add minimal config to .zprofile
    if ! grep -q "managed by ${SCRIPT_NAME}" "$zprofile"; then
        cat >> "$zprofile" <<EOF
# Mirror key PATH entries for login shells (managed by ${SCRIPT_NAME})
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export PATH="$NPM_PREFIX/bin:\$PATH"
EOF
        log_info "Added configuration to .zprofile"
    fi
    
    log_success "Shell environment configured"
}

# ============================================================================
# GIT CONFIGURATION
# ============================================================================

configure_git() {
    log_info "Configuring Git..."
    
    # Configure credential helper
    if ! git config --global credential.helper 2>/dev/null | grep -q 'osxkeychain'; then
        git config --global credential.helper osxkeychain
        log_info "Git credential helper set to osxkeychain"
    fi
    
    log_success "Git configuration complete"
}

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION
macOS Development Environment Setup Script

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show script version
    -l, --log-level LEVEL   Set log level (DEBUG, INFO, WARN, ERROR)
    --skip-android          Skip Android SDK setup
    --skip-xcode            Skip Xcode setup
    --skip-appium           Skip Appium setup
    --skip-ssh              Skip SSH configuration
    --skip-power            Skip power management configuration
    --log-file PATH         Set custom log file path

ENVIRONMENT VARIABLES:
    INSTALL_ANDROID         Set to 'false' to skip Android setup
    INSTALL_XCODE           Set to 'false' to skip Xcode setup
    INSTALL_APPIUM          Set to 'false' to skip Appium setup
    CONFIGURE_SSH           Set to 'false' to skip SSH configuration
    CONFIGURE_POWER         Set to 'false' to skip power configuration
    LOG_LEVEL               Set logging level (DEBUG, INFO, WARN, ERROR)
    LOG_FILE                Set custom log file path

EXAMPLES:
    # Run with default settings
    $SCRIPT_NAME

    # Skip Xcode installation
    $SCRIPT_NAME --skip-xcode

    # Run with debug logging
    $SCRIPT_NAME --log-level DEBUG

    # Use environment variables
    INSTALL_XCODE=false LOG_LEVEL=DEBUG $SCRIPT_NAME

EOF
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v$SCRIPT_VERSION"
                exit 0
                ;;
            -l|--log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --skip-android)
                INSTALL_ANDROID="false"
                shift
                ;;
            --skip-xcode)
                INSTALL_XCODE="false"
                shift
                ;;
            --skip-appium)
                INSTALL_APPIUM="false"
                shift
                ;;
            --skip-ssh)
                CONFIGURE_SSH="false"
                shift
                ;;
            --skip-power)
                CONFIGURE_POWER="false"
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Start logging
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Log file: $LOG_FILE"
    log_info "Configuration:"
    log_info "  - Install Android: $INSTALL_ANDROID"
    log_info "  - Install Xcode: $INSTALL_XCODE"
    log_info "  - Install Appium: $INSTALL_APPIUM"
    log_info "  - Configure SSH: $CONFIGURE_SSH"
    log_info "  - Configure Power: $CONFIGURE_POWER"
    
    # Validate system
    validate_system
    
    # Setup sudo keepalive
    setup_sudo_keepalive
    
    # Set file creation mask
    umask 002
    
    # Core setup
    setup_homebrew
    setup_java
    install_core_tools
    setup_ruby
    configure_git
    
    # Development tools setup (can run in parallel)
    log_info "Starting parallel installation tasks..."
    
    (setup_android_sdk && log_success "Android SDK task completed") &
    local android_pid=$!
    
    (setup_xcode && log_success "Xcode task completed") &
    local xcode_pid=$!
    
    # Wait for parallel tasks
    wait $android_pid || log_warn "Android SDK setup had issues"
    wait $xcode_pid || log_warn "Xcode setup had issues"
    
    # Sequential tasks that depend on above
    setup_appium
    
    # System configuration
    configure_ssh
    configure_remote_management
    configure_power_management
    configure_dock
    
    # Shell environment (should be last)
    configure_shell_environment
    
    # Final message
    echo
    log_success "Installation complete!"
    echo
    echo "Next steps:"
    echo "  1. Open a new terminal window or run: exec zsh -l"
    echo "  2. Review the log file: $LOG_FILE"
    echo "  3. Test your development environment"
    echo
    
    # Optional post-installation script
    if [[ -f "$HOME/post_internet_setup.sh" ]]; then
        log_info "Scheduling post-installation script..."
        echo "bash ~/post_internet_setup.sh" | at now + 2 minutes 2>/dev/null || \
            (nohup bash ~/post_internet_setup.sh >/tmp/post_internet_setup.log 2>&1 &)
    fi
}

# Run main function
main "$@" 
