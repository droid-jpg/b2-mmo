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
