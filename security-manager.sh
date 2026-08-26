#!/bin/bash
################################################################################
# 🛡️  Security Manager - Installation and Health Management
# Version: 3.0.0
# Description: Installs, configures, and maintains security monitoring system
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly VERSION="3.0.0"
readonly CONFIG_DIR="/etc/security-monitor"
readonly CONFIG_FILE="$CONFIG_DIR/security-monitor.conf"
readonly SCRIPT_DIR="/usr/local/bin"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly LOGROTATE_FILE="/etc/logrotate.d/security-monitor"
readonly LEGACY_CRON_FILE="/etc/cron.d/security-monitor"

readonly SCAN_TIMER="security-monitor-scan.timer"
readonly HEALTH_TIMER="security-monitor-health.timer"

# Defaults. Overridable via CONFIG_FILE once installed.
SECURITY_DIR="/var/lib/security-monitor"
LOG_DIR="/var/log/security-monitor"
QUARANTINE_DIR=""
SCAN_SCHEDULE="*-*-* 02:00:00"
HEALTH_SCHEDULE="*-*-* 00/6:00:00"
SCAN_MODE="full"
DB_MAX_AGE_DAYS="7"
LOG_RETENTION_DAYS="30"

# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"

: "${QUARANTINE_DIR:="$SECURITY_DIR/quarantine"}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly GRAY='\033[0;90m'

# Runtime state
OS="unknown"
VER="unknown"
STEP=0
readonly TOTAL_STEPS=9

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

detect_os() {
    if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-unknown}"
        VER="${VERSION_ID:-unknown}"
    fi
}

# The ClamAV daemon unit name differs per distro. Returns empty when unknown.
clamd_unit() {
    case "$OS" in
        ubuntu|debian) echo "clamav-daemon" ;;
        amzn|rhel|centos|fedora) echo "clamd@scan" ;;
        *) echo "" ;;
    esac
}

print_header() {
    local title="$1"
    local subtitle="${2:-}"

    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $title${NC}"
    [ -n "$subtitle" ] && echo -e "${CYAN}  $subtitle${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════${NC}"
    echo ""
}

# Advances the install progress counter so step numbers can never drift.
next_step() {
    STEP=$((STEP + 1))
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS] $1...${NC}"
}

show_status() {
    local level="$1"
    local message="$2"

    case "$level" in
        success) echo -e "${GREEN}✓ $message${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $message${NC}" ;;
        error)   echo -e "${RED}✗ $message${NC}" ;;
        *)       echo "$message" ;;
    esac
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        show_status "error" "Root privileges required"
        echo "Run: sudo $0 ${1:-}"
        exit 1
    fi
}

log_message() {
    local level="$1"
    shift
    [ -w "$LOG_DIR" ] || return 0
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_DIR/manager.log"
}

# Runs a command in the background with a spinner, returning its exit code.
# The command's output goes to $log; the spinner goes to the terminal.
run_with_spinner() {
    local log="$1"
    shift
    # shellcheck disable=SC1003  # literal backslash is an intended spinner frame
    local frames='|/-\'
    local i=0
    local rc=0
    local pid

    "$@" >> "$log" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s' "${frames:i++%4:1}"
        sleep 0.2
    done
    printf '\r   \r'

    wait "$pid" || rc=$?
    return $rc
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

install_packages() {
    local log="$LOG_DIR/install.log"
    echo "=== Installation $(date) ===" >> "$log"

    case "$OS" in
        ubuntu|debian) install_ubuntu_packages "$log" ;;
        amzn|rhel|centos|fedora) install_amazon_packages "$log" ;;
        *)
            show_status "error" "Unsupported OS: $OS"
            return 1
            ;;
    esac

    if command -v clamscan &>/dev/null && command -v jq &>/dev/null; then
        show_status "success" "Packages installed"
        log_message "INFO" "Package installation successful"
        return 0
    fi

    show_status "error" "Installation verification failed (see $log)"
    log_message "ERROR" "Package installation failed"
    return 1
}

install_ubuntu_packages() {
    local log="$1"

    next_step "Updating package lists"
    run_with_spinner "$log" apt-get update -qq \
        || show_status "warning" "Package list update reported errors"

    next_step "Installing ClamAV and dependencies"
    run_with_spinner "$log" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -qq \
        clamav clamav-daemon clamav-freshclam \
        unattended-upgrades jq curl \
        || show_status "warning" "Package install reported errors"
}

