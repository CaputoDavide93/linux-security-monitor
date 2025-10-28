#!/bin/bash
# Security Manager - Install/Uninstall/Health
VERSION="2.1.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
GRAY='\033[0;90m'

SECURITY_DIR="/var/lib/security-monitor"
LOG_DIR="/var/log/security-monitor"
SCRIPT_DIR="/usr/local/bin"
CRON_FILE="/etc/cron.d/security-monitor"

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS="unknown"
        VER="unknown"
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    [ -n "$2" ] && echo -e "${CYAN}  $2${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════${NC}"
    echo ""
}

show_progress() { echo -e "${YELLOW}[$1/$2] $3...${NC}"; }
show_success() { echo -e "${GREEN}✓ $1${NC}"; }
show_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
show_error() { echo -e "${RED}✗ $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_error "Root required"
        echo "Run: sudo $0"
        exit 1
    fi
}

install_packages() {
    local log="$LOG_DIR/install.log"
    echo "=== Install $(date) ===" >> "$log"
    
    case "$OS" in
        ubuntu|debian)
            show_progress "1" "6" "Updating packages"
            apt-get update -qq 2>&1 | grep -E "Hit:|Get:|Fetched" | while read line; do
                printf "."
            done
            echo ""
            
            show_progress "2" "6" "Installing ClamAV"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                clamav clamav-daemon clamav-freshclam \
                unattended-upgrades jq curl 2>&1 | while read line; do
                printf "."
            done
            echo ""
            
            command -v clamscan &>/dev/null || { show_error "Install failed"; return 1; }
            show_success "Packages installed"
            ;;
            
        amzn)
            show_progress "1" "6" "Updating packages"
            dnf check-update -q 2>&1 | while read line; do
                printf "."
            done
            echo ""
            
            show_progress "2" "6" "Installing ClamAV"
            # Replace curl-minimal with full curl to avoid conflicts
            dnf install -y -q clamav clamd clamav-update jq dnf-automatic curl --allowerasing 2>&1 | while read line; do
                printf "."
            done
            echo ""
            
            command -v clamscan &>/dev/null || { show_error "Install failed"; return 1; }
            show_success "Packages installed"
            ;;
            
        *)
            show_error "Unsupported OS: $OS"
            return 1
            ;;
    esac
}

configure_clamav() {
    show_progress "3" "6" "Configuring ClamAV"
    
    case "$OS" in
        ubuntu|debian)
            systemctl stop clamav-freshclam 2>/dev/null || true
            sleep 1
            
            if [ -f /etc/clamav/freshclam.conf ]; then
                sed -i 's/^Example/#Example/' /etc/clamav/freshclam.conf
            fi
            
            echo -n "  Downloading virus definitions"
            freshclam 2>&1 | while read line; do printf "."; done || show_warning "Cooldown active"
            echo ""
            
            systemctl start clamav-freshclam
            sleep 2
            
            # Start and enable ClamAV daemon
            systemctl enable clamav-daemon 2>/dev/null || true
            systemctl start clamav-daemon 2>/dev/null || true
            
            # Verify daemon is running
            sleep 3
            if ! systemctl is-active --quiet clamav-daemon 2>/dev/null; then
                show_warning "ClamAV daemon starting..."
                systemctl restart clamav-daemon 2>/dev/null || true
            fi
            ;;
            
        amzn)
            systemctl stop clamav-freshclam 2>/dev/null || true
            sleep 1
            
            if [ -f /etc/freshclam.conf ]; then
                sed -i 's/^Example/#Example/' /etc/freshclam.conf
                grep -q "^DatabaseDirectory" /etc/freshclam.conf || echo "DatabaseDirectory /var/lib/clamav" >> /etc/freshclam.conf
            fi
            
            mkdir -p /var/lib/clamav /var/run/clamd.scan
            chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true
            
            cat > /etc/tmpfiles.d/clamd.scan.conf <<'EOF'
d /var/run/clamd.scan 0755 clamscan clamscan -
EOF
            systemd-tmpfiles --create
            
            cat > /etc/clamd.d/scan.conf <<'EOF'
LogSyslog yes
PidFile /var/run/clamd.scan/clamd.pid
DatabaseDirectory /var/lib/clamav
LocalSocket /var/run/clamd.scan/clamd.sock
User clamscan
ScanMail yes
ScanArchive yes
EOF
            
            freshclam 2>&1 | tail -5 || show_warning "Freshclam will retry"
            
            systemctl enable clamav-freshclam
            systemctl start clamav-freshclam
            systemctl enable clamd@scan 2>/dev/null || true
            systemctl start clamd@scan 2>/dev/null || true
            
            # Ensure daemon stays running
            sleep 3
            if ! systemctl is-active --quiet clamd@scan 2>/dev/null; then
                show_warning "ClamAV daemon starting..."
                systemctl restart clamd@scan 2>/dev/null || true
            fi
            ;;
    esac
    
    show_success "ClamAV configured"
}

