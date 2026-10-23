#!/bin/bash
# Opens another menu bar app's popover (Ludus), runs Nox's fade test, checks the popover stayed open,
# and records frames of the fade (brightness of the left and right of the screen should move together).
# Needs Screen Recording for the terminal. Usage: tests/mac-fade-test.sh <frames-dir>
set -e
D=$(cd "$(dirname "$0")" && pwd); OUT=${1:-/tmp/nox-fade-frames}; mkdir -p "$OUT"; T=$(mktemp -d)
swiftc -O "$D/post.swift" -o "$T/post"; swiftc -O "$D/cap.swift" -o "$T/cap" 2>/dev/null
"$T/post" com.solomon.Ludus.test panel; sleep 0.4
("$T/cap" 4 "$OUT" >/dev/null &); sleep 0.2
"$T/post" com.solomon.DarkSwitch.test fadetest; sleep 1.9
"$T/post" com.solomon.Ludus.test status; sleep 0.4
tail -1 ~/Library/Logs/Ludus.log | grep -q "shown=true" && echo "PASS: other popover still open" || echo "FAIL: other popover closed"
"$T/post" com.solomon.Ludus.test close
