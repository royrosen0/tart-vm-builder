#!/bin/bash
# macOS Development Environment Setup Script (The "Not Stupid" Version)
# Version: 2.1.0-refactored
# Description: Automated setup for iOS/Android dev. Now with 100% less race conditions.

set -euo pipefail

# ============================================================================
# CONFIGURATION SECTION - DON'T FUCK THIS UP
# ============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Paths
readonly ANDROID_SDK_ROOT="/Users/Shared/dev/sdk"
readonly ANDROID_HOME="$ANDROID_SDK_ROOT"
readonly NPM_PREFIX="$HOME/.npm-global"
readonly SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
readonly DOCK_BACKUP_DIR="$HOME"

# Network & System
readonly SSH_PORT="20022"
readonly SSH_CONFIG="/etc/ssh/sshd_config"

# Installation Toggles (Overridable via ENV vars)
readonly INSTALL_ANDROID="${INSTALL_ANDROID:-true}"
readonly INSTALL_XCODE="${INSTALL_XCODE:-true}"
readonly INSTALL_APPIUM="${INSTALL_APPIUM:-true}"
readonly CONFIGURE_SSH="${CONFIGURE_SSH:-true}"
readonly CONFIGURE_POWER="${CONFIGURE_POWER:-true}"

# Versions - Change these if your project is stuck in the past
readonly JAVA_VERSION="${JAVA_VERSION:-openjdk@17}"
readonly TARGET_XCODE_VERSION="${TARGET_XCODE_VERSION:-latest}" # or e.g., "15.2"

# Logging
readonly LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME%.sh}.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}" 

# ============================================================================
# LOGGING SYSTEM (Because reading raw stdout is for amateurs)
# ============================================================================

readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
    local level=$1
    local color=$2
    shift 2
    local msg="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    # Filter output based on level
    if [[ "$LOG_LEVEL" == "ERROR" ]] && [[ "$level" != "ERROR" ]]; then return; fi
    if [[ "$LOG_LEVEL" == "WARN" ]] && [[ "$level" == "INFO" || "$level" == "DEBUG" ]]; then return; fi
    
    echo -e "${color}[$level]${COLOR_RESET} $msg" >&2
}

log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log "DEBUG" "$COLOR_BLUE" "$@"; }
log_info()  { log "INFO"  "$COLOR_BLUE" "$@"; }
log_warn()  { log "WARN"  "$COLOR_YELLOW" "$@"; }
log_error() { log "ERROR" "$COLOR_RED" "$@"; }
log_success() { log "SUCCESS" "$COLOR_GREEN" "$@"; }

# ============================================================================
# ERROR TRAPPING
# ============================================================================

error_handler() {
    local line_no=$1
    local exit_code=$2
    log_error "Script shit the bed at line $line_no. Exit code: $exit_code"
    exit "$exit_code"
}

trap 'error_handler $LINENO $?' ERR

