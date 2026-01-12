# Security Policy

## 🔒 Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | ✅ Yes    |
| < Latest| ❌ No     |

## 🛡️ Reporting a Vulnerability

**Do NOT create a public GitHub issue for security vulnerabilities.**

This is especially important for a security-focused tool.

Please email: **CaputoDav@gmail.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

| Timeframe | Action |
|-----------|--------|
| 24 hours | Acknowledgment |
| 72 hours | Initial assessment |
| 7 days | Status update |
| 30 days | Resolution target |

## 🔐 Security Best Practices

### For Users

1. **Run with minimum required privileges** when possible
2. **Review scripts** before running on production systems
3. **Keep the tool updated** for latest security checks
4. **Secure report files** - they contain system information
5. **Use encrypted channels** when sending reports

### Script Security

```bash
# ❌ Bad - Running without review
curl https://... | sudo bash

# ✅ Good - Download, review, then run
git clone https://github.com/CaputoDavide93/linux-security-monitor.git
less security-monitor.sh  # Review the code
sudo ./security-monitor.sh
```

## ✅ Security Checklist

- [ ] Running latest version of the scripts
- [ ] Report files have restricted permissions (600)
- [ ] Cron job logs are secured
- [ ] Email alerts use encrypted transport
- [ ] Scripts are verified after download

---

Thank you for helping keep this project secure! 🙏