install_amazon_packages() {
    local log="$1"

    next_step "Checking for updates"
    dnf check-update -q >> "$log" 2>&1 || true

    next_step "Installing ClamAV and dependencies"
    run_with_spinner "$log" dnf install -y -q \
        clamav clamd clamav-update jq dnf-automatic curl \
        --allowerasing \
        || show_status "warning" "Package install reported errors"
}

# ============================================================================
# CLAMAV CONFIGURATION
# ============================================================================

configure_clamav() {
    next_step "Configuring ClamAV"

    case "$OS" in
        ubuntu|debian) configure_clamav_ubuntu ;;
        amzn|rhel|centos|fedora) configure_clamav_amazon ;;
    esac

    show_status "success" "ClamAV configured"
    log_message "INFO" "ClamAV configuration completed"
}

configure_clamav_ubuntu() {
    systemctl stop clamav-freshclam 2>/dev/null || true
    sleep 1

    if [ -f /etc/clamav/freshclam.conf ]; then
        sed -i 's/^Example/#Example/' /etc/clamav/freshclam.conf
    fi

    echo "  Downloading virus definitions..."
    freshclam 2>&1 | tail -5 || show_status "warning" "Freshclam in cooldown (will retry automatically)"

    systemctl enable --now clamav-freshclam 2>/dev/null || true
    systemctl enable --now clamav-daemon 2>/dev/null || true

    verify_clamd_started
}

configure_clamav_amazon() {
    systemctl stop clamav-freshclam 2>/dev/null || true
    sleep 1

    if [ -f /etc/freshclam.conf ]; then
        sed -i 's/^Example/#Example/' /etc/freshclam.conf
        grep -q "^DatabaseDirectory" /etc/freshclam.conf || \
            echo "DatabaseDirectory /var/lib/clamav" >> /etc/freshclam.conf
    fi

    mkdir -p /var/lib/clamav /var/run/clamd.scan
    chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true

    cat > /etc/tmpfiles.d/clamd.scan.conf <<'EOF'
d /var/run/clamd.scan 0755 clamscan clamscan -
EOF
    systemd-tmpfiles --create 2>/dev/null || true

    cat > /etc/clamd.d/scan.conf <<'EOF'
LogSyslog yes
PidFile /var/run/clamd.scan/clamd.pid
DatabaseDirectory /var/lib/clamav
LocalSocket /var/run/clamd.scan/clamd.sock
User clamscan
ScanMail yes
ScanArchive yes
EOF

    echo "  Downloading virus definitions..."
    freshclam 2>&1 | tail -5 || show_status "warning" "Freshclam will retry automatically"

    systemctl enable --now clamav-freshclam 2>/dev/null || true
    systemctl enable --now clamd@scan 2>/dev/null || true

    verify_clamd_started
}

verify_clamd_started() {
    local unit
    unit=$(clamd_unit)
    [ -n "$unit" ] || return 0

    sleep 3
    if ! systemctl is-active --quiet "$unit" 2>/dev/null; then
        show_status "warning" "ClamAV daemon starting (may take 10-20 seconds)..."
        systemctl restart "$unit" 2>/dev/null || true
    fi
}

# ============================================================================
# AUTO-UPDATE CONFIGURATION
# ============================================================================

configure_auto_updates() {
    next_step "Configuring automatic updates"

    case "$OS" in
        ubuntu|debian) configure_ubuntu_updates ;;
        amzn|rhel|centos|fedora) configure_amazon_updates ;;
    esac

    show_status "success" "Auto-updates configured"
    log_message "INFO" "Auto-updates configured"
}

configure_ubuntu_updates() {
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    systemctl enable --now unattended-upgrades 2>/dev/null || true
}

configure_amazon_updates() {
    cat > /etc/dnf/automatic.conf <<'EOF'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
EOF

    systemctl enable --now dnf-automatic.timer 2>/dev/null || true
}

# ============================================================================
# CONFIG FILE
# ============================================================================

