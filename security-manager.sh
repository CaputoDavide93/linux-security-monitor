#!/bin/bash
################################################################################
# Security Manager - Installation and Health Management
# Version: 2.1.0
# Description: Installs, configures, and maintains security monitoring system
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly VERSION="2.1.0"
readonly SECURITY_DIR="/var/lib/security-monitor"
readonly LOG_DIR="/var/log/security-monitor"
readonly SCRIPT_DIR="/usr/local/bin"
readonly CRON_FILE="/etc/cron.d/security-monitor"

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

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="${ID:-unknown}"
        VER="${VERSION_ID:-unknown}"
    else
        OS="unknown"
        VER="unknown"
    fi
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

show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    echo -e "${YELLOW}[$current/$total] $message...${NC}"
}

show_status() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        success) echo -e "${GREEN}✓ $message${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $message${NC}" ;;
        error) echo -e "${RED}✗ $message${NC}" ;;
        *) echo "$message" ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_status "error" "Root privileges required"
        echo "Run: sudo $0 $*"
        exit 1
    fi
}

log_message() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_DIR/manager.log"
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

install_packages() {
    local log="$LOG_DIR/install.log"
    mkdir -p "$LOG_DIR"
    echo "=== Installation $(date) ===" >> "$log"
    
    case "$OS" in
        ubuntu|debian)
            install_ubuntu_packages "$log"
            ;;
        amzn)
            install_amazon_packages "$log"
            ;;
        *)
            show_status "error" "Unsupported OS: $OS"
            return 1
            ;;
    esac
    
    # Verify installation
    if command -v clamscan &>/dev/null && command -v jq &>/dev/null; then
        show_status "success" "Packages installed"
        log_message "INFO" "Package installation successful"
        return 0
    else
        show_status "error" "Installation verification failed"
        log_message "ERROR" "Package installation failed"
        return 1
    fi
}

install_ubuntu_packages() {
    local log="$1"
    
    show_progress "1" "6" "Updating package lists"
    if apt-get update -qq >> "$log" 2>&1; then
        echo -n "  "
        while ps aux | grep -q "[a]pt-get update"; do printf "."; sleep 0.5; done
        echo ""
    fi
    
    show_progress "2" "6" "Installing ClamAV and dependencies"
    echo -n "  "
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        clamav clamav-daemon clamav-freshclam \
        unattended-upgrades jq curl >> "$log" 2>&1 &
    local install_pid=$!
    while ps -p $install_pid &>/dev/null; do printf "."; sleep 0.5; done
    wait $install_pid
    echo ""
}

install_amazon_packages() {
    local log="$1"
    
    show_progress "1" "6" "Checking for updates"
    dnf check-update -q >> "$log" 2>&1 || true
    
    show_progress "2" "6" "Installing ClamAV and dependencies"
    echo -n "  "
    dnf install -y -q \
        clamav clamd clamav-update jq dnf-automatic curl \
        --allowerasing >> "$log" 2>&1 &
    local install_pid=$!
    while ps -p $install_pid &>/dev/null; do printf "."; sleep 0.5; done
    wait $install_pid
    echo ""
}

# ============================================================================
# CLAMAV CONFIGURATION
# ============================================================================

configure_clamav() {
    show_progress "3" "6" "Configuring ClamAV"
    
    case "$OS" in
        ubuntu|debian)
            configure_clamav_ubuntu
            ;;
        amzn)
            configure_clamav_amazon
            ;;
    esac
    
    show_status "success" "ClamAV configured"
    log_message "INFO" "ClamAV configuration completed"
}

configure_clamav_ubuntu() {
    # Stop freshclam to configure
    systemctl stop clamav-freshclam 2>/dev/null || true
    sleep 1
    
    # Configure freshclam
    if [ -f /etc/clamav/freshclam.conf ]; then
        sed -i 's/^Example/#Example/' /etc/clamav/freshclam.conf
    fi
    
    # Initial virus definitions update
    echo -n "  Downloading virus definitions"
    if freshclam 2>&1 | while read -r line; do printf "."; done; then
        echo ""
    else
        echo ""
        show_status "warning" "Freshclam in cooldown (will retry automatically)"
    fi
    
    # Start and enable services
    systemctl enable clamav-freshclam 2>/dev/null || true
    systemctl start clamav-freshclam 2>/dev/null || true
    systemctl enable clamav-daemon 2>/dev/null || true
    systemctl start clamav-daemon 2>/dev/null || true
    
    # Verify daemon startup
    sleep 3
    if ! systemctl is-active --quiet clamav-daemon 2>/dev/null; then
        show_status "warning" "ClamAV daemon starting (may take 10-20 seconds)..."
        systemctl restart clamav-daemon 2>/dev/null || true
    fi
}

