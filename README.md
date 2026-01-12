<div align="center">

# 🛡️ Linux Security Monitor

> **Comprehensive security monitoring and hardening toolkit for Linux servers**

![Shell](https://img.shields.io/badge/Shell-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Security](https://img.shields.io/badge/Security-FF0000?style=for-the-badge&logo=hackaday&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

[Features](#-features) • [Quick Start](#-quick-start) • [Configuration](#️-configuration) • [Contributing](#-contributing)

</div>

---

## 📑 Table of Contents

- [✨ Features](#-features)
- [📋 Prerequisites](#-prerequisites)
- [🚀 Quick Start](#-quick-start)
- [📖 Scripts Overview](#-scripts-overview)
- [⚙️ Configuration](#️-configuration)
- [🔒 Security Checks](#-security-checks)
- [📊 Reports](#-reports)
- [🐛 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)
- [👤 Author](#-author)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔍 **System Audit** | Comprehensive security scanning |
| 🛡️ **Hardening** | Automated security hardening |
| 📊 **Reporting** | Detailed security reports |
| 🔐 **User Audit** | User and permission analysis |
| 🌐 **Network Scan** | Open port and service detection |
| 📝 **Logging** | Centralized security logging |
| ⚡ **Lightweight** | Pure shell scripts, no dependencies |
| 🔄 **Automated** | Cron-ready for scheduled monitoring |

---

## 📋 Prerequisites

| Requirement | Version |
|-------------|---------|
| Linux | Any modern distro |
| Bash | 4.0+ |
| Root Access | Required for full functionality |

### Tested Distributions

- ✅ Ubuntu 20.04 / 22.04
- ✅ Debian 11 / 12
- ✅ CentOS 7 / 8
- ✅ RHEL 8 / 9
- ✅ Fedora 36+

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/CaputoDavide93/linux-security-monitor.git
cd linux-security-monitor
```

### 2. Make Scripts Executable

```bash
chmod +x security-monitor.sh security-manager.sh
```

### 3. Run Security Monitor

```bash
sudo ./security-monitor.sh
```

### 4. Run Security Manager (Interactive)

```bash
sudo ./security-manager.sh
```

---

## 📖 Scripts Overview

### security-monitor.sh

Comprehensive security monitoring script that:

- Scans for security vulnerabilities
- Checks file permissions
- Audits user accounts
- Analyzes network configuration
- Generates detailed reports

```bash
# Full security scan
sudo ./security-monitor.sh --full

# Quick scan
sudo ./security-monitor.sh --quick

# Generate report
sudo ./security-monitor.sh --report /var/log/security-report.txt
```

### security-manager.sh

Interactive security management tool for:

- Applying security hardening
- Managing firewall rules
- Configuring security policies
- Scheduling automated scans

```bash
# Interactive mode
sudo ./security-manager.sh

# Apply hardening profile
sudo ./security-manager.sh --harden basic

# Check compliance
sudo ./security-manager.sh --compliance cis
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_DIR` | Log directory | `/var/log/security` |
| `REPORT_DIR` | Report output directory | `/var/log/security/reports` |
| `EMAIL_ALERTS` | Email for alerts | - |
| `SEVERITY_LEVEL` | Min severity to report | `medium` |
| `QUIET_MODE` | Suppress output | `false` |

### Configuration File

Create `/etc/security-monitor.conf`:

```bash
# Security Monitor Configuration
LOG_DIR="/var/log/security"
REPORT_DIR="/var/log/security/reports"
EMAIL_ALERTS="security@example.com"
SEVERITY_LEVEL="medium"  # low, medium, high, critical

# Scan Options
SCAN_USERS=true
SCAN_NETWORK=true
SCAN_FILESYSTEM=true
SCAN_SERVICES=true

# Hardening Options
DISABLE_ROOT_SSH=true
ENFORCE_STRONG_PASSWORDS=true
ENABLE_FAIL2BAN=true
```

---

## 🔒 Security Checks

### User & Access

| Check | Description |
|-------|-------------|
| Root Login | SSH root access disabled |
| Empty Passwords | No accounts without passwords |
| Sudo Access | Validate sudoers configuration |
| Failed Logins | Detect brute force attempts |
| Inactive Users | Find dormant accounts |

### Network

| Check | Description |
|-------|-------------|
| Open Ports | Identify listening services |
| Firewall Status | Verify firewall is active |
| SSH Config | Secure SSH configuration |
| Network Services | Audit running services |

### Filesystem

| Check | Description |
|-------|-------------|
| World Writable | Find insecure permissions |
| SUID/SGID | Locate privilege escalation risks |
| Sensitive Files | Check /etc/passwd, /etc/shadow |
| Mounted Drives | Verify mount options |

### System

| Check | Description |
|-------|-------------|
| Kernel Version | Check for known vulnerabilities |
| Updates | Pending security updates |
| Running Processes | Suspicious process detection |
| Cron Jobs | Audit scheduled tasks |

---

## 📊 Reports

### Report Types

```bash
# Text report
sudo ./security-monitor.sh --report-format text

# JSON report (for automation)
sudo ./security-monitor.sh --report-format json

# HTML report
sudo ./security-monitor.sh --report-format html
```

### Sample Report Output

```
═══════════════════════════════════════════════════════
             SECURITY AUDIT REPORT
═══════════════════════════════════════════════════════
Generated: 2024-01-12 10:30:00
Hostname:  production-server-01
═══════════════════════════════════════════════════════

[CRITICAL] 2 issues found
[HIGH]     5 issues found
[MEDIUM]   12 issues found
[LOW]      8 issues found

─────────────────────────────────────────────────────
CRITICAL FINDINGS:
─────────────────────────────────────────────────────
❌ Root SSH login is enabled
❌ 3 accounts have empty passwords
...
```

---

## ⏰ Automated Monitoring

### Cron Setup

```bash
# Edit crontab
sudo crontab -e

# Daily security scan at 2 AM
0 2 * * * /opt/linux-security-monitor/security-monitor.sh --full --email

# Weekly full report
0 3 * * 0 /opt/linux-security-monitor/security-monitor.sh --report /var/log/security/weekly-report.txt
```

---

## 🐛 Troubleshooting

### Common Issues

<details>
<summary>❌ Permission Denied</summary>

```bash
# Run with sudo
sudo ./security-monitor.sh

# Or fix permissions
chmod +x security-monitor.sh
```
</details>

<details>
<summary>❌ Command Not Found</summary>

Some checks require additional tools:
```bash
# Debian/Ubuntu
sudo apt install net-tools procps

# RHEL/CentOS
sudo yum install net-tools procps-ng
```
</details>

<details>
<summary>❌ Report Not Generated</summary>

```bash
# Check log directory permissions
sudo mkdir -p /var/log/security
sudo chmod 755 /var/log/security
```
</details>

---

## 🧪 Testing

See [TEST-GUIDE.txt](TEST-GUIDE.txt) for testing instructions:

```bash
# Run in test mode (no changes)
./security-monitor.sh --dry-run

# Verbose output
./security-monitor.sh --verbose
```

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

## 👤 Author

**Davide Caputo**

[![GitHub](https://img.shields.io/badge/GitHub-CaputoDavide93-181717?style=for-the-badge&logo=github)](https://github.com/CaputoDavide93)
[![Email](https://img.shields.io/badge/Email-CaputoDav%40gmail.com-EA4335?style=for-the-badge&logo=gmail&logoColor=white)](mailto:CaputoDav@gmail.com)

---

⭐ **If this tool helped you, please give it a star!** ⭐

</div>
