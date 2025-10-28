# 🛡️ Linux Security Monitor

Automated security scanning and monitoring system for Ubuntu/Debian and Amazon Linux servers with ClamAV antivirus, automatic updates, and a beautiful status dashboard.

## ✨ Features

- 🦠 **ClamAV Antivirus** - Automated virus definition updates and malware scanning
- 🔄 **Automatic Updates** - Security and system updates applied automatically  
- 📊 **Status Dashboard** - 6 detailed cards with real-time security information and progress bars
- ⏰ **Scheduled Scans** - Daily scans at 2:00 AM via systemd timers
- 🔧 **Health Monitoring** - Service checks every 6 hours
- 💻 **Easy Commands** - Shell functions for all operations
- 🎨 **Beautiful UI** - Clean terminal dashboard with color-coded status indicators

---

## 🚀 Quick Installation

### One-Line Install

```bash
# Ubuntu/Debian
wget -O - https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/install-security.sh | sudo bash

# Amazon Linux 2023
wget -O - https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/install-security.sh | sudo bash
```

### Manual Installation

```bash
# Download the scripts
wget https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-manager.sh
wget https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-monitor.sh

# Make executable
chmod +x security-manager.sh security-monitor.sh

# Install (auto-detects OS)
sudo ./security-manager.sh install

# Activate shortcuts (or start a new shell session)
source /etc/profile.d/security-monitor.sh
```

---

## 📋 Command Reference

### 🔍 sudo Requirements by OS

| Command | Ubuntu/Debian | Amazon Linux 2023 | Description |
|---------|---------------|-------------------|-------------|
| `security-status` | ✅ **No sudo needed** | ✅ **No sudo needed** | View security dashboard |
| `security-scan` | ✅ **No sudo needed** | ✅ **No sudo needed** | Run malware scan |
| `security-health` | ✅ **No sudo needed** | ✅ **No sudo needed** | Check system health |

> **Note:** All shortcuts are **shell functions** (not aliases) and work in all contexts including scripts and non-interactive shells. The functions internally use `sudo` where needed, so you don't have to remember when to use it.

### Quick Commands

```bash
# View status dashboard (no sudo needed - works for all users)
security-status

# Run quick scan (~30-90 seconds, no sudo needed)
security-scan

# Run full system scan (~10-30 minutes, no sudo needed)
security-scan full

# Check system health (no sudo needed)
security-health
```

### Alternative Direct Commands

If shortcuts don't work, use the full paths:

```bash
# View status (no sudo needed)
/usr/local/bin/security-monitor status

# Run scans (no sudo needed)
/usr/local/bin/security-monitor scan
/usr/local/bin/security-monitor scan full

# Health check (no sudo needed)
/usr/local/bin/security-manager health

# Manual virus database update (sudo required)
sudo freshclam
```

---

## 📊 Status Dashboard

The `security-status` command displays a comprehensive dashboard with 6 detailed cards:

```
═══════════════════════════════════════════════════════════
         🛡️  SECURITY STATUS DASHBOARD
═══════════════════════════════════════════════════════════

╔════════════════════════════════════════════════════════╗
║ 📊 SCAN STATUS                                            ║
╚════════════════════════════════════════════════════════╝
  Status:         ✓ CLEAN
  Last Scan:      2025-10-28T15:20:14+00:00
  Next Scan:      2025-10-29 02:00
  Files Scanned:  7654
  Infected:       0
  Freshness:      ● Recently scanned

╔════════════════════════════════════════════════════════╗
║ ✓ SECURITY COMPLIANCE                                    ║
╚════════════════════════════════════════════════════════╝
  Compliance:     100%
  ████████████████████
  ● All systems operational

╔════════════════════════════════════════════════════════╗
║ 🔄 SYSTEM UPDATES                                         ║
╚════════════════════════════════════════════════════════╝
  Available:      0 updates (system up to date)
  Type:           All packages current
  Auto-Apply:     Enabled (during scans)
  Apply Now:      sudo security-scan
  Last Check:     During last scan
  Schedule:       Daily at 2:00 AM

╔════════════════════════════════════════════════════════╗
║ ⚙️  SERVICES STATUS                                        ║
╚════════════════════════════════════════════════════════╝
  ClamAV Daemon:  ● Running
  FreshClam:      ● Running
  Scheduled Scans: ● Active (daily at 2:00 AM)
  Auto Updates:   ● Enabled

╔════════════════════════════════════════════════════════╗
║ 🦠 VIRUS DATABASE                                         ║
╚════════════════════════════════════════════════════════╝
  Status:         ✓ Active and loaded
  Action:         Up to date
  Info:           Last updated: 2025-10-28
  Check Logs:     sudo tail /var/log/clamav/freshclam.log

╔════════════════════════════════════════════════════════╗
║ ⚡ QUICK ACTIONS                                          ║
╚════════════════════════════════════════════════════════╝

  Force Scan Now:
    security-scan            or  security-monitor scan

  View Status:
    security-status          or  security-monitor status

  Check Health:
    security-health          or  security-manager health

  Update Virus DB:
    sudo freshclam           (manual virus definition update)

  System Updates:
    sudo apt upgrade -y      (Ubuntu/Debian)
    sudo dnf upgrade -y      (Amazon Linux)
```

