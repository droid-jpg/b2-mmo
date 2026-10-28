#!/bin/bash
# Stops what test/up.sh started in this checkout (only those processes).
out="$(cd "$(dirname "$0")/.." && pwd)/test/out"
[ -f "$out/pids" ] && kill $(cat "$out/pids") 2>/dev/null
rm -f "$out/pids"
true
