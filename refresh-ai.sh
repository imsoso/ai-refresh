#!/bin/bash
# refresh-ai.sh — pre-warm the 5h usage window of AI coding plans (GLM etc.)
# with one minimal request. Fired by crontab at 8/13/18 daily, or run manually:
#   refresh-ai.sh [all|zcode|opencode|claude|codex]
# "all" only runs the AIs switched on via `ai-toggle enable|disable <name>`.
# zcode first (CLI bundled with ZCode.app); opencode is used per its own switch.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/opt/node@22/bin:/usr/local/bin:/usr/bin:$PATH"

ZCODE_CJS="${ZCODE_CJS:-/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs}"

REFRESH_DIR="$HOME/.ai-refresh-empty"
LOCK_DIR="${TMPDIR:-/tmp}/ai-refresh.lock"
mkdir -p "$REFRESH_DIR"
cd "$REFRESH_DIR" || exit 1

MAX_RETRIES=3
RETRY_DELAY=120
ZCODE_TIMEOUT=180
OPENCODE_TIMEOUT=120
CLAUDE_TIMEOUT=120
CODEX_TIMEOUT=240
AGY_TIMEOUT=180

# Per-AI switch file (one name per line); when absent, only zcode is enabled
ENABLED_FILE="$HOME/.config/ai-refresh/enabled"

ai_enabled() {
    if [ ! -f "$ENABLED_FILE" ]; then
        [ "$1" = "zcode" ]
    else
        grep -qx "$1" "$ENABLED_FILE"
    fi
}

PROMPT="Reply only with: ready

Do not inspect files.
Do not scan directories.
Do not load skills.
Do not use tools.
Do not explore anything."

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

ts() { date '+%Y-%m-%d %H:%M:%S'; }

release_lock() {
    rm -rf "$LOCK_DIR"
}

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        trap release_lock EXIT INT TERM
        return 0
    fi

    if [ -f "$LOCK_DIR/pid" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -rf "$LOCK_DIR"
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                echo $$ > "$LOCK_DIR/pid"
                trap release_lock EXIT INT TERM
                return 0
            fi
        fi
    fi

    echo -e "${YELLOW}[$(ts)] Another refresh-ai.sh run is already in progress, skipping duplicate trigger${NC}"
    exit 0
}

scheduled_pmset_wake_exists() {
    local day="$1"
    local time="$2"
    pmset -g sched 2>/dev/null | grep -F "wake at ${day} ${time} by 'pmset'" >/dev/null
}

last_nonempty_line() {
    awk 'NF { line = $0 } END { print line }' <<<"$1"
}

has_proxy_env() {
    [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ] || \
    [ -n "${HTTPS_PROXY:-}" ] || [ -n "${ALL_PROXY:-}" ] || [ -n "${all_proxy:-}" ]
}

print_success_output() {
    local name="$1"
    local output="$2"
    local reply

    reply=$(last_nonempty_line "$output")
    if [ -n "$reply" ]; then
        echo -e "${DIM}${name}: ${reply}${NC}"
    fi
}

run_with_timeout() {
    local timeout_seconds="$1"
    shift

    perl -e '
        use strict;
        use warnings;

        my $timeout = shift @ARGV;
        my $pid = fork();
        exit 127 unless defined $pid;

        if ($pid == 0) {
            exec @ARGV;
            exit 127;
        }

        local $SIG{ALRM} = sub {
            kill q{TERM}, $pid;
            select undef, undef, undef, 2;
            kill q{KILL}, $pid;
            exit 124;
        };

        alarm $timeout;
        waitpid($pid, 0);
        alarm 0;

        if ($? == -1) {
            exit 127;
        }

        if ($? & 127) {
            exit 128 + ($? & 127);
        }

        exit($? >> 8);
    ' "$timeout_seconds" "$@"
}

run_attempt() {
    local timeout_seconds="$1"
    local mode="$2"
    shift 2

    if [ "$mode" = "direct" ]; then
        run_with_timeout "$timeout_seconds" \
            env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy -u no_proxy -u NO_PROXY \
            "$@"
    else
        run_with_timeout "$timeout_seconds" "$@"
    fi
}

run_with_retry() {
    local name="$1"
    local timeout_seconds="$2"
    shift 2
    local attempt=1
    local mode="default"

    while [ $attempt -le $MAX_RETRIES ]; do
        if [ $attempt -ge 2 ] && has_proxy_env; then
            mode="direct"
            echo -e "${DIM}[$(ts)] ${name}: retrying without proxy environment${NC}"
        else
            mode="default"
        fi

        local output rc
        output=$(run_attempt "$timeout_seconds" "$mode" "$@" 2>&1)
        rc=$?

        if [ $rc -eq 0 ]; then
            print_success_output "$name" "$output"
            echo -e "${GREEN}[$(ts)] ${name} ✓${NC}"
            return 0
        fi

        if [ -n "$output" ]; then
            echo -e "${DIM}${output}${NC}"
        fi

        if [ $rc -eq 124 ]; then
            echo -e "${YELLOW}[$(ts)] ${name} timed out after ${timeout_seconds}s${NC}"
        fi

        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}[$(ts)] ${name} failed (attempt ${attempt}/${MAX_RETRIES}), retrying in ${RETRY_DELAY}s...${NC}"
            sleep $RETRY_DELAY
        fi
        attempt=$((attempt + 1))
    done

    echo -e "${RED}[$(ts)] ${name} ✗ (${MAX_RETRIES} attempts)${NC}"
    return 1
}

