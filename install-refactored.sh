#!/bin/bash
# macOS Setup Script: The "No More Clicking" Edition
# Version: 3.2.0-automated-hatred
# Author: Roy

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="${LOG_FILE:-/tmp/mac_setup_full.log}"

# Paths
readonly ANDROID_SDK_ROOT="/Users/Shared/dev/sdk"
readonly NPM_PREFIX="$HOME/.npm-global"
readonly NETWORK_BACKUP="$HOME/.network_restore_order"
readonly DOCK_BACKUP_DIR="$HOME"
readonly PROVISIONING_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

# Network Defaults (102 Env)
readonly NET_SUBNET="172.21.102"
readonly NET_ROUTER="172.21.102.254"
readonly NET_MASK="255.255.255.0"
readonly NET_DNS=("172.21.104.236" "172.22.80.12" "172.22.80.11")

# Toggles (Override with ENV vars)
export INSTALL_ANDROID="${INSTALL_ANDROID:-true}"
export INSTALL_XCODE="${INSTALL_XCODE:-true}"
export INSTALL_APPIUM="${INSTALL_APPIUM:-true}"
export CONFIGURE_SYSTEM="${CONFIGURE_SYSTEM:-true}"
export CONFIGURE_NETWORK_IP="${CONFIGURE_NETWORK_IP:-false}" # Set to true to force static IP setup
export OFFLINE_MODE="${OFFLINE_MODE:-false}"

# ============================================================================
# LOGGING
# ============================================================================

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
    local level=$1
    local color=$2
    shift 2
    local msg="$*"
    local ts="$(date '+%H:%M:%S')"
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
    echo -e "${color}[$level]${C_RESET} $msg" >&2
}

info()    { log "INFO"    "$C_BLUE"   "$@"; }
success() { log "OK"      "$C_GREEN"  "$@"; }
warn()    { log "WARN"    "$C_YELLOW" "$@"; }
error()   { log "ERROR"   "$C_RED"    "$@"; }
fatal()   { error "$@"; exit 1; }

# ============================================================================
# TRAPS & CLEANUP
# ============================================================================

cleanup() {
    local exit_code=$?
    
    # Kill Sudo Keepalive
    if [[ -n "${KEEPALIVE_PID:-}" ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
    fi

    if [[ $exit_code -ne 0 ]]; then
        error "Script failed. Check logs at $LOG_FILE"
    else
        success "Script finished. Verify networking and reboot."
    fi
}
trap cleanup EXIT

# ============================================================================
# SANITY CHECKS
# ============================================================================

check_environment() {
    info "Validating environment..."
    [[ $EUID -eq 0 ]] && fatal "Don't run as root."

    if ! ls "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1; then
        warn "MISSING FULL DISK ACCESS (FDA). System settings WILL FAIL."
        read -p "Press Enter to continue (risky) or Ctrl+C to abort..."
    fi

    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        warn "No internet. Switching to OFFLINE mode."
        export OFFLINE_MODE="true"
    fi
}

setup_sudo_keepalive() {
    sudo -v
    ( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
}

brew_ensure() {
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    if ! brew list --versions "$1" >/dev/null 2>&1; then
        info "Installing $1..."
        brew install "$1"
    fi
}

# ============================================================================
# SYSTEM CONFIGURATION
# ============================================================================

configure_ssh() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Configuring SSH on port 20022..."
    
    local p="20022"
    local services="/etc/services"
    local sshd="/etc/ssh/sshd_config"

    # Patch /etc/services
    if grep -qE '^ssh[[:space:]]+22/' "$services"; then
        sudo cp "$services" "$services.bak"
        sudo sed -i '' -E "s/^(ssh[[:space:]]+)22\//\1${p}\//" "$services"
        success "Patched /etc/services"
    fi

    # Patch sshd_config
    if ! sudo grep -qE "^[#]*[[:space:]]*Port[[:space:]]+${p}\b" "$sshd"; then
        echo "Port ${p}" | sudo tee -a "$sshd" >/dev/null
        success "Patched sshd_config"
    fi

    sudo systemsetup -setremotelogin on >/dev/null 2>&1 || warn "Failed to enable SSH (FDA?)"
    
    if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "dev@$(hostname)" -N ""
    fi
}

configure_keychain_security() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Unlocking keychain for codesigning tools..."

    # This prevents "Always Allow" popups. 
    # Requires the user password. If this is headless, you need to pipe it in or set ENV.
    
    # We assume the login keychain password is the same as sudo.
    # If not, this fails, and you deserve it.
    
    local kc_path="$HOME/Library/Keychains/login.keychain-db"
    
    # Grant access to codesign, productbuild, etc.
    # We use 'security set-key-partition-list'.
    # Warning: This asks for a password if not provided.
    
    echo "Need keychain password to authorize codesign tools:"
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(whoami)" "$kc_path" || \
        warn "Failed to set partition list. You will get popups."
        
    success "Keychain authorized for codesigning."
}

configure_power() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Configuring Power Management..."
    sudo pmset -a sleep 0 displaysleep 0 disksleep 0 powernap 0
    defaults -currentHost write com.apple.screensaver idleTime -int 0
    success "Power settings applied."
}

