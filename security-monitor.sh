#!/bin/bash
################################################################################
# 🛡️  Security Monitor - Scan and Status Dashboard
# Version: 3.0.0
# Description: Automated security scanning with ClamAV and system updates
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly VERSION="3.0.0"
readonly CONFIG_FILE="/etc/security-monitor/security-monitor.conf"

# Defaults. Every value below can be overridden in CONFIG_FILE.
SECURITY_DIR="/var/lib/security-monitor"
LOG_DIR="/var/log/security-monitor"
QUARANTINE_DIR=""
QUARANTINE_ENABLED="yes"
ALERT_COMMAND=""
LOG_RETENTION_DAYS="30"
SCAN_TIMER="security-monitor-scan.timer"
HEALTH_TIMER="security-monitor-health.timer"
QUICK_SCAN_PATHS="/home /root"
FULL_SCAN_PATHS="/home /root /opt /tmp /var /usr/local"
DB_MAX_AGE_DAYS="7"
SCAN_MAX_AGE_HOURS="48"

# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"

: "${QUARANTINE_DIR:="$SECURITY_DIR/quarantine"}"
STATUS_FILE="$SECURITY_DIR/status.json"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Runtime state
OS="unknown"
UPDATES_APPLIED=0
UPDATES_AVAILABLE=0
SCAN_LOG=""
SCAN_RC=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

detect_os() {
    if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-unknown}"
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

# The package-manager command a user would run by hand, for the actions card.
manual_update_command() {
    case "$OS" in
        ubuntu|debian) echo "sudo apt-get upgrade" ;;
        amzn|rhel|centos|fedora) echo "sudo dnf upgrade -y" ;;
        *) echo "(distro package manager)" ;;
    esac
}

log_message() {
    local level="$1"
    shift
    # Never fail a read-only command just because the log is unwritable.
    [ -w "$LOG_DIR" ] || return 0
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_DIR/monitor.log"
}

print_status() {
    local color="$1"
    local symbol="$2"
    local message="$3"
    echo -e "${color}${symbol} ${message}${NC}"
}

validate_integer() {
    local value="${1:-}"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

require_root() {
    local action="$1"
    if [ "$(id -u)" -ne 0 ]; then
        print_status "$RED" "✗" "Root privileges required for '$action'"
        echo "Run: sudo security-monitor $action"
        exit 1
    fi
}

ensure_dirs() {
    mkdir -p "$SECURITY_DIR" "$LOG_DIR"
}

# Sends an alert body on stdin to ALERT_COMMAND. No-op when unconfigured.
send_alert() {
    local subject="$1"
    local body="$2"

    [ -n "$ALERT_COMMAND" ] || return 0

    if printf '%s\n\n%s\n' "$subject" "$body" | sh -c "$ALERT_COMMAND"; then
        log_message "INFO" "Alert dispatched: $subject"
    else
        log_message "ERROR" "Alert command failed: $ALERT_COMMAND"
    fi
}

# ============================================================================
# SCAN FUNCTION
# ============================================================================

run_security_scan() {
    local scan_mode="${1:-quick}"

    case "$scan_mode" in
        quick|full) ;;
        *)
            print_status "$RED" "✗" "Unknown scan mode: $scan_mode (expected 'quick' or 'full')"
            exit 1
            ;;
    esac

    require_root "scan"
    detect_os
    ensure_dirs

    local timestamp
    timestamp=$(date -Iseconds)

    log_message "INFO" "Starting $scan_mode scan"

    if [ "$scan_mode" = "full" ]; then
        print_status "$BLUE" "●" "Running FULL security scan..."
    else
        print_status "$BLUE" "●" "Running quick security scan..."
        echo -e "${CYAN}(For full scan, use: security-monitor scan full)${NC}"
    fi

    echo -e "\n${YELLOW}[1/3] Updating virus definitions${NC}"
    update_virus_definitions

    echo -e "\n${YELLOW}[2/3] Applying system updates${NC}"
    apply_system_updates

    echo -e "\n${YELLOW}[3/3] Scanning for malware${NC}"
    scan_for_malware "$scan_mode"

    save_scan_results "$timestamp" "$scan_mode"
    prune_old_logs

    print_status "$GREEN" "✓" "Scan complete!"
    log_message "INFO" "Scan completed (exit $SCAN_RC)"
}

