#!/usr/bin/env bash
# Run run_all.sh automatically on a Mac with launchd.
#   bash scripts/09_schedule_macos.sh install 06:30     every day at 06:30 (default)
#   bash scripts/09_schedule_macos.sh install 06:30 1   only on Mondays (0/7 = Sunday ... 6 = Saturday)
#   bash scripts/09_schedule_macos.sh status
#   bash scripts/09_schedule_macos.sh uninstall
# If the Mac is asleep at that time, launchd runs the job when it wakes up. The Mac must be on and Postgres running.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.rentaldwh.refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UIDN="$(id -u)"
cmd="${1:-status}"

case "$cmd" in
install)
    TIME="${2:-06:30}"; HOUR="${TIME%%:*}"; MIN="${TIME##*:}"
    HOUR=$((10#$HOUR)); MIN=$((10#$MIN))
    WEEKDAY="${3:-}"
    mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/logs"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo "  <key>Label</key><string>$LABEL</string>"
        echo "  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/scripts/run_all.sh</string></array>"
        echo "  <key>WorkingDirectory</key><string>$ROOT</string>"
        echo "  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/Applications/Postgres.app/Contents/Versions/latest/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>"
        echo '  <key>StartCalendarInterval</key><dict>'
        echo "    <key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MIN</integer>"
        if [ -n "$WEEKDAY" ]; then echo "    <key>Weekday</key><integer>$WEEKDAY</integer>"; fi
        echo '  </dict>'
        echo "  <key>StandardOutPath</key><string>$ROOT/logs/launchd.out.txt</string>"
        echo "  <key>StandardErrorPath</key><string>$ROOT/logs/launchd.err.txt</string>"
        echo '</dict></plist>'
    } > "$PLIST"
    plutil -lint "$PLIST"
    launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UIDN" "$PLIST"
    echo "Scheduled: ${WEEKDAY:+weekday $WEEKDAY, }$(printf '%02d:%02d' "$HOUR" "$MIN"). Test it now with:  launchctl kickstart -k gui/$UIDN/$LABEL"
    ;;
uninstall)
    launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"; echo "Schedule removed." ;;
status)
    if launchctl print "gui/$UIDN/$LABEL" >/dev/null 2>&1; then echo "Scheduled. Plist: $PLIST"; grep -A3 StartCalendarInterval "$PLIST" | tr -d '\n' | sed 's/<[^>]*>/ /g'; echo
    else echo "Not scheduled."; fi
    ls -1t "$ROOT"/logs/run_*.log 2>/dev/null | head -3 | sed 's/^/  last logs: /' ;;
*) echo "usage: $0 install [HH:MM] [weekday] | uninstall | status"; exit 1 ;;
esac
