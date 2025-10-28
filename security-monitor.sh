#!/bin/bash
################################################################################
# Security Monitor - Scan and Status Dashboard
# Version: 2.1.0
# Description: Automated security scanning with ClamAV and system updates
################################################################################

set -eo pipefail  # Exit on error, pipe failures (but allow unset vars for sourcing)

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly SECURITY_DIR="/var/lib/security-monitor"
readonly LOG_DIR="/var/log/security-monitor"
readonly STATUS_FILE="$SECURITY_DIR/status.json"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${ID:-unknown}"
else
    OS="unknown"
fi

# Ensure directories exist
mkdir -p "$SECURITY_DIR" "$LOG_DIR"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_message() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_DIR/monitor.log"
}

print_status() {
    local color="$1"
    local symbol="$2"
    local message="$3"
    echo -e "${color}${symbol} ${message}${NC}"
}

validate_integer() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

# ============================================================================
# SCAN FUNCTION
# ============================================================================

run_security_scan() {
    local scan_mode="${1:-quick}"
    local timestamp=$(date -Iseconds)
    
    log_message "INFO" "Starting $scan_mode scan"
    
    if [ "$scan_mode" = "full" ]; then
        print_status "$BLUE" "●" "Running FULL security scan..."
    else
        print_status "$BLUE" "●" "Running quick security scan..."
        echo -e "${CYAN}(For full scan, use: security-monitor scan full)${NC}"
    fi
    
    # Step 1: Update virus definitions
    echo -e "\n${YELLOW}[1/3] Updating virus definitions${NC}"
    update_virus_definitions
    
    # Step 2: Apply system updates
    echo -e "\n${YELLOW}[2/3] Applying system updates${NC}"
    local updates=$(apply_system_updates)
    
    # Step 3: Scan for malware
    echo -e "\n${YELLOW}[3/3] Scanning for malware${NC}"
    scan_for_malware "$scan_mode"
    
    # Parse results and save status
    save_scan_results "$timestamp" "$updates"
    
    print_status "$GREEN" "✓" "Scan complete!"
    log_message "INFO" "Scan completed successfully"
}

update_virus_definitions() {
    # Stop freshclam service to avoid conflicts
    local freshclam_was_running=0
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        freshclam_was_running=1
        systemctl stop clamav-freshclam 2>/dev/null || true
        sleep 1
    fi
    
    if freshclam --quiet 2>/dev/null; then
        print_status "$GREEN" "✓" "Virus definitions updated"
    else
        print_status "$YELLOW" "⚠" "Freshclam had issues (may be in cooldown)"
    fi
    
    # Restart if it was running
    [ $freshclam_was_running -eq 1 ] && systemctl start clamav-freshclam 2>/dev/null || true
}

apply_system_updates() {
    local update_count=0
    
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq 2>/dev/null
            update_count=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
            update_count=$(validate_integer "$update_count")
            
            if [ "$update_count" -gt 0 ]; then
                echo "  Found $update_count updates, applying..."
                DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 | grep -E "^(Setting up|Processing)" | tail -5
                DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq 2>/dev/null
                print_status "$GREEN" "✓" "Updates applied"
            else
                print_status "$GREEN" "✓" "System up to date"
            fi
            ;;
            
        amzn)
            dnf check-update -q 2>/dev/null || true
            update_count=$(dnf list updates 2>/dev/null | tail -n +2 | grep -v "^$" | wc -l | tr -d ' ')
            update_count=$(validate_integer "$update_count")
            
            if [ "$update_count" -gt 0 ]; then
                echo "  Found $update_count updates, applying..."
                dnf upgrade -y --refresh 2>&1 | grep -E "^(Installing|Upgrading|Complete)" | tail -8
                dnf autoremove -y 2>/dev/null
                print_status "$GREEN" "✓" "Updates applied"
            else
                print_status "$GREEN" "✓" "System up to date"
            fi
            ;;
            
        *)
            print_status "$YELLOW" "⚠" "Unknown OS, skipping updates"
            ;;
    esac
    
    echo "$update_count"
}

scan_for_malware() {
    local scan_mode="$1"
    local scan_log="$LOG_DIR/scan-$(date +%s).log"
    local scan_paths
    local scan_opts=""
    
    if [ "$scan_mode" = "full" ]; then
        echo "  Mode: FULL SCAN (all directories, 10-30 minutes)"
        scan_paths="/home /root /opt /tmp /var /usr/local"
    else
        echo "  Mode: QUICK SCAN (critical directories, 30-90 seconds)"
        scan_paths="/home /root"
        scan_opts="--max-filesize=50M --max-scansize=100M --max-recursion=5"
    fi
    
    echo "  Scanning: $scan_paths"
    echo ""
    
    # Run scan
    clamscan -r -i \
        --exclude-dir="^/sys" \
        --exclude-dir="^/proc" \
        --exclude-dir="^/dev" \
        --exclude="\.git" \
        --exclude="node_modules" \
        --exclude="\.cache" \
        $scan_opts \
        $scan_paths 2>&1 | tee "$scan_log" || true
    
    echo ""
}