configure_auto_updates() {
    show_progress "4" "6" "Configuring auto-updates"
    
    case "$OS" in
        ubuntu|debian)
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
            ;;
            
        amzn)
            cat > /etc/dnf/automatic.conf <<'EOF'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
EOF
            systemctl enable dnf-automatic.timer
            systemctl start dnf-automatic.timer
            ;;
    esac
    
    show_success "Auto-updates configured"
}

setup_automation() {
    show_progress "5" "6" "Setting up cron"
    
    cat > "$CRON_FILE" <<'EOF'
0 2 * * * root /usr/local/bin/security-monitor scan >/dev/null 2>&1
0 */6 * * * root /usr/local/bin/security-manager health >/dev/null 2>&1
EOF
    
    chmod 644 "$CRON_FILE"
    show_success "Cron configured"
}

create_monitor_script() {
    show_progress "6" "7" "Installing monitor script"
    
    # Copy the security-monitor.sh from same directory
    SCRIPT_SOURCE="$(dirname "$0")/security-monitor.sh"
    
    if [ -f "$SCRIPT_SOURCE" ]; then
        cp "$SCRIPT_SOURCE" "$SCRIPT_DIR/security-monitor"
        chmod +x "$SCRIPT_DIR/security-monitor"
        show_success "Monitor installed"
    else
        show_error "security-monitor.sh not found in $(dirname "$0")"
        return 1
    fi
}

create_aliases() {
    show_progress "7" "7" "Creating shell aliases"
    
    local alias_content='# Security monitoring aliases
alias security-status="sudo /usr/local/bin/security-monitor status"
alias security-scan="sudo /usr/local/bin/security-monitor scan"
alias security-health="sudo /usr/local/bin/security-manager health"
'
    
    # Add to system-wide profile
    if [ -d /etc/profile.d ]; then
        echo "$alias_content" > /etc/profile.d/security-monitor.sh
        chmod 755 /etc/profile.d/security-monitor.sh
    fi
    
    # Add to root's bashrc
    if [ -f /root/.bashrc ]; then
        if ! grep -q "# Security monitoring aliases" /root/.bashrc; then
            echo "" >> /root/.bashrc
            echo "$alias_content" >> /root/.bashrc
        fi
    fi
    
    # Add for ec2-user if exists
    if [ -d /home/ec2-user ]; then
        if [ -f /home/ec2-user/.bashrc ]; then
            if ! grep -q "# Security monitoring aliases" /home/ec2-user/.bashrc; then
                echo "" >> /home/ec2-user/.bashrc
                echo "$alias_content" >> /home/ec2-user/.bashrc
            fi
        fi
    fi
    
    # Add for ubuntu user if exists
    if [ -d /home/ubuntu ]; then
        if [ -f /home/ubuntu/.bashrc ]; then
            if ! grep -q "# Security monitoring aliases" /home/ubuntu/.bashrc; then
                echo "" >> /home/ubuntu/.bashrc
                echo "$alias_content" >> /home/ubuntu/.bashrc
            fi
        fi
    fi
    
    show_success "Aliases created"
}

