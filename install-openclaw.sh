#!/usr/bin/env bash
# ============================================================================
# OpenClaw — One-Shot Hetzner VPS Installer
# ============================================================================
# First-time setup on a FRESH Ubuntu 24.04 Hetzner VPS as root:
#
#   git clone https://github.com/lylo/bunkbot.git /root/bunkbot
#   bash /root/bunkbot/install-openclaw.sh
#
# To update after making changes:
#
#   cd /root/bunkbot && git pull
#   bash /root/bunkbot/install-openclaw.sh
#
# What it does:
#   1. Updates the system and installs dependencies
#   2. Installs Docker
#   3. Clones OpenClaw (the software) to /root/openclaw
#   4. Creates persistent directories
#   5. Generates secure tokens
#   6. Copies .env, docker-compose.yml, Dockerfile.skills, openclaw.json
#   7. Builds the Docker image
#   8. Starts the gateway
#
# After it finishes, you run the onboarding wizard interactively to:
#   - Add your Anthropic API key
#   - Pair WhatsApp (scan QR code)
#   - Choose skills
# ============================================================================

set -euo pipefail

# --- Configuration (edit these before running if you want) ---
OPENCLAW_BRANCH="main"
OPENCLAW_DIR="/root/openclaw"
OPENCLAW_CONFIG="/root/.openclaw"
OPENCLAW_PORT="18789"
HEARTBEAT_INTERVAL="30m"
# Read model from existing config if available
if [ -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
    PRIMARY_MODEL="${PRIMARY_MODEL:-$(jq -r '.agents.defaults.model.primary // empty' "$OPENCLAW_CONFIG/openclaw.json" 2>/dev/null)}"
fi
PRIMARY_MODEL="${PRIMARY_MODEL:-anthropic/claude-haiku-4-5}"
# Directory where this script (and its companion files) lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# --- Preflight checks ---
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root."
    exit 1
fi

if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu/Debian. Other distros may need adjustments."
fi

if [ -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
    log "Existing openclaw.json found — channel config will be preserved"
fi

# --- Step 1: System update ---
step "Updating system packages"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq git curl ca-certificates jq
log "System updated"

# --- Step 2: Install Docker ---
step "Installing Docker"
if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    log "Docker installed: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    err "Docker Compose not found. Please install Docker Compose v2."
    exit 1
fi
log "Docker Compose: $(docker compose version --short)"

# --- Step 3: Clone OpenClaw ---
step "Cloning OpenClaw"
if [ -d "$OPENCLAW_DIR" ]; then
    warn "Directory $OPENCLAW_DIR already exists. Pulling latest..."
    cd "$OPENCLAW_DIR"
    git pull --ff-only || warn "Git pull failed — using existing checkout"
else
    git clone --branch "$OPENCLAW_BRANCH" https://github.com/openclaw/openclaw.git "$OPENCLAW_DIR"
    cd "$OPENCLAW_DIR"
fi
log "OpenClaw cloned to $OPENCLAW_DIR"

# --- Step 4: Persistent directories ---
step "Creating persistent directories"
mkdir -p "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG/workspace"
chown -R 1000:1000 "$OPENCLAW_CONFIG"
log "Config dir: $OPENCLAW_CONFIG"
log "Workspace:  $OPENCLAW_CONFIG/workspace"

# --- Step 5: Generate secrets ---
step "Generating secrets"
GATEWAY_TOKEN=$(openssl rand -hex 32)
KEYRING_PASSWORD=$(openssl rand -hex 32)
log "Gateway token generated (saved to .env)"

# --- Step 6: Write .env ---
step "Checking .env"
if [ -f "$OPENCLAW_DIR/.env" ]; then
    log ".env already exists — preserving existing secrets"
    warn "To regenerate secrets, manually delete $OPENCLAW_DIR/.env and re-run"
else
    log "Creating .env"
    cat > "$OPENCLAW_DIR/.env" <<EOF
OPENCLAW_IMAGE=openclaw:latest
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=${OPENCLAW_PORT}
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_CONFIG}/workspace
GOG_KEYRING_PASSWORD=${KEYRING_PASSWORD}
XDG_CONFIG_HOME=/home/node/.openclaw
EOF
    log ".env written with new secrets"
fi

# --- Step 7: Write docker-compose.yml ---
step "Copying docker-compose.yml"
if [ -f "$OPENCLAW_DIR/docker-compose.yml" ]; then
    log "docker-compose.yml already exists — overwriting with latest template"
fi
cp "$SCRIPT_DIR/docker-compose.yml" "$OPENCLAW_DIR/docker-compose.yml"
log "docker-compose.yml copied from $SCRIPT_DIR"

# --- Step 8: Write initial config ---
step "Checking openclaw.json"
if [ -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
    log "openclaw.json already exists — preserving existing configuration"
    warn "To reset config, manually delete $OPENCLAW_CONFIG/openclaw.json and re-run"
else
    log "Creating initial openclaw.json from template"
    cp "$SCRIPT_DIR/openclaw.json.template" "$OPENCLAW_CONFIG/openclaw.json"

    # --- Channel setup ---
    echo ""
    echo -e "${CYAN}Which messaging channel(s) do you want to enable?${NC}"
    echo "  1) Telegram"
    echo "  2) WhatsApp"
    echo "  3) Both"
    echo ""
    read -rp "Choose [1/2/3]: " channel_choice

    ENABLE_TELEGRAM=false
    ENABLE_WHATSAPP=false
    case "$channel_choice" in
        1) ENABLE_TELEGRAM=true ;;
        2) ENABLE_WHATSAPP=true ;;
        3) ENABLE_TELEGRAM=true; ENABLE_WHATSAPP=true ;;
        *) warn "Invalid choice — defaulting to Telegram"; ENABLE_TELEGRAM=true ;;
    esac

    JQ_FILTER=".agents.defaults.model.primary = \$model | .agents.defaults.heartbeat.every = \$heartbeat"
    JQ_ARGS=(--arg model "$PRIMARY_MODEL" --arg heartbeat "$HEARTBEAT_INTERVAL")

    if [ "$ENABLE_TELEGRAM" = true ]; then
        echo ""
        read -rp "Telegram bot token (from @BotFather): " tg_token
        read -rp "Your Telegram user ID: " tg_user_id
        JQ_FILTER="$JQ_FILTER | .channels.telegram.botToken = \$tg_token | .channels.telegram.allowFrom = [\$tg_user_id] | .plugins.entries.telegram.enabled = true"
        JQ_ARGS+=(--arg tg_token "$tg_token" --arg tg_user_id "$tg_user_id")
    else
        JQ_FILTER="$JQ_FILTER | .plugins.entries.telegram.enabled = false | del(.channels.telegram)"
    fi

    if [ "$ENABLE_WHATSAPP" = true ]; then
        echo ""
        read -rp "Your phone number (international format, e.g. +44...): " phone_number
        JQ_FILTER="$JQ_FILTER | .channels.whatsapp.allowFrom = [\$phone] | .plugins.entries.whatsapp.enabled = true"
        JQ_ARGS+=(--arg phone "$phone_number")
    else
        JQ_FILTER="$JQ_FILTER | .plugins.entries.whatsapp.enabled = false | del(.channels.whatsapp)"
    fi

    jq "${JQ_ARGS[@]}" "$JQ_FILTER" \
       "$OPENCLAW_CONFIG/openclaw.json" > "$OPENCLAW_CONFIG/openclaw.json.tmp" \
    && mv "$OPENCLAW_CONFIG/openclaw.json.tmp" "$OPENCLAW_CONFIG/openclaw.json"
    chown 1000:1000 "$OPENCLAW_CONFIG/openclaw.json"
    log "openclaw.json written"