update_virus_definitions() {
    # Pause freshclam so it does not hold the database lock while we update.
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

    if [ "$freshclam_was_running" -eq 1 ]; then
        systemctl start clamav-freshclam 2>/dev/null || true
    fi
}

count_apt_updates() {
    apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true
}

count_dnf_updates() {
    dnf -q check-update 2>/dev/null | awk '
        /^$/ { next }
        /^(Last metadata|Obsoleting|Security:)/ { next }
        NF >= 3 { c++ }
        END { print c + 0 }
    ' || true
}

# Sets UPDATES_APPLIED and UPDATES_AVAILABLE. Writes progress to the terminal;
# results are returned via globals so the output is never swallowed by $(...).
apply_system_updates() {
    UPDATES_APPLIED=0
    UPDATES_AVAILABLE=0

    case "$OS" in
        ubuntu|debian)
            apt-get update -qq 2>/dev/null || true
            UPDATES_APPLIED=$(validate_integer "$(count_apt_updates)")

            if [ "$UPDATES_APPLIED" -gt 0 ]; then
                echo "  Found $UPDATES_APPLIED updates, applying..."
                DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 \
                    | grep -E "^(Setting up|Processing)" | tail -5 || true
                DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq 2>/dev/null || true
                print_status "$GREEN" "✓" "Updates applied"
            else
                print_status "$GREEN" "✓" "System up to date"
            fi

            UPDATES_AVAILABLE=$(validate_integer "$(count_apt_updates)")
            ;;

        amzn|rhel|centos|fedora)
            UPDATES_APPLIED=$(validate_integer "$(count_dnf_updates)")

            if [ "$UPDATES_APPLIED" -gt 0 ]; then
                echo "  Found $UPDATES_APPLIED updates, applying..."
                dnf upgrade -y --refresh 2>&1 \
                    | grep -E "^(Installing|Upgrading|Complete)" | tail -8 || true
                dnf autoremove -y 2>/dev/null || true
                print_status "$GREEN" "✓" "Updates applied"
            else
                print_status "$GREEN" "✓" "System up to date"
            fi

            UPDATES_AVAILABLE=$(validate_integer "$(count_dnf_updates)")
            ;;

        *)
            print_status "$YELLOW" "⚠" "Unknown OS ($OS), skipping updates"
            ;;
    esac
}