configure_clamav_amazon() {
    # Stop services for configuration
    systemctl stop clamav-freshclam 2>/dev/null || true
    sleep 1
    
    # Configure freshclam
    if [ -f /etc/freshclam.conf ]; then
        sed -i 's/^Example/#Example/' /etc/freshclam.conf
        grep -q "^DatabaseDirectory" /etc/freshclam.conf || \
            echo "DatabaseDirectory /var/lib/clamav" >> /etc/freshclam.conf
    fi
    
    # Create required directories
    mkdir -p /var/lib/clamav /var/run/clamd.scan
    chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true
    
    # Configure tmpfiles
    cat > /etc/tmpfiles.d/clamd.scan.conf <<'EOF'
d /var/run/clamd.scan 0755 clamscan clamscan -
EOF
    systemd-tmpfiles --create 2>/dev/null || true
    
    # Configure clamd
    cat > /etc/clamd.d/scan.conf <<'EOF'
LogSyslog yes
PidFile /var/run/clamd.scan/clamd.pid
DatabaseDirectory /var/lib/clamav
LocalSocket /var/run/clamd.scan/clamd.sock
User clamscan
ScanMail yes
ScanArchive yes
EOF
    
    # Initial virus definitions update
    echo "  Downloading virus definitions..."
    freshclam 2>&1 | tail -5 || show_status "warning" "Freshclam will retry automatically"
    
    # Start and enable services
    systemctl enable clamav-freshclam 2>/dev/null || true
    systemctl start clamav-freshclam 2>/dev/null || true
    systemctl enable clamd@scan 2>/dev/null || true
    systemctl start clamd@scan 2>/dev/null || true
    
    # Verify daemon startup
    sleep 3
    if ! systemctl is-active --quiet clamd@scan 2>/dev/null; then
        show_status "warning" "ClamAV daemon starting (may take 10-20 seconds)..."
        systemctl restart clamd@scan 2>/dev/null || true
    fi
}

# ============================================================================
# AUTO-UPDATE CONFIGURATION
# ============================================================================

configure_auto_updates() {
    show_progress "4" "6" "Configuring automatic updates"
    
    case "$OS" in
        ubuntu|debian)
            configure_ubuntu_updates
            ;;
        amzn)
            configure_amazon_updates
            ;;
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
    
    systemctl enable unattended-upgrades 2>/dev/null || true
    systemctl start unattended-upgrades 2>/dev/null || true
}

configure_amazon_updates() {
    cat > /etc/dnf/automatic.conf <<'EOF'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
EOF
    
    systemctl enable dnf-automatic.timer 2>/dev/null || true
    systemctl start dnf-automatic.timer 2>/dev/null || true
}

# ============================================================================
# AUTOMATION SETUP
# ============================================================================

setup_automation() {
    show_progress "5" "6" "Setting up cron jobs"
    
    cat > "$CRON_FILE" <<'EOF'
# Daily full scan at 2:00 AM
0 2 * * * root /usr/local/bin/security-monitor scan full >/dev/null 2>&1

# Health check every 6 hours
0 */6 * * * root /usr/local/bin/security-manager health >/dev/null 2>&1
EOF
    
    chmod 644 "$CRON_FILE"
    show_status "success" "Cron jobs configured"
    log_message "INFO" "Cron automation configured"
}

create_monitor_script() {
    show_progress "6" "6" "Installing monitor script"
    
    local script_source="$(dirname "$0")/security-monitor.sh"
    
    if [ ! -f "$script_source" ]; then
        show_status "error" "security-monitor.sh not found in $(dirname "$0")"
        log_message "ERROR" "Monitor script not found: $script_source"
        return 1
    fi
    
    cp "$script_source" "$SCRIPT_DIR/security-monitor"
    chmod +x "$SCRIPT_DIR/security-monitor"
    show_status "success" "Monitor script installed"
    log_message "INFO" "Monitor script installed"
}

