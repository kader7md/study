#!/usr/bin/env bash
# Multiplayer test: a headless host and a headless client on 127.0.0.1 (plus a latecomer who must be turned away).
#   tests/run_net_test.sh            (uses $GODOT, else `godot` from PATH)
#   GODOT=/path/to/godot NET_TEST_PORT=24599 tests/run_net_test.sh
# Without NET_TEST_PORT a random free UDP port is used, so parallel runs on one machine don't cross-connect.
# Then a 3-player run (host + 2 clients) checks that exactly one player becomes the secret impostor.
# Prints every log's results; exits 0 only if all of them print PASSED.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# true if something already listens on UDP port $1 (needs `ss`; without it every port counts as free)
port_busy() {
	command -v ss >/dev/null 2>&1 && ss -Hlun 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"
}
if [ -n "${NET_TEST_PORT:-}" ]; then
	PORT="$NET_TEST_PORT"
	if port_busy "$PORT" || port_busy $((PORT + 1)); then
		echo "UDP port $PORT or $((PORT + 1)) is already in use: pick another NET_TEST_PORT" >&2
		exit 2
	fi
else
	for try in $(seq 1 50); do
		PORT=$((20000 + RANDOM % 20000))
		port_busy "$PORT" || port_busy $((PORT + 1)) || break
	done
fi
LIMIT="${NET_TEST_TIMEOUT:-240}"
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

# Three players without the debug override: the real "one secret impostor" rule, and a player who drops and rejoins.
CREW_PORT=$((PORT + 1))
timeout 150 "$GODOT" --headless --path . res://tests/NetTest.tscn -- crew_host --port "$CREW_PORT" >"$LOGS/crew_host.log" 2>&1 &
CREW_HOST_PID=$!
sleep 1
for n in 1 2; do
	# the second crew client drops out mid-run; a forged rejoin ticket is turned away, its real one gets back in
	EXTRA=""; [ "$n" -eq 2 ] && EXTRA="rejoin"
	timeout 150 "$GODOT" --headless --path . res://tests/NetTest.tscn -- crew_client --port "$CREW_PORT" $EXTRA >"$LOGS/crew_client$n.log" 2>&1 &
	eval "CREW_PID_$n=\$!"
done
wait "$CREW_HOST_PID"; CREW_CODE=$?
wait "$CREW_PID_1" || CREW_CODE=1
wait "$CREW_PID_2" || CREW_CODE=1

status=0
for side in host client late crew_host crew_client1 crew_client2; do
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
[ "$HOST_CODE" -eq 0 ] && [ "$CLIENT_CODE" -eq 0 ] && [ "$LATE_CODE" -eq 0 ] && [ "$CREW_CODE" -eq 0 ] || status=1
if [ "$status" -eq 0 ]; then
	echo "NET TEST PASSED"
else
	echo "NET TEST FAILED (host $HOST_CODE, client $CLIENT_CODE, late $LATE_CODE, 3 players $CREW_CODE)"
fi
exit "$status"
