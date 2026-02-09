# OpenClaw Skills Management

Guide for installing and managing skills to extend your OpenClaw bot's capabilities.

## What Are Skills?

Skills are modular capabilities that extend what your bot can do. They're small code modules that add functionality like:
- Checking model usage/costs
- Summarizing text
- Weather lookups
- Custom integrations
- And more from the community

---

## Installing Skills with clawhub

**clawhub** is OpenClaw's skill package manager (like npm for skills).

### Search for Skills

```bash
docker compose exec openclaw-gateway npx clawhub search <query>

# Example
docker compose exec openclaw-gateway npx clawhub search weather
```

### List Available Skills

```bash
docker compose exec openclaw-gateway npx clawhub list
```

### Install a Skill

```bash
docker compose exec openclaw-gateway npx clawhub install <skill-name>

# Examples
docker compose exec openclaw-gateway npx clawhub install model-usage
docker compose exec openclaw-gateway npx clawhub install summarize
docker compose exec openclaw-gateway npx clawhub install weather
```

**Output:**
```
✔ OK. Installed model-usage -> /home/node/.openclaw/workspace/skills/model-usage
```

Skills are installed to: `/home/node/.openclaw/workspace/skills/`

---

## Activating New Skills

After installing skills, **restart the gateway** to load them:

```bash
# Quick restart
docker compose restart openclaw-gateway

# Or full restart
docker compose down
docker compose up -d
```

**Verify skills loaded:**
```bash
docker compose logs openclaw-gateway | grep -i skill
```

You should see:
```
[gateway] loaded skills: model-usage, summarize, weather
```

---

## Using Installed Skills

Once installed and loaded, skills are automatically available. Just ask your bot:

**Examples:**
- "Show my model usage" (uses `model-usage` skill)
- "Summarize this article: [URL]" (uses `summarize` skill)
- "What's the weather in New York?" (uses `weather` skill)

The bot will automatically use the appropriate skill based on your request.

---

## Managing Skills

### List Installed Skills

```bash
docker compose exec openclaw-gateway openclaw skills list

# Or check the directory
docker compose exec openclaw-gateway ls -la /home/node/.openclaw/workspace/skills/
```

### Remove a Skill

```bash
# Remove skill directory
docker compose exec openclaw-gateway rm -rf /home/node/.openclaw/workspace/skills/<skill-name>

# Restart to apply
docker compose restart openclaw-gateway
```

### Update a Skill

```bash
# Reinstall to get latest version
docker compose exec openclaw-gateway npx clawhub install <skill-name> --force

# Restart
docker compose restart openclaw-gateway
```

---

## Useful Skills

Here are some commonly used skills:

### model-usage
Track API costs and token usage across conversations.
```bash
docker compose exec openclaw-gateway npx clawhub install model-usage
```

### summarize
Summarize long text, articles, or web pages.
```bash
docker compose exec openclaw-gateway npx clawhub install summarize
```

### weather
Get current weather and forecasts for any location.
```bash
docker compose exec openclaw-gateway npx clawhub install weather
```

### healthcheck
Security audit and system health checks.
```bash
docker compose exec openclaw-gateway npx clawhub install healthcheck
```

---

## Creating Custom Skills

Skills are just Node.js modules. You can create your own:

### Skill Structure

```
/home/node/.openclaw/workspace/skills/my-skill/
├── package.json
├── index.js
└── README.md
```

**Example skill (`index.js`):**
```javascript
export default {
  name: 'my-skill',
  description: 'Does something useful',

  async run(context) {
    // Your skill logic here
    return { result: 'Success!' };
  }
};
```

**Create skill interactively:**
```bash
docker compose exec openclaw-gateway openclaw skills create
```

Or just message your bot:
```
"Create a skill that tracks my daily water intake"
```

The bot can write and install skills for you!

---

## Troubleshooting

### Skill not found
```bash
docker compose exec openclaw-gateway npx clawhub install summarise
✖ Skill not found
```

**Cause:** Typo in skill name (e.g., `summarise` vs `summarize`)

**Fix:** Check exact spelling:
```bash
docker compose exec openclaw-gateway npx clawhub search summar
```

### Skill installed but not available

**Check if loaded:**
```bash
docker compose logs openclaw-gateway | grep -i skill
```

**Fix:** Restart gateway:
```bash
docker compose restart openclaw-gateway
```

### Permission errors

**Cause:** Running clawhub on host instead of in container

**Fix:** Always prefix with container exec:
```bash
# Wrong
npx clawhub install weather

# Right
docker compose exec openclaw-gateway npx clawhub install weather
```

---

## clawhub Command Reference

```bash
# Search skills
npx clawhub search <query>

# List all skills
npx clawhub list

# Show skill details
npx clawhub info <skill-name>

# Install skill
npx clawhub install <skill-name>

# Install with force (update)
npx clawhub install <skill-name> --force

# Sync skills from config
npx clawhub sync
```

**Always run inside container:**
```bash
docker compose exec openclaw-gateway npx clawhub <command>
```

---

## Skill Allowlists

Control which skills the bot can use via config:

**Edit config:**
```bash
nano /root/.openclaw/openclaw.json
```

**Restrict to specific skills:**
```json
{
  "agents": {
    "defaults": {
      "skills": {
        "allowlist": ["model-usage", "summarize", "weather"]
      }
    }
  }
}
```

**Block specific skills:**
```json
{
  "agents": {
    "defaults": {
      "skills": {
        "denylist": ["risky-skill"]
      }
    }
  }
}
```

Restart after config changes:
```bash
docker compose restart openclaw-gateway
```

---

## Skills in Different Channels

Configure skills per channel:

```json
{
  "channels": {
    "telegram": {
      "skills": ["model-usage", "weather"]
    },
    "whatsapp": {
      "skills": ["summarize"]
    }
  }
}
```

---

## Backup Your Skills

Skills are in the workspace, which persists outside the container:

```bash
# Backup skills
tar -czf openclaw-skills-backup.tar.gz /root/.openclaw/workspace/skills/

# Restore skills
tar -xzf openclaw-skills-backup.tar.gz -C /

# Restart
docker compose restart openclaw-gateway
```

---

## Quick Reference

**Install workflow:**
```bash
# 1. Search for skill
docker compose exec openclaw-gateway npx clawhub search <keyword>

# 2. Install skill
docker compose exec openclaw-gateway npx clawhub install <skill-name>

# 3. Restart gateway
docker compose restart openclaw-gateway

# 4. Test in Telegram/WhatsApp
"Use the <skill-name> skill"
```

**Create alias for convenience:**

Add to `~/.bashrc` on VPS:
```bash
alias clawhub="docker compose -f /root/openclaw/docker-compose.yml exec openclaw-gateway npx clawhub"
```

Then just:
```bash
clawhub install weather
```

