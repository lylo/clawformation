# OpenClaw on a Hetzner VPS — Simple Setup Guide

> **Goal:** A 24/7 personal AI assistant you message via WhatsApp or Signal, powered by Claude, that teaches itself new skills over time. Cost: ~€4–6/month for the VPS + Anthropic API usage.

---

## What You're Building

OpenClaw is an open-source AI agent that runs on your own server. You message it through WhatsApp or Signal like a normal contact, and it replies using Claude (via the Anthropic API). It has persistent memory, can run shell commands, browse the web, create files, and — critically for your "self-learning" goal — it can **write its own skills**: small code modules that extend what it can do, triggered simply by you asking it to do something new.

---

## What You Need Before Starting

- A **Hetzner Cloud account** (hetzner.com)
- An **Anthropic API key** (console.anthropic.com → API Keys)
- **WhatsApp** on your phone (to scan a QR code for pairing) and/or a **spare phone number** for Signal
- SSH on your laptop (Terminal on Mac/Linux, or PuTTY/WSL on Windows)
- ~30 minutes

---

## Part 1: Provision the VPS

1. Log into Hetzner Cloud Console.
2. Create a new server:
   - **Location:** Wherever is closest to you.
   - **Image:** Ubuntu 24.04
   - **Type:** CX22 (2 vCPU, 4 GB RAM) is plenty. Even CX11 works for light use.
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

## Part 3: Clone and Set Up OpenClaw

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

### Create persistent directories

Docker containers are ephemeral — everything inside them vanishes on restart. These host directories store OpenClaw's config, memory, and workspace permanently:

```bash
mkdir -p /root/.openclaw /root/.openclaw/workspace
chown -R 1000:1000 /root/.openclaw /root/.openclaw/workspace
```

### Run the setup script

```bash
./docker-setup.sh
```

This interactive wizard will:
- Build the Docker image
- Walk you through onboarding (gateway type, model provider, channels, skills)
- Generate a gateway token
- Start the gateway via Docker Compose

**When prompted during the wizard:**

| Prompt | What to pick |
|---|---|
| Gateway location | **Local** |
| Model provider | **Anthropic API Key**, then paste your key |
| Channel | **WhatsApp** (easiest to start) |
| Skills | Say **Yes** and accept the defaults — you can always add more later |
| Hooks | Accept defaults or skip |

### Save your gateway token

The setup prints a token at the end. You can also retrieve it later:

```bash
cat /root/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN
```

---

## Part 4: Connect WhatsApp

During onboarding, you'll see a **QR code** in the terminal. Open WhatsApp on your phone → Settings → Linked Devices → Link a Device → scan the QR code.

Once paired, your OpenClaw instance appears as a linked device. You can now message yourself (or have someone message the number) and OpenClaw will reply.

**Important:** Set a DM policy so only you can talk to it. In your config (`/root/.openclaw/openclaw.json`), make sure:

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

Replace `+YOUR_PHONE_NUMBER` with your number in international format (e.g. `+447700900000`).

---

## Part 4b (Alternative): Connect Signal

Signal requires `signal-cli`, which needs Java. This adds more moving parts, so WhatsApp is easier for a first test. If you still want Signal:

1. You need a **separate phone number** for the bot (Signal won't let the bot reply to itself on your own number).
2. Install Java and signal-cli on the VPS (or bake them into the Docker image).
3. Register the bot number with signal-cli.
4. Configure OpenClaw:

```json
{
  "channels": {
    "signal": {
      "enabled": true,
      "account": "+BOT_PHONE_NUMBER",
      "cliPath": "signal-cli",
      "dmPolicy": "allowlist",
      "allowFrom": ["+YOUR_PHONE_NUMBER"]
    }
  }
}
```

The official docs cover this in detail: https://docs.openclaw.ai/channels/signal

**Recommendation:** Start with WhatsApp. You can add Signal later — OpenClaw supports multiple channels simultaneously.

---

## Part 5: Set Claude as the Model

If you picked Anthropic during onboarding, this is already done. To verify or change it later, edit `/root/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5-20250929"
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

Once everything is running, open WhatsApp and send your first messages to prime it. Here's a suggested sequence:

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

The Control UI lets you see sessions, config, and health from a browser. It's bound to localhost by default (good for security), so access it through an SSH tunnel:

```bash
# Run this on YOUR laptop, not the VPS
ssh -L 18789:127.0.0.1:18789 root@YOUR_VPS_IP
```

Then open http://localhost:18789 in your browser and paste the gateway token.

---

## Part 8: Keep It Updated

OpenClaw moves fast. To update:

```bash
cd /root/openclaw
git pull
docker compose build
docker compose up -d
```

Or if you installed via npm inside Docker, the `docker-setup.sh` script handles rebuilds.

---

## Security Reminders

- **Never run OpenClaw on a machine with sensitive personal data.** A VPS is ideal because the blast radius is contained.
- **Keep `dmPolicy: "allowlist"`** so only your number can talk to it.
- **Don't expose port 18789 publicly** without a firewall and token auth. Use SSH tunnels.
- **Rotate your gateway token** if you suspect it's been leaked.
- **Monitor API costs.** The heartbeat and skill-building consume API tokens. Start with Sonnet to keep costs reasonable, and check your Anthropic dashboard regularly.

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
| Update | `git pull && docker compose build && docker compose up -d` |
| Get dashboard URL | `docker compose run --rm openclaw-cli dashboard --no-open` |

---

## Useful Links

- **Official docs:** https://docs.openclaw.ai
- **Hetzner-specific guide:** https://docs.openclaw.ai/platforms/hetzner
- **WhatsApp channel:** https://docs.openclaw.ai/channels/whatsapp
- **Signal channel:** https://docs.openclaw.ai/channels/signal
- **Skills docs:** https://docs.openclaw.ai/tools/skills
- **Heartbeat docs:** https://docs.openclaw.ai/gateway/heartbeat
- **GitHub:** https://github.com/openclaw/openclaw
- **Discord community:** https://discord.gg/clawd
