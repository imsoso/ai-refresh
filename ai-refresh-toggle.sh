#!/bin/bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

STATE_FILE="$HOME/.ai-wake-state"

ensure_cron() {
    if ! crontab -l 2>/dev/null | grep -q "refresh-ai.sh"; then
        (crontab -l 2>/dev/null; echo "0 8,13,18 * * * ${HOME}/bin/refresh-ai.sh >> ${HOME}/.ai-refresh.log 2>&1") | crontab -
    fi
}

wake_on() {
    echo -e "${GREEN}Enabling scheduled wake...${NC}"
    ensure_cron
    "${HOME}/bin/schedule-wakes.sh" 30
    echo "on" > "$STATE_FILE"
}

wake_off() {
    echo -e "${RED}Cancelling all scheduled wakes...${NC}"
    sudo -n pmset repeat cancel &>/dev/null
    for event in $(pmset -g sched 2>/dev/null | grep 'by .*pmset' | awk '{print $4}'); do
        sudo -n pmset schedule cancel "$event" &>/dev/null
    done
    echo -e "${RED}All pmset wake events cancelled.${NC}"
    echo -e "${DIM}Crontab kept — AI refreshes when Mac is awake.${NC}"
    echo "off" > "$STATE_FILE"
}

show_status() {
    local state="unknown"
    [ -f "$STATE_FILE" ] && state=$(cat "$STATE_FILE")

    echo -e "${BOLD}AI Auto-Refresh${NC}"
    echo -e "  Crontab (always on):"
    crontab -l 2>/dev/null | grep "refresh-ai" || echo "    (none)"
    echo -e "  Scheduled wake: ${state}"
    local count
    count=$(pmset -g sched 2>/dev/null | grep -c 'by .*pmset')
    echo -e "  Wake events queued: ${count}"
    local next
    next=$(pmset -g sched 2>/dev/null | grep 'by .*pmset' | head -1 | sed 's/.*wake at //')
    echo -e "  Next wake: ${next:-none}"
}

case "${1:-status}" in
    on|1)  wake_on ;;
    off|0) wake_off ;;
    status|s) show_status ;;
    *)
        echo "Usage: $(basename "$0") [on|off|status]"
        echo ""
        echo "  on      Schedule 30 days of wakes (crontab always stays)"
        echo "  off     Cancel all wakes only"
        echo "  status  Show current state"
        ;;
esac