create_aliases() {
    show_progress "7" "7" "Creating shell aliases"
    
    local alias_content='# Security monitoring aliases
alias security-status="sudo /usr/local/bin/security-monitor status"
alias security-scan="sudo /usr/local/bin/security-monitor scan"
alias security-health="sudo /usr/local/bin/security-manager health"
'
    
    # System-wide aliases
    if [ -d /etc/profile.d ]; then
        echo "$alias_content" > /etc/profile.d/security-monitor.sh
        chmod 755 /etc/profile.d/security-monitor.sh
    fi
    
    # Add to user bashrc files
    add_user_aliases "/root" "$alias_content"
    add_user_aliases "/home/ec2-user" "$alias_content"
    add_user_aliases "/home/ubuntu" "$alias_content"
    
    show_status "success" "Aliases created"
    log_message "INFO" "Shell aliases created"
}

add_user_aliases() {
    local user_home="$1"
    local alias_content="$2"
    
    [ ! -d "$user_home" ] && return
    
    local bashrc="$user_home/.bashrc"
    [ ! -f "$bashrc" ] && return
    
    if ! grep -q "# Security monitoring aliases" "$bashrc" 2>/dev/null; then
        echo "" >> "$bashrc"
        echo "$alias_content" >> "$bashrc"
    fi
}

# ============================================================================
# HEALTH CHECK
# ============================================================================

health_check() {
    print_header "Health Check"
    detect_os
    local issues=0
    
    echo "Checking services..."
    issues=$((issues + check_freshclam_service))
    issues=$((issues + check_clamd_service))
    
    echo ""
    echo "Checking virus definitions..."
    issues=$((issues + check_virus_definitions))
    
    echo ""
    echo "Checking automation..."
    issues=$((issues + check_cron_jobs))
    
    echo ""
    echo "Checking scripts..."
    issues=$((issues + check_installed_scripts))
    
    echo ""
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
        log_message "INFO" "Health check passed"
    else
        echo -e "${YELLOW}⚠ Fixed $issues issue(s)${NC}"
        log_message "WARN" "Health check found $issues issues"
    fi
}

check_freshclam_service() {
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        show_status "success" "clamav-freshclam running"
        return 0
    else
        show_status "warning" "Restarting clamav-freshclam"
        systemctl restart clamav-freshclam 2>/dev/null || true
        return 1
    fi
}

check_clamd_service() {
    if systemctl is-active --quiet clamav-daemon clamd@scan 2>/dev/null; then
        show_status "success" "ClamAV daemon running"
        return 0
    else
        show_status "warning" "ClamAV daemon not running (on-demand mode)"
        return 0  # Not critical
    fi
}

