#!/bin/bash

DAYS_AHEAD=${1:-30}

scheduled_pmset_wake_exists() {
    local day="$1"
    local time="$2"
    pmset -g sched 2>/dev/null | grep -F "wake at ${day} ${time} by 'pmset'" >/dev/null
}

if ! sudo -n pmset -g &>/dev/null; then
    echo "Need sudo (passwordless pmset not configured)"
    echo "Run: sudo bash -c 'echo \"$USER ALL=(ALL) NOPASSWD: /usr/bin/pmset\" > /etc/sudoers.d/pmset'"
    exit 1
fi

echo "Scheduling wake events for next ${DAYS_AHEAD} days..."

count=0
for i in $(seq 0 $((DAYS_AHEAD - 1))); do
    day=$(date -v+${i}d "+%m/%d/%Y")
    for t in 07:59:00 12:59:00 17:59:00; do
        if ! scheduled_pmset_wake_exists "$day" "$t"; then
            sudo pmset schedule wake "$day $t" 2>/dev/null
            count=$((count + 1))
        fi
    done
done

echo "Scheduled ${count} new wake events for ${DAYS_AHEAD} days."
echo ""
echo "Current schedule:"
pmset -g sched | head -20
echo "  ... (total: $(pmset -g sched | grep -c 'wake') wake events)"