configure_dock() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Resetting Dock..."
    defaults write com.apple.dock persistent-apps -array
    defaults write com.apple.dock persistent-others -array
    defaults write com.apple.dock show-recents -bool false
    
    # Minimal Dock
    local apps=("/System/Applications/Utilities/Terminal.app" "/Applications/Safari.app")
    for app in "${apps[@]}"; do
        [[ -d "$app" ]] && defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    done
    
    killall Dock || true
}

configure_static_ip() {
    # Only run if explicitly asked, or if we are interactive and want to.
    [[ "$CONFIGURE_NETWORK_IP" != "true" ]] && return 0
    
    info "Configuring Static IP for 102 Environment..."
    
    local eth_service
    eth_service=$(networksetup -listallnetworkservices | grep -E "Ethernet|Thunderbolt|LAN" | head -n 1 | sed 's/^\*//')
    
    if [[ -z "$eth_service" ]]; then
        error "No Ethernet service found. Skipping static IP setup."
        return 0
    fi
    
    echo "Detected Service: $eth_service"
    echo "Subnet: $NET_SUBNET.X"
    
    # Interactive prompt for the octet
    read -p "Enter the last octet for this machine (e.g. 50): " octet
    
    if [[ ! "$octet" =~ ^[0-9]+$ ]]; then
        error "Invalid octet. Skipping."
        return
    fi
    
    local ip="${NET_SUBNET}.${octet}"
    info "Setting IP to $ip on $eth_service..."
    
    sudo networksetup -setmanual "$eth_service" "$ip" "$NET_MASK" "$NET_ROUTER"
    sudo networksetup -setdnsservers "$eth_service" "${NET_DNS[@]}"
    
    success "Network configured. You may lose connectivity if you are on the wrong VLAN."
}

configure_tmp_and_dns() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    sudo chmod -R 1777 /private/tmp /private/var/tmp || warn "Failed to chmod tmp"
    sudo dscacheutil -flushcache >/dev/null 2>&1 || true
    sudo killall -HUP mDNSResponder >/dev/null 2>&1 || true
}

configure_remote_management() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Enabling Remote Management (ARD)..."
    local kickstart="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
    [[ -x "$kickstart" ]] && sudo "$kickstart" -activate -configure -access -on -users admin -privs -all -restart -agent -menu
}

# ============================================================================
# INSTALLATION
# ============================================================================

install_core() {
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    info "Installing Core Tools..."
    
    if ! command -v brew >/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    local formulas=(node jq aria2 maven gradle tree htop carthage swiftlint ios-deploy sshpass)
    for f in "${formulas[@]}"; do brew_ensure "$f"; done

    brew_ensure openjdk@17
    sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
    
    git config --global credential.helper osxkeychain
}

