#!/bin/bash
# Shared helpers for install.sh and restore.sh. Every outside command can be replaced
# by an environment variable so the tests can run on any machine.
PROC_MODEL="${WM_PROC_MODEL:-/proc/device-tree/model}"
MEMINFO="${WM_MEMINFO:-/proc/meminfo}"
SYSTEMCTL="${WM_SYSTEMCTL:-systemctl}"
CURL="${WM_CURL:-curl}"
GIT="${WM_GIT:-git}"
UNAME_M="${WM_UNAME_M:-$(uname -m)}"
HOME_DIR="${WM_HOME:-$HOME}"
BACKUP_ROOT="${WM_BACKUP_ROOT:-$HOME_DIR/wm-vanilla-factory-backups}"
LOG="${WM_LOG:-$HOME_DIR/wm-vanilla-factory.log}"
MOONRAKER="${WM_MOONRAKER:-http://127.0.0.1:7125}"

# Services this project looks at (the factory board ships them installed but disabled)
STACK_SERVICES="klipper moonraker nginx crowsnest klipper-mcu KlipperScreen"

C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_D=$'\e[2m'; C_N=$'\e[0m'
say()  { printf '%s\n' "$*"; printf '%s %s\n' "$(date +%F\ %T)" "$*" >>"$LOG" 2>/dev/null || true; }
ok()   { say "${C_G}OK${C_N}    $*"; }
warn() { say "${C_Y}WARN${C_N}  $*"; WARNINGS=$((WARNINGS+1)); }
fail() { say "${C_R}STOP${C_N}  $*"; exit 1; }
WARNINGS=0

ram_mb()      { awk '/^MemTotal:/{printf "%d",$2/1024}' "$MEMINFO"; }
avail_mb()    { awk '/^MemAvailable:/{printf "%d",$2/1024}' "$MEMINFO"; }
board_model() { tr -d '\0' <"$PROC_MODEL" 2>/dev/null; }
disk_free_mb(){ df -Pm "${1:-$HOME_DIR}" | awk 'NR==2{print $4}'; }

# Is a print running? (Moonraker answers "printing" or "paused")
print_active() {
    local s
    s="$($CURL -s -m 4 "$MOONRAKER/printer/objects/query?print_stats" 2>/dev/null \
        | sed -n 's/.*"state"[: ]*"\([a-z]*\)".*/\1/p' | head -1)"
    [ "$s" = printing ] || [ "$s" = paused ]
}

service_enabled() { $SYSTEMCTL is-enabled "$1" 2>/dev/null || true; }
service_active()  { $SYSTEMCTL is-active  "$1" 2>/dev/null || true; }
