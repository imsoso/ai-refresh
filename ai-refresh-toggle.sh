#!/bin/bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

STATE_FILE="$HOME/.ai-wake-state"
ENABLED_FILE="$HOME/.config/ai-refresh/enabled"
VALID_AIS="zcode opencode claude codex antigravity"

ensure_enabled_file() {
    mkdir -p "$(dirname "$ENABLED_FILE")"
    [ -f "$ENABLED_FILE" ] || echo "zcode" > "$ENABLED_FILE"
}

is_enabled() {
    if [ ! -f "$ENABLED_FILE" ]; then
        [ "$1" = "zcode" ]
    else
        grep -qx "$1" "$ENABLED_FILE"
    fi
}

cli_installed() {
    case "$1" in
        zcode)    [ -f "/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs" ] && command -v node &>/dev/null ;;
        opencode) command -v opencode &>/dev/null ;;
        claude)   command -v claude &>/dev/null ;;
        codex)    command -v codex &>/dev/null ;;
        antigravity) command -v agy &>/dev/null ;;
    esac
}

ai_validate() {
    case " $VALID_AIS " in
        *" $1 "*) ;;
        *) echo -e "${RED}Unknown AI: $1 (choose: $VALID_AIS)${NC}"; exit 1 ;;
    esac
}

ai_on() {
    ai_validate "$1"
    ensure_enabled_file
    grep -qx "$1" "$ENABLED_FILE" || echo "$1" >> "$ENABLED_FILE"
    echo -e "${GREEN}$1 enabled${NC}"
}

ai_off() {
    ai_validate "$1"
    ensure_enabled_file
    grep -vqx "$1" "$ENABLED_FILE" 2>/dev/null || true
    grep -vx "$1" "$ENABLED_FILE" > "$ENABLED_FILE.tmp" 2>/dev/null || true
    mv "$ENABLED_FILE.tmp" "$ENABLED_FILE"
    echo -e "${YELLOW}$1 disabled${NC}"
}

ai_list() {
    echo -e "${BOLD}AI switches${NC} (order: zcode → opencode → claude → codex → antigravity)"
    for ai in $VALID_AIS; do
        if is_enabled "$ai"; then st="${GREEN}on${NC}"; else st="${RED}off${NC}"; fi
        if cli_installed "$ai"; then cli="${DIM}CLI ✓${NC}"; else cli="${YELLOW}CLI missing${NC}"; fi
        printf "  %-9s [%b] %b\n" "$ai" "$st" "$cli"
    done
    echo -e "${DIM}toggle: ai-toggle enable|disable <name>${NC}"
}

ensure_schedule() {
    PLIST="$HOME/Library/LaunchAgents/me.imsoso.ai-refresh.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>me.imsoso.ai-refresh</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${HOME}/bin/refresh-ai.sh</string>
        <string>all</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>${HOME}/.ai-refresh.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.ai-refresh.log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/me.imsoso.ai-refresh" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
}

wake_on() {
    echo -e "${GREEN}Enabling scheduled refresh + wake...${NC}"
    ensure_schedule
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
    echo -e "${DIM}LaunchAgent kept — AI refreshes when Mac is awake.${NC}"
    echo "off" > "$STATE_FILE"
}

show_status() {
    local state="unknown"
    [ -f "$STATE_FILE" ] && state=$(cat "$STATE_FILE")

    echo -e "${BOLD}AI Auto-Refresh${NC}"
    echo -e "  LaunchAgent (always on, catches up missed runs on wake):"
    launchctl list 2>/dev/null | grep "ai-refresh" || echo "    (not installed — run: ai-toggle on)"
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
    list|l) ai_list ;;
    enable|on-ai)   shift; [ -n "${1:-}" ] && ai_on "$1" || { echo "Usage: ai-toggle enable <zcode|opencode|claude|codex>"; exit 1; } ;;
    disable|off-ai) shift; [ -n "${1:-}" ] && ai_off "$1" || { echo "Usage: ai-toggle disable <zcode|opencode|claude|codex>"; exit 1; } ;;
    *)
        echo "Usage: $(basename "$0") [on|off|status|list|enable|disable]"
        echo ""
        echo "  on            Install LaunchAgent (8/13/18, catches up missed runs) + 30 days of wakes"
        echo "  off           Cancel all wakes only"
        echo "  status        Show current state"
        echo "  list          Show per-AI switches and CLI availability"
        echo "  enable <ai>   Enable one AI: zcode|opencode|claude|codex|antigravity"
        echo "  disable <ai>  Disable one AI"
        ;;
esac
