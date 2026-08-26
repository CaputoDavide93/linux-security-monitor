# 🔒 Security Policy

## 🛡️ Reporting a vulnerability

**Do not open a public issue for a security vulnerability.** This matters more than usual
here: the tool runs as root on every host that installs it.

Report privately via
[GitHub Security Advisories](https://github.com/CaputoDavide93/EC2-Linux-Security-Monitor/security/advisories/new).

Please include the affected script and version (`security-monitor version`), the
distribution, what an attacker could achieve, and a reproduction if you have one.

---

## ⚠️ What this tool does to a host

Read this before installing. `security-manager install` is not a read-only operation:

| Action | Where |
|---|---|
| Runs as **root**, on a timer, unattended | `security-monitor-scan.timer`, `security-monitor-health.timer` |
| **Applies package updates** without confirmation | `apt-get upgrade` / `dnf upgrade` during every scan |
| Enables unattended security updates | `unattended-upgrades` / `dnf-automatic.timer` |
| **Moves files** flagged by ClamAV out of their original location | `$QUARANTINE_DIR` |
| Overwrites ClamAV and auto-update configuration | `/etc/clamav/`, `/etc/clamd.d/scan.conf`, `/etc/freshclam.conf`, `/etc/apt/apt.conf.d/50unattended-upgrades`, `/etc/dnf/automatic.conf` |
| Installs shell functions for all users | `/etc/profile.d/security-monitor.sh` and each `~/.bashrc` |
| Executes an operator-supplied command | `ALERT_COMMAND`, when a scan finds something |

Review both scripts before running them:

```bash
# ❌ Never
curl https://... | sudo bash

# ✅ Clone, read, then run
git clone https://github.com/CaputoDavide93/EC2-Linux-Security-Monitor.git
cd EC2-Linux-Security-Monitor
less security-monitor.sh security-manager.sh
sudo ./security-manager.sh install
```

---

## 🗂️ Data handling

- **No telemetry.** Nothing is sent anywhere unless *you* configure `ALERT_COMMAND`.
- **Scan logs** (`/var/log/security-monitor/scan-*.log`) contain absolute paths of scanned
  and infected files — that is a map of the filesystem. Treat them as confidential. They are
  pruned after `LOG_RETENTION_DAYS` (default 30).
- **`status.json`** is written `0640` and holds counts and timestamps only.
- **Quarantine** (`$QUARANTINE_DIR`, `0700`, root-owned) contains **live malware**. Files are
  moved rather than deleted so false positives are recoverable — which means the directory is
  hostile. Don't back it up to shared storage, don't copy files out of it to inspect them on
  a workstation, and remember `uninstall` deletes it (it warns first if it isn't empty).
- **`ALERT_COMMAND`** is run via `sh -c` as root with the findings on stdin. It is arbitrary
  code from the config file, and the findings include infected file paths — so anything you
  pipe them to receives sensitive data. Keep its credentials out of the config file; use an
  instance role or a file readable only by root.
- **No secrets are stored by this project.** The config file holds no credentials, and
  nothing in the repo contains real values.

---

## ✅ Hardening checklist

- [ ] Both scripts reviewed before install
- [ ] `/var/log/security-monitor/` and `/var/lib/security-monitor/` are not world-readable
- [ ] `QUARANTINE_ENABLED` set deliberately — `no` if an application might depend on a
      flagged file, `yes` to contain what's found
- [ ] `ALERT_COMMAND` configured, and tested with the EICAR test file
- [ ] Unattended updates acceptable for this host (they can restart services)
- [ ] Quarantine directory excluded from backups
- [ ] Running the latest commit on `main`

---

## Supported versions

Only the latest commit on `main` is supported.
