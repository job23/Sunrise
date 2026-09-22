#!/usr/bin/env bash
# Captures a full backtrace of every thread in a hung game under CrossOver.
# Run it while the game is frozen; it writes one text file and leaves the game as it was.
#
# Usage: scripts/macos/attach-debugger.sh [--bottle NAME] [--out FILE]
set -euo pipefail

readonly CROSSOVER_BIN="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin"
bottle="Sunrise"
out="$HOME/Desktop/sunrise-backtrace-$(date +%Y%m%d-%H%M%S).txt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bottle) bottle="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

wine="${CROSSOVER_BIN}/wine"
[[ -x "$wine" ]] || { echo "CrossOver not found at ${CROSSOVER_BIN}" >&2; exit 1; }
pgrep -f "destiny2.exe" >/dev/null || { echo "destiny2.exe is not running" >&2; exit 1; }

dbg() { "$wine" --bottle "$bottle" --no-update winedbg "$@" 2>/dev/null | grep -vE '^msync:|^Wine-dbg>$'; }

# winedbg only lists processes from inside a session, so a throwaway cmd.exe hosts the query.
wpid=$(printf 'info proc\nquit\n' | dbg cmd.exe /c exit | awk -F"'" '/destiny2\.exe/ {print $0}' | grep -oE '[0-9a-f]{8}' | head -1 || true)
[[ -n "$wpid" ]] || { echo "could not find the game's Windows process id" >&2; exit 1; }
echo "game wpid: 0x$wpid"

# First attach: list the game's threads. detach keeps the game alive; quit alone would end it.
tids=$(printf 'info threads\ndetach\nquit\n' | dbg "$((16#$wpid))" | sed 's/^Wine-dbg>//' \
    | awk -v p="$wpid" '$0 ~ "^"p" " {inproc=1; next} /^[0-9a-f]{8} / {inproc=0} inproc && /^[[:space:]]+[0-9a-f]{8}/ {print $1}')
[[ -n "$tids" ]] || { echo "no threads listed for 0x$wpid" >&2; exit 1; }

# Second attach: one backtrace per thread in a single session, then detach.
commands=$(printf 'info threads\n'; for tid in $tids; do printf 'echo === thread 0x%s ===\nbt 0x%s\n' "$tid" "$tid"; done; printf 'detach\nquit\n')
{
    echo "=== Sunrise backtrace capture $(date) bottle=$bottle wpid=0x$wpid ==="
    printf '%s\n' "$commands" | dbg "$((16#$wpid))" | sed 's/^Wine-dbg>//'
} > "$out"
echo "wrote $out ($(wc -l < "$out") lines)"
