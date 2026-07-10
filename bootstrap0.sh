#!/usr/bin/env bash
#
# bootstrap0.sh - Stage 0 bootstrap for fresh Mac
#
# Breaks the SSH/1Password/dotfiles dependency cycle by front-loading
# 1Password installation before any private git clones. This script is
# public-safe — it contains only an opaque UUID-based 1Password reference,
# no git server addresses or paths.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<you>/bootstrap/main/bootstrap0.sh | bash
#   OR
#   bash bootstrap0.sh
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# This is a UUID-based op:// reference to a 1Password secure note.
# It's opaque and useless without being signed into the account.
# To set it up:
#   1. Create a secure note in 1Password with the body:
#      DOTFILES_REPO="git@<host>:/<path>/dotfiles.git"
#   2. Get its UUID reference and paste it here:
#      op item get "dotfiles-bootstrap" --format json | jq -r '"\(.vault.id)/\(.id)"'
#   3. The format is: op://<vault-uuid>/<item-uuid>/notesPlain
CONFIG_REF="op://kvj3nhzsnosk57qofp4u45rbsy/4zqr26nxshpln3lpydl5xu3ebi/notesPlain"

DOTFILES_DIR="$HOME/src/dotfiles"
CONFIG_FILE="${BOOTSTRAP0_CONFIG:-$HOME/.config/bootstrap0.conf}"

log_info() {
    echo -e "${BLUE}==>${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Step 1: Install Homebrew if absent
install_homebrew() {
    log_info "Checking for Homebrew..."

    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew already installed: $(brew --version | head -n1)"
        return 0
    fi

    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for current shell
    if [[ $(uname -m) == "arm64" ]]; then
        BREW_PREFIX="/opt/homebrew"
    else
        BREW_PREFIX="/usr/local"
    fi

    if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
        eval "$($BREW_PREFIX/bin/brew shellenv)"
        log_success "Homebrew installed and added to PATH"
    else
        log_error "Homebrew installation failed"
        exit 1
    fi
}

# Step 2: Install 1Password + CLI
install_1password() {
    log_info "Checking for 1Password..."

    local needs_install=false

    if [[ ! -d "/Applications/1Password.app" ]]; then
        log_info "1Password app not found, will install"
        needs_install=true
    else
        log_success "1Password app already installed"
    fi

    if ! command -v op >/dev/null 2>&1; then
        log_info "1Password CLI not found, will install"
        needs_install=true
    else
        log_success "1Password CLI already installed: $(op --version)"
    fi

    if [[ "$needs_install" == "true" ]]; then
        log_info "Installing 1Password and 1Password CLI via Homebrew..."
        brew install --cask 1password 1password-cli
        log_success "1Password installation complete"
    fi
}

# Step 3: Pause for manual 1Password setup
wait_for_1password_setup() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn "MANUAL STEP REQUIRED: Set up 1Password SSH Agent & CLI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Please complete the following steps:"
    echo ""
    echo "  1. Open 1Password app"
    echo "  2. Sign in to your account"
    echo "  3. Go to: Settings → Developer"
    echo "  4. Enable: ${BLUE}Use the SSH agent${NC}"
    echo "     (This will offer to add an IdentityAgent line to ~/.ssh/config)"
    echo "  5. Enable: ${BLUE}Integrate with 1Password CLI${NC}"
    echo "     (This allows 'op' to authenticate via the desktop app)"
    echo "  6. Ensure your SSH key is unlocked/authorized in 1Password"
    echo ""
    echo "Once complete, press ENTER to continue..."
    # Read from /dev/tty so this works when script is piped via curl | bash
    read -r < /dev/tty
}

