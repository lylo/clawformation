# OpenClaw Project Guide

This file serves as context for AI agents working on the OpenClaw project. Read this when starting any session.

## Project Overview

**OpenClaw** is a self-hosted, autonomous AI agent platform that runs 24/7 on a VPS. It's designed to be:
- **Always-on**: Runs continuously with periodic heartbeats
- **Multi-channel**: WhatsApp, Discord, CLI, REST API
- **Skill-based**: Extensible through dynamically installable skills
- **Privacy-focused**: Self-hosted, encrypted, no cloud dependencies (beyond Claude API)
- **Docker-based**: Portable, isolated environment

**Current deployment:**
- VPS: Hetzner Ubuntu 24.04
- Gateway: `localhost:18789`
- Primary model: `claude-sonnet-4-5-20250929`
- Agent name: "Bunk"
- User: Olly (Edinburgh, UK, GMT timezone)

## Repository Structure

```
bunkbot/
├── install-openclaw.sh          # VPS installation script (THE KEY FILE)
├── openclaw.json                # Main configuration
├── AGENTS.md                    # This file - project context
├── BROWSER_SETUP.md             # Browser automation documentation
├── openclaw-hetzner-guide.md    # Deployment guide
│
├── workspace/                    # Agent workspace (persistent)
│   ├── SOUL.md                  # Agent core identity
│   ├── IDENTITY.md              # Agent personality (Bunk)
│   ├── USER.md                  # User profile (Olly)
│   ├── AGENTS.md                # Workspace guidelines
│   ├── TOOLS.md                 # Environment-specific tool docs
│   ├── HEARTBEAT.md             # Periodic check config
│   └── memory/                  # Daily memory logs
│
├── agents/main/                 # Agent runtime data
│   ├── agent/auth-profiles.json # API keys
│   └── sessions/sessions.json   # Session history
│
├── canvas/                      # Mobile app integration UI
├── credentials/                 # WhatsApp & auth storage
├── identity/                    # Device keypairs
├── devices/                     # Device pairing
└── cron/                        # Background jobs
```

## Key Files

### `install-openclaw.sh` (335 lines)
**THE MOST IMPORTANT FILE.** This is the single-script installer that:
1. Updates Ubuntu and installs Docker
2. Clones OpenClaw repo
3. Generates secure tokens
4. Writes `.env` and `docker-compose.yml`
5. Builds base image, then extended image with:
   - Go 1.24.0
   - Homebrew (for skill dependencies)
   - npm global prefix config
   - **Browser automation** (Chromium + Playwright) ← recent addition
6. Starts gateway service

**When modifying deployment:** Edit this file, then rebuild the Docker image.

### `openclaw.json`
Runtime configuration. Key sections:
- `agents.defaults` - Model, heartbeat interval, concurrency
- `gateway` - Port, auth token, bind address
- `channels.whatsapp` - DM/group policies, allowlist
- `plugins` - Enabled features (WhatsApp, etc.)
- `skills.install` - Package manager preference (npm)

## Development Preferences

### Code Style
- **Bash scripts**: Use `set -euo pipefail`, colored output, clear step logging
- **Docker**: Multi-stage builds, non-root user (node:1000), minimal layers
- **Config**: JSON with comments explaining each section
- **Documentation**: Markdown, clear structure, code examples

### Conventions
- **Secrets**: Generate with `openssl rand -hex 32`, never hardcode
- **Paths**:
  - Config: `/root/.openclaw` (VPS) or `~/.openclaw` (local)
  - Workspace: `$OPENCLAW_CONFIG/workspace`
  - Docker home: `/home/node`
- **Ports**: Gateway on 18789, bind to `127.0.0.1` (SSH tunnel for access)
- **User**: Everything runs as `node` user (UID 1000) in Docker

### Tools & Stack
- **Runtime**: Node.js (base image), Docker Compose
- **Languages**: TypeScript (OpenClaw core), Bash (deployment), Go/Python (skills)
- **Package managers**: npm (preferred), Homebrew (system tools), Go modules
- **Browser**: Chromium + Playwright (headless automation)
- **Messaging**: WhatsApp via `@whiskeysockets/baileys`

## Browser Automation

**Status**: Recently added to install script (2026-02-04)

