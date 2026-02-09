# OpenClaw on an Ubuntu VPS — Setup Guide

> **Goal:** A 24/7 personal AI assistant you message via Telegram or WhatsApp, powered by Claude, that teaches itself new skills over time. Cost: A few dollars/month for the VPS (varies by provider) + Anthropic API usage.

---

## What You're Building

OpenClaw is an open-source AI agent that runs on your own server. You message it through Telegram or WhatsApp like a normal contact, and it replies using Claude (via the Anthropic API). It has persistent memory, can run shell commands, browse the web, create files, and — critically for your "self-learning" goal — it can **write its own skills**: small code modules that extend what it can do, triggered simply by you asking it to do something new.

---

## What You Need Before Starting

- A **VPS from any provider** (e.g. Hetzner, DigitalOcean, Linode, Vultr)
- An **Anthropic API key** (console.anthropic.com → API Keys)
- **Telegram** (create a bot via @BotFather) and/or **WhatsApp** on your phone
- SSH on your laptop (Terminal on Mac/Linux, or PuTTY/WSL on Windows)
- ~30 minutes

---

## Part 1: Provision the VPS

1. Log into your VPS provider's dashboard.
2. Create a new server:
   - **Location:** Wherever is closest to you.
   - **Image:** Ubuntu 24.04
   - **Type:** 2 vCPU, 4 GB RAM is plenty. Even the smallest tier works for light use.
   - **SSH Key:** Add your public key (strongly recommended over password).
3. Note the server's **IP address** once it's created.
4. SSH in:

```bash
ssh root@YOUR_VPS_IP
```

---

## Part 2: Install Docker

```bash
apt-get update && apt-get upgrade -y
apt-get install -y git curl ca-certificates
curl -fsSL https://get.docker.com | sh
```

Verify both are working:

```bash
docker --version
docker compose version
```

---

## Part 3: Install OpenClaw

Clone the deployment repo and run the installer:

```bash
git clone https://github.com/lylo/clawformation.git /root/clawformation
bash /root/clawformation/setup.sh
```

The installer will:
1. Clone the OpenClaw source code to `/root/openclaw/`
2. Create persistent directories at `/root/.openclaw/`
3. Generate secure tokens
4. Prompt you to choose a messaging channel (Telegram, WhatsApp, or both)
5. Build Docker images (base + extended with browser automation)
6. Start the gateway

**When prompted for channel setup:**

| Channel | What you'll need |
|---|---|
| **Telegram** | Bot token (from @BotFather) and your Telegram user ID |
| **WhatsApp** | Your phone number in international format |

### Save your gateway token

The installer prints a token at the end. You can also retrieve it later:

```bash
grep OPENCLAW_GATEWAY_TOKEN /root/openclaw/.env
```

### Run onboarding

```bash
cd /root/openclaw
docker compose run --rm openclaw-cli onboard
```

This interactive wizard will:
- Add your Anthropic API key
- Connect your messaging channel
- Install default skills

---

## Part 4: Connect a Messaging Channel

The installer prompts you to choose Telegram, WhatsApp, or both. The config is written to `/root/.openclaw/openclaw.json`.

### Telegram (recommended)

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Enter the bot token and your Telegram user ID when prompted
3. Send a message to your bot to test

The config uses an allowlist so only you can talk to it:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "botToken": "YOUR_BOT_TOKEN",
      "allowFrom": ["YOUR_TELEGRAM_USER_ID"],
      "groupPolicy": "allowlist"
    }
  }
}
```

See `telegram-setup.md` for detailed Telegram setup instructions.

### WhatsApp

During onboarding, you'll see a **QR code** in the terminal. Open WhatsApp on your phone → Settings → Linked Devices → Link a Device → scan the QR code.

```json
{
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "allowFrom": ["+YOUR_PHONE_NUMBER"],
      "groupPolicy": "disabled"
    }
  }
}
```

OpenClaw supports multiple channels simultaneously — you can add more later.

---

## Part 5: Set Claude as the Model

If you picked Anthropic during onboarding, this is already done. To verify or change it later, edit `/root/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-haiku-4-5"
      },
      "models": {
        "anthropic/claude-haiku-4-5": {},
        "anthropic/claude-sonnet-4-5": {},
        "anthropic/claude-opus-4-6": {}
      }
    }
  }
}
```

**Two things to configure:**

1. **`primary`** — the default model used for conversations and heartbeats.
2. **`models`** — the allowlist of all models the agent is permitted to use. Any model referenced by cron jobs, channel overrides, or subagents must be listed here or it will fail with `"model not allowed"`.

**Available models:**

| Model | Best for | Relative cost |
|---|---|---|
| `anthropic/claude-haiku-4-5` | Fast responses, simple tasks, low cost | $ |
| `anthropic/claude-sonnet-4-5` | Good balance of cost and capability | $$ |
| `anthropic/claude-opus-4-6` | Complex reasoning, highest quality | $$$ |

To add a model, add its key to the `models` object with an empty `{}` value. To change the default, update `primary`.

After editing, restart the gateway:

```bash
cd /root/openclaw
docker compose restart
```

---

## Part 6: Enable Self-Learning

This is the key part. OpenClaw has a **skills system** — small code modules that live in your workspace and extend what the bot can do. The magic is that OpenClaw can **write new skills for itself** when you ask it to do something it doesn't already know how to do.

### How it works

When you message OpenClaw something like "track my daily water intake and remind me every 2 hours", it will:

1. Realise it doesn't have a skill for that yet.
2. Write the code for a new skill.
3. Save it to its workspace.
4. Start using it immediately.

This is what people mean by "self-improving" — it writes code to give itself new capabilities, and those capabilities persist because they live on disk.

### Enable the heartbeat

The heartbeat lets OpenClaw wake up periodically on its own (rather than only responding when you message it). This is essential for proactive behaviour — reminders, scheduled checks, background tasks.

In your `openclaw.json`, heartbeat lives under `agents.defaults`:

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "30m"
      }
    }
  }
}
```

