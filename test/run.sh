#!/bin/bash
# Runs one BizHawk test: bash test/run.sh test/<name>.lua [timeout s]
# Each checkout (worktree) gets its own BizHawk config and output folder (test/out), so several
# checkouts can run tests at the same time. The test reads its paths and port from test/out/env.lua.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/test/out"
mkdir -p "$out"
BIZHAWK=${BIZHAWK:-/e/Tools/BizHawk}
ROM=${ROM:-"C:\Users\samin\Downloads\Black2.nds"}
STATES=${STATES:-E:/b2-mmo/scratch/states}
port=$(cat "$out/port" 2>/dev/null || echo "${B2PORT:-7777}")
[ -f "$out/config.ini" ] || cp "$BIZHAWK/config.ini" "$out/config.ini"
wroot="$(cygpath -m "$root")"
cat > "$out/env.lua" <<LUA
return { root = "$wroot/", out = "$wroot/test/out/", states = "$STATES/", port = $port }
LUA
lua="$(cygpath -w "$(realpath "$1")")"
rm -f "$out"/shot_*.png
cd "$BIZHAWK"
./EmuHawk.exe --config="$(cygpath -w "$out/config.ini")" --lua="$lua" "$ROM" > "$out/emu.out" 2>&1 &
pid=$!
for i in $(seq 1 "${2:-300}"); do sleep 1; kill -0 $pid 2>/dev/null || break; done
kill $pid 2>/dev/null
cat "$out/test.log" 2>/dev/null
true
