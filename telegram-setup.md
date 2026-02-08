# Switching OpenClaw from WhatsApp to Telegram

Complete guide for migrating your OpenClaw bot from WhatsApp to Telegram.

## Why Telegram is Better

✅ **Official Bot API** - Stable, supported, won't break
✅ **No QR scanning** - Just use a token
✅ **No disconnections** - Stays connected reliably
✅ **No ban risk** - Bots are first-class citizens
✅ **Multi-device** - Phone, desktop, web simultaneously
✅ **Better privacy** - Bot doesn't need your phone number
✅ **Simpler setup** - 5 minutes vs 15+ for WhatsApp

---

## Step 1: Get Telegram (If You Don't Have It)

**Download Telegram:**
- **macOS/iOS:** App Store
- **Android:** Play Store
- **Linux:** https://telegram.org/dl/desktop/linux
- **Web:** https://web.telegram.org

**Create account:**
1. Open Telegram
2. Enter your phone number
3. Enter SMS verification code
4. Set up profile (name, photo)

**Privacy tip:**
- Settings → Privacy → Phone Number → "Nobody" (hide your number)

---

## Step 2: Create Your Bot

**Open Telegram and message @BotFather:**

1. Search for **@BotFather** (verified bot with checkmark)
2. Start a chat: `/start`

**Create the bot:**
```
/newbot
```

BotFather will ask:

**Bot name:** (shown to users)
```
Bunk Bot
```

**Bot username:** (must end in "bot")
```
bunk_assistant_bot
```

**You'll get a token like:**
```
7123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
```

⚠️ **Save this token!** You'll need it for OpenClaw.

**Additional bot settings (optional):**
```
/setdescription - Set bot description
/setabouttext - Set about text
/setuserpic - Upload bot profile picture
```

---

## Step 3: Get Your Telegram User ID

You need your Telegram user ID to configure the allowlist.

**Option A: Use @userinfobot**
1. Search for **@userinfobot** on Telegram
2. Start a chat with it
3. It will reply with your user ID (e.g., `123456789`)

**Option B: Use @getidsbot**
1. Search for **@getidsbot**
2. Send any message
3. It replies with your ID

**Save your user ID** - you'll need it for the config.

---

## Step 4: Configure OpenClaw for Telegram

**SSH into your VPS:**
```bash
ssh root@openclaw  # or ssh openclaw
cd /root/openclaw
```

**Stop the gateway:**
```bash
docker compose down
```

**Edit OpenClaw config:**
```bash
nano /root/.openclaw/openclaw.json
```

**Add Telegram configuration:**

Telegram needs TWO sections - `channels` for config and `plugins.entries` to enable:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "7123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw",
      "dmPolicy": "allowlist",
      "allowFrom": ["123456789"]
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      },
      "whatsapp": {
        "enabled": false
      }
    }
  }
}
```

**Replace:**
- `"botToken"` - Your bot token from @BotFather
- `"123456789"` - Your Telegram user ID as a string

**Save and exit:** `Ctrl+X`, `Y`, `Enter`

---

## Step 5: Install Telegram Plugin (If Needed)

OpenClaw might need the Telegram plugin installed.

**Check if installed:**
```bash
docker compose exec openclaw-gateway openclaw plugins list
```

**If Telegram plugin is missing, the gateway will auto-install it on startup.**

---

## Step 6: Start OpenClaw

```bash
docker compose up -d
```

**Watch logs:**
```bash
docker compose logs -f openclaw-gateway
```

Look for:
```
[telegram] Connected to Telegram
[telegram] Listening for Telegram messages
```

If you see errors, check:
- Token is correct
- User ID is a number (no quotes)
- JSON syntax is valid

---

## Step 7: Test Your Bot

**On Telegram:**

1. Search for your bot: `@bunk_assistant_bot` (your bot username)
2. Start a chat: `/start`
3. Send a message: `Hello!`

**Your bot should respond!**

**Check logs on VPS:**
```bash
docker compose logs -f openclaw-gateway | grep telegram
```

You should see:
```
[telegram] Received message from user 123456789
[telegram] Sent response to user 123456789
```

---

## Step 8: Disable WhatsApp (Optional)

If everything works with Telegram, you can disable WhatsApp:

**Already done in Step 4 - in the plugins section:**
```json
"plugins": {
  "entries": {
    "whatsapp": {
      "enabled": false
    }
  }
}
```

**Or keep both enabled** if you want multi-channel support:
```json
{
  "channels": {
    "telegram": { ... },
    "whatsapp": { ... }
  },
  "plugins": {
    "entries": {
      "telegram": { "enabled": true },
      "whatsapp": { "enabled": true }
    }
  }
}
```

---

## Complete Config Example

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-haiku-4-5"
      },
      "heartbeat": {
        "every": "30m"
      },
      "maxConcurrent": 4
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "7123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw",
      "dmPolicy": "allowlist",
      "allowFrom": ["123456789"],
      "streamMode": "partial"
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      },
      "whatsapp": {
        "enabled": false
      }
    }
  },
  "gateway": {
    "port": 18789,
    "bind": "127.0.0.1",
    "token": "your-gateway-token-here"
  }
}
```

