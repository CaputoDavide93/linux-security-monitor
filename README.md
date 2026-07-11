<div align="center">

# 🛡️ EC2 - Linux Security Monitor

**ClamAV malware scanning, automatic security updates, and a terminal status dashboard for systemd Linux — built for EC2, tested on Ubuntu and Amazon Linux**

![Shell](https://img.shields.io/badge/Shell-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![ClamAV](https://img.shields.io/badge/ClamAV-FF0000?style=for-the-badge&logo=hackaday&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

[Features](#-features) • [Quick Start](#-quick-start) • [Usage](#-usage) • [Contributing](#-contributing)

</div>

---

## ✨ Features

| | Feature | What it does |
|---|---------|--------------|
| 🦠 | **ClamAV scanning** | Quick (30–90 s) or full (10–30 min) `clamscan` malware sweeps |
| 🔄 | **Auto updates** | Applies pending security updates during every scan (apt / dnf) |
| 🧬 | **Fresh definitions** | Runs `freshclam` before each scan and keeps the freshclam service healthy |
| 📊 | **Status dashboard** | Terminal dashboard: last scan, infected count, services, virus DB, updates |
| ⏰ | **Scheduled scans** | Installer drops a cron file — daily full scan at 02:00, health check every 6 h |
| 🩺 | **Self-healing health check** | Restarts dead services and refreshes stale virus definitions (> 7 days) |
| 📦 | **One-command install** | `security-manager.sh install` sets up packages, services, cron, and shell shortcuts |
| 📝 | **Logging** | Everything logged under `/var/log/security-monitor/`, scan status as JSON |

---

## 📋 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux + systemd | Services are managed with `systemctl` |
| Bash 4.0+ | Both scripts are pure Bash |
| Root access | `install`, `uninstall`, `health`, and `scan` all need `sudo` |
| Internet access | To download ClamAV packages and virus definitions |

### Supported distributions

The installer validates the OS and supports:

- ✅ Ubuntu / Debian (`apt`, `unattended-upgrades`)
- ✅ Amazon Linux 2023 (`dnf`, `dnf-automatic`)

Anything else exits with `Unsupported operating system`.

---

## 🚀 Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/CaputoDavide93/EC2-Linux-Security-Monitor.git
cd EC2-Linux-Security-Monitor
```

### 2. Make the scripts executable

```bash
chmod +x security-monitor.sh security-manager.sh
```

### 3. Install

```bash
sudo ./security-manager.sh install
```

The installer:

1. Installs ClamAV, `jq`, `curl`, and the distro's auto-update tooling
2. Configures `freshclam` and the ClamAV daemon
3. Enables automatic security updates (`unattended-upgrades` / `dnf-automatic`)
4. Creates `/etc/cron.d/security-monitor` (daily scan + 6-hourly health check)
5. Installs the monitor to `/usr/local/bin/security-monitor`
6. Adds shell shortcuts: `security-status`, `security-scan`, `security-health`

Then reload your shell to pick up the shortcuts:

```bash
source /etc/profile.d/security-monitor.sh
```

### 4. Run your first scan

```bash
sudo security-monitor scan        # quick scan (default)
security-monitor status           # dashboard
```

---

## 📖 Usage

### security-monitor.sh

```text
Usage: security-monitor [scan|status]

  scan [quick|full]   Run a security scan (default: quick)
  status              Show the status dashboard (default)
```

Every scan runs three steps:

1. **Update virus definitions** — `freshclam` (pausing the service to avoid lock conflicts)
2. **Apply system updates** — `apt-get upgrade` or `dnf upgrade`, security-focused
3. **Scan for malware** — `clamscan -r -i`, excluding `/sys`, `/proc`, `/dev`, `.git`, `node_modules`, `.cache`

| Mode | Paths | Typical duration |
|------|-------|------------------|
| `quick` (default) | `/home /root` (file-size and recursion limits) | 30–90 seconds |
| `full` | `/home /root /opt /tmp /var /usr/local` | 10–30 minutes |

Results are written to `/var/lib/security-monitor/status.json` and scan logs to
`/var/log/security-monitor/scan-<timestamp>.log`.

```bash
sudo security-monitor scan          # quick scan
sudo security-monitor scan full     # full scan
security-monitor status             # dashboard (also the default with no args)
```

The `status` dashboard shows: scan status and freshness, compliance indicator,
pending updates, ClamAV service state, virus database state, and quick actions.

### security-manager.sh

```text
Usage: security-manager.sh [install|uninstall|health]

  install     Install the security monitoring system
  uninstall   Remove the security monitoring system
  health      Perform a health check

Run without arguments for an interactive menu.
```

```bash
sudo ./security-manager.sh            # interactive menu
sudo ./security-manager.sh install    # non-interactive install
sudo ./security-manager.sh health     # check & self-heal services, defs, cron
sudo ./security-manager.sh uninstall  # remove (asks for confirmation)
```

`health` verifies — and where possible repairs — the freshclam service, the
ClamAV daemon, virus-definition age (re-downloads if older than 7 days), the
cron file, and the installed scripts.

`uninstall` removes the cron jobs, installed scripts, shell shortcuts, data,
and logs. **ClamAV packages stay installed**; remove them separately with
`apt-get remove --purge 'clamav*'` or `dnf remove 'clamav*'`.

---

## ⏰ Automated Monitoring

`install` creates `/etc/cron.d/security-monitor` for you:

```bash
# Daily full scan at 2:00 AM
0 2 * * * root /usr/local/bin/security-monitor scan full >/dev/null 2>&1

# Health check every 6 hours
0 */6 * * * root /usr/local/bin/security-manager health >/dev/null 2>&1
```

Adjust the schedule by editing that file — the commands above are the only
ones you need.

---

## 🐛 Troubleshooting

<details>
<summary>❌ Permission denied / "Root privileges required"</summary>

All commands except `status` need root:

```bash
sudo ./security-manager.sh install
sudo security-monitor scan
```
</details>

<details>
<summary>⚠ "Freshclam had issues (may be in cooldown)"</summary>

ClamAV rate-limits definition downloads. The scan continues with the current
database and freshclam retries automatically. Check progress with:

```bash
sudo tail /var/log/clamav/freshclam.log
```
</details>

<details>
<summary>❌ Dashboard says "No scan data available"</summary>

The dashboard reads `/var/lib/security-monitor/status.json`, which is created
by the first scan (and requires `jq`, installed by `install`):

```bash
sudo security-monitor scan
```
</details>

<details>
<summary>❌ "Unsupported operating system"</summary>

The installer only supports Ubuntu, Debian, and Amazon Linux (`dnf`). On other
distributions the package and service names differ, so `install` refuses to run.
</details>

---

## 🧪 Testing

There is no automated test suite. Before opening a PR, lint both scripts:

```bash
shellcheck security-monitor.sh security-manager.sh
bash -n security-monitor.sh && bash -n security-manager.sh
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
