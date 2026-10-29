# Black 2 MMO — status (updated 2026-10-28)

Co-op mod for **Pokémon Black 2 (USA, IREO rev 0)** on BizHawk 2.11.1 (melonDS core, DS mode):
a BizHawk Lua script, a piece of ARM code it puts into the game, and the oras-mmo relay server.
How it works and how it was found: [`docs/NOTES.md`](docs/NOTES.md).

Everything marked ✅ was run in BizHawk against `server/server.mjs` with `tools/fakefriend.mjs`
as the other player, on a completed save (8 badges, Nimbasa City).

## What works

| Feature | State |
|---|---|
| Code injection | ✅ the ARM code goes into ITCM (free from 0x01FF93A0; untouched while walking, in menus and in battles) and the field's event provider (`GameSystem+0x10`) is pointed at it. Re-done automatically after a reset or a new field. Cold boot tested: title → Continue → friends shown on the first map |
| Friends as real trainers | ✅ each friend on your map is one of the game's own other-player actors (move code 0x44, `FldCommActSys` of overlay 36, which the game uses for wireless sessions). They follow the position/direction we write every frame, with the game's walk animation, and its run animation on fast moves. Model = the friend's own player object code (231 Nate, 240 Rosa) |
| Smooth movement | ✅ friends are replayed 150 ms behind, interpolated between packets (sender clock in STATE) |
| Collision | ✅ you can't walk through a friend; it stops blocking while it shares your tile |
| Name labels | ✅ over each friend's head (projected with a fit of the field camera); off-screen friends get a label at the screen edge. Labels and notices hide during menus, text boxes and battles |
| Notices | ✅ joins, leaves, chat, talks, arrivals, catches, evolutions, badges, trade and battle results, one at a time in a box at the top of the screen |
| Chat, `/who` | ✅ in the Black 2 MMO window (BizHawk Lua form) |
| Player list | ✅ hold Tab: everyone's zone name (`lua/zones.lua`, from the decomp's zone list) |
| Talking | ✅ A facing a friend: their greeting as a notice, they get "X is talking to you!". The game itself does nothing (no hang, no script) |
| Trading | ✅ window: both offer, both accept, the server commits to both at once, the received Pokémon is written into your party by the game's CPU (data cache safe). Tested: Kyurem traded for a Sigilyph, the game's party screen shows it |
| Battling a friend's team | ✅ window → Battle their team: the game's trainer battle (`EventTrainerBattleCall_Create`, single, no-blackout flag) against trainer 360 (Nate) or 363 (Rosa) with the friend's party swapped in (healed) and their name ("You are challenged by PKMN Trainer Ann!"). Afterwards our party and cash are put back and the field fades back in. Tested to the end of a battle |
| Activity notices | ✅ catches (Pokédex caught flags, scanned every 2 s by the ARM code), evolutions (same PID, new species in the party), badges. Received side tested with `fakefriend --events`; our own catch/evolution/badge not yet triggered in a real game |
| Watching a friend's battle | ✅ while you battle (wild, trainer, a friend's team) your game sends BATTLE frames, read by Lua from the battle's own memory (`lua/features/watch.lua`; tested in a trainer battle: HP and a faint followed). A on a friend in a battle: a notice with what each side has out, and the bottom screen lists both teams with live HP bars until their battle ends, you walk away or press B. The Tab list says "(in a battle)". Received side tested with `fakefriend --plugin watch` |
| "Ann is inside" on doors | ✅ every map change seen (yours, and every friend's on any map) teaches a warp both ways, plus the game's own warp list of each zone you're in (`lua/features/doors.lua`). A friend on another map gets a steady label on the door or map edge of your map that leads toward them, up to 4 doors deep: "Ann is inside" (a building of this place, or the one right through that door) or "Cal, Dee are in Musical Theater"; off screen, at the screen edge with an arrow. A friend leaving your map leaves a fading "Ann → Pokémon Center" note. Fly, Teleport, Dig, Escape Rope, whiteouts and cutscenes teach nothing (STATE bit 3: a map change counts as a warp only when you left from one of the old zone's warps to the new zone). Saved in `lua/b2mmo-warps.txt`. Tested in Nimbasa City (`test/t_doors.lua`: our own trip, a friend's, a flagged hop, two doors deep). Fly itself not walked in a test |
| Windows package | ✅ `scripts/package.sh` zip; `Install Black 2 MMO.bat` (tested with scripted answers) writes `lua/b2mmo.ini` and `Play Black 2 MMO.bat` |

## Not tested yet

- Two real BizHawk windows against each other (only the fake friend so far).
- Friends in another zone of the overworld matrix (routes next to each other) — the code draws them
  (matrices 0 and 175), but no test walked between routes yet.
- Bike and surf: the friend's object code follows theirs, so a cycling friend should show on the
  bike; surfing has no surf Pokémon under them.
- Warping into buildings with friends shown (actors persist across zone changes, flag 0x20; the Lua
  side releases them when zones differ).
- Over the internet.

## Not done (ORAS MMO has these)

- **Live battles** (each player picks their own moves): needs the battle server's sync hooks found in
  Black 2's battle overlays (ORAS: `LiveBattle.cpp`).
- **Trade evolutions** and a trade animation.
- **Talking in the game's own text box** and a Battle/Trade menu there (ORAS runs its own script
  through the NPC-talk event); here talking is a notice and the rest is in the window.

## How to pick it up

1. Build: `wsl -e bash -lc 'cd /mnt/e/b2-mmo && bash scripts/build.sh'` (devkitARM in WSL).
2. Server: `node server/server.mjs`; fake friend: `node tools/fakefriend.mjs --room TEST --zone 64
   --x 584 --z 184` (Nimbasa City, next to the test save's spot; `--path stand|line|square`,
   `--party file`, `--trade file`, `--events`, `--chat`, `--listen`).
3. BizHawk: `EmuHawk.exe --lua=E:\b2-mmo\lua\b2mmo.lua <rom>`. Tests set `B2MMO_CFG` and a
   per-frame `B2MMO_TEST(state)` hook before `dofile`-ing the script (see docs/NOTES.md, Testing).
