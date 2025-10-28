# 🛡️ Linux Security Monitor

Automated security scanning and monitoring system for Ubuntu/Debian and Amazon Linux servers with ClamAV antivirus, automatic updates, and a beautiful status dashboard.

## ✨ Features

- 🦠 **ClamAV Antivirus** - Automated virus definition updates and malware scanning
- 🔄 **Automatic Updates** - Security and system updates applied automatically
- 📊 **Status Dashboard** - Color-coded cards showing security status at a glance
- ⏰ **Scheduled Scans** - Daily scans at 2:00 AM via cron
- 🔧 **Health Monitoring** - Service checks every 6 hours
- 💻 **Easy Commands** - Simple aliases for all operations
- 🎨 **Beautiful UI** - Clean terminal dashboard with status cards

## 🚀 Quick Start

### Installation

```bash
# Download the scripts
wget https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-manager.sh
wget https://raw.githubusercontent.com/CaputoDavide93/linux-security-monitor/main/security-monitor.sh

# Make executable
chmod +x security-manager.sh security-monitor.sh

# Install (works on Ubuntu/Debian/Amazon Linux)
sudo ./security-manager.sh install

# Activate aliases
source /etc/profile.d/security-monitor.sh
```

## 📋 Usage

### View Security Status
```bash
security-status
```

### Run Manual Scan
```bash
sudo security-scan
```

### Check System Health
```bash
sudo security-health
```

## 📊 Dashboard

The status dashboard shows 5 detailed cards with real-time security information.

## ⏰ Automation

- **Daily Scans**: 2:00 AM - Full scan (virus DB + updates + malware scan)
- **Health Checks**: Every 6 hours - Service monitoring

## 🐧 Supported Systems

- ✅ Ubuntu 20.04+
- ✅ Debian 10+
- ✅ Amazon Linux 2023
- ✅ Amazon Linux 2

## 👤 Author

**Davide Caputo**
- GitHub: [@CaputoDavide93](https://github.com/CaputoDavide93)

## 📝 License

MIT License