fi

# --- Step 9: Build stock image first, then extend with skill support ---
step "Building base OpenClaw image"
cd "$OPENCLAW_DIR"
docker build -t openclaw:base -f Dockerfile .
log "Base image built"

step "Copying Dockerfile.skills"
if [ -f "$SCRIPT_DIR/Dockerfile.skills" ]; then
    cp "$SCRIPT_DIR/Dockerfile.skills" "$OPENCLAW_DIR/Dockerfile.skills"
    log "Dockerfile.skills copied from $SCRIPT_DIR"
elif [ -f "$OPENCLAW_DIR/Dockerfile.skills" ]; then
    warn "Dockerfile.skills not found alongside install script — using existing copy in $OPENCLAW_DIR"
else
    err "Dockerfile.skills not found. Place it next to install-openclaw.sh and re-run."
    exit 1
fi

step "Building extended image (this installs Homebrew — takes a few minutes)"
docker build -t openclaw:latest -f "$OPENCLAW_DIR/Dockerfile.skills" .
log "Extended image built"

# --- Step 10: Start gateway ---
step "Starting OpenClaw gateway"
docker compose up -d openclaw-gateway
log "Gateway started"

# --- Wait for health ---
echo -n "Waiting for gateway to become healthy "
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:${OPENCLAW_PORT}/health &>/dev/null; then
        echo ""
        log "Gateway is healthy!"
        break
    fi
    echo -n "."
    sleep 2
done

if ! curl -sf http://127.0.0.1:${OPENCLAW_PORT}/health &>/dev/null; then
    echo ""
    warn "Gateway hasn't responded yet. Check logs: docker compose logs -f openclaw-gateway"
fi

# --- Done ---
step "INSTALLATION COMPLETE"
echo ""
echo -e "  ${GREEN}Gateway token:${NC}  ${GATEWAY_TOKEN}"
echo -e "  ${GREEN}Config dir:${NC}     ${OPENCLAW_CONFIG}"
echo -e "  ${GREEN}Logs:${NC}           cd $OPENCLAW_DIR && docker compose logs -f"
echo -e "  ${GREEN}Dashboard:${NC}      ssh -L 18789:127.0.0.1:18789 root@THIS_VPS_IP"
echo -e "                  then open http://localhost:18789"
echo ""
echo -e "${CYAN}━━━ NEXT STEPS (interactive — must be done manually) ━━━${NC}"
echo ""
echo "  1. Run the onboarding wizard to pair WhatsApp:"
echo ""
echo -e "     ${YELLOW}cd $OPENCLAW_DIR && docker compose run --rm openclaw-cli onboard${NC}"
echo ""
echo "     → Select 'Anthropic API Key' and paste your key"
echo "     → Select 'WhatsApp' as the channel"
echo "     → Scan the QR code with your phone"
echo "     → Accept default skills"
echo ""
echo "  2. Once paired, send a WhatsApp message to yourself to test."
echo ""
echo "  3. (Optional) Seed it with self-learning:"
echo "     Send: 'Please create a skill that summarises any URL I share with you'"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${RED}IMPORTANT: Save your gateway token somewhere safe.${NC}"
echo -e "  ${RED}           Change YOUR_PHONE_NUMBER in openclaw.json if you used the default.${NC}"
echo ""
