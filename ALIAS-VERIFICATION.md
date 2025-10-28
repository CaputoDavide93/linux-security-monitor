# Alias Verification Guide

## ✅ Aliases Status

### Installed Aliases
All three aliases are properly installed on both servers:

```bash
# /etc/profile.d/security-monitor.sh
alias security-status="sudo /usr/local/bin/security-monitor status"
alias security-scan="sudo /usr/local/bin/security-monitor scan"
alias security-health="sudo /usr/local/bin/security-manager health"
```

---

## 🧪 Verification Steps

### **Ubuntu 24.04** (ec2-54-247-169-52)

```bash
# SSH into server
ssh -i ~/.ssh/snipe-it.pem ubuntu@ec2-54-247-169-52.eu-west-1.compute.amazonaws.com

# Check aliases (in interactive shell)
alias | grep security

# Test commands directly (these always work)
sudo /usr/local/bin/security-monitor status
sudo /usr/local/bin/security-monitor scan quick
sudo /usr/local/bin/security-manager health
```

### **Amazon Linux 2023** (ec2-52-50-220-209)

```bash
# SSH into server
ssh -i ~/.ssh/techops-cron-script.pem ec2-user@ec2-52-50-220-209.eu-west-1.compute.amazonaws.com

# Check aliases (in interactive shell)
alias | grep security

# Test commands directly (these always work)
sudo /usr/local/bin/security-monitor status
sudo /usr/local/bin/security-monitor scan quick
sudo /usr/local/bin/security-manager health
```

---

## 📋 Alias Usage

### For **New SSH Sessions**

Aliases work automatically in **new interactive shells**:

```bash
# After SSH login
security-status          # ✅ Works
security-scan            # ✅ Works  
security-health          # ✅ Works
```

### For **Current SSH Sessions**

If you were already logged in during installation, reload the shell:

```bash
# Option 1: Reload profile
source /etc/profile.d/security-monitor.sh

# Option 2: Start new shell
bash

# Option 3: Re-login
exit
# Then SSH back in
```

### For **Scripts or Cron Jobs**

Aliases don't work in non-interactive contexts. Use full paths:

```bash
#!/bin/bash
# ❌ This won't work in scripts
security-status

# ✅ Use full paths instead
sudo /usr/local/bin/security-monitor status
```

---

##  Verification Results

### Ubuntu 24.04 ✅

| Command | Status | Notes |
|---------|--------|-------|
| **security-status** | ✅ Working | Alias properly defined |
| **security-scan** | ✅ Working | Alias properly defined |
| **security-health** | ✅ Working | Alias properly defined |
| Direct commands | ✅ Working | `/usr/local/bin/security-monitor` |

**Alias File:** `/etc/profile.d/security-monitor.sh` ✅  
**Script Location:** `/usr/local/bin/security-monitor` ✅  
**Permissions:** `755 (executable)` ✅

### Amazon Linux 2023 ✅

| Command | Status | Notes |
|---------|--------|-------|
| **security-status** | ✅ Working | Alias properly defined |
| **security-scan** | ✅ Working | Alias properly defined |
| **security-health** | ✅ Working | Alias properly defined |
| Direct commands | ✅ Working | `/usr/local/bin/security-monitor` |

**Alias File:** `/etc/profile.d/security-monitor.sh` ✅  
**Script Location:** `/usr/local/bin/security-monitor` ✅  
**Permissions:** `755 (executable)` ✅

---

## 🔍 Troubleshooting

### "command not found" Error

**Cause:** Aliases not loaded in current shell session.

**Solution:**
```bash
# Reload the shell configuration
source /etc/profile.d/security-monitor.sh

# Or exit and SSH back in
exit
```

### Aliases Not Working in Scripts

**Cause:** Bash doesn't expand aliases in non-interactive mode.

**Solution:** Use full paths:
```bash
# Instead of:
security-status

# Use:
sudo /usr/local/bin/security-monitor status
```

### Permission Denied

**Cause:** Commands require sudo privileges.

**Solution:** The aliases already include `sudo`, but if you removed it:
```bash
sudo security-monitor status
sudo security-monitor scan
sudo security-manager health
```

---

## 📦 Manual Testing Commands

### Test 1: View Security Status
```bash
# Using alias (in interactive shell)
security-status

# Using full path (works everywhere)
sudo /usr/local/bin/security-monitor status
```

**Expected Output:**
- Dashboard with 6 cards
- No escape code artifacts
- Color-coded status indicators

### Test 2: Run Quick Scan
```bash
# Using alias (in interactive shell)
security-scan

# Using full path (works everywhere)
sudo /usr/local/bin/security-monitor scan quick
```

**Expected Output:**
- [1/3] Updating virus definitions
- [2/3] Applying system updates  
- [3/3] Scanning for malware
- Scan summary with file counts

### Test 3: Check System Health
```bash
# Using alias (in interactive shell)
security-health

# Using full path (works everywhere)
sudo /usr/local/bin/security-manager health
```

**Expected Output:**
- Service status checks
- Virus definition checks
- Automation checks
- Cron job verification

---

## ✅ Conclusion

**Status:** All aliases are properly installed and functional on both servers.

**Working Methods:**
1. ✅ Aliases in new interactive SSH sessions
2. ✅ Aliases after sourcing `/etc/profile.d/security-monitor.sh`
3. ✅ Direct commands using full paths (always work)

**Important Note:** For automated tasks (cron, scripts), always use full paths:
- `/usr/local/bin/security-monitor`
- `/usr/local/bin/security-manager`

Aliases are convenience wrappers for interactive use only.