---

## ⏰ Automation

### Scheduled Tasks

The system runs automatically via **cron jobs** in `/etc/cron.d/security-monitor`:

| Task | Schedule | Command | Description |
|------|----------|---------|-------------|
| **Daily Scans** | 2:00 AM | `security-monitor scan` | Full scan (virus DB + updates + malware) |
| **Health Checks** | Every 6 hours | `security-manager health` | Service monitoring & auto-healing |

### View Cron Schedule

```bash
# View the cron configuration
cat /etc/cron.d/security-monitor

# Output:
# 0 2 * * * root /usr/local/bin/security-monitor scan >/dev/null 2>&1
# 0 */6 * * * root /usr/local/bin/security-manager health >/dev/null 2>&1
```

### Manual Scheduling

To change scan schedule, edit the cron file:

```bash
# Edit cron schedule
sudo nano /etc/cron.d/security-monitor

# Change to 3:00 AM:
# 0 3 * * * root /usr/local/bin/security-monitor scan >/dev/null 2>&1

# Cron will automatically pick up changes (no restart needed)
```

---

## 🐧 Supported Systems

| OS | Version | Status | Notes |
|----|---------|--------|-------|
| **Ubuntu** | 20.04+ | ✅ Tested | Uses `unattended-upgrades` |
| **Ubuntu** | 24.04 | ✅ Tested | Production ready |
| **Debian** | 10+ | ✅ Supported | Uses `unattended-upgrades` |
| **Amazon Linux** | 2023 | ✅ Tested | Uses `dnf-automatic` |
| **Amazon Linux** | 2 | ✅ Supported | Uses `yum-cron` |

---

## 🔧 Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| **security-monitor.sh** | Main monitoring script | `/usr/local/bin/security-monitor` |
| **security-manager.sh** | Installation & health checks | `/usr/local/bin/security-manager` |
| **Shell functions** | Command shortcuts | `/etc/profile.d/security-monitor.sh` |
| **Cron jobs** | Automated scheduling | `/etc/cron.d/security-monitor` |
| **Status data** | Scan results & metrics | `/var/lib/security-monitor/status.json` |
| **Scan logs** | Detailed scan output | `/var/log/security-monitor/scan.log` |
| **ClamAV logs** | Virus DB updates | `/var/log/clamav/freshclam.log` |

---

## 🛠️ Management Commands

### Installation
```bash
# Install on new server
sudo ./security-manager.sh install

# Uninstall completely
sudo ./uninstall-security.sh

# Deploy to multiple servers
./deploy-multiple.sh
```

### Health & Diagnostics
```bash
# Full health check
security-health

# Check service status
sudo systemctl status clamav-daemon
sudo systemctl status clamav-freshclam

# View scheduled tasks
cat /etc/cron.d/security-monitor

# View logs
sudo tail -f /var/log/security-monitor/scan.log
sudo tail -f /var/log/clamav/freshclam.log

# Check virus database version
clamscan --version
```

### Updates
```bash
# Update scripts from GitHub
cd /usr/local/bin
sudo wget -O security-monitor.sh https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-monitor.sh
sudo wget -O security-manager.sh https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-manager.sh
sudo chmod +x security-monitor.sh security-manager.sh
```

---

## 🔒 Security Best Practices

### Permissions
- Scripts run with **root privileges** (sudo required for scans)
- Status viewing requires **no sudo** (read-only access)
- Log files readable by root only
- Configuration files protected with 644 permissions