install_config_file() {
    next_step "Installing configuration"

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_FILE" ]; then
        show_status "success" "Existing config kept ($CONFIG_FILE)"
        return 0
    fi

    local source_conf
    source_conf="$(dirname "$(readlink -f "$0")")/security-monitor.conf"

    if [ -f "$source_conf" ]; then
        cp "$source_conf" "$CONFIG_FILE"
    else
        cat > "$CONFIG_FILE" <<EOF
# Security Monitor configuration
SECURITY_DIR="$SECURITY_DIR"
LOG_DIR="$LOG_DIR"
QUARANTINE_ENABLED="yes"
ALERT_COMMAND=""
SCAN_SCHEDULE="$SCAN_SCHEDULE"
HEALTH_SCHEDULE="$HEALTH_SCHEDULE"
SCAN_MODE="$SCAN_MODE"
DB_MAX_AGE_DAYS="$DB_MAX_AGE_DAYS"
LOG_RETENTION_DAYS="$LOG_RETENTION_DAYS"
EOF
    fi

    chmod 644 "$CONFIG_FILE"
    show_status "success" "Config installed ($CONFIG_FILE)"
    log_message "INFO" "Config installed"
}

install_logrotate() {
    next_step "Configuring log rotation"

    cat > "$LOGROTATE_FILE" <<EOF
$LOG_DIR/monitor.log $LOG_DIR/manager.log $LOG_DIR/install.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

    chmod 644 "$LOGROTATE_FILE"
    show_status "success" "Log rotation configured"
    log_message "INFO" "Logrotate configured"
}

# ============================================================================
# SCRIPT INSTALLATION
# ============================================================================

install_scripts() {
    next_step "Installing scripts"

    local src_dir
    src_dir="$(dirname "$(readlink -f "$0")")"

    local name
    for name in security-monitor security-manager; do
        if [ ! -f "$src_dir/$name.sh" ]; then
            show_status "error" "$name.sh not found in $src_dir"
            log_message "ERROR" "Source script missing: $src_dir/$name.sh"
            return 1
        fi
    done

    for name in security-monitor security-manager; do
        install -m 755 -o root -g root "$src_dir/$name.sh" "$SCRIPT_DIR/$name"
    done

    show_status "success" "Scripts installed to $SCRIPT_DIR"
    log_message "INFO" "Scripts installed"
}

# ============================================================================
# AUTOMATION SETUP (systemd timers)
# ============================================================================

setup_automation() {
    next_step "Setting up systemd timers"

    # Replaced by systemd timers; remove any cron file from older versions.
    if [ -f "$LEGACY_CRON_FILE" ]; then
        rm -f "$LEGACY_CRON_FILE"
        show_status "warning" "Removed legacy cron file $LEGACY_CRON_FILE"
    fi

    cat > "$SYSTEMD_DIR/security-monitor-scan.service" <<EOF
[Unit]
Description=Security Monitor malware scan
Documentation=https://github.com/CaputoDavide93/EC2-Linux-Security-Monitor

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/security-monitor scan $SCAN_MODE
# Keep scans off the critical path on small instances.
Nice=10
IOSchedulingClass=idle
EOF

    cat > "$SYSTEMD_DIR/$SCAN_TIMER" <<EOF
[Unit]
Description=Scheduled Security Monitor malware scan

[Timer]
OnCalendar=$SCAN_SCHEDULE
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

    cat > "$SYSTEMD_DIR/security-monitor-health.service" <<EOF
[Unit]
Description=Security Monitor health check

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/security-manager health
EOF

    cat > "$SYSTEMD_DIR/$HEALTH_TIMER" <<EOF
[Unit]
Description=Scheduled Security Monitor health check

[Timer]
OnCalendar=$HEALTH_SCHEDULE
Persistent=true

[Install]
WantedBy=timers.target
EOF

    chmod 644 "$SYSTEMD_DIR"/security-monitor-*.service "$SYSTEMD_DIR"/security-monitor-*.timer

    systemctl daemon-reload
    systemctl enable --now "$SCAN_TIMER" 2>/dev/null || \
        show_status "warning" "Could not enable $SCAN_TIMER"
    systemctl enable --now "$HEALTH_TIMER" 2>/dev/null || \
        show_status "warning" "Could not enable $HEALTH_TIMER"

    show_status "success" "Timers enabled (scan: $SCAN_SCHEDULE, health: $HEALTH_SCHEDULE)"
    log_message "INFO" "systemd timers configured"
}

# ============================================================================
# SHELL SHORTCUTS
# ============================================================================