# Step 4: Load config from 1Password and write to local file
load_config() {
    log_info "Loading configuration..."

    # Check if config already exists (re-run case)
    if [[ -f "$CONFIG_FILE" ]]; then
        log_success "Config file already exists: $CONFIG_FILE"
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"

        if [[ -z "${DOTFILES_REPO:-}" ]]; then
            log_error "Config file exists but DOTFILES_REPO is not set"
            exit 1
        fi

        log_success "Loaded DOTFILES_REPO from existing config"
        return 0
    fi

    # Fetch config from 1Password
    log_info "Fetching config from 1Password..."

    if [[ "$CONFIG_REF" == *"REPLACE_WITH"* ]]; then
        log_error "CONFIG_REF has not been configured"
        log_error "Please edit this script and replace the CONFIG_REF placeholder with your actual 1Password secret reference"
        log_error "See the comments at the top of the script for instructions"
        exit 1
    fi

    local config_content
    if ! config_content=$(op read "$CONFIG_REF" 2>&1); then
        log_error "Failed to fetch config from 1Password"
        log_error "Error: $config_content"
        log_error ""
        log_error "Please verify:"
        log_error "  - 1Password CLI integration is enabled (Settings → Developer)"
        log_error "  - The secure note exists and CONFIG_REF is correct"
        log_error "  - You are signed into 1Password"
        exit 1
    fi

    # Write config to file
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$config_content" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log_success "Config written to $CONFIG_FILE (mode 600)"

    # Source it
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    if [[ -z "${DOTFILES_REPO:-}" ]]; then
        log_error "Config fetched but DOTFILES_REPO is not set"
        log_error "Check the content of your 1Password secure note"
        exit 1
    fi

    log_success "Loaded DOTFILES_REPO from 1Password"
}

# Step 5: Verify SSH auth works
verify_ssh_auth() {
    # Derive SSH host from the repo URL
    local ssh_host="${DOTFILES_REPO%%:*}"

    log_info "Verifying SSH authentication to $ssh_host..."

    # Check if ssh-add can list keys from the 1Password agent
    if ssh-add -l >/dev/null 2>&1; then
        log_success "SSH agent is running with keys loaded"
    else
        log_warn "No SSH keys found via ssh-add -l, but will try $ssh_host anyway"
    fi

    # Try to connect to the git server (git servers typically reject shell sessions)
    # We expect either a success or a "shell access denied" message, but not "permission denied"
    if ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$ssh_host" 2>&1 | grep -qE "denied \(publickey|permission denied"; then
        log_error "SSH authentication to $ssh_host failed"
        log_error "Please verify:"
        log_error "  - 1Password SSH agent is enabled"
        log_error "  - The correct SSH key is unlocked in 1Password"
        log_error "  - The key is authorized for $ssh_host"
        exit 1
    fi

    log_success "SSH authentication verified"
}

# Step 6: Clone dotfiles over SSH
clone_dotfiles() {
    log_info "Checking for dotfiles at $DOTFILES_DIR..."

    if [[ -d "$DOTFILES_DIR" ]]; then
        if [[ -d "$DOTFILES_DIR/.git" ]]; then
            log_success "Dotfiles already cloned at $DOTFILES_DIR"

            # Verify it's the right remote
            pushd "$DOTFILES_DIR" >/dev/null
            local current_remote
            current_remote=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$current_remote" == "$DOTFILES_REPO" ]]; then
                log_success "Remote is correct: $current_remote"
            else
                log_warn "Remote mismatch. Expected: $DOTFILES_REPO"
                log_warn "                    Got: $current_remote"
                log_warn "Run 'git remote set-url origin $DOTFILES_REPO' if needed"
            fi
            popd >/dev/null
            return 0
        else
            log_error "$DOTFILES_DIR exists but is not a git repository"
            log_error "Please remove or rename it, then re-run this script"
            exit 1
        fi
    fi

    log_info "Cloning dotfiles from $DOTFILES_REPO..."
    mkdir -p "$(dirname "$DOTFILES_DIR")"

    if git clone "$DOTFILES_REPO" "$DOTFILES_DIR"; then
        log_success "Dotfiles cloned successfully"
    else
        log_error "Failed to clone dotfiles"
        exit 1
    fi
}

# Step 7: Print handoff instructions
print_handoff() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Stage 0 bootstrap complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. cd $DOTFILES_DIR"
    echo "  2. Run ONE of:"
    echo ""
    echo "     ${GREEN}make personal-install${NC}   # For personal/home use"
    echo "     ${GREEN}make work-install${NC}       # For work machines"
    echo ""
    echo "After 'make install', your shell configs will be active."
    echo "You can then clone other private repos using the 1Password SSH agent."
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "Starting stage-0 bootstrap for fresh Mac"
    echo ""

    install_homebrew
    install_1password
    wait_for_1password_setup
    load_config
    verify_ssh_auth
    clone_dotfiles
    print_handoff
}

main "$@"