health_check() {
    print_header "Health Check"
    detect_os
    local issues=0
    
    echo "Services..."
    if ! systemctl is-active --quiet clamav-freshclam; then
        show_warning "Restarting clamav-freshclam"
        systemctl restart clamav-freshclam
        ((issues++))
    else
        show_success "clamav-freshclam running"
    fi
    
    echo ""
    echo "Virus definitions..."
    if [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; then
        show_success "Definitions present"
    else
        show_warning "Updating definitions"
        freshclam 2>&1 | tail -5
        ((issues++))
    fi
    
    echo ""
    echo "Automation..."
    if [ -f "$CRON_FILE" ]; then
        show_success "Cron configured"
    else
        show_warning "Cron missing"
        ((issues++))
    fi
    
    echo ""
    [ $issues -eq 0 ] && echo -e "${GREEN}✓ All checks passed${NC}" || echo -e "${YELLOW}⚠ Fixed $issues issue(s)${NC}"
}

do_install() {
    print_header "Installation" "v$VERSION"
    detect_os
    echo "OS: $OS $VER"
    
    [[ "$OS" != "ubuntu" && "$OS" != "debian" && "$OS" != "amzn" ]] && { show_error "Unsupported OS"; exit 1; }
    
    mkdir -p "$SECURITY_DIR" "$LOG_DIR"
    
    install_packages || { show_error "Install failed"; exit 1; }
    configure_clamav || { show_error "Config failed"; exit 1; }
    configure_auto_updates
    setup_automation
    create_monitor_script
    create_aliases
    
    print_header "Complete!"
    echo -e "${GREEN}✓ ClamAV installed${NC}"
    echo -e "${GREEN}✓ Auto-updates enabled${NC}"
    echo -e "${GREEN}✓ Daily scans at 2 AM${NC}"
    echo -e "${GREEN}✓ Shell aliases created${NC}"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT: Reload your shell to activate aliases${NC}"
    echo -e "${CYAN}Run this command:${NC}"
    echo -e "  ${GREEN}source /etc/profile.d/security-monitor.sh${NC}"
    echo ""
    echo "Then you can use:"
    echo -e "  ${CYAN}security-status${NC}     → View dashboard"
    echo -e "  ${CYAN}security-scan${NC}       → Run scan now"
    echo -e "  ${CYAN}security-health${NC}     → Check health"
    echo ""
    echo -e "${YELLOW}Note: First scan scheduled for 2:00 AM${NC}"
    echo ""
}

do_uninstall() {
    print_header "Uninstall"
    echo -e "${YELLOW}This will remove:${NC}"
    echo "  • /usr/local/bin/security-monitor"
    echo "  • /etc/cron.d/security-monitor"
    echo "  • /etc/profile.d/security-monitor.sh"
    echo "  • /var/lib/security-monitor/"
    echo "  • /var/log/security-monitor/"
    echo "  • Shell aliases from .bashrc files"
    echo ""
    echo -e "${CYAN}ClamAV packages will remain installed${NC}"
    echo ""
    read -p "Continue? (yes/no): " -r
    
    [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && { echo "Cancelled"; return; }
    
    echo ""
    show_progress "1" "6" "Stopping services"
    systemctl stop clamav-daemon 2>/dev/null || true
    systemctl stop clamd@scan 2>/dev/null || true
    show_success "Services stopped"
    
    show_progress "2" "6" "Removing cron jobs"
    rm -f "$CRON_FILE"
    show_success "Cron removed"
    
    show_progress "3" "6" "Removing scripts"
    rm -f "$SCRIPT_DIR/security-monitor"
    show_success "Scripts removed"
    
    show_progress "4" "6" "Removing aliases"
    rm -f /etc/profile.d/security-monitor.sh
    # Remove from bashrc files
    for file in /root/.bashrc /home/*/.bashrc; do
        if [ -f "$file" ]; then
            sed -i '/# Security monitoring aliases/,/^$/d' "$file" 2>/dev/null || true
        fi
    done
    show_success "Aliases removed"
    
    show_progress "5" "6" "Removing data directories"
    rm -rf "$SECURITY_DIR"
    show_success "Data removed"
    
    show_progress "6" "6" "Removing logs"
    rm -rf "$LOG_DIR"
    show_success "Logs removed"
    
    echo ""
    print_header "Uninstall Complete"
    echo -e "${GREEN}✓ All monitoring components removed${NC}"
    echo ""
    echo -e "${CYAN}ClamAV packages still installed${NC}"
    echo "To remove ClamAV:"
    echo "  Ubuntu/Debian: apt-get remove --purge clamav*"
    echo "  Amazon Linux:  dnf remove clamav*"
}

show_menu() {
    clear
    echo ""
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  Security Manager v$VERSION${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}1${NC}) ${GREEN}Install${NC}"
    echo -e "  ${WHITE}2${NC}) ${RED}Uninstall${NC}"
    echo -e "  ${WHITE}3${NC}) ${YELLOW}Health Check${NC}"
    echo -e "  ${WHITE}4${NC}) ${GRAY}Exit${NC}"
    echo ""
    read -p "Choice (1-4): " choice
    echo ""
    
    case $choice in
        1) check_root; do_install ;;
        2) check_root; do_uninstall ;;
        3) check_root; health_check ;;
        4) echo "Goodbye"; exit 0 ;;
        *) show_error "Invalid"; sleep 1; show_menu ;;
    esac
}

if [ -z "$1" ]; then
    show_menu
else
    case "$1" in
        install) check_root; do_install ;;
        uninstall) check_root; do_uninstall ;;
        health) check_root; health_check ;;
        *) echo "Usage: $0 [install|uninstall|health]"; exit 1 ;;
    esac
fi