setup_ruby() {
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    info "Setting up Ruby/xcpretty..."
    local gem_bin="$(ruby -rrubygems -e 'print Gem.user_dir')/bin"
    export PATH="$gem_bin:$PATH"
    if ! command -v xcpretty >/dev/null; then
        gem install --user-install xcpretty --no-document || warn "xcpretty failed"
    fi
}

install_provisioning_profiles() {
    [[ "$CONFIGURE_SYSTEM" != "true" ]] && return 0
    info "Scanning for Provisioning Profiles in ~/Downloads..."
    
    mkdir -p "$PROVISIONING_DIR"
    
    # If you put profiles in Downloads, we scavenge them.
    if ls "$HOME/Downloads/"*.mobileprovision >/dev/null 2>&1; then
        cp "$HOME/Downloads/"*.mobileprovision "$PROVISIONING_DIR/"
        success "Imported profiles from Downloads."
    else
        warn "No profiles found in Downloads. You'll need to drag them in manually."
    fi
}

install_android() {
    [[ "$INSTALL_ANDROID" != "true" ]] && return 0
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    info "Setting up Android SDK..."
    
    sudo mkdir -p "$ANDROID_SDK_ROOT"
    sudo chown -R "$(whoami):staff" "$ANDROID_SDK_ROOT"
    brew_ensure android-commandlinetools
    
    local brew_tools="$(brew --prefix)/share/android-commandlinetools"
    [[ -d "$brew_tools" ]] && {
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        rsync -a "$brew_tools/" "$ANDROID_SDK_ROOT/cmdline-tools/latest/" --ignore-existing
    }

    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
    sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "emulator" "platforms;android-34" "build-tools;34.0.0"
}

install_xcode() {
    [[ "$INSTALL_XCODE" != "true" ]] && return 0
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    info "Checking Xcode..."
    brew_ensure xcodes

    local ver=$(xcodes list | grep -vE 'Beta|RC' | sort -rV | head -n1 | awk '{print $1}')
    local app_path=""
    
    if [[ -d "/Applications/Xcode-$ver.app" ]]; then app_path="/Applications/Xcode-$ver.app"; fi
    
    if [[ -z "$app_path" ]]; then
        info "Installing Xcode $ver (Unxip)..."
        xcodes install "$ver" --experimental-unxip
        app_path="/Applications/Xcode-$ver.app"
    fi
    
    if [[ -d "$app_path" ]]; then
        sudo xcode-select -s "$app_path/Contents/Developer"
        sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
    fi
}

install_appium() {
    [[ "$INSTALL_APPIUM" != "true" ]] && return 0
    [[ "$OFFLINE_MODE" == "true" ]] && return 0
    info "Setting up Appium..."
    
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX"
    export PATH="$NPM_PREFIX/bin:$PATH"

    npm install -g appium appium-doctor
    appium driver install xcuitest 2>/dev/null || true
    appium driver install uiautomator2 2>/dev/null || true
}

configure_shell() {
    info "Patching .zshrc..."
    local zshrc="$HOME/.zshrc"
    touch "$zshrc"
    if ! grep -q "Roy-Script-Managed" "$zshrc"; then
        cat <<EOT >> "$zshrc"

# --- Roy-Script-Managed Config ---
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export PATH="\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
export PATH="$NPM_PREFIX/bin:\$PATH"
export PATH="\$(ruby -rrubygems -e 'print Gem.user_dir')/bin:\$PATH"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home"
# ---------------------------------
EOT
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    check_environment
    setup_sudo_keepalive
    
    # Configs
    configure_power
    configure_ssh
    configure_dock
    configure_keychain_security # Added this to kill the popups
    configure_static_ip         # Added this so you don't have to type IPs manually
    configure_tmp_and_dns
    configure_remote_management
    
    # Installs
    install_core
    setup_ruby
    install_provisioning_profiles # Attempts to import from Downloads
    install_android
    install_xcode
    install_appium
    
    configure_shell
    
    success "Done. Restart your terminal."
}

main "$@"
