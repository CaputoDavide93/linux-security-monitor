# 🤝 Contributing

Thanks for your interest in improving EC2 - Linux Security Monitor.

---

## 🚀 Getting started

```bash
git clone https://github.com/YOUR_USERNAME/EC2-Linux-Security-Monitor.git
cd EC2-Linux-Security-Monitor
git checkout -b feature/your-feature
```

---

## 🧪 Before you open a PR

CI ([lint.yml](.github/workflows/lint.yml)) runs these on every push and PR. Run them
locally first — they're the whole gate:

```bash
shellcheck --severity=warning security-monitor.sh security-manager.sh
bash -n security-monitor.sh && bash -n security-manager.sh
bash -n security-monitor.conf && ( set -eu; . ./security-monitor.conf )
```

If you changed a schedule default, validate it:

```bash
systemd-analyze calendar "*-*-* 02:00:00"
```

There is **no automated test suite** — so exercising your change on a real host matters.
Ubuntu and Amazon Linux 2023 are the two supported targets; say in the PR which you tested
on. A cheap way to test a scan end to end without real malware is the EICAR test file:

```bash
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /root/eicar.txt
sudo security-monitor scan
```

---

## 📋 Code style

Both scripts are `set -euo pipefail` Bash. Beyond shellcheck:

- **Quote every expansion** — `"$var"`, `"${arr[@]}"`. Use arrays for argument lists, never
  a string you rely on word-splitting.
- **Never call a function inside `$(( ))`.** Bash treats the name as an unset variable, so
  the call silently evaluates to `0`. Use `func || rc=$?`.
- **Don't capture a function's stdout with `$(...)` if it also prints progress** — the
  progress disappears. Return values through a global instead.
- **`systemctl is-active` with multiple units is an AND**, and unit names differ per distro.
  Resolve the name through `clamd_unit()`.
- **Capture exit codes with `cmd || rc=$?`**, not `if ! cmd; then rc=$?`, which yields the
  status of the negation (always `0`).
- **New tunables go in [security-monitor.conf](security-monitor.conf)** with a default in
  both scripts' header block. Never hardcode a value the dashboard also displays.

### The documentation rule

**The dashboard and the README must never state something the code doesn't check.** No
hardcoded dates, no placeholder status text, no fabricated "Type: all packages current"
lines. If a value can't be determined, say `unknown` — don't invent a plausible one.

---

## 📝 Commits

```text
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `chore`.

---

## 🐛 Bug reports

Include the distribution and version, `bash --version`, `security-monitor version`, the
exact command, and what you expected versus what happened. For scheduling problems add
`systemctl list-timers 'security-monitor-*'` and
`journalctl -u security-monitor-scan.service`.

---

## 💡 Feature requests

Open an issue with the use case, the security benefit, and which distros it would affect.

---

## 🔒 Security issues

Don't open a public issue — see [SECURITY.md](SECURITY.md).
