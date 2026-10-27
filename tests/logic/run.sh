#!/bin/bash
# Compiles NoxDark.swift with the logic checks and runs them (no app, no dark-mode change).
set -e
D=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d)
swiftc "$D/../../App/NoxDark.swift" "$D/main.swift" -o "$T/logic" && "$T/logic"