check_virus_definitions() {
    if [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; then
        local db_age=$(find /var/lib/clamav/daily.c* -mtime +7 2>/dev/null | wc -l)
        if [ "$db_age" -gt 0 ]; then
            show_status "warning" "Virus definitions outdated, updating..."
            freshclam 2>&1 | tail -5
            return 1
        else
            show_status "success" "Virus definitions up to date"
            return 0
        fi
    else
        show_status "warning" "Downloading virus definitions..."
        freshclam 2>&1 | tail -5
        return 1
    fi
}

check_cron_jobs() {
    if [ -f "$CRON_FILE" ]; then
        show_status "success" "Cron jobs configured"
        return 0
    else
        show_status "warning" "Cron file missing"
        return 1
    fi
}

check_installed_scripts() {
    local missing=0
    
    if [ -f "$SCRIPT_DIR/security-monitor" ]; then
        show_status "success" "Monitor script present"
    else
        show_status "warning" "Monitor script missing"
        missing=1
    fi
    
    if [ -f /etc/profile.d/security-monitor.sh ]; then
        show_status "success" "Shell aliases configured"
    else
        show_status "warning" "Shell aliases missing"
        missing=1
    fi
    
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
    
    # Validate OS
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" && "$OS" != "amzn" ]]; then
        show_status "error" "Unsupported operating system: $OS"
        log_message "ERROR" "Unsupported OS: $OS"
        exit 1
    fi
    
    # Create directories
    mkdir -p "$SECURITY_DIR" "$LOG_DIR"
    
    # Installation steps
    install_packages || { show_status "error" "Package installation failed"; exit 1; }
    configure_clamav || { show_status "error" "ClamAV configuration failed"; exit 1; }
    configure_auto_updates
    setup_automation
    create_monitor_script || { show_status "error" "Monitor script installation failed"; exit 1; }
    create_aliases
    
    # Success summary
    print_header "Installation Complete!"
    echo -e "${GREEN}✓ ClamAV antivirus installed and configured${NC}"
    echo -e "${GREEN}✓ Automatic security updates enabled${NC}"
    echo -e "${GREEN}✓ Daily scans scheduled for 2:00 AM${NC}"
    echo -e "${GREEN}✓ Health checks every 6 hours${NC}"
    echo -e "${GREEN}✓ Shell aliases created${NC}"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT: Reload your shell to activate aliases${NC}"
    echo -e "${CYAN}Run this command:${NC}"
    echo -e "  ${GREEN}source /etc/profile.d/security-monitor.sh${NC}"
    echo ""
    echo "Available commands:"
    echo -e "  ${CYAN}security-status${NC}     View security dashboard"
    echo -e "  ${CYAN}security-scan${NC}       Run security scan now"
    echo -e "  ${CYAN}security-health${NC}     Check system health"
    echo ""
    echo -e "${YELLOW}Note: First automated scan scheduled for 2:00 AM${NC}"
    echo ""
    
    log_message "INFO" "Installation completed successfully"
}

# ============================================================================
# UNINSTALLATION
# ============================================================================

do_uninstall() {
    print_header "Uninstallation"
    
    echo -e "${YELLOW}This will remove the following:${NC}"
    echo "  • Security monitor script ($SCRIPT_DIR/security-monitor)"
    echo "  • Cron jobs ($CRON_FILE)"
    echo "  • Shell aliases (/etc/profile.d/security-monitor.sh)"
    echo "  • Data directory ($SECURITY_DIR)"
    echo "  • Log directory ($LOG_DIR)"
    echo "  • Aliases from user .bashrc files"
    echo ""
    echo -e "${CYAN}Note: ClamAV packages will remain installed${NC}"
    echo ""
    read -p "Continue with uninstallation? (yes/no): " -r
    
    [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && { echo "Cancelled"; return; }
    
    echo ""
    
    show_progress "1" "6" "Stopping services"
    systemctl stop clamav-daemon 2>/dev/null || true
    systemctl stop clamd@scan 2>/dev/null || true
    show_status "success" "Services stopped"
    
    show_progress "2" "6" "Removing cron jobs"
    rm -f "$CRON_FILE"
    show_status "success" "Cron jobs removed"
    
    show_progress "3" "6" "Removing scripts"
    rm -f "$SCRIPT_DIR/security-monitor"
    rm -f "$SCRIPT_DIR/security-manager"
    show_status "success" "Scripts removed"
    
    show_progress "4" "6" "Removing shell aliases"
    rm -f /etc/profile.d/security-monitor.sh
    for file in /root/.bashrc /home/*/.bashrc; do
        [ -f "$file" ] && sed -i '/# Security monitoring aliases/,/^$/d' "$file" 2>/dev/null || true
    done
    show_status "success" "Aliases removed"
    
    show_progress "5" "6" "Removing data directory"
    rm -rf "$SECURITY_DIR"
    show_status "success" "Data removed"
    
    show_progress "6" "6" "Removing logs"
    rm -rf "$LOG_DIR"
    show_status "success" "Logs removed"
    
    echo ""
    print_header "Uninstallation Complete"
    echo -e "${GREEN}✓ All monitoring components removed${NC}"
    echo ""
    echo -e "${CYAN}ClamAV packages are still installed${NC}"
    echo "To remove ClamAV packages:"
    echo "  Ubuntu/Debian: apt-get remove --purge clamav*"
    echo "  Amazon Linux:  dnf remove clamav*"
    echo ""
    
    log_message "INFO" "Uninstallation completed"
}

# ============================================================================
# MENU INTERFACE
# ============================================================================

show_menu() {
    clear
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
    read -p "Select option (1-4): " choice
    echo ""
    
    case $choice in
        1) check_root "$@"; do_install ;;
        2) check_root "$@"; do_uninstall ;;
        3) check_root "$@"; health_check ;;
        4) echo "Goodbye"; exit 0 ;;
        *) show_status "error" "Invalid choice"; sleep 1; show_menu ;;
    esac
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    if [ $# -eq 0 ]; then
        show_menu
    else
        case "$1" in
            install)
                check_root "$@"
                do_install
                ;;
            uninstall)
                check_root "$@"
                do_uninstall
                ;;
            health)
                check_root "$@"
                health_check
                ;;
            *)
                echo "Usage: $0 [install|uninstall|health]"
                echo ""
                echo "Commands:"
                echo "  install    - Install security monitoring system"
                echo "  uninstall  - Remove security monitoring system"
                echo "  health     - Perform health check"
                echo ""
                echo "Run without arguments for interactive menu."
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
