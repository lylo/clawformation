# Tailscale Setup for Your VPS

Secure your VPS by making SSH only accessible via your private Tailscale network.

## What This Does

- Creates a private VPN mesh network (100.x.x.x subnet)
- SSH only accessible from your devices on the Tailscale network
- No SSH port exposed to the public internet
- Direct access to internal services (like OpenClaw dashboard) without SSH tunnels

## Prerequisites

- SSH access to your VPS (current setup working)
- A Tailscale account (free at https://tailscale.com)

---

## Step 1: Install Tailscale on Your Laptop

**macOS:**
```bash
# Install via Homebrew
brew install tailscale

# Or download from https://tailscale.com/download/mac
```

**Linux:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

**Start Tailscale:**
```bash
sudo tailscale up
```

This opens a browser to authenticate. Log in with your Tailscale account.

**Check your IP:**
```bash
tailscale ip -4
```

You'll get something like `100.x.x.x` - this is your laptop's Tailscale IP.

---

## Step 2: Install Tailscale on Your VPS

**SSH into your VPS:**
```bash
ssh root@YOUR_VPS_IP
```

**Install Tailscale:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

**Start Tailscale:**
```bash
sudo tailscale up
```

Copy the authentication URL it gives you, open it in a browser, and authenticate.

**Get your VPS Tailscale IP:**
```bash
tailscale ip -4
```

Note this IP (e.g., `100.101.102.103`) - this is how you'll access your VPS.

**Enable IP forwarding (optional, for subnet routing):**
```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf
```

---

## Step 3: Test Tailscale Access

**From your laptop, SSH via Tailscale:**
```bash
ssh root@100.101.102.103  # Use your VPS Tailscale IP
```

If this works, you're connected via Tailscale!

**Add to your SSH config for convenience:**
```bash
# Edit ~/.ssh/config on your laptop
nano ~/.ssh/config
```

Add:
```
Host openclaw-tailscale
    HostName 100.101.102.103  # Your VPS Tailscale IP
    User root
    IdentityFile ~/.ssh/id_ed25519
```

Now you can use: `ssh openclaw-tailscale`

---

## Step 4: Restrict SSH to Tailscale Only

⚠️ **CRITICAL: Only do this after Step 3 works!** ⚠️

You're about to block SSH from the public internet. Make sure Tailscale works first.

### Option A: Using Your Provider's Cloud Firewall (Recommended)

1. **Go to your VPS provider's web console**
2. **Firewall** → Create Firewall or edit existing
3. **Inbound Rules:**
   - SSH (Port 22):
     - Protocol: TCP
     - Port: 22
     - Source: `100.64.0.0/10` (Tailscale subnet)
   - (Optional) ICMP for ping: Source `Any`

4. **Attach firewall to your server**

This blocks SSH from the internet but allows it from Tailscale.

### Option B: Using UFW on the VPS

**WARNING: If you mess this up, you'll be locked out. Keep a console/rescue access ready.**

```bash
# Remove current SSH rule
sudo ufw delete allow 22/tcp

# Allow SSH only from Tailscale subnet
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH via Tailscale'

# Reload
sudo ufw reload

# Check status
sudo ufw status
```

---

## Step 5: Access OpenClaw Dashboard Directly

With Tailscale, you can access the dashboard without SSH tunnels:

**On your laptop, open:**
```
http://100.101.102.103:18789
```

(Use your VPS Tailscale IP)

Enter your gateway token and you're in!

---

## Recovery: If You Get Locked Out

### Method 1: Web Console
1. Go to your VPS provider's web console
2. Click the console/terminal access button
3. Log in with password (if set)
4. Disable Tailscale restriction or fix config

### Method 2: Rescue Mode
1. Use your provider's rescue/recovery mode
2. Enable rescue mode and power cycle the server
3. SSH into rescue mode with the provided password
4. Mount filesystem: `mount /dev/sda1 /mnt`
5. Fix firewall: `chroot /mnt ufw allow 22/tcp`
6. Reboot

### Method 3: Remove Firewall in Provider UI
1. Go to your provider's web console → Firewall settings
2. Detach or delete the firewall
3. SSH access restored

---

## Benefits

✅ **SSH invisible to attackers** - No brute force attempts
✅ **No SSH tunnel needed** - Access dashboard directly
✅ **Multi-device** - Add phone, tablet, etc. to Tailscale
✅ **Secure by default** - Encrypted WireGuard VPN
✅ **Fast** - Direct peer-to-peer when possible

---

## Managing Tailscale

**Check status:**
```bash
tailscale status
```

**List devices:**
```bash
tailscale status --peers
```

**Disable Tailscale (temporarily):**
```bash
sudo tailscale down
```

**Re-enable:**
```bash
sudo tailscale up
```

**Remove a device:**
Go to https://login.tailscale.com/admin/machines and delete it.

---

## SSH Config Example

Add this to `~/.ssh/config` on your laptop:

```
# Via Tailscale (secure, recommended)
Host openclaw
    HostName 100.101.102.103
    User root
    IdentityFile ~/.ssh/id_ed25519

# Via public IP (fallback, if Tailscale is down)
Host openclaw-public
    HostName YOUR_VPS_PUBLIC_IP
    User root
    IdentityFile ~/.ssh/id_ed25519
```

Now:
- `ssh openclaw` - Uses Tailscale
- `ssh openclaw-public` - Uses public IP (only works if firewall allows it)

---

## Troubleshooting

### Can't connect via Tailscale
```bash
# On both machines, check Tailscale status
tailscale status

# Restart Tailscale
sudo tailscale down
sudo tailscale up

# Check if both machines see each other
tailscale ping 100.x.x.x
```

### Locked out after restricting SSH
Use your provider's web console or rescue mode (see Recovery section above).

### OpenClaw dashboard not accessible
Check if OpenClaw is running:
```bash
ssh openclaw  # Via Tailscale
cd /root/openclaw
docker compose ps
docker compose logs -f openclaw-gateway
```

---

## Costs

**Tailscale:** Free for personal use (up to 100 devices)
**VPS:** No additional cost for Tailscale traffic

---

## Security Notes

- Tailscale uses WireGuard (modern, secure VPN)
- End-to-end encrypted between your devices
- Tailscale coordination servers don't see your traffic
- Keep your Tailscale account secured with 2FA
- Regularly review connected devices in Tailscale admin

---

## Next Steps

1. Test Tailscale access thoroughly before restricting SSH
2. Add SSH config entries for convenience
3. Optionally restrict SSH via your provider's firewall or UFW
4. Access OpenClaw dashboard directly via Tailscale IP
5. Add more devices (phone, tablet) to your Tailscale network
