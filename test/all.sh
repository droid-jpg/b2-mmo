#!/bin/bash
# Runs the BizHawk tests in test/ one after another, each with the fake friends it needs, and prints
# a summary table (test, PASS/FAIL, seconds). Logs go to test/out/all/<name>.log, screenshots to
# test/out/all/<name>/.
#   bash test/all.sh              every test and mode
#   bash test/all.sh talk chat    only tests whose name contains one of the words
# B2PORT is the relay port (default 7777). Doors modes run in order (doors-self before doors-reload).
# A test passes when its log has its success marker and no FAIL line or "test error:" line:
#   pass  (default) a line "PASS" or "ALL PASS"
#   smoke           lines "friends=1" and "features: 7"
#   evolve          a line "done, 0 failures"
# Uses set -u, not set -e.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1
out="$root/test/out"
all="$out/all"
mkdir -p "$all"
export B2PORT=${B2PORT:-7777}
wroot="$(cygpath -m "$root")"
wout="$wroot/test/out"
WORDS=("$@")

# want NAME: true when no words were given, or NAME contains one of them
want() {
  [ ${#WORDS[@]} -eq 0 ] && return 0
  local w
  for w in "${WORDS[@]}"; do [[ $1 == *"$w"* ]] && return 0; done
  return 1
}

# verdict NAME MARKER LOG: prints the reason when the test failed, returns 0 when it passed
verdict() {
  local marker=$2 log=$3
  if grep -q 'test error:' "$log"; then echo "test error line"; return 1; fi
  if grep -q 'FAIL' "$log"; then echo "FAIL line"; return 1; fi
  case $marker in
    smoke)
      grep -q 'friends=1' "$log" && grep -q 'features: 7' "$log" || { echo "no smoke result (friends=1, features: 7)"; return 1; } ;;
    evolve)
      grep -q '^done, 0 failures$' "$log" || { echo "no final 'done, 0 failures'"; return 1; } ;;
    none)
      echo "the test prints no verdict"; return 1 ;;
    *)
      grep -qE '^(ALL )?PASS$' "$log" || { echo "no final PASS"; return 1; } ;;
  esac
}

RESULTS=()
FAILS=()

# one NAME SECONDS MARKER KV LUA [FRIEND ARGS...]: setup, up.sh with the fake friends, run.sh, down.sh
# KV is an environment assignment for the test (e.g. DOORS=self) or "-"
one() {
  local name=$1 secs=$2 marker=$3 kv=$4 lua=$5
  shift 5
  want "$name" || return 0
  [ "$kv" = "-" ] && kv=""
  # Files the tests expect to exist before they start
  case $name in
    talk|talk-leave) touch "$out/party.bin" "$out/trade.bin" ;;
    evolve) touch "$out/offer.bin" ;;
    ride3) cp -f "$root/scratch/slot2.bin" "$out/party1.bin" ;;
  esac
  local log="$all/$name.log" t0 t1 why="" res
  bash test/up.sh "$@"
  rm -f "$out/test.log"
  t0=$(date +%s)
  env $kv bash test/run.sh "$lua" "$secs" > "$log" 2>&1
  t1=$(date +%s)
  bash test/down.sh
  mkdir -p "$all/$name"
  rm -f "$all/$name"/shot_*.png
  cp -f "$out"/shot_*.png "$all/$name/" 2>/dev/null
  if why=$(verdict "$name" "$marker" "$log"); then res=PASS; else res=FAIL; FAILS+=("$name: $why"); fi
  RESULTS+=("$(printf '%-14s %-5s %4d' "$name" "$res" $((t1 - t0)))")
  printf '%-14s %-5s %4ds\n' "$name" "$res" $((t1 - t0))
}

# Smoke: one fake friend walking next to us
one smoke 120 smoke - test/t_smoke.lua "--name Ann --x 584 --z 184 --path square"

# Chat: the quick-chat list and the keyboard, with a fake friend to receive the text
one chat 240 pass - test/t_chat.lua "--name Ann --x 584 --z 184 --path stand"