This wakes the bot every 30 minutes to check if there's anything it should do.

### Seed it with your first conversation

Once everything is running, send your first messages to prime it. Here's a suggested sequence:

> **You:** Hi! I'd like you to be my personal assistant. Learn my preferences over time and build new skills when I ask you to do things you can't do yet.

> **You:** Please create a skill that checks Hacker News every morning at 8am and sends me a summary of the top 5 stories.

> **You:** What skills do you currently have installed?

OpenClaw will write the skill, install it, and start using it. You can check what skills exist:

```bash
docker compose exec openclaw-gateway openclaw skills list
```

### More self-learning prompts to try

- "Build a skill to track my expenses when I message you receipts"
- "Set up a daily standup reminder at 9am on weekdays"
- "Learn to summarise any URL I send you"
- "Create a skill that monitors [website] and tells me when it changes"

Each of these will cause OpenClaw to write and install a new skill autonomously.

---

## Part 7: Access the Dashboard (Optional)

The Control UI lets you see sessions, config, and health from a browser. The gateway only exposes port 18789 on `127.0.0.1`, so access it through an SSH tunnel:

```bash
# Run this on YOUR laptop, not the VPS (-N means no shell, just tunnel)
ssh -N -L 18789:127.0.0.1:18789 root@YOUR_VPS_IP
```

Then open http://localhost:18789 in your browser and paste the gateway token (from `/root/openclaw/.env`).

**Note:** The config template sets `gateway.bind: "lan"` so the gateway listens on all interfaces inside the Docker container (required for Docker port mapping). Docker still only exposes the port on the host's `127.0.0.1`, so it's not publicly accessible. The template also sets `gateway.controlUi.allowInsecureAuth: true` which skips device pairing — safe since access is gated by the SSH tunnel and gateway token.

---

## Part 8: Keep It Updated

OpenClaw moves fast. To update:

**Update OpenClaw software:**
```bash
cd /root/openclaw && git pull
docker compose build && docker compose up -d
```

**Update deployment config (Dockerfile, docker-compose, etc.):**
```bash
cd /root/clawformation && git pull
bash /root/clawformation/setup.sh
```

---

## Security Reminders

- **Never run OpenClaw on a machine with sensitive personal data.** A VPS is ideal because the blast radius is contained.
- **Keep `dmPolicy: "allowlist"`** so only you can talk to it.
- **Don't expose port 18789 publicly** without a firewall and token auth. Use SSH tunnels.
- **Rotate your gateway token** if you suspect it's been leaked.
- **Monitor API costs.** The heartbeat and skill-building consume API tokens. Start with Haiku to keep costs low, and check your Anthropic dashboard regularly.

---

## Quick Reference

| Task | Command |
|---|---|
| Start gateway | `cd /root/openclaw && docker compose up -d` |
| Stop gateway | `docker compose down` |
| Restart | `docker compose restart` |
| View logs | `docker compose logs -f openclaw-gateway` |
| Check health | `curl http://127.0.0.1:18789/health` |
| List skills | `docker compose exec openclaw-gateway openclaw skills list` |
| Edit config | `nano /root/.openclaw/openclaw.json` (then restart) |
| Update OpenClaw | `cd /root/openclaw && git pull && docker compose build && docker compose up -d` |
| Update deployment | `cd /root/clawformation && git pull && bash /root/clawformation/setup.sh` |
| Get dashboard URL | `docker compose run --rm openclaw-cli dashboard --no-open` |

---

## Useful Links

- **Official docs:** https://docs.openclaw.ai
- **WhatsApp channel:** https://docs.openclaw.ai/channels/whatsapp
- **Signal channel:** https://docs.openclaw.ai/channels/signal
- **Skills docs:** https://docs.openclaw.ai/tools/skills
- **Heartbeat docs:** https://docs.openclaw.ai/gateway/heartbeat
- **GitHub:** https://github.com/openclaw/openclaw
- **Discord community:** https://discord.gg/clawd
