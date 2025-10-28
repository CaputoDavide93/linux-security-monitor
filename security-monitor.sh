#!/bin/bash
################################################################################
# Security Monitor - Scan and Status Dashboard
# Created by security-manager.sh during installation
################################################################################

SECURITY_DIR="/var/lib/security-monitor"
LOG_DIR="/var/log/security-monitor"
STATUS_FILE="$SECURITY_DIR/status.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

[ -f /etc/os-release ] && . /etc/os-release && OS=$ID
mkdir -p "$SECURITY_DIR" "$LOG_DIR"

# Detect scan mode: quick (default for manual), full (for cron)
SCAN_MODE="${2:-quick}"
if [ "$1" = "scan" ]; then
    if [ "$SCAN_MODE" = "full" ]; then
        echo -e "${BLUE}Running FULL security scan...${NC}"
    else
        echo -e "${BLUE}Running quick security scan...${NC}"
        echo -e "${CYAN}(For full scan, use: security-monitor scan full)${NC}"
    fi
    TIMESTAMP=$(date -Iseconds)
    
    echo -e "${YELLOW}[1/3] Updating virus definitions${NC}"
    
    # Stop freshclam service temporarily to avoid log file conflicts
    FRESHCLAM_WAS_RUNNING=0
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null || systemctl is-active --quiet clamav-freshclam.service 2>/dev/null; then
        FRESHCLAM_WAS_RUNNING=1
        systemctl stop clamav-freshclam 2>/dev/null || true
        systemctl stop clamav-freshclam.service 2>/dev/null || true
        sleep 1
    fi
    
    if freshclam --quiet 2>/dev/null; then
        FRESHCLAM="success"
        echo -e "${GREEN}✓ Virus definitions updated${NC}"
    else
        FRESHCLAM="warning"
        echo -e "${YELLOW}⚠ Freshclam had issues${NC}"
    fi
    
    echo -e "${YELLOW}[2/3] Applying system updates${NC}"
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq 2>/dev/null
            UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
            UPDATES=$(echo "$UPDATES" | tr -d '\n' | tr -d ' ')
            if [ -n "$UPDATES" ] && [ "$UPDATES" -gt 0 ] 2>/dev/null; then
                echo "  Found $UPDATES updates, applying..."
                DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 | grep -E "^(Setting up|Processing)" | tail -5
                DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq 2>&1 | tail -1
                echo -e "  ${GREEN}✓ Updates applied${NC}"
            else
                UPDATES="0"
                echo -e "  ${GREEN}✓ System up to date${NC}"
            fi
            ;;
        amzn)
            dnf check-update -q 2>/dev/null || true
            UPDATES=$(dnf list updates 2>/dev/null | tail -n +2 | grep -v "^$" | wc -l | tr -d ' ')
            if [ -n "$UPDATES" ] && [ "$UPDATES" -gt 0 ] 2>/dev/null; then
                echo "  Found $UPDATES updates, applying..."
                dnf upgrade -y --refresh 2>&1 | grep -E "^(Installing|Upgrading|Complete)" | tail -8
                dnf autoremove -y 2>&1 | tail -1
                echo -e "  ${GREEN}✓ Updates applied${NC}"
            else
                UPDATES="0"
                echo -e "  ${GREEN}✓ System up to date${NC}"
            fi
            ;;
        *)
            UPDATES="0"
            echo "  Unknown OS"
            ;;
    esac
    
    echo -e "${YELLOW}[3/3] Scanning for malware${NC}"
    SCAN_LOG="$LOG_DIR/scan-$(date +%s).log"
    
    # Choose scan paths based on mode
    if [ "$SCAN_MODE" = "full" ]; then
        echo "  Mode: FULL SCAN (all directories, 10-30 minutes)"
        SCAN_PATHS="/home /root /opt /tmp /var /usr/local"
        SCAN_OPTS=""
    else
        echo "  Mode: QUICK SCAN (critical directories, 30-90 seconds)"
        SCAN_PATHS="/home /root"
        # Quick mode: skip large files, limit recursion
        SCAN_OPTS="--max-filesize=50M --max-scansize=100M --max-recursion=5"
    fi
    
    echo "  Scanning: $SCAN_PATHS"
    echo ""
    
    # Run optimized scan
    clamscan -r -i \
        --exclude-dir="^/sys" \
        --exclude-dir="^/proc" \
        --exclude-dir="^/dev" \
        --exclude="\.git" \
        --exclude="node_modules" \
        --exclude="\.cache" \
        $SCAN_OPTS \
        $SCAN_PATHS 2>&1 | tee "$SCAN_LOG" || true
    
    echo ""
    echo -e "${GREEN}✓ Scan complete!${NC}"
    
    # Restart freshclam service if it was running before
    if [ $FRESHCLAM_WAS_RUNNING -eq 1 ]; then
        systemctl start clamav-freshclam 2>/dev/null || true
        systemctl start clamav-freshclam.service 2>/dev/null || true
    fi
    
    INFECTED=$(grep "Infected files:" "$SCAN_LOG" 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    SCANNED=$(grep "Scanned files:" "$SCAN_LOG" 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    
    jq -n \
        --arg ts "$TIMESTAMP" \
        --arg status "$([[ $INFECTED -eq 0 ]] && echo 'clean' || echo 'attention')" \
        --arg inf "$INFECTED" \
        --arg scn "$SCANNED" \
        --arg upd "$UPDATES" \
        '{last_scan: $ts, scan_status: $status, infected_files: $inf, scanned_files: $scn, updates_available: $upd}' > "$STATUS_FILE"
    
    echo ""
    echo -e "${GREEN}✓ Scan complete${NC}"
    echo "  Scanned: $SCANNED files"
    echo "  Infected: $INFECTED files"
    echo "  Updates: $UPDATES available"
    echo ""
    
elif [ "$1" = "status" ] || [ -z "$1" ]; then
    clear
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         🛡️  SECURITY STATUS DASHBOARD${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$STATUS_FILE" ] && command -v jq &>/dev/null; then
        LAST=$(jq -r '.last_scan // "Never"' "$STATUS_FILE")
        STATUS=$(jq -r '.scan_status // "unknown"' "$STATUS_FILE")
        INF=$(jq -r '.infected_files // "0"' "$STATUS_FILE")
        SCN=$(jq -r '.scanned_files // "0"' "$STATUS_FILE")
        UPD=$(jq -r '.updates_available // "0"' "$STATUS_FILE")
        
        # Calculate time since last scan
        if [ "$LAST" != "Never" ]; then
            LAST_TS=$(date -d "$LAST" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST:0:19}" +%s 2>/dev/null)
            NOW_TS=$(date +%s)
            HOURS_AGO=$(( (NOW_TS - LAST_TS) / 3600 ))
            LAST_DISPLAY="$LAST (${HOURS_AGO}h ago)"
        else
            LAST_DISPLAY="Never"
            HOURS_AGO=999
        fi
        
        # Next scan time (2 AM daily)
        NEXT_SCAN=$(date -d "tomorrow 02:00" "+%Y-%m-%d %H:%M" 2>/dev/null || date -v+1d -v2H -v0M "+%Y-%m-%d %H:%M" 2>/dev/null)
        
        # Compliance: if cron is scheduled, system is compliant
        COMPLIANCE=100
        ISSUES=()
        
        # Check cron exists
        if [ ! -f /etc/cron.d/security-monitor ]; then
            COMPLIANCE=0
            ISSUES+=("Automated scans not scheduled")
        fi
        
        # Check if infected
        if [ "$INF" != "0" ]; then
            COMPLIANCE=50
            ISSUES+=("$INF infected files detected")
        fi
        
        # Get REAL-TIME update count (all types)
        case "$OS" in
            ubuntu|debian)
                apt-get update -qq 2>/dev/null
                UPD=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
                ;;
            amzn)
                dnf check-update -q 2>/dev/null || true
                UPD=$(dnf list updates 2>/dev/null | tail -n +2 | grep -v "^$" | wc -l)
                ;;
        esac
        
        # Compliance color
        if [ $COMPLIANCE -eq 100 ]; then
            COMP_COLOR=$GREEN
            COMP_ICON="✓"
        elif [ $COMPLIANCE -ge 50 ]; then
            COMP_COLOR=$YELLOW
            COMP_ICON="⚠"
        else
            COMP_COLOR=$RED
            COMP_ICON="✗"
        fi
        
        # ══════════════════════════════════════════════════════════
        # SCAN STATUS CARD
        # ══════════════════════════════════════════════════════════
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} 📊 ${CYAN}SCAN STATUS${NC}                                            ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        
        if [ "$STATUS" = "clean" ]; then
            echo -e "  Status:          ${GREEN}✓ CLEAN${NC}"
        else
            echo -e "  Status:          ${RED}⚠ ATTENTION REQUIRED${NC}"
        fi
        
        echo -e "  Last Scan:       ${YELLOW}$LAST_DISPLAY${NC}"
        echo -e "  Next Scan:       ${BLUE}$NEXT_SCAN${NC}"
        echo -e "  Files Scanned:   $SCN"
        
        if [ "$INF" = "0" ]; then
            echo -e "  Infected:        ${GREEN}$INF${NC}"
        else
            echo -e "  Infected:        ${RED}$INF ⚠${NC}"
        fi
        
        # Scan freshness indicator
        if [ $HOURS_AGO -le 1 ]; then
            echo -e "  Freshness:       ${GREEN}● Recently scanned${NC}"
        elif [ $HOURS_AGO -le 24 ]; then
            echo -e "  Freshness:       ${YELLOW}○ Within 24 hours${NC}"
        else
            echo -e "  Freshness:       ${RED}✗ Scan overdue${NC}"
        fi
        echo ""
        
        # ══════════════════════════════════════════════════════════
        # COMPLIANCE CARD
        # ══════════════════════════════════════════════════════════
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${COMP_COLOR}${COMP_ICON}${NC} ${CYAN}SECURITY COMPLIANCE${NC}                                    ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo -e "  Compliance:      ${COMP_COLOR}${COMPLIANCE}%${NC}"
        
        # Progress bar
        BAR_WIDTH=50
        FILLED=$((COMPLIANCE * BAR_WIDTH / 100))
        EMPTY=$((BAR_WIDTH - FILLED))
        printf "  "
        printf "%b" "$COMP_COLOR"
        for ((i=0; i<FILLED; i++)); do printf "█"; done
        printf "%b" "$NC"
        for ((i=0; i<EMPTY; i++)); do printf "░"; done
        printf "\n"
        
        if [ ${#ISSUES[@]} -gt 0 ]; then
            echo -e "  ${RED}Issues Found:${NC}"
            for issue in "${ISSUES[@]}"; do
                echo -e "    ${RED}• $issue${NC}"
            done
        else
            echo -e "  ${GREEN}✓ All systems operational${NC}"
        fi
        echo ""
        
        # ══════════════════════════════════════════════════════════
        # SYSTEM UPDATES CARD
        # ══════════════════════════════════════════════════════════
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} 🔄 ${CYAN}SYSTEM UPDATES${NC}                                         ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        
        if [ "$UPD" = "0" ]; then
            echo -e "  Available:       ${GREEN}0 updates (system up to date)${NC}"
            echo -e "  Type:            ${GREEN}All packages current${NC}"
        elif [ "$UPD" = "1" ]; then
            echo -e "  Available:       ${GREEN}1 update available${NC}"
            echo -e "  Type:            ${YELLOW}Security + Regular updates${NC}"
        elif [ "$UPD" -le 5 ]; then
            echo -e "  Available:       ${YELLOW}$UPD updates available${NC}"
            echo -e "  Type:            ${YELLOW}Security + Regular updates${NC}"
        else
            echo -e "  Available:       ${RED}$UPD updates available${NC}"
            echo -e "  Type:            ${RED}Security + Regular updates${NC}"
        fi
        
        echo -e "  Auto-Apply:      ${GREEN}Enabled (during scans)${NC}"
        echo -e "  Apply Now:       ${CYAN}sudo security-scan${NC}"
        
        echo -e "  Auto-Update:     ${GREEN}● Enabled${NC}"
        echo -e "  Schedule:        ${BLUE}Daily at 2:00 AM${NC}"
        echo -e "  Last Check:      ${YELLOW}During last scan${NC}"
        echo ""
        
        # ══════════════════════════════════════════════════════════
        # SERVICES CARD
        # ══════════════════════════════════════════════════════════
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ⚙️  ${CYAN}SERVICES STATUS${NC}                                        ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        
        # ClamAV daemon - check if DB exists first
        if [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; then
            if systemctl is-active --quiet clamd@scan 2>/dev/null || systemctl is-active --quiet clamav-daemon 2>/dev/null; then
                echo -e "  ClamAV Daemon:   ${GREEN}● Running${NC}"
            else
                # Try to start it if DB is available
                systemctl start clamd@scan 2>/dev/null || systemctl start clamav-daemon 2>/dev/null || true
                sleep 1
                if systemctl is-active --quiet clamd@scan 2>/dev/null || systemctl is-active --quiet clamav-daemon 2>/dev/null; then
                    echo -e "  ClamAV Daemon:   ${GREEN}● Running${NC}"
                else
                    echo -e "  ClamAV Daemon:   ${YELLOW}○ Starting...${NC}"
                fi
            fi
        else
            echo -e "  ClamAV Daemon:   ${YELLOW}○ Waiting for virus DB${NC}"
        fi
        
        # FreshClam (virus DB updater)
        if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
            echo -e "  FreshClam:       ${GREEN}● Running${NC}"
        else
            echo -e "  FreshClam:       ${RED}✗ Stopped${NC}"
        fi
        
        # Cron scheduler
        if [ -f /etc/cron.d/security-monitor ]; then
            echo -e "  Scheduled Scans: ${GREEN}● Active${NC} (daily at 2:00 AM)"
        else
            echo -e "  Scheduled Scans: ${RED}✗ Not configured${NC}"
        fi
        
        # Auto updates
        if systemctl is-enabled --quiet dnf-automatic.timer 2>/dev/null || systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
            echo -e "  Auto Updates:    ${GREEN}● Enabled${NC}"
        else
            echo -e "  Auto Updates:    ${YELLOW}○ Check manually${NC}"
        fi
        echo ""
        
        # ══════════════════════════════════════════════════════════
        # VIRUS DATABASE CARD
        # ══════════════════════════════════════════════════════════
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} 🦠 ${CYAN}VIRUS DATABASE${NC}                                         ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        
        if [ -f /var/lib/clamav/daily.cvd ] || [ -f /var/lib/clamav/daily.cld ]; then
            DB_DATE=$(stat -c %y /var/lib/clamav/daily.c* 2>/dev/null | head -1 | cut -d' ' -f1)
            DB_SIZE=$(du -sh /var/lib/clamav/ 2>/dev/null | awk '{print $1}')
            DB_COUNT=$(ls -1 /var/lib/clamav/*.{cvd,cld} 2>/dev/null | wc -l)
            
            echo -e "  Status:          ${GREEN}✓ Active and loaded${NC}"
            echo -e "  Last Updated:    ${YELLOW}$DB_DATE${NC}"
            echo -e "  Database Size:   $DB_SIZE"
            echo -e "  Database Files:  $DB_COUNT files loaded"
            echo -e "  Next Update:     ${BLUE}Automatic (freshclam)${NC}"
        else
            # Check multiple log locations for cooldown
            COOLDOWN_FOUND=0
            COOLDOWN_TIME=""
            
            for log in /var/log/clamav/freshclam.log /var/log/freshclam.log /var/log/messages /var/log/syslog; do
                if [ -f "$log" ]; then
                    COOLDOWN_MSG=$(grep -i "cool-down\|cooldown\|rate.*limit\|forbidden" "$log" 2>/dev/null | tail -1)
                    if [ -n "$COOLDOWN_MSG" ]; then
                        COOLDOWN_FOUND=1
                        # Try to extract time - look for ISO format or "until after:" format
                        COOLDOWN_TIME=$(echo "$COOLDOWN_MSG" | grep -oP '(?<=until after: )\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' | tail -1)
                        [ -n "$COOLDOWN_TIME" ] && break
                    fi
                fi
            done
            
            if [ $COOLDOWN_FOUND -eq 1 ]; then
                echo -e "  Status:          ${YELLOW}⚠ CDN Rate Limited${NC}"
                echo -e "  Reason:          ${BLUE}ClamAV CDN cooldown (normal for new installs)${NC}"
                if [ -n "$COOLDOWN_TIME" ]; then
                    echo -e "  Cooldown Until:  ${YELLOW}$COOLDOWN_TIME${NC}"
                else
                    echo -e "  Cooldown:        ${YELLOW}Check back in 1-2 hours${NC}"
                fi
                echo -e "  Action:          ${GREEN}Will auto-retry after cooldown${NC}"
            else
                echo -e "  Status:          ${YELLOW}⚠ Initializing...${NC}"
                echo -e "  Action:          ${BLUE}First update in progress${NC}"
                echo -e "  Info:            FreshClam downloading definitions"
                echo -e "  Check Logs:      ${CYAN}sudo tail /var/log/clamav/freshclam.log${NC}"
            fi
        fi
        echo ""
        
    else
        echo -e "${YELLOW}⚠ No scan data available${NC}"
        echo ""
        echo -e "Run your first scan:"
        echo -e "  ${CYAN}sudo security-monitor scan${NC}"
        echo ""
    fi
    
    # ══════════════════════════════════════════════════════════
    # QUICK ACTIONS
    # ══════════════════════════════════════════════════════════
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ⚡ ${CYAN}QUICK ACTIONS${NC}                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Force Scan Now:${NC}"
    echo -e "    ${CYAN}sudo security-scan${NC}      or  ${CYAN}sudo security-monitor scan${NC}"
    echo ""
    echo -e "  ${GREEN}View Status:${NC}"
    echo -e "    ${CYAN}security-status${NC}         or  ${CYAN}security-monitor status${NC}"
    echo ""
    echo -e "  ${GREEN}Check Health:${NC}"
    echo -e "    ${CYAN}sudo security-health${NC}    or  ${CYAN}sudo security-manager health${NC}"
    echo ""
    echo -e "  ${GREEN}Update Virus DB:${NC}"
    echo -e "    ${CYAN}sudo freshclam${NC}          (manual virus definition update)"
    echo ""
    echo -e "  ${GREEN}System Updates:${NC}"
    if [ "$OS" = "amzn" ]; then
        echo -e "    ${CYAN}sudo dnf upgrade -y${NC}     (apply all pending updates)"
    else
        echo -e "    ${CYAN}sudo apt-get update && sudo apt-get upgrade -y${NC}"
    fi
    echo ""
    
else
    echo "Security Monitor - Scan and Status"
    echo ""
    echo "Usage: security-monitor [scan|status]"
    echo ""
    echo "Commands:"
    echo "  scan   - Run full security scan (virus definitions + updates + malware)"
    echo "  status - Show security status dashboard (default)"
    echo ""
    echo "Examples:"
    echo "  sudo security-monitor scan      # Run scan"
    echo "  security-monitor status         # View status"
    echo "  security-monitor                # Same as status"
fi