save_scan_results() {
    local timestamp="$1"
    local updates="$2"
    local scan_log=$(ls -t "$LOG_DIR"/scan-*.log 2>/dev/null | head -1)
    
    local infected=$(grep "Infected files:" "$scan_log" 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    local scanned=$(grep "Scanned files:" "$scan_log" 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    local status="clean"
    
    [ "$infected" != "0" ] && status="attention"
    
    # Save to JSON
    command -v jq &>/dev/null && jq -n \
        --arg ts "$timestamp" \
        --arg status "$status" \
        --arg inf "$(validate_integer $infected)" \
        --arg scn "$(validate_integer $scanned)" \
        --arg upd "$(validate_integer $updates)" \
        '{last_scan: $ts, scan_status: $status, infected_files: $inf, scanned_files: $scn, updates_available: $upd}' > "$STATUS_FILE"
    
    echo "  Scanned: $scanned files"
    echo "  Infected: $infected files"
    echo "  Updates: $updates available"
}

# ============================================================================
# STATUS DASHBOARD FUNCTION
# ============================================================================

show_status_dashboard() {
    command clear 2>/dev/null || true
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         🛡️  SECURITY STATUS DASHBOARD${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -f "$STATUS_FILE" ] || ! command -v jq &>/dev/null; then
        print_status "$YELLOW" "⚠" "No scan data available"
        echo ""
        echo "Run your first scan:"
        echo -e "  ${CYAN}sudo security-monitor scan${NC}"
        echo ""
        return
    fi
    
    # Load status data
    local last=$(jq -r '.last_scan // "Never"' "$STATUS_FILE")
    local status=$(jq -r '.scan_status // "unknown"' "$STATUS_FILE")
    local infected=$(jq -r '.infected_files // "0"' "$STATUS_FILE")
    local scanned=$(jq -r '.scanned_files // "0"' "$STATUS_FILE")
    local updates=$(jq -r '.updates_available // "0"' "$STATUS_FILE" | tr -d '\n' | tr -d ' ')
    
    # Validate
    updates=$(validate_integer "$updates")
    
    # Display cards
    display_scan_card "$last" "$status" "$infected" "$scanned"
    display_compliance_card "$infected"
    display_updates_card "$updates"
    display_services_card
    display_virus_db_card
    display_quick_actions
}

display_scan_card() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} 📊 ${CYAN}SCAN STATUS${NC}                                            ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    local last="$1" status="$2" infected="$3" scanned="$4"
    
    if [ "$status" = "clean" ]; then
        print_status "$GREEN" "✓" "  Status: CLEAN"
    else
        print_status "$RED" "⚠" "  Status: ATTENTION REQUIRED"
    fi
    
    echo "  Last Scan: $last"
    echo "  Files Scanned: $scanned"
    echo "  Infected: $infected"
    echo ""
}

display_compliance_card() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ✓ ${CYAN}SECURITY COMPLIANCE${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    local infected="$1"
    local compliance=100
    
    [ "$infected" != "0" ] && compliance=50
    [ ! -f /etc/cron.d/security-monitor ] && compliance=0
    
    echo "  Compliance: ${compliance}%"
    echo ""
}

display_updates_card() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} 🔄 ${CYAN}SYSTEM UPDATES${NC}                                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    local updates="$1"
    
    if [ "$updates" = "0" ]; then
        print_status "$GREEN" "✓" "  System up to date (0 updates)"
    else
        print_status "$YELLOW" "⚠" "  $updates updates available"
    fi
    
    echo "  Auto-Apply: Enabled (during scans)"
    echo ""
}

display_services_card() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ⚙️  ${CYAN}SERVICES STATUS${NC}                                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # ClamAV Daemon
    if systemctl is-active --quiet clamd@scan clamav-daemon 2>/dev/null; then
        print_status "$GREEN" "●" "  ClamAV Daemon: Running"
    else
        print_status "$YELLOW" "○" "  ClamAV Daemon: On-demand"
    fi
    
    # FreshClam
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        print_status "$GREEN" "●" "  FreshClam: Active (updating now)"
    elif systemctl is-enabled --quiet clamav-freshclam 2>/dev/null; then
        print_status "$GREEN" "✓" "  FreshClam: Enabled (auto-updates)"
    else
        print_status "$YELLOW" "○" "  FreshClam: Updates during scans"
    fi
    
    # Scheduled Scans
    if [ -f /etc/cron.d/security-monitor ]; then
        print_status "$GREEN" "●" "  Scheduled Scans: Active (2:00 AM daily)"
    else
        print_status "$RED" "✗" "  Scheduled Scans: Not configured"
    fi
    
    echo ""
}

display_virus_db_card() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} 🦠 ${CYAN}VIRUS DATABASE${NC}                                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    if [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; then
        local db_date=$(stat -c %y /var/lib/clamav/daily.c* 2>/dev/null | head -1 | cut -d' ' -f1)
        print_status "$GREEN" "✓" "  Status: Active and loaded"
        echo "  Last Updated: $db_date"
    else
        print_status "$YELLOW" "⚠" "  Status: Initializing..."
    fi
    
    echo ""
}

display_quick_actions() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ⚡ ${CYAN}QUICK ACTIONS${NC}                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Force Scan:${NC}        ${CYAN}security-scan${NC}"
    echo -e "  ${GREEN}View Status:${NC}       ${CYAN}security-status${NC}"
    echo -e "  ${GREEN}Check Health:${NC}      ${CYAN}security-health${NC}"
    echo ""
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    local command="${1:-status}"
    local arg2="${2:-}"
    
    case "$command" in
        scan)
            run_security_scan "$arg2"
            ;;
        status|"")
            show_status_dashboard
            ;;
        *)
            echo "Usage: security-monitor [scan|status]"
            echo ""
            echo "Commands:"
            echo "  scan [quick|full]  - Run security scan (default: quick)"
            echo "  status             - Show dashboard (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
