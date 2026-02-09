#!/usr/bin/env bash
set -euo pipefail

# VPS Security Hardening Script for Ubuntu 24.04
# Run this on a fresh Ubuntu 24.04 VPS to secure it

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

log "Starting VPS security hardening..."

# ============================================================================
# 1. Update System
# ============================================================================
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq

# ============================================================================
# 2. Configure SSH Security
# ============================================================================
log "Hardening SSH configuration..."
SSH_CONFIG="/etc/ssh/sshd_config"
cp $SSH_CONFIG ${SSH_CONFIG}.backup

# Allow root login with SSH keys only (no passwords)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' $SSH_CONFIG

# Disable password authentication (SSH keys only)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSH_CONFIG

# Keep UsePAM enabled (required for SSH key auth on Ubuntu)
sed -i 's/^#*UsePAM.*/UsePAM yes/' $SSH_CONFIG

# Disable empty passwords
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' $SSH_CONFIG

# Enable public key authentication
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSH_CONFIG

# Limit authentication attempts
if ! grep -q "MaxAuthTries" $SSH_CONFIG; then
    echo "MaxAuthTries 3" >> $SSH_CONFIG
fi

# Set login grace time
if ! grep -q "LoginGraceTime" $SSH_CONFIG; then
    echo "LoginGraceTime 20" >> $SSH_CONFIG
fi

log "SSH configured:"
log "  - Root login allowed with SSH keys only (no passwords)"
log "  - Password authentication disabled"
log "  - Max auth attempts: 3"

# ============================================================================
# 3. Setup UFW Firewall
# ============================================================================
log "Configuring UFW firewall..."
apt-get install -y -qq ufw

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow HTTP/HTTPS (if running web services)
read -p "Allow HTTP/HTTPS? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
fi

# Enable firewall
echo "y" | ufw enable
log "Firewall enabled"

# ============================================================================
# 4. Install and configure fail2ban
# ============================================================================
log "Installing fail2ban..."
apt-get install -y -qq fail2ban

# Create local jail configuration
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban configured and started"

# ============================================================================
# 5. Setup automatic security updates
# ============================================================================
log "Configuring automatic security updates..."
apt-get install -y -qq unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

log "Automatic security updates enabled"

# ============================================================================
# 6. Harden network settings
# ============================================================================
log "Hardening network settings..."
cat >> /etc/sysctl.conf <<'EOF'

# Security hardening
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
EOF

sysctl -p >/dev/null
log "Network security settings applied"

# ============================================================================
# 7. Setup swap (if not present)
# ============================================================================
if ! swapon --show | grep -q "/swapfile"; then
    log "Setting up swap file..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "2GB swap file created"
else
    log "Swap already configured"
fi

# ============================================================================
# 8. Install useful security tools
# ============================================================================
log "Installing security tools..."
apt-get install -y -qq \
    curl \
    wget \
    git \
    htop \
    net-tools \
    ufw \
    fail2ban

# ============================================================================
# 9. Restart SSH
# ============================================================================
warn ""
warn "Security hardening complete!"
warn ""
warn "IMPORTANT: SSH will now be restarted with new settings."
warn "Make sure you can log in with SSH keys before logging out!"
warn ""
read -p "Restart SSH now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart ssh
    log "SSH restarted"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
log "================================================"
log "Security Hardening Complete!"
log "================================================"
echo ""
log "What was done:"
echo "  ✓ System updated"
echo "  ✓ SSH hardened (SSH keys only, no passwords)"
echo "  ✓ UFW firewall enabled"
echo "  ✓ fail2ban installed and configured"
echo "  ✓ Automatic security updates enabled"
echo "  ✓ Network security settings applied"
echo "  ✓ Swap configured"
echo ""
warn "Next steps:"
echo "  1. Test SSH login in a NEW terminal before logging out"
echo "  2. Review firewall rules: ufw status"
echo "  3. Check fail2ban status: fail2ban-client status"
echo ""
log "Stay secure!"
