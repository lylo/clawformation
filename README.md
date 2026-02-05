# OpenClaw Deployment Configuration

Production-ready deployment system for running [OpenClaw](https://github.com/openclaw/openclaw) on a Hetzner VPS.

## What This Is

This repository contains deployment automation and configuration for OpenClaw - **not the OpenClaw source code itself**. It provides:

- ✅ One-script installation for fresh Ubuntu 24.04 VPS
- ✅ Automated Docker setup with browser automation (Chromium + Playwright)
- ✅ Configuration templates
- ✅ Safe re-run capability (preserves existing configs)
- ✅ WhatsApp integration setup

**OpenClaw** is an autonomous AI agent platform that runs 24/7, with multi-channel support (WhatsApp, Discord, CLI), skill-based extensibility, and persistent memory.

## Quick Start

### Fresh VPS Installation

1. **Spin up a Hetzner Ubuntu 24.04 VPS**

2. **Clone this repo and run the installer:**

```bash
git clone <YOUR_REPO_URL> /root/bunkbot
cd /root/bunkbot
bash install-openclaw.sh
```

3. **The script will:**
   - Install Docker
   - Clone OpenClaw source from GitHub
   - Install browser automation (Chromium + Playwright)
   - Generate secure tokens
   - Build Docker images
   - Start the gateway

4. **Run onboarding to pair WhatsApp:**

```bash
cd /root/openclaw
docker compose run --rm openclaw-cli onboard
```

   - Add your Anthropic API key
   - Scan QR code to pair WhatsApp
   - Accept default skills

5. **Test it:**

Send a WhatsApp message to yourself!

## Configuration

### Before First Install

Edit these variables at the top of `install-openclaw.sh`:

```bash
YOUR_PHONE_NUMBER="+447700900000"  # Change to your number
PRIMARY_MODEL="anthropic/claude-sonnet-4-5-20250929"
HEARTBEAT_INTERVAL="30m"
```

### After Installation

Config files are created at `/root/.openclaw/`:

- **`openclaw.json`** - Main configuration (model, channels, heartbeat)
- **`workspace/`** - Agent personality, memory, and state
  - `SOUL.md` - Core agent identity
  - `IDENTITY.md` - Agent name and personality
  - `USER.md` - Your profile
  - `memory/` - Daily logs

The install script **preserves existing configs** - safe to re-run for updates.

## What Gets Installed

### On the VPS

```
/root/openclaw/              # OpenClaw source (cloned from GitHub)
├── Dockerfile               # Base image
├── Dockerfile.skills        # Extended image (Go, Homebrew, browser)
├── docker-compose.yml       # Services
└── .env                     # Secrets

/root/.openclaw/             # Configuration (persistent)
├── openclaw.json            # Main config
└── workspace/               # Agent state & memory
```

### Docker Services

- **openclaw-gateway** - REST API on port 18789 (localhost only)
- **openclaw-cli** - Command-line interface (on-demand)

### Installed in Container

- Node.js (base runtime)
- Go 1.24.0 (for Go-based skills)
- Homebrew (for package management)
- Chromium + Playwright (browser automation)
- npm + global packages

## Features

### Browser Automation

Full web automation via the `browser` tool:
- Headless Chromium
- Playwright for advanced automation
- Screenshot capture
- Form filling, scraping, navigation
- JavaScript execution

Test it:
```
"Take a screenshot of https://example.com"
```

### Heartbeat System

Agent checks in every 30 minutes (configurable) and can:
- Check email
- Monitor calendar
- Proactive reminders
- Background maintenance

Edit `workspace/HEARTBEAT.md` to customize checks.

### Skills

Dynamically installable capabilities. Bundled skills:
- `healthcheck` - Security auditing
- `skill-creator` - Create new skills on the fly
- `weather` - Current weather and forecasts

Agent can learn new skills when you ask!

## Accessing Your Agent

### WhatsApp
Just message yourself after pairing.

### SSH Tunnel (for Dashboard)
```bash
ssh -L 18789:127.0.0.1:18789 root@YOUR_VPS_IP
```
Then open http://localhost:18789

### CLI
```bash
ssh root@YOUR_VPS_IP
cd /root/openclaw
docker compose run --rm openclaw-cli
```

## Maintenance

### View Logs

**Docker container logs:**
```bash
cd /root/openclaw

# Follow logs in real-time (Ctrl+C to exit)
docker compose logs -f openclaw-gateway

# View all logs
docker compose logs openclaw-gateway

# Last 50 lines
docker compose logs --tail=50 openclaw-gateway

# Last 100 lines and follow
docker compose logs --tail=100 -f openclaw-gateway

# All services
docker compose logs -f
```

**OpenClaw internal logs:**
```bash
# Agent's daily memory logs
cat /root/.openclaw/workspace/memory/$(date +%Y-%m-%d).md

# Session history
cat /root/.openclaw/agents/main/sessions/sessions.json

# List all memory logs
ls -lh /root/.openclaw/workspace/memory/
```

### Restart Services
```bash
docker compose restart openclaw-gateway
```

### Update OpenClaw
```bash
cd /root/openclaw
docker compose down
git pull
docker compose build
docker compose up -d
```

### Rebuild with Changes
If you update `install-openclaw.sh` and want to apply changes:
```bash
cd /root/openclaw
bash /root/bunkbot/install-openclaw.sh
```

Config in `/root/.openclaw/` is preserved.

## Files in This Repo

```
bunkbot/
├── README.md                      # This file
├── AGENTS.md                      # Project context for AI agents
├── install-openclaw.sh            # Main installer
├── openclaw.json.template         # Config template (example)
├── openclaw-hetzner-guide.md      # Detailed setup guide
└── .gitignore                     # Excludes secrets and runtime data
```

**Not committed:**
- `openclaw.json` (contains phone numbers)
- `credentials/` (WhatsApp session keys)
- `agents/*/agent/` (API keys)
- `workspace/` (agent memory and state)

## Troubleshooting

### Gateway won't start
```bash
docker compose logs openclaw-gateway
```

Check for config errors in `/root/.openclaw/openclaw.json`.

### Browser tool not working

**Check Chromium is installed:**
```bash
docker compose exec openclaw-gateway which chromium
docker compose exec openclaw-gateway npx playwright --version
```
Should show `/usr/bin/chromium` and Playwright version.

**"Can't reach the OpenClaw browser control service" / timeout:**

This usually means Chromium is crashing on launch due to stale lock files from a previous unclean shutdown. Remove them:
```bash
docker compose exec openclaw-gateway rm -f \
  /home/node/.openclaw/browser/openclaw/user-data/SingletonLock \
  /home/node/.openclaw/browser/openclaw/user-data/SingletonSocket \
  /home/node/.openclaw/browser/openclaw/user-data/SingletonCookie \
  /home/node/.openclaw/browser/chrome/user-data/SingletonLock \
  /home/node/.openclaw/browser/chrome/user-data/SingletonSocket \
  /home/node/.openclaw/browser/chrome/user-data/SingletonCookie
docker compose restart openclaw-gateway
```

To prevent this permanently, ensure your `docker-compose.yml` has `init: true` and `shm_size: '1gb'` on the gateway service. The `init` flag adds a proper init process (tini) that reaps zombie Chromium processes, and `shm_size` gives Chromium enough shared memory.

### WhatsApp disconnected
Re-run onboarding:
```bash
docker compose run --rm openclaw-cli onboard
```

### Config schema error
OpenClaw 2026.2.3+ requires `heartbeat` under `agents.defaults`, not at root:

```json
{
  "agents": {
    "defaults": {
      "heartbeat": { "every": "30m" }  // ← Correct location
    }
  }
}
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  VPS (Hetzner Ubuntu 24.04)                 │
│                                              │
│  ┌────────────────────────────────────┐     │
│  │  Docker Container                  │     │
│  │                                    │     │
│  │  OpenClaw Gateway :18789           │     │
│  │  ├─ Claude Sonnet 4.5              │     │
│  │  ├─ Browser Tool (Chromium)        │     │
│  │  ├─ WhatsApp Plugin                │     │
│  │  └─ Skills                         │     │
│  │                                    │     │
│  │  Volume: /root/.openclaw           │     │
│  │  ├─ openclaw.json                  │     │
│  │  └─ workspace/                     │     │
│  └────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
           ↓                    ↓
    WhatsApp Messages      REST API
```

## Security Notes

- Gateway only binds to `127.0.0.1` (use SSH tunnel for remote access)
- Secrets generated with `openssl rand -hex 32`
- WhatsApp allowlist prevents unauthorized access
- All agent runtime as non-root user (node:1000)
- Credentials stored encrypted in Docker volumes

## Support

- **OpenClaw Docs**: https://github.com/openclaw/openclaw
- **Issues**: Check install logs and `docker compose logs`
- **Config Reference**: See `openclaw.json.template` and `AGENTS.md`

## License

This deployment configuration is provided as-is. OpenClaw itself is licensed separately.

---

**Last Updated**: 2026-02-04
**OpenClaw Version**: 2026.2.3
**Tested On**: Hetzner Ubuntu 24.04 VPS