**Capabilities:**
- Full web automation via Playwright
- Headless Chromium browser
- 28-parameter `browser` tool available to agents
- Screenshot capture, form filling, scraping, etc.

**Configuration:**
- Browser: `/usr/bin/chromium`
- Driver: `chromium-driver`
- Playwright: Installed globally via npm
- Environment variables set for both Puppeteer and Playwright
- Runs in Docker as `node` user

**See:** `BROWSER_SETUP.md` for full details

## Agent Behavior

### Core Identity (workspace/SOUL.md)
The deployed agent ("Bunk") has these traits:
- Professional but personable
- Proactive during heartbeats
- Reads memory files every session
- Writes daily logs to `memory/YYYY-MM-DD.md`
- Uses reactions in group chats appropriately
- Knows when to speak vs stay silent

### Security Principles
- Never exfiltrate private data
- Ask before destructive commands
- Use `trash` over `rm`
- Don't skip git hooks
- Don't force-push to main
- Validate user input at boundaries only

## Common Tasks

### Modifying Deployment
1. Edit `install-openclaw.sh`
2. Test changes locally if possible
3. SCP to VPS: `scp install-openclaw.sh root@VPS_IP:~`
4. SSH and run: `bash install-openclaw.sh`
5. Or just rebuild: `cd /root/openclaw && docker compose build && docker compose up -d`

### Updating Configuration
1. Edit `/root/.openclaw/openclaw.json` on VPS (or local `openclaw.json`)
2. Restart gateway: `docker compose restart openclaw-gateway`
3. No rebuild needed for config changes

### Adding Skills
- Agent can self-install skills dynamically
- Skills install to `/home/node/.openclaw/skills/`
- Use npm/go/brew as needed (all available in container)
- Bundled skills: `healthcheck`, `skill-creator`, `weather`

### Debugging
- Logs: `docker compose logs -f openclaw-gateway`
- Health check: `curl http://127.0.0.1:18789/health`
- Sessions: Check `agents/main/sessions/sessions.json`
- Memory: Check `workspace/memory/YYYY-MM-DD.md`

## Recent Changes

### 2026-02-04: Browser Automation Support
- Added Chromium + dependencies to Dockerfile
- Installed Playwright globally
- Set environment variables for both services
- Updated `install-openclaw.sh` (lines 237-245, 268-272, 153-155, 178-180, 289-291)
- Created `BROWSER_SETUP.md` documentation

**Next deployment:** Will include browser automation by default

## Deployment Workflow

**Fresh VPS:**
```bash
curl -fsSL https://your-url/install-openclaw.sh | bash
# or
scp install-openclaw.sh root@VPS_IP:~ && ssh root@VPS_IP 'bash install-openclaw.sh'
```

**Update existing VPS:**
```bash
cd /root/openclaw
git pull
docker compose build
docker compose down
docker compose up -d
```

**Access gateway:**
```bash
ssh -L 18789:127.0.0.1:18789 root@VPS_IP
# Then open http://localhost:18789
```

## Testing

**WhatsApp integration:**
1. Run onboarding: `docker compose run --rm openclaw-cli onboard`
2. Scan QR code
3. Send test message

**Browser tool:**
```
"Take a screenshot of https://example.com"
```

**Heartbeat:**
Wait 30 minutes or trigger manually via gateway API

## Resources

- **Repo**: https://github.com/openclaw/openclaw
- **Discord**: (if applicable - not in current config)
- **Docs**: `openclaw-hetzner-guide.md` for deployment details
- **API**: Gateway REST API on port 18789

## Notes for Future Sessions

- **Always read this file first** when working on OpenClaw
- Check `BROWSER_SETUP.md` for browser-related tasks
- The install script is the source of truth for deployment
- Test in Docker locally before pushing to VPS
- Agent workspace is precious - don't mess with memory files
- Gateway token is in `.env` - keep it secret

## Philosophy

OpenClaw is about **autonomy with oversight**. The agent should:
- Be proactive but not intrusive
- Learn and adapt through skills
- Maintain continuity through memory
- Respect privacy and security
- Work 24/7 but know when to stay quiet

Build features that support this vision.

---

**Last updated**: 2026-02-04 (Browser automation added)
**Maintainer**: Olly
**Agent**: Bunk (claude-sonnet-4-5-20250929)
