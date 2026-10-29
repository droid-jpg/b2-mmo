#!/bin/bash
# Two real games in one live battle: bash test/live2.sh [timeout s]
# Game A (test/out, "Michael", t_live_a.lua) challenges game B (test/out/b, "Hilda", t_live_b.lua),
# which answers Yes in the game's own text box; both play with the touch screen. Both start from
# field2.State. Needs the server: B2PORT=7782 bash test/up.sh (no fake friend needed).
# Logs: test/out/test.log, test/out/b/test.log; then compares both games' HP step by step.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
BIZHAWK=${BIZHAWK:-/e/Tools/BizHawk}
ROM=${ROM:-"C:\Users\samin\Downloads\Black2.nds"}
STATES=${STATES:-E:/b2-mmo/scratch/states}
port=$(cat "$root/test/out/port" 2>/dev/null || echo "${B2PORT:-7777}")
wroot="$(cygpath -m "$root")"
pids=()
for g in a b; do
  out="$root/test/out"; [ $g = b ] && out="$root/test/out/b"
  name=out; [ $g = b ] && name=out/b
  mkdir -p "$out"
  [ -f "$out/config.ini" ] || cp "$BIZHAWK/config.ini" "$out/config.ini"
  # The touch screen follows the host mouse unless unbound: the tests touch it from Lua
  sed -i -E 's/"Value": "WMouse [XY]"/"Value": ""/' "$out/config.ini"
  cat > "$out/env.lua" <<LUA
return { root = "$wroot/", out = "$wroot/test/$name/", states = "$STATES/", port = $port }
LUA
  rm -f "$out"/shot_*.png "$out/test.log"
  lua="$(cygpath -w "$root/test/t_live_$g.lua")"
  cfgw="$(cygpath -w "$out/config.ini")"
  pushd "$BIZHAWK" > /dev/null
  ./EmuHawk.exe --config="$cfgw" --lua="$lua" "$ROM" > "$out/emu.out" 2>&1 &
  popd > /dev/null
  pids+=($!)
  sleep 4
done
for i in $(seq 1 "${1:-600}"); do
  sleep 1
  alive=0
  for p in "${pids[@]}"; do kill -0 $p 2>/dev/null && alive=1; done
  [ $alive = 0 ] && break
done
for p in "${pids[@]}"; do kill $p 2>/dev/null; done
echo "== A (Michael, host)"; cat "$root/test/out/test.log"
echo "== B (Hilda, guest)"; cat "$root/test/out/b/test.log"
# Each game logs "step N check C hp [..]" when it asks step N (both host-first): they must agree
echo "== compare"
grep -o 'STEP .*' "$root/test/out/test.log" | sort > "$root/test/out/steps_a.txt"
grep -o 'STEP .*' "$root/test/out/b/test.log" | sort > "$root/test/out/b/steps_b.txt"
if diff "$root/test/out/steps_a.txt" "$root/test/out/b/steps_b.txt"; then
  echo "SAME in both games: $(wc -l < "$root/test/out/steps_a.txt") steps"
else
  echo "DIFFERENT"
fi
