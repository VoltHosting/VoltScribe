#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: voltscribe-input-safety-smoke.sh <path-to-VoltScribe.app> [duration-seconds]

Arms a timed kill before launching a fixed development build, captures the
relevant unified log, and fails if the incident signatures recur.
EOF
  exit 2
}

APP_PATH="${1:-}"
DURATION="${2:-45}"

[[ -n "$APP_PATH" ]] || usage
[[ "$DURATION" =~ ^[0-9]+$ ]] || usage
(( DURATION >= 10 && DURATION <= 120 )) || {
  echo "duration must be between 10 and 120 seconds" >&2
  exit 2
}

APP_PATH="${APP_PATH%/}"
[[ "$APP_PATH" == *.app ]] || {
  echo "refusing to launch a path that is not an .app bundle: $APP_PATH" >&2
  exit 1
}
[[ "$APP_PATH" != *.disabled* ]] || {
  echo "refusing to launch a quarantined .disabled bundle" >&2
  exit 1
}
[[ -x "$APP_PATH/Contents/MacOS/VoltScribe" ]] || {
  echo "VoltScribe executable not found: $APP_PATH" >&2
  exit 1
}

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
[[ "$bundle_id" == "uk.co.volthosting.voltscribe.dev" ]] || {
  echo "unexpected bundle identifier: $bundle_id" >&2
  exit 1
}

if /usr/bin/pgrep -x VoltScribe >/dev/null; then
  echo "VoltScribe is already running; refusing an ambiguous smoke test" >&2
  exit 1
fi

stamp="$(/bin/date '+%Y%m%d-%H%M%S')"
start_time="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
log_file="$HOME/Desktop/VoltScribe-input-safety-smoke-$stamp.txt"
watchdog_log="/tmp/voltscribe-input-safety-watchdog-$stamp.log"

# This independent watchdog is armed before launch. It does not depend on
# keyboard or mouse input after VoltScribe starts.
(
  /bin/sleep "$DURATION"
  /usr/bin/pkill -x VoltScribe 2>/dev/null || true
  printf 'watchdog fired at %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')"
) >"$watchdog_log" 2>&1 &
watchdog_pid=$!

printf 'Automatic VoltScribe termination armed for %s seconds (watchdog PID %s).\n' \
  "$DURATION" "$watchdog_pid"
printf 'During onboarding, verify ordinary typing, Command-Tab and the menu-bar Quit action.\n'

if ! /usr/bin/open -n "$APP_PATH"; then
  /bin/kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  echo "failed to launch the supplied app bundle" >&2
  exit 1
fi

wait "$watchdog_pid"
end_time="$(/bin/date '+%Y-%m-%d %H:%M:%S')"

/usr/bin/log show \
  --start "$start_time" \
  --end "$end_time" \
  --style compact \
  --info \
  --debug \
  --predicate '
    (process == "VoltScribe") OR
    (process == "CursorUIViewService") OR
    (process == "WindowServer") OR
    (subsystem == "com.apple.TextInputUI") OR
    (subsystem == "com.apple.HIToolbox")
  ' >"$log_file" 2>&1

failures=0
if /usr/bin/grep -Fq 'Sender is prohibited from synthesizing events' "$log_file"; then
  echo "FAIL: WindowServer rejected synthetic events" >&2
  failures=1
fi
if /usr/bin/grep -Fiq 'ordered front from a non-active application' "$log_file"; then
  echo "FAIL: onboarding was ordered by a non-active application" >&2
  failures=1
fi
if /usr/bin/grep -Fq 'ViewBridge to RemoteViewService Terminated' "$log_file"; then
  echo "FAIL: a TextInputUI ViewBridge terminated" >&2
  failures=1
fi

printf 'Unified log: %s\n' "$log_file"
printf 'Watchdog log: %s\n' "$watchdog_log"

if (( failures != 0 )); then
  exit 1
fi

printf 'PASS: no known keyboard-lockout signature occurred during the controlled window.\n'
