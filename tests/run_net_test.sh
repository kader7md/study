#!/usr/bin/env bash
# Multiplayer test: a headless host and a headless client on 127.0.0.1 (plus a latecomer who must be turned away).
#   tests/run_net_test.sh            (uses $GODOT, else `godot` from PATH)
#   GODOT=/path/to/godot NET_TEST_PORT=24599 tests/run_net_test.sh
# Prints both logs' results; exits 0 only if both print PASSED.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${NET_TEST_PORT:-24599}"
LIMIT="${NET_TEST_TIMEOUT:-175}"
LOGS="${NET_TEST_LOGS:-$(mktemp -d)}"
mkdir -p "$LOGS"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found: set GODOT=/path/to/godot" >&2
	exit 2
fi

echo "Net test on port $PORT (logs in $LOGS)"
timeout "$LIMIT" "$GODOT" --headless --path . res://tests/NetTest.tscn -- host --port "$PORT" >"$LOGS/host.log" 2>&1 &
HOST_PID=$!
sleep 1
timeout "$LIMIT" "$GODOT" --headless --path . res://tests/NetTest.tscn -- client --port "$PORT" >"$LOGS/client.log" 2>&1 &
CLIENT_PID=$!
# a third player who knocks once the run has started (must be turned away)
(sleep 18; timeout 60 "$GODOT" --headless --path . res://tests/NetTest.tscn -- late --port "$PORT" >"$LOGS/late.log" 2>&1) &
LATE_PID=$!

wait "$HOST_PID"; HOST_CODE=$?
wait "$CLIENT_PID"; CLIENT_CODE=$?
wait "$LATE_PID"; LATE_CODE=$?

status=0
for side in host client late; do
	log="$LOGS/$side.log"
	grep -E "^  (ok|FAIL) " "$log"
	if grep -qE "^(SCRIPT ERROR|ERROR):" "$log"; then
		echo "--- $side: errors in the log:"
		grep -E -A2 "^(SCRIPT ERROR|ERROR):" "$log" | head -40
		status=1
	fi
	if grep -q "PASSED: 0 failure(s)" "$log"; then
		grep "PASSED" "$log"
	else
		echo "${side^^} FAILED (see $log)"
		tail -n 25 "$log"
		status=1
	fi
done
[ "$HOST_CODE" -eq 0 ] && [ "$CLIENT_CODE" -eq 0 ] && [ "$LATE_CODE" -eq 0 ] || status=1
if [ "$status" -eq 0 ]; then
	echo "NET TEST PASSED"
else
	echo "NET TEST FAILED (host exit $HOST_CODE, client exit $CLIENT_CODE, late exit $LATE_CODE)"
fi
exit "$status"
