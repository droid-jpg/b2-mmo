# Black 2 MMO — status (updated 2026-10-29)

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
| Chat in the game | ✅ **Select** on the field: a quick list (Hi!, Follow me!, Wait for me!, Battle?, Trade?, /who) in the game's text box and choice list, or **Type a message...** for the game's own keyboard (up to 10 letters), sent like the window's chat. The last few lines stay on the bottom screen for a while. `lua/features/chat.lua`, `arm/chat.c`; tested with `test/t_chat.lua` (list, keyboard, empty name sends nothing, walking again after) |
| Player list | ✅ hold Tab: everyone's zone name (`lua/zones.lua`, from the decomp's zone list), "(in a battle)" for those battling |
| Talk menu | ✅ **A** facing a friend: their greeting in the game's own text box (`arm/talk.c`), with a choice list: **Battle**, **Trade**, **Live battle**, **Cancel** (B backs out). Each feature adds its own choice (`api.actions`). A friend in a battle gets a line first ("X is battling: A vs B"). The friend sees "X is talking to you!". Long texts run over several pages. `lua/features/talk.lua`, tested with `test/t_talk.lua` and `test/t_talk_leave.lua` (greeting, choice list, trades by talking both ways, B and Cancel, 10 talks in a row, a friend leaving mid-talk) |
| Trading | ✅ window: both offer, both accept, the server commits to both at once, the received Pokémon is written into your party by the game's CPU (data cache safe). Also by talking: pick your Pokémon from the choice list, the friend answers Yes/No in their box. Tested: Kyurem traded for a Sigilyph, the game's party screen shows it |
| Trade evolutions | ✅ a Pokémon that evolves by trade (the game's check: trade, trade holding an item, Everstone) gets "X sent over Y!" in the game's box, then the game's evolution scene on that slot. The Pokémon is put in the Pokédex as the in-game trade does. `lua/features/evolve.lua`, `arm/evolve.c`; tested with `test/t_evolve.lua` |
| Battling a friend's team | ✅ window → Battle their team, or **Battle** in the talk menu: the game's trainer battle (`EventTrainerBattleCall_Create`, single, no-blackout flag) against trainer 360 (Nate) or 363 (Rosa) with the friend's party swapped in (healed) and their name ("You are challenged by PKMN Trainer Ann!"). Afterwards our party and cash are put back and the field fades back in. Tested to the end of a battle |
| Live battles | ✅ talk to a friend → **Live battle** (or the window): our whole party (PARTY op 3) and a LIVE CHALLENGE with a random seed go to them; their game asks "X challenges you to a live battle! Battle X now?" in its own text box. Yes → their party and ACCEPT come back and both games start the friend battle against the other's team with the live hooks armed (`arm/live.c`): the battle server's "has every client answered?" poll (`BattleServer_AllClientsReplied`) is replaced, so our answers to commands 3/5/6 (move, item, switch, send-in) go to the friend and their answers replace the AI's for their side (move targets mirrored); both games seed the battle RNG with the shared seed (jump at `buildSeed` while the battle starts), the battle RNG is put back after every command as the server left it (the AI and UI can't move it in one game only), both speed sorts (`ActionOrder_Sort`, `SortBySpeed`) put the host's side first so coin-flip ties agree, EXP off, battle style Set while it runs, no field weather, both teams healed. An HP checksum rides along with every step. **Tested 2026-10-29 with two BizHawk games** (`test/live2.sh`, same save, Kyurem + Sigilyph mirror: speed ties every turn, two knock-outs and send-ins each side, Fly's two turns): 26 steps, identical HP in both games at every step, every check matched, "You lost to Hilda!" / "You beat Michael!", both parties byte-identical afterwards. Against the fake friend (`test/t_live.lua`, `tools/ff/live.mjs`): host, guest (answered in the text box), decline, and the friend disconnecting mid-battle (the AI plays on). Not tried: double/triple battles (always single), over the internet |
| Watching a friend's battle | ✅ while you battle (wild, trainer, a friend's team) your game sends BATTLE frames, read by Lua from the battle's own memory (`lua/features/watch.lua`; tested in a trainer battle: HP and a faint followed). **A** on a friend in a battle (talk menu's text box, or the first line of it): a notice with what each side has out, and the bottom screen lists both teams with live HP bars until their battle ends, you walk away or press **B**. The Tab list says "(in a battle)". Received side tested with `fakefriend --plugin watch` (`test/t_watch.lua`); sending side with `test/t_watch_send.lua` |
| Friends biking and surfing | ✅ a friend on a bike shows the game's cycling form (their own object code). A surfing friend gets the game's surf Pokémon and wake under them (`arm/ride.c`, its own task so two surfers, us and a friend, don't draw over each other; a battle that rebuilds the field forgets the old one, not deletes it). Only the walking, cycling and surfing forms (231–233 Nate, 240–242 Rosa) are sent or accepted: fishing, cutscene poses or any other code show the walking form, since an actor made from those can crash the game. Tested with `test/t_ride.lua`, `t_ride2.lua` (two surfers, one leaving), `t_ride3.lua` (across a battle) |
| Activity notices | ✅ catches (Pokédex caught flags, scanned every 2 s by the ARM code), evolutions (same PID, new species in the party), badges. Received side tested with `fakefriend --events`; our own catch/evolution/badge not yet triggered in a real game |
| "Ann is inside" on doors | ✅ every map change seen (yours, and every friend's on any map) teaches a warp both ways, plus the game's own warp list of each zone you're in (`lua/features/doors.lua`). A friend on another map gets a steady label on the door or map edge of your map that leads toward them, up to 4 doors deep: "Ann is inside" (a building of this place, or the one right through that door) or "Cal, Dee are in Musical Theater"; off screen, at the screen edge with an arrow. A friend leaving your map leaves a fading "Ann → Pokémon Center" note. Fly, Teleport, Dig, Escape Rope, whiteouts and cutscenes teach nothing (STATE bit 3: a map change counts as a warp only when you left from one of the old zone's warps to the new zone). Saved in `lua/b2mmo-warps.txt`. Tested in Nimbasa City (`test/t_doors.lua`, modes self, reload, friend, nowarp, town: our own trip, a friend's, a flagged hop, two doors deep). Fly itself not walked in a test |
| Windows package | ✅ `scripts/package.sh` zip; `Install Black 2 MMO.bat` (tested with scripted answers) writes `lua/b2mmo.ini` and `Play Black 2 MMO.bat` |
| Party editor | `tools/pkedit.mjs` (`show`, `edit`, `pick`, `selftest`): edits Gen 5 party dumps, to set up a test team. A port of the decoding in `lua/pkm.lua` |

## Known limits

- **Chat:** 10 characters max; typing on the touch screen untested.
- **Talk:** the party pick is a choice list, not the party screen.
- **Watch:** status conditions are not sent; wild and double battles untested.
- **Trade evolutions:** Karrablast/Shelmet untested.
- **Doors:** real Fly and Dig untested.
- **Ride:** no rail maps, no sounds.
- **Live battles:** singles only; bag items not restored; terrain not equalised; untested over the internet.

## Not tested yet

- Two real BizHawk windows against each other: only for live battles so far (`test/live2.sh`).
- Friends in another zone of the overworld matrix (routes next to each other) — the code draws them
  (matrices 0 and 175), but no test walked between routes yet.
- Warping into buildings with friends shown (actors persist across zone changes, flag 0x20; the Lua
  side releases them when zones differ).
- Over the internet.

## Not done (ORAS MMO has these)

- **A trade animation:** the trade itself is the mod's own (the server commits both sides); trade
  evolutions show the game's evolution scene, nothing more.
- Rail maps and sounds for the bike and surf (see Ride above).

## Tests

`bash test/all.sh` runs the BizHawk tests with their fake friends and prints PASS/FAIL per test;
`bash test/live2.sh` runs the two-game live battle. Both need BizHawk and the ROM on this machine
(see [`test/README.md`](test/README.md)).

## How to pick it up

1. Build: `wsl -e bash -lc 'cd /mnt/e/b2-mmo && bash scripts/build.sh'` (devkitARM in WSL).
2. Server: `node server/server.mjs`; fake friend: `node tools/fakefriend.mjs --room TEST --zone 64
   --x 584 --z 184` (Nimbasa City, next to the test save's spot; `--path stand|line|square`,
   `--party file`, `--trade file`, `--events`, `--chat`, `--listen`, `--plugin` for the plugins in
   `tools/ff/`, see [`tools/ff/README.md`](tools/ff/README.md)).
3. BizHawk: `EmuHawk.exe --lua=E:\b2-mmo\lua\b2mmo.lua <rom>`. Tests set `B2MMO_CFG` and a
   per-frame `B2MMO_TEST(state)` hook before `dofile`-ing the script (see docs/NOTES.md, Testing).
