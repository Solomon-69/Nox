#!/bin/bash
# Opens another menu bar app's popover (Ludus), runs Nox's fade test, and checks the popover
# stayed open. Needs no Screen Recording. Usage: tests/mac-fade-test.sh
set -e
D=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d)
swiftc -O "$D/post.swift" -o "$T/post"
"$T/post" com.solomon.Ludus.test panel; sleep 0.4
"$T/post" com.solomon.DarkSwitch.test fadetest; sleep 1.9
"$T/post" com.solomon.Ludus.test status; sleep 0.4
tail -1 ~/Library/Logs/Ludus.log | grep -q "shown=true" && echo "PASS: other popover still open" || echo "FAIL: other popover closed"
"$T/post" com.solomon.Ludus.test close