# Marker used to add and later remove the shell shortcut block. Both
# create_aliases and do_uninstall must use this exact string.
readonly ALIAS_MARKER="# Security monitoring shortcuts"

alias_block() {
    cat <<EOF
$ALIAS_MARKER
security-status() { sudo $SCRIPT_DIR/security-monitor status "\$@"; }
security-scan() { sudo $SCRIPT_DIR/security-monitor scan "\$@"; }
security-health() { sudo $SCRIPT_DIR/security-manager health "\$@"; }
# End security monitoring shortcuts
EOF
}

create_aliases() {
    next_step "Creating shell shortcuts"

    local content
    content="$(alias_block)"

    if [ -d /etc/profile.d ]; then
        printf '%s\n' "$content" > /etc/profile.d/security-monitor.sh
        chmod 755 /etc/profile.d/security-monitor.sh
    fi

    local home
    for home in /root /home/*; do
        add_user_aliases "$home" "$content"
    done

    show_status "success" "Shell shortcuts created"
    log_message "INFO" "Shell shortcuts created"
}

add_user_aliases() {
    local user_home="$1"
    local content="$2"
    local bashrc="$user_home/.bashrc"

    [ -d "$user_home" ] || return 0
    [ -f "$bashrc" ] || return 0

    if ! grep -qF "$ALIAS_MARKER" "$bashrc" 2>/dev/null; then
        printf '\n%s\n' "$content" >> "$bashrc"
    fi
}

remove_user_aliases() {
    local bashrc="$1"

    [ -f "$bashrc" ] || return 0

    # Current format: marker through explicit end marker.
    sed -i "/^${ALIAS_MARKER}\$/,/^# End security monitoring shortcuts\$/d" "$bashrc" 2>/dev/null || true
    # Pre-3.0 format: marker through the last function line, no end marker.
    sed -i "/^${ALIAS_MARKER}\$/,/^security-health()/d" "$bashrc" 2>/dev/null || true
}

# ============================================================================
# HEALTH CHECK
# ============================================================================

health_check() {
    print_header "Health Check"
    detect_os
    local issues=0

    echo "Checking services..."
    check_freshclam_service || issues=$((issues + 1))
    check_clamd_service || issues=$((issues + 1))

    echo ""
    echo "Checking virus definitions..."
    check_virus_definitions || issues=$((issues + 1))

    echo ""
    echo "Checking automation..."
    check_timers || issues=$((issues + 1))

    echo ""
    echo "Checking scripts..."
    check_installed_scripts || issues=$((issues + 1))

    echo ""
    if [ "$issues" -eq 0 ]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
        log_message "INFO" "Health check passed"
    else
        echo -e "${YELLOW}⚠ $issues check(s) needed attention${NC}"
        log_message "WARN" "Health check found $issues issue(s)"
    fi
}

check_freshclam_service() {
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        show_status "success" "clamav-freshclam running"
        return 0
    fi

    show_status "warning" "Restarting clamav-freshclam"
    systemctl restart clamav-freshclam 2>/dev/null || true
    return 1
}

check_clamd_service() {
    local unit
    unit=$(clamd_unit)

    if [ -z "$unit" ]; then
        show_status "warning" "Unknown distro, cannot check ClamAV daemon"
        return 0
    fi

    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        show_status "success" "ClamAV daemon running ($unit)"
    else
        # clamscan works without the daemon, so this is not an error.
        show_status "warning" "ClamAV daemon not running (on-demand mode)"
    fi
    return 0
}

check_virus_definitions() {
    local db=""
    local f
    for f in /var/lib/clamav/daily.cvd /var/lib/clamav/daily.cld; do
        [ -f "$f" ] && { db="$f"; break; }
    done

    if [ -z "$db" ]; then
        show_status "warning" "Virus definitions missing, downloading..."
        freshclam 2>&1 | tail -5 || true
        return 1
    fi

    if [ -n "$(find "$db" -mtime "+$DB_MAX_AGE_DAYS" 2>/dev/null)" ]; then
        show_status "warning" "Virus definitions older than ${DB_MAX_AGE_DAYS}d, updating..."
        freshclam 2>&1 | tail -5 || true
        return 1
    fi

    show_status "success" "Virus definitions up to date"
    return 0
}

check_timers() {
    local missing=0
    local timer

    for timer in "$SCAN_TIMER" "$HEALTH_TIMER"; do
        if systemctl is-active --quiet "$timer" 2>/dev/null; then
            show_status "success" "$timer active"
        else
            show_status "warning" "$timer not active, starting"
            systemctl enable --now "$timer" 2>/dev/null || true
            missing=1
        fi
    done

    return $missing
}

check_installed_scripts() {
    local missing=0
    local path

    for path in "$SCRIPT_DIR/security-monitor" "$SCRIPT_DIR/security-manager"; do
        if [ -x "$path" ]; then
            show_status "success" "$(basename "$path") present"
        else
            show_status "warning" "$(basename "$path") missing at $path"
            missing=1
        fi
    done

    for path in /etc/profile.d/security-monitor.sh "$CONFIG_FILE"; do
        if [ -f "$path" ]; then
            show_status "success" "$path present"
        else
            show_status "warning" "$path missing"
            missing=1
        fi
    done

    return $missing
}

# ============================================================================
# INSTALLATION
# ============================================================================

do_install() {
    print_header "Installation" "v$VERSION"
    detect_os
    echo "Operating System: $OS $VER"
    echo ""

    case "$OS" in
        ubuntu|debian|amzn) ;;
        *)
            show_status "error" "Unsupported operating system: $OS"
            exit 1
            ;;
    esac

    if ! command -v systemctl &>/dev/null; then
        show_status "error" "systemd is required (systemctl not found)"
        exit 1
    fi

    mkdir -p "$SECURITY_DIR" "$LOG_DIR"
    mkdir -p "$QUARANTINE_DIR"
    chmod 700 "$QUARANTINE_DIR"

    install_packages   || { show_status "error" "Package installation failed"; exit 1; }
    configure_clamav   || { show_status "error" "ClamAV configuration failed"; exit 1; }
    configure_auto_updates
    install_config_file
    install_logrotate
    install_scripts    || { show_status "error" "Script installation failed"; exit 1; }
    setup_automation
    create_aliases

    print_header "Installation Complete!"
    echo -e "${GREEN}✓ ClamAV antivirus installed and configured${NC}"
    echo -e "${GREEN}✓ Automatic security updates enabled${NC}"
    echo -e "${GREEN}✓ Scan timer: $SCAN_SCHEDULE ($SCAN_MODE scan)${NC}"
    echo -e "${GREEN}✓ Health timer: $HEALTH_SCHEDULE${NC}"
    echo -e "${GREEN}✓ Infected files quarantined to $QUARANTINE_DIR${NC}"
    echo -e "${GREEN}✓ Shell shortcuts created${NC}"
    echo ""
    echo -e "${YELLOW}⚠ Reload your shell to activate the shortcuts:${NC}"
    echo -e "  ${GREEN}source /etc/profile.d/security-monitor.sh${NC}"
    echo ""
    echo "Available commands:"
    echo -e "  ${CYAN}security-status${NC}     View security dashboard"
    echo -e "  ${CYAN}security-scan${NC}       Run security scan now"
    echo -e "  ${CYAN}security-health${NC}     Check system health"
    echo ""
    echo -e "${CYAN}Tune behaviour (schedule, quarantine, alerts) in:${NC} $CONFIG_FILE"
    echo -e "${CYAN}Next scheduled scan:${NC} $(systemctl show "$SCAN_TIMER" --property=NextElapseRealtimeUSec --value 2>/dev/null || echo unknown)"
    echo ""

    log_message "INFO" "Installation completed successfully"
}

# ============================================================================
# UNINSTALLATION
# ============================================================================

do_uninstall() {
    print_header "Uninstallation"

    echo -e "${YELLOW}This will remove the following:${NC}"
    echo "  • Scripts ($SCRIPT_DIR/security-monitor, $SCRIPT_DIR/security-manager)"
    echo "  • systemd timers and services (security-monitor-*)"
    echo "  • Legacy cron file ($LEGACY_CRON_FILE), if present"
    echo "  • Logrotate config ($LOGROTATE_FILE)"
    echo "  • Shell shortcuts (/etc/profile.d/security-monitor.sh and .bashrc blocks)"
    echo "  • Config directory ($CONFIG_DIR)"
    echo "  • Data directory ($SECURITY_DIR)"
    echo "  • Log directory ($LOG_DIR)"
    echo ""
    echo -e "${CYAN}Note: ClamAV packages will remain installed${NC}"
    echo ""

    if [ -d "$QUARANTINE_DIR" ]; then
        local qcount
        qcount=$(find "$QUARANTINE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$qcount" -gt 0 ]; then
            echo -e "${RED}⚠ WARNING: $qcount quarantined file(s) in $QUARANTINE_DIR${NC}"
            echo -e "${RED}  Removing the data directory will delete them permanently.${NC}"
            echo ""
        fi
    fi

    read -r -p "Continue with uninstallation? (yes/no): " reply
    if [[ ! "$reply" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cancelled"
        return
    fi

    echo ""
    STEP=0

    echo -e "${YELLOW}[1/6] Stopping timers and services...${NC}"
    local unit
    for unit in "$SCAN_TIMER" "$HEALTH_TIMER"; do
        systemctl disable --now "$unit" 2>/dev/null || true
    done
    rm -f "$SYSTEMD_DIR"/security-monitor-*.service "$SYSTEMD_DIR"/security-monitor-*.timer
    rm -f "$LEGACY_CRON_FILE"
    systemctl daemon-reload 2>/dev/null || true
    show_status "success" "Timers and services removed"

    echo -e "${YELLOW}[2/6] Removing scripts...${NC}"
    rm -f "$SCRIPT_DIR/security-monitor" "$SCRIPT_DIR/security-manager"
    show_status "success" "Scripts removed"

    echo -e "${YELLOW}[3/6] Removing shell shortcuts...${NC}"
    rm -f /etc/profile.d/security-monitor.sh
    local bashrc
    for bashrc in /root/.bashrc /home/*/.bashrc; do
        remove_user_aliases "$bashrc"
    done
    show_status "success" "Shortcuts removed"

    echo -e "${YELLOW}[4/6] Removing logrotate config...${NC}"
    rm -f "$LOGROTATE_FILE"
    show_status "success" "Logrotate config removed"

    echo -e "${YELLOW}[5/6] Removing config and data...${NC}"
    rm -rf "$CONFIG_DIR" "$SECURITY_DIR"
    show_status "success" "Config and data removed"

    echo -e "${YELLOW}[6/6] Removing logs...${NC}"
    rm -rf "$LOG_DIR"
    show_status "success" "Logs removed"

    print_header "Uninstallation Complete"
    echo -e "${GREEN}✓ All monitoring components removed${NC}"
    echo ""
    echo -e "${CYAN}ClamAV packages are still installed${NC}"
    echo "To remove ClamAV packages:"
    echo "  Ubuntu/Debian: apt-get remove --purge 'clamav*'"
    echo "  Amazon Linux:  dnf remove 'clamav*'"
    echo ""
}

