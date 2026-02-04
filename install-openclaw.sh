#!/usr/bin/env bash
# ============================================================================
# OpenClaw — One-Shot Hetzner VPS Installer
# ============================================================================
# Run this on a FRESH Ubuntu 24.04 Hetzner VPS as root:
#
#   curl -fsSL https://your-url/install.sh | bash
#   — or —
#   scp install-openclaw.sh root@YOUR_VPS_IP:~ && ssh root@YOUR_VPS_IP 'bash install-openclaw.sh'
#
# What it does:
#   1. Updates the system and installs dependencies
#   2. Installs Docker
#   3. Clones OpenClaw
#   4. Creates persistent directories
#   5. Generates secure tokens
#   6. Writes .env and docker-compose.yml
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
# Your phone number in international format — CHANGE THIS
YOUR_PHONE_NUMBER="${YOUR_PHONE_NUMBER:-+447700900000}"
# Primary model — change if you prefer a different Claude model
PRIMARY_MODEL="${PRIMARY_MODEL:-anthropic/claude-sonnet-4-5-20250929}"

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

if [ "$YOUR_PHONE_NUMBER" = "+447700900000" ]; then
    warn "You haven't set YOUR_PHONE_NUMBER. The default placeholder will be used."
    warn "You can fix this later in /root/.openclaw/openclaw.json"
    echo ""
    read -rp "Continue anyway? (y/N) " confirm
    [[ "$confirm" =~ ^[Yy] ]] || exit 0
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
step "Checking docker-compose.yml"
if [ -f "$OPENCLAW_DIR/docker-compose.yml" ]; then
    log "docker-compose.yml already exists — preserving existing configuration"

    # Check if browser variables are present
    if ! grep -q "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" "$OPENCLAW_DIR/docker-compose.yml"; then
        warn "Your docker-compose.yml doesn't have browser environment variables"
        warn "Add these lines to both services after the PATH line:"
        warn "  - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium"
        warn "  - PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium"
        warn "  - PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright"
        echo ""
        read -rp "Automatically add browser variables now? (y/N) " add_browser_vars
        if [[ "$add_browser_vars" =~ ^[Yy] ]]; then
            cp "$OPENCLAW_DIR/docker-compose.yml" "$OPENCLAW_DIR/docker-compose.yml.backup-$(date +%Y%m%d-%H%M%S)"
            sed -i '/PATH=.*\/sbin:\/bin/a\      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium\n      - PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium\n      - PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright' "$OPENCLAW_DIR/docker-compose.yml"
            log "Browser variables added to docker-compose.yml"
        else
            warn "Skipping browser variable addition — browser tool may not work"
        fi
    else
        log "Browser environment variables already present"
    fi
else
    log "Creating docker-compose.yml"
    cat > "$OPENCLAW_DIR/docker-compose.yml" <<'COMPOSE'
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE}
    build: .
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - NPM_CONFIG_PREFIX=/home/node/.npm-global
      - GOPATH=/home/node/go
      - PATH=/home/node/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/go/bin:/home/node/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
      - PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
      - PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright
    volumes:
      - openclaw_home:/home/node
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:18789"

  openclaw-cli:
    image: ${OPENCLAW_IMAGE}
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - NPM_CONFIG_PREFIX=/home/node/.npm-global
      - GOPATH=/home/node/go
      - PATH=/home/node/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/go/bin:/home/node/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
      - PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
      - PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright
    volumes:
      - openclaw_home:/home/node
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    profiles:
      - cli
    entrypoint: ["node", "dist/index.js"]

volumes:
  openclaw_home:
COMPOSE
    log "docker-compose.yml written"
fi

# --- Step 8: Write initial config ---
step "Checking openclaw.json"
if [ -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
    log "openclaw.json already exists — preserving existing configuration"
    warn "To reset config, manually delete $OPENCLAW_CONFIG/openclaw.json and re-run"
else
    log "Creating initial openclaw.json"
    cat > "$OPENCLAW_CONFIG/openclaw.json" <<EOF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "${PRIMARY_MODEL}"
      },
      "heartbeat": {
        "every": "${HEARTBEAT_INTERVAL}"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "allowFrom": ["${YOUR_PHONE_NUMBER}"],
      "groupPolicy": "disabled",
      "mediaMaxMb": 50,
      "debounceMs": 0
    }
  }
}
EOF
    chown 1000:1000 "$OPENCLAW_CONFIG/openclaw.json"
    log "openclaw.json written with allowlist for $YOUR_PHONE_NUMBER"
fi

# --- Step 9: Build stock image first, then extend with skill support ---
step "Building base OpenClaw image"
cd "$OPENCLAW_DIR"
docker build -t openclaw:base -f Dockerfile .
log "Base image built"

step "Creating extended Dockerfile with Homebrew, npm prefix, Go"
cat > "$OPENCLAW_DIR/Dockerfile.skills" <<'SKILLSDOCKERFILE'
FROM openclaw:base

USER root

# System deps for Homebrew, skill builds, and browser automation
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    build-essential procps curl file git ca-certificates \
    chromium chromium-driver \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
    libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
    libatspi2.0-0 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Go (pinned — some skills need 1.24+)
ARG GO_VERSION=1.24.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
       | tar -C /usr/local -xz \
    && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
    && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Fix npm global prefix for the node user
RUN mkdir -p /home/node/.npm-global \
    && chown -R 1000:1000 /home/node/.npm-global

# Write npmrc so the prefix is always picked up regardless of env vars
RUN echo "prefix=/home/node/.npm-global" > /home/node/.npmrc \
    && chown 1000:1000 /home/node/.npmrc

# Also fix /usr/local/lib/node_modules to be writable by node as fallback
RUN chown -R 1000:1000 /usr/local/lib/node_modules 2>/dev/null || true \
    && mkdir -p /usr/local/lib/node_modules \
    && chown -R 1000:1000 /usr/local/lib/node_modules

# Install Playwright for browser automation (as node user)
# System deps already installed above, so skip --with-deps
USER node
RUN npm install -g playwright@latest \
    && npx playwright install chromium
USER root

# Homebrew: create dir, install as node user
RUN mkdir -p /home/linuxbrew && chown -R 1000:1000 /home/linuxbrew

USER node
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Shims so skill installers always find brew/go even with sanitised PATH
USER root
RUN ln -sf /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew

# Create openclaw symlink for easy CLI access
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && chmod +x /usr/local/bin/openclaw

# Ensure node owns everything in its home
RUN chown -R 1000:1000 /home/node

USER node

ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV GOPATH=/home/node/go
ENV PATH="/home/node/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/go/bin:/home/node/go/bin:${PATH}"
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright
SKILLSDOCKERFILE

log "Dockerfile.skills created"

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
