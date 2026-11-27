#!/bin/zsh
# End-to-end check of a built Laf.app, without a person at the keyboard:
#   1. the bundled speech server downloads its model and transcribes speech made with `say`
#   2. the app starts, writes its settings and launches its own speech server
# Hotkeys, pasting and edit learning need Accessibility permission, so they are tested by hand.
# usage: macos/smoke-test.sh [path/to/Laf.app]
set -euo pipefail
cd "$(dirname "$0")"

APP=${1:-build/Laf.app}
PORT=8199
SUPPORT="$HOME/Library/Application Support/Laf"
tmp=$(mktemp -d)
server_pid=""
app_pid=""
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null || true
  pkill -f "parakeet-server.*--port" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "== speech server"
"$APP/Contents/MacOS/parakeet-server" --port $PORT >"$tmp/server.log" 2>&1 &
server_pid=$!
say -o "$tmp/speech.wav" --data-format=LEI16@16000 "Please bump the version and then update the readme."
# The first request waits for the model download and Core ML compile.
response=$(curl -sS --max-time 900 --retry 30 --retry-connrefused --retry-delay 2 \
  -F "file=@$tmp/speech.wav" "http://127.0.0.1:$PORT/inference")
echo "transcript: $response"
cat "$tmp/server.log"
text=$(print -r -- "$response" | tr '[:upper:]' '[:lower:]')
for word in bump version update readme; do
  [[ "$text" == *"$word"* ]] || { echo "FAIL: transcript is missing \"$word\""; exit 1; }
done
kill "$server_pid"; wait "$server_pid" 2>/dev/null || true
server_pid=""

echo "== app launch"
rm -rf "$SUPPORT"
"$APP/Contents/MacOS/Laf" &
app_pid=$!
for _ in {1..30}; do
  [[ -f "$SUPPORT/config.json" ]] && pgrep -f "parakeet-server.*--port 8178" >/dev/null && break
  sleep 1
done
kill -0 "$app_pid" || { echo "FAIL: Laf exited"; exit 1; }
[[ -f "$SUPPORT/config.json" ]] || { echo "FAIL: no config.json"; exit 1; }
[[ -f "$SUPPORT/memory.json" ]] || { echo "FAIL: no memory.json"; exit 1; }
[[ "$(stat -f %Lp "$SUPPORT/config.json")" == 600 ]] || { echo "FAIL: config.json is not private"; exit 1; }
pgrep -f "parakeet-server.*--port 8178" >/dev/null || { echo "FAIL: Laf did not start its speech server"; exit 1; }
cat "$SUPPORT/laf.log"
echo "PASS"