# Door: walk into the building and back out with two friends on the map
one door 150 pass - test/t_door.lua \
  "--name Ann --x 584 --z 232 --path square --size 2 --speed 1 --model 231" \
  "--name Bob --x 520 --z 216 --path line --size 3 --speed 1 --model 240 --plugin ride --ride surf"

# Doors: one run per mode, each with its own fake friend (see the header of test/t_doors.lua)
one doors-self 200 pass DOORS=self test/t_doors.lua "--name Bot --matrix 107 --path stand --x 520 --z 200"
one doors-reload 200 pass DOORS=reload test/t_doors.lua   # no friend; reads the warps self saved
one doors-friend 200 pass DOORS=friend test/t_doors.lua \
  "--name Ann --plugin doors --matrix 107 --path stand --x 600 --z 200 --stay -1"
one doors-nowarp 200 pass DOORS=nowarp test/t_doors.lua \
  "--name Ann --plugin doors --matrix 107 --path stand --x 600 --z 200 --stay -1 --nowarp"
one doors-town 200 pass DOORS=town test/t_doors.lua \
  "--name Ann --plugin doors --matrix 107 --path stand --x 200 --z 200 --stay -1 --route 168,200>62,0,6968,16,7384;6936,6952>77,380,232,0,400"

# Evolve: trades offered by a fake friend whose offer file is written by the test
one evolve 480 evolve - test/t_evolve.lua "--name Ann --x 616 --z 120 --path stand --trade $wout/offer.bin"

# Rides: a friend biking and surfing (ride), two surfing friends (ride2), a surfing friend across a battle (ride3)
one ride 200 pass - test/t_ride.lua \
  "--name Ann --x 584 --z 184 --path square --size 3 --speed 2 --model 231 --plugin ride --ride bike:6,surf:6,walk:5"
one ride2 200 pass - test/t_ride2.lua \
  "--name Ann --x 584 --z 232 --path square --size 2 --speed 1 --model 231 --plugin ride --ride surf --ride-leave 25" \
  "--name Bob --x 520 --z 216 --path line --size 3 --speed 1 --model 240 --plugin ride --ride surf" \
  "--name Cid --x 616 --z 232 --path stand --model 9999" \
  "--name Dee --x 504 --z 184 --path stand --model 234"
one ride3 240 pass - test/t_ride3.lua \
  "--name Bob --x 600 --z 216 --path line --size 2 --speed 1 --model 240 --plugin ride --ride surf --party $wout/party1.bin"

# Talk: the text box, trades by talking, the choice list (test/out/party.bin and trade.bin are written by the test)
one talk 400 pass - test/t_talk.lua \
  "--name Ann --x 568 --z 184 --path stand --party $wout/party.bin --trade $wout/trade.bin --plugin talk"
one talk-leave 300 pass - test/t_talk_leave.lua "--name Ann --x 568 --z 184 --path stand --party $wout/party.bin --plugin talk"

# Watch: a fake friend's battles seen from the receiving side, and our battle frames sent to a watcher
one watch 120 pass - test/t_watch.lua "--name Ann --x 568 --z 184 --path stand --plugin watch"
one watch-send 400 pass - test/t_watch_send.lua \
  "--name Ann --x 584 --z 184 --path stand --party $wroot/scratch/slot2.bin --plugin watch --watch listen"

# Summary
if [ ${#RESULTS[@]} -eq 0 ]; then
  echo "no test matches: ${WORDS[*]}"
  exit 2
fi
echo
printf '%-14s %-5s %5s\n' "test" "result" "secs"
printf '%-14s %-5s %5s\n' "--------------" "-----" "-----"
for r in "${RESULTS[@]}"; do echo "$r"; done
if [ ${#FAILS[@]} -gt 0 ]; then
  echo
  echo "failed:"
  for f in "${FAILS[@]}"; do echo "  $f"; done
  exit 1
fi
echo
echo "all passed"
exit 0