### Network
- FreshClam updates virus definitions via HTTPS
- No incoming connections required
- Outbound: Port 443 for virus DB updates

### Data
- Scan results stored in JSON format
- No sensitive data logged
- Logs rotated automatically by system

---

## 📖 Shell Functions vs Aliases

This system uses **shell functions** instead of aliases for better compatibility:

### Why Functions?
- ✅ Work in all contexts (interactive, non-interactive, scripts)
- ✅ Support argument pass-through with `"$@"`
- ✅ No need for `shopt -s expand_aliases`
- ✅ Work immediately in new SSH sessions

### How They Work
```bash
# Function definition in /etc/profile.d/security-monitor.sh
security-status() { sudo /usr/local/bin/security-monitor status "$@"; }
security-scan() { sudo /usr/local/bin/security-monitor scan "$@"; }
```

### Usage in Scripts
Functions work directly in your scripts:
```bash
#!/bin/bash
# This works!
security-status

# This also works!
sudo security-scan quick
```

---

## 🧪 Testing & Verification

### Quick Test
```bash
# Test status (no sudo)
security-status

# Test scan (with sudo)
sudo security-scan

# Verify services
sudo systemctl status clamav-daemon
sudo systemctl status security-scan.timer
```

### Full Verification
```bash
# 1. Check functions are loaded
type security-status security-scan security-health

# 2. Run health check
sudo security-health

# 3. View dashboard
security-status

# 4. Check cron schedule
cat /etc/cron.d/security-monitor

# 5. Verify virus database
sudo /usr/bin/clamdscan --version
```

---

## 🐛 Troubleshooting

### Commands Not Found

```bash
# Option 1: Reload shell functions
source /etc/profile.d/security-monitor.sh

# Option 2: Start new shell
bash

# Option 3: Use direct paths
/usr/local/bin/security-monitor status
sudo /usr/local/bin/security-monitor scan
```

### ClamAV Not Running

```bash
# Check daemon status
sudo systemctl status clamav-daemon

# Start daemon (Ubuntu)
sudo systemctl start clamav-daemon

# On Amazon Linux (on-demand mode is normal)
# ClamAV runs automatically during scans
```

### Virus Database Issues

```bash
# Update manually
sudo freshclam

# Check logs
sudo tail -50 /var/log/clamav/freshclam.log

# Restart service
sudo systemctl restart clamav-freshclam
```

### Permission Denied

```bash
# Status viewing should work without sudo
security-status

# Scanning requires sudo
sudo security-scan

# If still fails, check script permissions
ls -la /usr/local/bin/security-*
```

---

## 📊 Performance

### Scan Times

| Scan Type | Files | Time | CPU | Memory |
|-----------|-------|------|-----|--------|
| **Quick Scan** | ~7,000 | 4-5 min | Low | ~200MB |
| **Full Scan** | ~50,000+ | 10-30 min | Medium | ~300MB |

### Resource Usage
- **Idle**: <10MB RAM
- **Scanning**: 200-300MB RAM
- **CPU**: Low priority (nice level 19)
- **Disk**: <50MB for logs and status

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test on Ubuntu and Amazon Linux
4. Submit a pull request

---

## 👤 Author

**Davide Caputo**
- GitHub: [@CaputoDavide93](https://github.com/CaputoDavide93)
- Repository: [linux-security-monitor](https://github.com/CaputoDavide93/linux-security-monitor)

---

## 📝 License

MIT License - See LICENSE file for details

---

## 🔄 Changelog

### v2.1.0 (2025-10-28)
- ✨ Converted aliases to shell functions for universal compatibility
- ✨ Enhanced dashboard with 6 detailed cards and progress bars
- ✨ Fixed auto-updates detection on both Ubuntu and Amazon Linux
- ✨ Improved error handling with `set -eo pipefail`
- ✨ Added comprehensive status indicators and freshness checks
- 🐛 Fixed ANSI escape code artifacts in output
- 🐛 Fixed clear command in non-interactive sessions
- 📝 Consolidated all documentation into single README

### v2.0.0 (2025-10-27)
- 🎨 Complete UI redesign with color-coded cards
- ♻️ Code refactoring: 906 → 808 lines (-11%)
- ✅ Modular architecture with 15+ single-responsibility functions
- 🔒 Enhanced error handling and input validation
- 📊 Added detailed compliance dashboard
- ⚡ Improved performance and reliability