zcode_available() {
    [ -f "$ZCODE_CJS" ] && command -v node &>/dev/null
}

refresh_zcode() {
    echo -e "\n${CYAN}━━━ ZCode (GLM Coding Plan, GLM-5.3-Flash low reasoning) ━━━${NC}"
    if zcode_available; then
        run_with_retry "ZCode" "$ZCODE_TIMEOUT" \
            env \
            ZCODE_CREDENTIAL_SECRET_FILE="${ZCODE_CREDENTIAL_SECRET_FILE:-$HOME/.zcode/cli/credential-secret}" \
            ZCODE_CREDENTIALS_FILE="${ZCODE_CREDENTIALS_FILE:-$HOME/.zcode/cli/credentials.json}" \
            node "$ZCODE_CJS" -p "$PROMPT"
    else
        echo -e "${YELLOW}[$(ts)] ZCode CLI not found${NC}"
        return 1
    fi
}

refresh_opencode() {
    echo -e "\n${CYAN}━━━ OpenCode (zhipuai-coding-plan / GLM-4.5-air) ━━━${NC}"
    if command -v opencode &>/dev/null; then
        run_with_retry "OpenCode" "$OPENCODE_TIMEOUT" \
            opencode run -m zhipuai-coding-plan/glm-4.5-air "Reply only with: ready"
    else
        echo -e "${YELLOW}[$(ts)] OpenCode not found, skipping${NC}"
        return 1
    fi
}

refresh_claude() {
    echo -e "\n${CYAN}━━━ Claude Code (haiku) ━━━${NC}"
    if command -v claude &>/dev/null; then
        run_with_retry "Claude Code" "$CLAUDE_TIMEOUT" \
            claude --model haiku --print --system-prompt "Reply only: ready" "Reply only with the word ready"
    else
        echo -e "${YELLOW}[$(ts)] Claude Code not found (install: npm i -g @anthropic-ai/claude-code)${NC}"
        return 1
    fi
}

refresh_codex() {
    echo -e "\n${CYAN}━━━ Codex (gpt-5.4-mini) ━━━${NC}"
    if command -v codex &>/dev/null; then
        echo -e "${DIM}[$(ts)] Refreshing Codex OAuth token...${NC}"
        python3 "$HOME/bin/codex-token-refresh.py" 2>&1 \
            || echo -e "${YELLOW}[$(ts)] Token refresh failed, continuing with existing token${NC}"
        run_with_retry "Codex" "$CODEX_TIMEOUT" \
            codex exec -m gpt-5.4-mini -c 'skills.include_instructions=false' \
            --skip-git-repo-check --ignore-user-config --ignore-rules "Reply only with: ready"
    else
        echo -e "${YELLOW}[$(ts)] Codex not found (install: npm i -g @openai/codex)${NC}"
        return 1
    fi
}

refresh_antigravity() {
    echo -e "\n${CYAN}━━━ Antigravity (Google AI Pro, Gemini) ━━━${NC}"
    if command -v agy &>/dev/null; then
        run_with_retry "Antigravity" "$AGY_TIMEOUT" \
            agy -p "$PROMPT" --effort low
    else
        echo -e "${YELLOW}[$(ts)] Antigravity CLI (agy) not found (install: brew install --cask antigravity-cli)${NC}"
        return 1
    fi
}

# "all": run only the AIs switched on (order: zcode → opencode → claude → codex → antigravity)
refresh_all_enabled() {
    local any=0
    for ai in zcode opencode claude codex antigravity; do
        ai_enabled "$ai" || continue
        any=1
        case "$ai" in
            zcode)
                if zcode_available; then
                    refresh_zcode
                elif ai_enabled opencode; then
                    echo -e "${YELLOW}[$(ts)] ZCode CLI missing, falling back to opencode${NC}"
                    refresh_opencode
                else
                    echo -e "${RED}[$(ts)] ZCode CLI missing and opencode switch is off — skipped${NC}"
                fi ;;
            opencode)    refresh_opencode ;;
            claude)      refresh_claude ;;
            codex)       refresh_codex ;;
            antigravity) refresh_antigravity ;;
        esac
    done
    [ "$any" -eq 1 ] || \
        echo -e "${YELLOW}[$(ts)] No AI enabled — toggle with: ai-toggle enable <zcode|opencode|claude|codex|antigravity>${NC}"
}

schedule_next_day() {
    local target_day
    target_day=$(date -v+30d "+%m/%d/%Y")
    for t in 07:59:00 12:59:00 17:59:00; do
        if ! scheduled_pmset_wake_exists "$target_day" "$t"; then
            sudo -n pmset schedule wake "$target_day $t" &>/dev/null
        fi
    done
}

acquire_lock

case "${1:-all}" in
    zcode)      refresh_zcode ;;
    opencode)   refresh_opencode ;;
    claude)     refresh_claude ;;
    codex)      refresh_codex ;;
    antigravity) refresh_antigravity ;;
    all)        refresh_all_enabled ;;
    *)
        echo "Usage: $0 [all|zcode|opencode|claude|codex|antigravity]   # all = 只跑开关打开的 AI"
        exit 1
        ;;
esac

schedule_next_day

echo -e "\n${BOLD}[$(ts)] All done.${NC}"
