# BizHawk tests

Each test is a Lua script BizHawk runs with the ROM: it loads a save state on the field (Nimbasa
City, zone 64, player at x 568 z 200), starts the client (`lua/b2mmo.lua`) with test settings, and
checks things every frame through the `B2MMO_TEST` hook (see `lib.lua`). A fake friend
(`tools/fakefriend.mjs`, plus plugins in `tools/ff/`) plays the other player.

```bash
B2PORT=7777 bash test/up.sh "--name Ann --x 584 --z 184 --path square"   # server + fake friend(s)
bash test/run.sh test/t_smoke.lua 120                                    # BizHawk, prints test/out/test.log
bash test/down.sh
```

- Every checkout (git worktree) has its own `test/out/` (log, `shot_*.png` screenshots, BizHawk
  config), so checkouts can run tests at the same time: give each its own `B2PORT`.
- `run.sh` needs BizHawk (`BIZHAWK`, default `/e/Tools/BizHawk`), the ROM (`ROM`) and the save
  states (`STATES`, default `E:/b2-mmo/scratch/states`). None of these are in the repo.
- Tests never save in-game. BizHawk's SaveRAM for the ROM holds a completed save (8 badges).
- Build the in-game code first if `arm/` changed: `wsl -e bash -lc 'cd /mnt/e/<checkout> && bash scripts/build.sh'`.

## Running all tests (`test/all.sh`)

`bash test/all.sh` runs every test and doors mode one after another, each with the fake friends
its header asks for (`up.sh`, then `run.sh`, then `down.sh`), and prints a table of PASS/FAIL and
seconds. Logs go to `test/out/all/<name>.log`, screenshots to `test/out/all/<name>/`. Pass words to
run only the tests whose name contains one of them: `bash test/all.sh talk chat`. The relay port is
`B2PORT` (default 7777). The exit code is 0 only if everything passed.

A test passes when its log has its verdict (`PASS` or `ALL PASS`; `friends=1` with `features: 7` for
smoke; `done, 0 failures` for evolve) and no `FAIL` or `test error:` line. Tests without a verdict
(ride, ride2, ride3, watch, watch-send) always count as FAIL until they print one.