cleanup() {
    # Kill the sudo keepalive if it's running
    if [[ -n "${KEEPALIVE_PID:-}" ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
    fi
    log_info "Log file saved at: $LOG_FILE"
}

trap cleanup EXIT

# ============================================================================
# CHECKS & PRE-FLIGHT
# ============================================================================

check_full_disk_access() {
    log_info "Checking for Full Disk Access (FDA)..."
    # Try to list a protected directory. 
    if ! ls "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1; then
        log_warn "****************************************************************"
        log_warn "HEY ROY, LISTEN UP:"
        log_warn "This terminal does NOT have Full Disk Access."
        log_warn "Commands like 'systemsetup' or remote management WILL fail silently or prompt."
        log_warn "Go to System Settings > Privacy & Security > Full Disk Access > Add Terminal/iTerm."
        log_warn "I'm continuing, but don't bitch when power settings fail."
        log_warn "****************************************************************"
        sleep 3
    else
        log_success "Full Disk Access detected. Good job."
    fi
}

validate_system() {
    log_info "Validating system..."
    
    if [[ $EUID -eq 0 ]]; then
        log_error "Don't run this as root, you moron. I'll ask for sudo when I need it."
        exit 1
    fi
    
    local free_space
    free_space=$(df -g / | awk 'NR==2 {print $4}')
    if [[ $free_space -lt 50 ]]; then
        log_warn "You only have ${free_space}GB free. Xcode usually takes 40GB to unzip. This might blow up."
    fi
    
    check_full_disk_access
}

setup_sudo_keepalive() {
    log_info "Refreshing sudo credentials..."
    sudo -v
    ( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
}

# ============================================================================
# TOOLING & BASICS
# ============================================================================

command_exists() { command -v "$1" >/dev/null 2>&1; }

brew_ensure() {
    local packages=("$@")
    for package in "${packages[@]}"; do
        if brew list --versions "$package" >/dev/null 2>&1; then
            log_debug "Already installed: $package"
        else
            log_info "Installing $package..."
            # Retry logic because brew creates network errors for sport
            local retries=3
            local count=0
            local success=0
            while [[ $count -lt $retries ]]; do
                if brew install "$package"; then
                    success=1
                    break
                fi
                ((count++))
                log_warn "Brew failed on $package. Retrying ($count/$retries)..."
                sleep 2
            done
            if [[ $success -eq 0 ]]; then
                log_error "Failed to install $package. Fix your internet."
                return 1
            fi
        fi
    done
}

brew_cask_ensure() {
    local packages=("$@")
    for package in "${packages[@]}"; do
        if brew list --cask --versions "$package" >/dev/null 2>&1; then
            log_debug "Already installed (cask): $package"
        else
            log_info "Installing cask: $package..."
            brew install --cask "$package" || log_warn "Cask $package failed. Maybe it's already there?"
        fi
    done
}

setup_homebrew() {
    if ! command_exists brew; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    log_info "Updating brew... this takes forever..."
    brew update || log_warn "Brew update failed, but I'm proceeding anyway."
}

install_core_tools() {
    log_info "Installing core toolset..."
    brew_ensure jq node xcodes bash autoconf coreutils fastlane htop maven nvm python tree aria2 sshpass rsync ktlint swiftlint "$JAVA_VERSION"
    brew_cask_ensure android-studio android-commandlinetools
}

setup_java() {
    log_info "Configuring Java ($JAVA_VERSION)..."
    # Brutal search for the home dir
    local j_home=""
    if [[ -d "/opt/homebrew/opt/${JAVA_VERSION}/libexec/openjdk.jdk/Contents/Home" ]]; then
        j_home="/opt/homebrew/opt/${JAVA_VERSION}/libexec/openjdk.jdk/Contents/Home"
    elif /usr/libexec/java_home -v "${JAVA_VERSION#*@}" >/dev/null 2>&1; then
        j_home="$(/usr/libexec/java_home -v "${JAVA_VERSION#*@}")"
    fi

    if [[ -z "$j_home" ]]; then
        log_warn "Could not locate JAVA_HOME for $JAVA_VERSION. You're on your own for that."
    else
        export JAVA_HOME="$j_home"
        export PATH="$JAVA_HOME/bin:$PATH"
        log_success "JAVA_HOME set to $JAVA_HOME"
    fi
}

setup_npm() {
    mkdir -p "$NPM_PREFIX"/{lib,node_modules,bin}
    npm config set prefix "$NPM_PREFIX"
    export PATH="$NPM_PREFIX/bin:$PATH"
}

setup_ruby() {
    log_info "Setting up Ruby environment..."
    local gem_bin
    gem_bin="$(ruby -rrubygems -e 'print Gem.user_dir')/bin"
    export PATH="$gem_bin:$PATH"
    
    if ! command_exists xcpretty; then
        gem install --user-install xcpretty --no-document || log_warn "Failed to install xcpretty via system ruby."
    fi
}

# ============================================================================
# HEAVY LIFTING (Android & Xcode)
# ============================================================================

setup_android_sdk() {
    [[ "$INSTALL_ANDROID" != "true" ]] && return 0
    log_info ">>> Setting up Android SDK (Sequential Task 1/2)..."
    
    sudo mkdir -p "$ANDROID_SDK_ROOT"
    sudo chown -R "$(whoami)":staff "$ANDROID_SDK_ROOT"
    sudo chmod -R 2775 "$ANDROID_SDK_ROOT"
    
    # Symlink for Android Studio default check
    mkdir -p "$HOME/Library/Android"
    ln -snf "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk"
    
    # Moving command line tools
    local brew_tools="$(brew --prefix)/share/android-commandlinetools"
    if [[ -d "$brew_tools" ]]; then
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        rsync -a "$brew_tools/" "$ANDROID_SDK_ROOT/cmdline-tools/latest/" --ignore-existing
    fi
    
    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
    
    log_info "Accepting licenses and installing platform-tools..."
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "emulator" >/dev/null 2>&1 || true
    
    log_success "Android SDK setup done."
}

setup_xcode() {
    [[ "$INSTALL_XCODE" != "true" ]] && return 0
    log_info ">>> Setting up Xcode (Sequential Task 2/2)..."
    
    # 1. Determine Version
    local install_ver=""
    if [[ "$TARGET_XCODE_VERSION" == "latest" ]]; then
        # Filter out betas because they are unstable trash
        install_ver=$(xcodes list | grep -v "Beta" | grep -v "RC" | grep -E '^[0-9]+\.[0-9]+' | sort -rV | head -n1 | awk '{print $1}')
        log_info "Auto-detected latest stable Xcode: $install_ver"
    else
        install_ver="$TARGET_XCODE_VERSION"
        log_info "Using specified Xcode version: $install_ver"
    fi

    # 2. Check if already installed
    if [[ -d "/Applications/Xcode-$install_ver.app" ]] || [[ -d "/Applications/Xcode.app" ]]; then
        # Weak check, but saves time. 
        if xcodes installed | grep -q "$install_ver"; then
             log_success "Xcode $install_ver is already installed. Skipping the 10GB download."
             return 0
        fi
    fi

    # 3. Install
    log_info "Downloading and installing Xcode $install_ver. This will take a while. Go get coffee."
    # Aria2 is faster but sometimes flakes. If it fails, we fall back? No, we die.
    if ! sudo xcodes install "$install_ver" --experimental-unxip; then
        log_error "xcodes install failed. Check if you're signed in (xcodes signin) or if Apple's servers are down."
        return 1
    fi

    # 4. Select and License
    local installed_path="/Applications/Xcode.app"
    # xcodes might name it differently, check generic location
    if [[ -d "/Applications/Xcode-${install_ver}.app" ]]; then
        installed_path="/Applications/Xcode-${install_ver}.app"
    fi

    log_info "Selecting Xcode at $installed_path..."
    sudo xcode-select -s "$installed_path/Contents/Developer"
    sudo xcodebuild -license accept >/dev/null 2>&1 || true
    sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
    
    log_success "Xcode setup done."
}

setup_appium() {
    [[ "$INSTALL_APPIUM" != "true" ]] && return 0
    log_info "Setting up Appium..."
    setup_npm
    
    npm install -g appium appium-doctor
    
    log_info "Installing Appium drivers..."
    appium driver list --installed | grep -q 'xcuitest' || appium driver install xcuitest
    appium driver list --installed | grep -q 'uiautomator2' || appium driver install uiautomator2
    
    brew_ensure ios-deploy
}

# ============================================================================
# SYSTEM CONFIG
# ============================================================================

configure_ssh() {
    [[ "$CONFIGURE_SSH" != "true" ]] && return 0
    log_info "Configuring SSH on port $SSH_PORT..."
    
    # Dirty sed hacks to change the port
    if ! sudo grep -qE "^Port ${SSH_PORT}" "$SSH_CONFIG"; then
        echo "Port ${SSH_PORT}" | sudo tee -a "$SSH_CONFIG"
    fi
    
    # Generate Key if missing
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "devbot@$(hostname)" -N ""
    fi
    
    # Try to enable SSH service. Needs FDA or it might fail silently.
    sudo systemsetup -setremotelogin on >/dev/null 2>&1 || log_warn "Failed to enable remote login via systemsetup. Check FDA."
}

configure_power_management() {
    [[ "$CONFIGURE_POWER" != "true" ]] && return 0
    log_info "Disabling sleep (Server Mode)..."
    
    # pmset usually works without FDA, systemsetup does not.
    sudo pmset -a sleep 0
    sudo pmset -a displaysleep 0
    sudo pmset -a disksleep 0
    sudo pmset -a powernap 0
    
    # Kill screensaver
    defaults -currentHost write com.apple.screensaver idleTime -int 0
}

configure_shell_environment() {
    local zshrc="$HOME/.zshrc"
    
    # Only append if not found
    if ! grep -q "ANDROID_SDK_ROOT" "$zshrc"; then
        log_info "Patching .zshrc..."
        cat <<EOF >> "$zshrc"

# --- Dev Setup Managed Block ---
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export JAVA_HOME="$JAVA_HOME"
export PATH="\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$JAVA_HOME/bin:$NPM_PREFIX/bin:\$PATH"
# --- End Block ---
EOF
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "Starting setup. Version: $SCRIPT_VERSION"
    
    validate_system
    setup_sudo_keepalive
    
    # 1. Base Tools
    setup_homebrew
    install_core_tools
    setup_java
    setup_ruby
    setup_npm
    
    # 2. Heavy Installers (SERIALIZED now, because parallel was a stupid idea)
    setup_android_sdk
    setup_xcode
    
    # 3. Layered Tools
    setup_appium
    
    # 4. System Config
    configure_ssh
    configure_power_management
    configure_shell_environment
    
    log_success "Setup finished. Please restart your shell."
    log_success "If something is broken, check $LOG_FILE before complaining."
}

main "$@"
