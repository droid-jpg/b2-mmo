#!/bin/bash
# (Re)starts this checkout's relay server and fake friends: bash test/up.sh "<fakefriend args>"...
# The port is B2PORT (default 7777); give each checkout its own. The room is TEST.
# Logs: test/out/server.out, test/out/ff1.out... Stop them with: bash test/down.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/test/out"
mkdir -p "$out"
bash "$root/test/down.sh"
port=${B2PORT:-7777}
echo "$port" > "$out/port"
node "$root/server/server.mjs" "$port" > "$out/server.out" 2>&1 & echo $! >> "$out/pids"
sleep 1
n=0
for a in "$@"; do
  n=$((n+1))
  node "$root/tools/fakefriend.mjs" --port "$port" --room TEST $a > "$out/ff$n.out" 2>&1 & echo $! >> "$out/pids"
done