scan_for_malware() {
    local scan_mode="$1"
    local -a scan_paths=()
    local -a scan_opts=()
    local path

    SCAN_LOG="$LOG_DIR/scan-$(date +%Y%m%dT%H%M%S).log"

    if [ "$scan_mode" = "full" ]; then
        echo "  Mode: FULL SCAN (all directories, 10-30 minutes)"
        read -r -a scan_paths <<< "$FULL_SCAN_PATHS"
    else
        echo "  Mode: QUICK SCAN (critical directories, 30-90 seconds)"
        read -r -a scan_paths <<< "$QUICK_SCAN_PATHS"
        scan_opts+=(--max-filesize=50M --max-scansize=100M --max-recursion=5)
    fi

    # clamscan errors out on a missing path, so only pass what exists.
    local -a existing_paths=()
    for path in ${scan_paths[@]+"${scan_paths[@]}"}; do
        [ -d "$path" ] && existing_paths+=("$path")
    done

    if [ ${#existing_paths[@]} -eq 0 ]; then
        print_status "$YELLOW" "⚠" "No scan paths exist, skipping malware scan"
        return 0
    fi

    if [ "$QUARANTINE_ENABLED" = "yes" ]; then
        mkdir -p "$QUARANTINE_DIR"
        chmod 700 "$QUARANTINE_DIR"
        scan_opts+=(--move="$QUARANTINE_DIR")
        echo "  Quarantine: $QUARANTINE_DIR"
    fi

    echo "  Scanning: ${existing_paths[*]}"
    echo ""

    # Capture clamscan's own status via ||, not "if ! ...", which would report
    # the exit code of the negation (always 0) instead of clamscan's.
    SCAN_RC=0
    clamscan -r -i \
        --exclude-dir="^/sys" \
        --exclude-dir="^/proc" \
        --exclude-dir="^/dev" \
        --exclude-dir="^${QUARANTINE_DIR}" \
        --exclude="\.git" \
        --exclude="node_modules" \
        --exclude="\.cache" \
        ${scan_opts[@]+"${scan_opts[@]}"} \
        "${existing_paths[@]}" 2>&1 | tee "$SCAN_LOG" || SCAN_RC=$?

    echo ""
}

prune_old_logs() {
    find "$LOG_DIR" -maxdepth 1 -type f -name 'scan-*.log' \
        -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

save_scan_results() {
    local timestamp="$1"
    local scan_mode="$2"
    local infected=0 scanned=0 quarantined=0
    local status="clean"

    if [ -n "$SCAN_LOG" ] && [ -f "$SCAN_LOG" ]; then
        infected=$(validate_integer "$(awk '/^Infected files:/ {v=$3} END {print v+0}' "$SCAN_LOG")")
        scanned=$(validate_integer "$(awk '/^Scanned files:/ {v=$3} END {print v+0}' "$SCAN_LOG")")
        # clamscan --move logs "moved to"; casing has varied across versions.
        quarantined=$(validate_integer "$(grep -ci "moved to" "$SCAN_LOG" || true)")
    fi

    # clamscan: 0 = clean, 1 = infected, 2+ = scan error.
    if [ "$infected" -gt 0 ]; then
        status="attention"
    elif [ "$SCAN_RC" -gt 1 ]; then
        status="error"
    fi

    if command -v jq &>/dev/null; then
        jq -n \
            --arg ts "$timestamp" \
            --arg status "$status" \
            --arg mode "$scan_mode" \
            --argjson inf "$infected" \
            --argjson scn "$scanned" \
            --argjson qtn "$quarantined" \
            --argjson upd "$UPDATES_AVAILABLE" \
            --argjson app "$UPDATES_APPLIED" \
            '{
                last_scan: $ts,
                scan_mode: $mode,
                scan_status: $status,
                infected_files: $inf,
                scanned_files: $scn,
                quarantined_files: $qtn,
                updates_available: $upd,
                updates_applied: $app
             }' > "$STATUS_FILE"
        chmod 640 "$STATUS_FILE" 2>/dev/null || true
    else
        print_status "$YELLOW" "⚠" "jq not installed, status.json not written"
    fi

    echo "  Scanned:     $scanned files"
    echo "  Infected:    $infected files"
    echo "  Quarantined: $quarantined files"
    echo "  Updates:     $UPDATES_APPLIED applied, $UPDATES_AVAILABLE still available"

    if [ "$infected" -gt 0 ]; then
        print_status "$RED" "✗" "Infected files detected!"
        log_message "ALERT" "$infected infected file(s), $quarantined quarantined"
        send_alert "[security-monitor] $infected infected file(s) on $(hostname)" \
                   "$(grep -Ei "FOUND|moved to" "$SCAN_LOG" 2>/dev/null | head -50 || true)"
    fi
}

# ============================================================================
# STATUS DASHBOARD FUNCTION
# ============================================================================

show_status_dashboard() {
    detect_os
    command clear 2>/dev/null || true
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         🛡️  SECURITY STATUS DASHBOARD${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -r "$STATUS_FILE" ] || ! command -v jq &>/dev/null; then
        print_status "$YELLOW" "⚠" "No scan data available"
        echo ""
        echo "Run your first scan:"
        echo -e "  ${CYAN}sudo security-monitor scan${NC}"
        echo ""
        return
    fi

    local last status infected scanned quarantined updates applied
    last=$(jq -r '.last_scan // "Never"' "$STATUS_FILE")
    status=$(jq -r '.scan_status // "unknown"' "$STATUS_FILE")
    infected=$(validate_integer "$(jq -r '.infected_files // 0' "$STATUS_FILE")")
    scanned=$(validate_integer "$(jq -r '.scanned_files // 0' "$STATUS_FILE")")
    quarantined=$(validate_integer "$(jq -r '.quarantined_files // 0' "$STATUS_FILE")")
    updates=$(validate_integer "$(jq -r '.updates_available // 0' "$STATUS_FILE")")
    applied=$(validate_integer "$(jq -r '.updates_applied // 0' "$STATUS_FILE")")

    display_scan_card "$last" "$status" "$infected" "$scanned" "$quarantined"
    display_compliance_card "$infected" "$last"
    display_updates_card "$updates" "$applied"
    display_services_card
    display_virus_db_card
    display_quick_actions
}

# Draws a boxed card header. Emoji are assumed two columns wide, matching the
# 56-column inner width of the box rule.
card_header() {
    local emoji="$1"
    local title="$2"
    local pad=$(( 56 - 1 - 2 - 1 - ${#title} ))
    [ "$pad" -lt 0 ] && pad=0

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    printf "%b║%b %s %b%s%b%*s%b║%b\n" \
        "$CYAN" "$NC" "$emoji" "$CYAN" "$title" "$NC" "$pad" "" "$CYAN" "$NC"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
}

# Age of the last scan in hours, or -1 when it cannot be determined.
scan_age_hours() {
    local last="$1"
    local then_ts now

    [ "$last" != "Never" ] || { echo "-1"; return; }
    then_ts=$(date -d "$last" +%s 2>/dev/null || echo "")
    [ -n "$then_ts" ] || { echo "-1"; return; }

    now=$(date +%s)
    echo $(( (now - then_ts) / 3600 ))
}

# Path to the installed daily signature database, or empty when absent.
virus_db_file() {
    local f
    for f in /var/lib/clamav/daily.cvd /var/lib/clamav/daily.cld; do
        [ -f "$f" ] && { echo "$f"; return; }
    done
    echo ""
}

virus_db_age_days() {
    local db="$1"
    local mtime
    mtime=$(stat -c %Y "$db" 2>/dev/null || echo "")
    [ -n "$mtime" ] || { echo "-1"; return; }
    echo $(( ( $(date +%s) - mtime ) / 86400 ))
}

timer_is_active() {
    local unit="$1"
    systemctl is-active --quiet "$unit" 2>/dev/null
}

# Next elapse of the scan timer as reported by systemd.
next_scan_time() {
    local value
    command -v systemctl &>/dev/null || { echo "unknown"; return; }

    value=$(systemctl show "$SCAN_TIMER" --property=NextElapseRealtimeUSec --value 2>/dev/null || echo "")
    if [ -z "$value" ] || [ "$value" = "0" ] || [ "$value" = "n/a" ]; then
        echo "not scheduled"
    else
        echo "$value"
    fi
}

auto_updates_enabled() {
    systemctl is-enabled --quiet unattended-upgrades 2>/dev/null \
        || systemctl is-enabled --quiet dnf-automatic.timer 2>/dev/null
}

display_scan_card() {
    local last="$1" status="$2" infected="$3" scanned="$4" quarantined="$5"

    card_header "📊" "SCAN STATUS"

    case "$status" in
        clean)     echo -e "  ${WHITE}Status:${NC}         ${GREEN}✓ CLEAN${NC}" ;;
        attention) echo -e "  ${WHITE}Status:${NC}         ${RED}⚠ ATTENTION REQUIRED${NC}" ;;
        error)     echo -e "  ${WHITE}Status:${NC}         ${YELLOW}⚠ LAST SCAN ERRORED${NC}" ;;
        *)         echo -e "  ${WHITE}Status:${NC}         ${GRAY}? UNKNOWN${NC}" ;;
    esac

    echo -e "  ${WHITE}Last Scan:${NC}      ${CYAN}$last${NC}"
    echo -e "  ${WHITE}Next Scan:${NC}      ${CYAN}$(next_scan_time)${NC}"
    echo -e "  ${WHITE}Files Scanned:${NC}  ${CYAN}$scanned${NC}"

    if [ "$infected" -eq 0 ]; then
        echo -e "  ${WHITE}Infected:${NC}       ${GREEN}$infected${NC}"
    else
        echo -e "  ${WHITE}Infected:${NC}       ${RED}$infected${NC}"
    fi

    if [ "$quarantined" -gt 0 ]; then
        echo -e "  ${WHITE}Quarantined:${NC}    ${YELLOW}$quarantined${NC} (in $QUARANTINE_DIR)"
    fi

    local hours
    hours=$(scan_age_hours "$last")
    if [ "$hours" -lt 0 ]; then
        echo -e "  ${WHITE}Freshness:${NC}      ${GRAY}? Unknown${NC}"
    elif [ "$hours" -lt 24 ]; then
        echo -e "  ${WHITE}Freshness:${NC}      ${GREEN}● Scanned ${hours}h ago${NC}"
    elif [ "$hours" -lt "$SCAN_MAX_AGE_HOURS" ]; then
        echo -e "  ${WHITE}Freshness:${NC}      ${YELLOW}○ Scanned ${hours}h ago${NC}"
    else
        echo -e "  ${WHITE}Freshness:${NC}      ${RED}✗ Scan overdue (${hours}h)${NC}"
    fi

    echo ""
}

display_compliance_card() {
    local infected="$1" last="$2"

    card_header "✓ " "SECURITY COMPLIANCE"

    # Five equally weighted checks, 20 points each.
    local score=0
    local -a failures=()
    local hours db db_age

    if [ "$infected" -eq 0 ]; then
        score=$((score + 20))
    else
        failures+=("Infected files detected")
    fi

    if timer_is_active "$SCAN_TIMER"; then
        score=$((score + 20))
    else
        failures+=("Scheduled scans not active")
    fi

    hours=$(scan_age_hours "$last")
    if [ "$hours" -ge 0 ] && [ "$hours" -lt "$SCAN_MAX_AGE_HOURS" ]; then
        score=$((score + 20))
    else
        failures+=("No recent scan")
    fi

    db=$(virus_db_file)
    if [ -n "$db" ]; then
        db_age=$(virus_db_age_days "$db")
        if [ "$db_age" -ge 0 ] && [ "$db_age" -le "$DB_MAX_AGE_DAYS" ]; then
            score=$((score + 20))
        else
            failures+=("Virus definitions stale")
        fi
    else
        failures+=("Virus definitions missing")
    fi

    if auto_updates_enabled; then
        score=$((score + 20))
    else
        failures+=("Automatic updates not enabled")
    fi

    if [ "$score" -eq 100 ]; then
        echo -e "  ${WHITE}Compliance:${NC}     ${GREEN}${score}%${NC}"
    elif [ "$score" -ge 60 ]; then
        echo -e "  ${WHITE}Compliance:${NC}     ${YELLOW}${score}%${NC}"
    else
        echo -e "  ${WHITE}Compliance:${NC}     ${RED}${score}%${NC}"
    fi

    echo -n "  "
    local filled=$((score / 5))
    local i
    for i in $(seq 1 20); do
        if [ "$i" -le "$filled" ]; then
            echo -ne "${GREEN}█${NC}"
        else
            echo -ne "${GRAY}░${NC}"
        fi
    done
    echo ""

    if [ ${#failures[@]} -eq 0 ]; then
        echo -e "  ${GREEN}● All systems operational${NC}"
    else
        local failure
        for failure in "${failures[@]}"; do
            echo -e "  ${RED}✗ ${failure}${NC}"
        done
    fi

    echo ""
}

display_updates_card() {
    local updates="$1" applied="$2"

    card_header "🔄" "SYSTEM UPDATES"

    if [ "$updates" -eq 0 ]; then
        echo -e "  ${WHITE}Available:${NC}      ${GREEN}0 updates${NC} (system up to date)"
    else
        echo -e "  ${WHITE}Available:${NC}      ${YELLOW}$updates updates${NC}"
    fi

    echo -e "  ${WHITE}Applied:${NC}        ${CYAN}$applied${NC} (during last scan)"

    if auto_updates_enabled; then
        echo -e "  ${WHITE}Auto-Apply:${NC}     ${GREEN}Enabled${NC} (unattended + during scans)"
    else
        echo -e "  ${WHITE}Auto-Apply:${NC}     ${YELLOW}During scans only${NC}"
    fi

    echo -e "  ${WHITE}Apply Now:${NC}      ${CYAN}sudo security-monitor scan${NC}"
    echo ""
}

display_services_card() {
    card_header "⚙️ " "SERVICES STATUS"

    local unit
    unit=$(clamd_unit)

    if [ -z "$unit" ]; then
        echo -e "  ${WHITE}ClamAV Daemon:${NC}  ${GRAY}○ Unknown distro${NC}"
    elif timer_is_active "$unit"; then
        echo -e "  ${WHITE}ClamAV Daemon:${NC}  ${GREEN}● Running${NC} ($unit)"
    elif systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        echo -e "  ${WHITE}ClamAV Daemon:${NC}  ${YELLOW}○ Enabled but not running${NC}"
    else
        echo -e "  ${WHITE}ClamAV Daemon:${NC}  ${YELLOW}○ On-demand mode${NC}"
    fi

    if timer_is_active clamav-freshclam; then
        echo -e "  ${WHITE}FreshClam:${NC}      ${GREEN}● Running${NC}"
    elif systemctl is-enabled --quiet clamav-freshclam 2>/dev/null; then
        echo -e "  ${WHITE}FreshClam:${NC}      ${YELLOW}○ Enabled but not running${NC}"
    else
        echo -e "  ${WHITE}FreshClam:${NC}      ${YELLOW}○ Updates during scans only${NC}"
    fi

    if timer_is_active "$SCAN_TIMER"; then
        echo -e "  ${WHITE}Scan Timer:${NC}     ${GREEN}● Active${NC} (next: $(next_scan_time))"
    else
        echo -e "  ${WHITE}Scan Timer:${NC}     ${RED}✗ Not active${NC}"
    fi

    if timer_is_active "$HEALTH_TIMER"; then
        echo -e "  ${WHITE}Health Timer:${NC}   ${GREEN}● Active${NC}"
    else
        echo -e "  ${WHITE}Health Timer:${NC}   ${RED}✗ Not active${NC}"
    fi

    if auto_updates_enabled; then
        echo -e "  ${WHITE}Auto Updates:${NC}   ${GREEN}● Enabled${NC}"
    else
        echo -e "  ${WHITE}Auto Updates:${NC}   ${YELLOW}○ Manual${NC}"
    fi

    echo ""
}

display_virus_db_card() {
    card_header "🦠" "VIRUS DATABASE"

    local db
    db=$(virus_db_file)

    if [ -z "$db" ]; then
        echo -e "  ${WHITE}Status:${NC}         ${RED}✗ Not downloaded${NC}"
        echo -e "  ${WHITE}Action:${NC}         ${CYAN}sudo freshclam${NC}"
        echo -e "  ${WHITE}Check Logs:${NC}     ${YELLOW}sudo tail /var/log/clamav/freshclam.log${NC}"
        echo ""
        return
    fi

    local age version="unknown" sigs="unknown" info=""
    age=$(virus_db_age_days "$db")

    if command -v sigtool &>/dev/null; then
        info=$(sigtool --info "$db" 2>/dev/null || true)
        version=$(echo "$info" | awk -F': ' '/^Version:/ {print $2; exit}')
        sigs=$(echo "$info" | awk -F': ' '/^Signatures:/ {print $2; exit}')
        : "${version:=unknown}"
        : "${sigs:=unknown}"
    fi

    if [ "$age" -lt 0 ]; then
        echo -e "  ${WHITE}Status:${NC}         ${GRAY}? Age unknown${NC}"
    elif [ "$age" -le "$DB_MAX_AGE_DAYS" ]; then
        echo -e "  ${WHITE}Status:${NC}         ${GREEN}● Up to date${NC} (${age}d old)"
    else
        echo -e "  ${WHITE}Status:${NC}         ${RED}✗ Stale${NC} (${age}d old, max ${DB_MAX_AGE_DAYS}d)"
    fi

    echo -e "  ${WHITE}Database:${NC}       ${CYAN}$(basename "$db")${NC}"
    echo -e "  ${WHITE}Version:${NC}        ${CYAN}${version}${NC}"
    echo -e "  ${WHITE}Signatures:${NC}     ${CYAN}${sigs}${NC}"
    echo ""
}

display_quick_actions() {
    card_header "⚡" "QUICK ACTIONS"
    echo ""
    echo -e "  ${WHITE}Force Scan Now:${NC}"
    echo -e "    ${YELLOW}sudo security-scan${NC}       or  ${YELLOW}sudo security-monitor scan${NC}"
    echo ""
    echo -e "  ${WHITE}View Status:${NC}"
    echo -e "    ${YELLOW}security-status${NC}         or  ${YELLOW}security-monitor status${NC}"
    echo ""
    echo -e "  ${WHITE}Check Health:${NC}"
    echo -e "    ${YELLOW}sudo security-health${NC}    or  ${YELLOW}sudo security-manager health${NC}"
    echo ""
    echo -e "  ${WHITE}Update Virus DB:${NC}"
    echo -e "    ${YELLOW}sudo freshclam${NC}          (manual virus definition update)"
    echo ""
    echo -e "  ${WHITE}System Updates:${NC}"
    echo -e "    ${YELLOW}$(manual_update_command)${NC}"
    echo ""
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

usage() {
    echo "Usage: security-monitor [scan [quick|full]|status|version]"
    echo ""
    echo "Commands:"
    echo "  scan [quick|full]  - Run security scan (default: quick, needs root)"
    echo "  status             - Show dashboard (default)"
    echo "  version            - Print version"
}

main() {
    local command="${1:-status}"
    local arg2="${2:-}"

    case "$command" in
        scan)
            run_security_scan "${arg2:-quick}"
            ;;
        status|"")
            show_status_dashboard
            ;;
        version|--version|-v)
            echo "security-monitor $VERSION"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