---

## Telegram Bot Commands

You can add custom commands via @BotFather:

```
/setcommands
```

Then send:
```
help - Show help
status - Bot status
skills - List installed skills
```

These appear in Telegram's command menu (/ button).

---

## Privacy Settings

**Hide your phone number:**
1. Telegram Settings → Privacy → Phone Number
2. Set to "Nobody" or "My Contacts"

**Bot privacy:**
- Bots can only see messages sent to them
- Your bot username is public (anyone can message it)
- Use `dmPolicy: "allowlist"` to restrict access

---

## Troubleshooting

### Bot doesn't respond

**Check logs:**
```bash
docker compose logs -f openclaw-gateway | grep telegram
```

**Common issues:**
- Wrong token format
- User ID as string instead of number: `"123"` → `123`
- JSON syntax error (missing comma, bracket)
- Bot token not saved correctly

**Test token manually:**
```bash
curl https://api.telegram.org/bot<TOKEN>/getMe
```

Replace `<TOKEN>` with your bot token. Should return bot info.

### "Unauthorized" error

- Token is wrong or expired
- Regenerate token: @BotFather → `/token` → select your bot

### Bot receives messages but doesn't reply

- Check `allowFrom` list includes your user ID
- Check `dmPolicy` is set correctly
- View full logs: `docker compose logs openclaw-gateway`

### Can't find bot

- Username must end in `bot`
- Wait a few minutes for Telegram to index it
- Try searching exact username: `@your_bot_username`

---

## Advantages Over WhatsApp

| Feature | Telegram | WhatsApp |
|---------|----------|----------|
| **Setup** | 5 min, just token | 15 min, QR scanning |
| **Stability** | Never disconnects | Frequent disconnects |
| **Multi-device** | ✅ All devices | ❌ Phone only |
| **Ban risk** | ✅ No risk | ❌ Can get banned |
| **Privacy** | ✅ Username-based | ❌ Phone exposed |
| **API** | ✅ Official | ❌ Unofficial |
| **Groups** | ✅ Full support | ⚠️ Limited |
| **Bots** | ✅ First-class | ❌ Hack/workaround |

---

## Advanced: Group Chats

**Add bot to a group:**

1. Create a Telegram group
2. Add your bot as member
3. Get group ID via @getidsbot (send message in group)
4. Update config:

```json
{
  "channels": {
    "telegram": {
      "groupPolicy": "allowlist",
      "allowFrom": ["123456789"],
      "allowGroups": ["-987654321"]
    }
  }
}
```

**Privacy settings for groups:**

Via @BotFather:
```
/setprivacy
```

- **Disabled** - Bot sees all messages
- **Enabled** - Bot only sees commands and mentions

---

## Backup & Recovery

**Your bot token** is the only credential you need. Save it securely:

```bash
# View current token
grep -A5 telegram /root/.openclaw/openclaw.json
```

**If you lose the token:**
1. Message @BotFather
2. `/mybots` → select your bot → API Token
3. Copy and update config

---

## Security Best Practices

✅ **Never share your bot token** - Anyone with it can control your bot
✅ **Use allowlist** - Only you can message the bot
✅ **Disable group policy** - Unless you need it
✅ **Rotate token** - If compromised, revoke via @BotFather
✅ **Monitor logs** - Check for unauthorized access attempts

---

## Next Steps

1. ✅ Create Telegram account
2. ✅ Create bot via @BotFather
3. ✅ Get your user ID
4. ✅ Configure OpenClaw
5. ✅ Test the bot
6. ✅ Disable WhatsApp (optional)
7. Enjoy stable, reliable bot messaging!

---

## Quick Reference

**Useful bots:**
- @BotFather - Create and manage bots
- @userinfobot - Get your user ID
- @getidsbot - Get user/group IDs

**Telegram API test:**
```bash
# Get bot info
curl https://api.telegram.org/bot<TOKEN>/getMe

# Get updates
curl https://api.telegram.org/bot<TOKEN>/getUpdates
```

**OpenClaw commands:**
```bash
# Restart
docker compose restart openclaw-gateway

# View logs
docker compose logs -f openclaw-gateway

# Check config
cat /root/.openclaw/openclaw.json | grep -A10 telegram
```

---

**Last updated:** 2026-02-04
**OpenClaw Version:** 2026.2.3
**Tested on:** Hetzner Ubuntu 24.04 VPS
