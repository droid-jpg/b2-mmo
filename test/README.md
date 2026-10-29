# BizHawk tests

Each test is a Lua script BizHawk runs with the ROM: it loads a save state on the field (Nimbasa
City, zone 64, player at x 568 z 200), starts the client (`lua/b2mmo.lua`) with test settings, and
checks things every frame through the `B2MMO_TEST` hook (see `lib.lua`). A fake friend
(`tools/fakefriend.mjs`, plus plugins in `tools/ff/`, see [`tools/ff/README.md`](../tools/ff/README.md))
plays the other player.

```bash
B2PORT=7777 bash test/up.sh "--name Ann --x 584 --z 184 --path square"   # server + fake friend(s)
bash test/run.sh test/t_smoke.lua 120                                    # BizHawk, prints test/out/test.log
bash test/down.sh
```

- Every checkout (git worktree) has its own `test/out/` (log, `shot_*.png` screenshots, BizHawk
  config), so checkouts can run tests at the same time: give each its own `B2PORT`.
- `run.sh` needs BizHawk (`BIZHAWK`, default `/e/Tools/BizHawk`), the ROM (`ROM`, default
  `C:\Users\samin\Downloads\Black2.nds`) and the save states (`STATES`, default
  `E:/b2-mmo/scratch/states`). None of these are in the repo.
- Tests never save in-game. BizHawk's SaveRAM for the ROM holds a completed save (8 badges).
- Build the in-game code first if `arm/` changed: `wsl -e bash -lc 'cd /mnt/e/<checkout> && bash scripts/build.sh'`.

## Writing a test (`lib.lua`)

`local K = dofile(<test dir> .. "lib.lua")`, then `K.start(cfg, fn)` loads the save state, sets the
settings (`cfg` becomes `B2MMO_CFG`) and calls `fn(s, f)` every frame: `s` is the client's API
(`s.me`, `s.friends`, `s.partyRaw()`, `s.monLabel(raw)`, `s.ir32(addr)`, ...), `f` the frame count.
Helpers: `K.log(s)` writes to `test.log`, `K.shot(name)` a screenshot, `K.press(keys)` the buttons,
`K.party(s)` our party as text, `K.dumpParty(s, path)` our party to a file for `--party`.

Verdicts: `K.check(ok, what)` logs `OK what` or `FAIL what`; `K.verdict()` logs `PASS` when there was
at least one check and all were OK, else `FAIL (n of m checks)`. An error inside the test logs
`test error:` and exits BizHawk.

## Running all tests (`test/all.sh`)

`bash test/all.sh` runs every test and mode one after another, each with the fake friends its
header asks for (`up.sh`, then `run.sh`, then `down.sh`), and prints a table of PASS/FAIL and
seconds. Logs go to `test/out/all/<name>.log`, screenshots to `test/out/all/<name>/`. Pass words to
run only the tests whose name contains one of them: `bash test/all.sh talk chat`. The relay port is
`B2PORT` (default 7777). The exit code is 0 only if everything passed.

A test passes when its log has its verdict and no `FAIL` or `test error:` line:

- default: a line `PASS` or `ALL PASS` (most tests)
- `smoke`: `friends=1` and `features: 7`
- `evolve`: `done, 0 failures`

| Test (`all.sh` name) | What it checks |
|---|---|
| `smoke` (`t_smoke.lua`) | the client starts and connects; a friend shows up next to us and walks |
| `chat` (`t_chat.lua`) | Select's quick list (the game's box), presets, B, the keyboard (up to 10 letters), an empty name sends nothing |
| `door`, `doors-*` (`t_door.lua`, `t_doors.lua`) | walking through a door with friends on the map; "Ann is inside" learned from our trips, a friend's trips, a flagged hop (not learned), two doors deep (`town`), the saved file reloaded (`reload`) |
| `evolve` (`t_evolve.lua`) | trades a friend offers come in, "X sent over Y!", the evolution scene, the Pokédex |
| `ride`, `ride2`, `ride3` (`t_ride*.lua`) | a friend biking and surfing; two surfers and one leaving while surfing; a surfing friend across a battle |
| `talk`, `talk-leave` (`t_talk*.lua`) | the talk box and choice list, trades by talking both ways, B and Cancel, Battle from the list; a friend who leaves while you talk |
| `watch`, `watch-send` (`t_watch*.lua`) | a friend's battles seen from the receiving side; our battle frames sent to a watcher |
| `live-normal`, `live-decline`, `live-leave`, `live-guest` (`t_live.lua`) | one game against the fake friend's live battle: accepted and played to the end, declined, the friend leaving mid-battle, challenged from the other side |

`t_doors_probe.lua` is a dev aid (lists the zone's warps and walks through one door), not in `all.sh`.

## Live battles with two games (`test/live2.sh`)

`B2PORT=7782 bash test/up.sh` (server only), then `bash test/live2.sh 900`: two BizHawk games
(`test/out` Michael, `test/out/b` Hilda, both from `field2.State`) play one live battle to the end
(`t_live_a.lua`, `t_live_b.lua`, `t_live_two.lua`) and the script compares the HP/checksum both
logged at every step ("SAME in both games: N steps"). It unbinds the mouse from the touch screen in
both test configs (the tests touch the screen from Lua).