# ============================================================================
# MENU INTERFACE
# ============================================================================

show_menu() {
    command clear 2>/dev/null || true
    echo ""
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  Security Manager v$VERSION${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}1${NC}) ${GREEN}Install${NC} - Set up security monitoring"
    echo -e "  ${WHITE}2${NC}) ${RED}Uninstall${NC} - Remove security monitoring"
    echo -e "  ${WHITE}3${NC}) ${YELLOW}Health Check${NC} - Verify system status"
    echo -e "  ${WHITE}4${NC}) ${GRAY}Exit${NC}"
    echo ""
    read -r -p "Select option (1-4): " choice
    echo ""

    case "$choice" in
        1) check_root install; do_install ;;
        2) check_root uninstall; do_uninstall ;;
        3) check_root health; health_check ;;
        4) echo "Goodbye"; exit 0 ;;
        *) show_status "error" "Invalid choice"; sleep 1; show_menu ;;
    esac
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

usage() {
    echo "Usage: $0 [install|uninstall|health|version]"
    echo ""
    echo "Commands:"
    echo "  install    - Install security monitoring system"
    echo "  uninstall  - Remove security monitoring system"
    echo "  health     - Perform health check"
    echo "  version    - Print version"
    echo ""
    echo "Run without arguments for interactive menu."
}

main() {
    if [ $# -eq 0 ]; then
        show_menu
        return
    fi

    case "$1" in
        install)   check_root install;   do_install ;;
        uninstall) check_root uninstall; do_uninstall ;;
        health)    check_root health;    health_check ;;
        version|--version|-v) echo "security-manager $VERSION" ;;
        help|--help|-h) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"
