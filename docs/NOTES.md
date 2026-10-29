# Black 2 MMO — how it was built

Target: Pokémon Black 2 (USA), game code `IREO`, revision 0, run by BizHawk 2.11.1's melonDS core in
DS mode (so the game takes its NTR paths: 4 MB of main RAM, `OS_IsRunOnTwl()` false).

## Starting point: ORAS MMO

ORAS MMO is a 3GX plugin: C++ that Azahar's plugin loader runs inside Alpha Sapphire, found with
Ghidra and a GDB stub (see that repo's `re/NOTES.md`). A DS game has no plugin loader, so the port is
split in two:

- **Lua in BizHawk** does what a plugin's host side did: TCP (BizHawk's Lua has .NET, so
  `System.Net.Sockets.TcpClient` through `luanet`; byte arrays come back as Lua strings and Lua strings
  go in as byte arrays, byte for byte), drawing (`gui.*`), the window (`forms.*`), and reading/writing
  memory every frame.
- **A small ARM program inside the game** (`arm/`) does what needs the game's own functions: it is
  written into the DS's instruction TCM by the Lua script and called by the game once a frame.

The relay server and wire protocol are ORAS MMO's unchanged.

## Finding things: the pokebw2 decompilation

Instead of starting from a bare disassembly, the work leaned on the
[pokebw2](https://github.com/fuddlesworth/pokebw2) decompilation (a byte-matching decomp of Black 2 /
White 2 USA). Its `config/b2_us/arm9/symbols.txt` and `overlays/ovNNN/symbols.txt` give the address
of every function by name, and `include/` gives the structures. The user's ROM is a scene dump whose
SHA1 differs from the decomp's base ROM (padding), but it is the same IREO rev 0 program: every
address used here was checked at run time (code bytes, return values) before it was trusted.

The things the mod uses, and why:

| What | Where | Notes |
|---|---|---|
| `g_GameSystem` | `0x021410F4` | `GameSystem*`. `+0x10` event provider, `+0x14` its data, `+0x1C` GameData, `+0x20` Field |
| Event provider | `GameSystem+0x10` | "asked for a new event every frame that none runs" (30 fps on the field). Replacing the pointer gives a per-frame call in the main loop, outside any event, and its return value **starts an event**: that's how the friend battle starts |
| `FldCommActSys_*` | ov036 `0x0218AEB4` create actor, `0x0218AF08` delete | The game's actors for other players in a wireless session (`field_comm_actor.c`): made with move code 0x44, they read a position, a direction and a hidden flag through pointers every frame. The struct is tiny, so the mod keeps its own in ITCM instead of calling `FldCommActSys_Create` |
| Actor flags | `fldmmdl.c` | The comm actors get flag 0x20 (survive `DeleteAllActors` on zone changes) and movement flag 0x100000 (`ActorSave_Save` skips them, so friends never end up in the save file). Collision is flag 0x80, toggled with `SetActorCollisionEnabled` |
| Player | `Field_GetPlayer`, `FieldPlayer_GetActor`, `CopyActorPosAllAdd`, `GetActorFaceDir`, `FldAct_GetObjCode`, `FieldPlayer_DeriveExState` | What `CommPlayer_GetMyStatus` (ov012 `comm_player.c`) sends in a real wireless session |
| Zone / matrix | `Field_GetPlayerStateZoneID`, `GetZoneMatrixId` | Only the overworld matrices (0, 175) hold several zones (`res/field/matrices/*.json` with a `zones` grid); every other matrix is one zone's and is shared by many buildings, so friends are matched by zone there |
| Party, badges, Pokédex | `GameData_GetParty`, `getTrainerCardDataBlkAddress` (+4 badges, +0 cash), `GameData_GetPokedex` + `PokeDex_IsCaught` | |
| Trainer battle | ov012 `EventTrainerBattleCall_Create(gsys, field, 0, 0, trainer, 0, 1)` | Flag 1 = losing doesn't black out. Its event data holds the `BtlSetup*` at +8; `BtlSetup_GetParty(setup, 1)` is the opponent's party, which the game itself rewrites the same way for in-game-trade rematches (`LoadTradedPokemonBattleStats`). Trainer names: `BtlSetupTrainer+0x14` and `BtlSetup.trainerNames[1]`, set with `GFL_StrBufLoadString`. Trainers 360/363 are "PKMN Trainer Nate/Rosa" |
| Our battle (watching) | `g_GameSystem`+0x08 `GameProcManager` +0x08 running `GameProc` (+0x00 functions, +0x08 state, +0x14 work, +0x18 parent) | The battle runs as a proc of the game system's own manager in place of the field (`functions` = `0x021D6CE0`, ov167's `BtlMain` table; state 2 = main), its work is the `BtlMainModule`: +0x46C player client id, +0xC8 `pokeCons[0]` (the clients' view; [1] at +0x1B0 is the server's), `BtlPokeCon`+4+client×0x1C a `BattleParty` (6 `BattleMon*`, u8 count @0x18, slot 0 the one out). `BattleMon` +0x0C species, +0x0E max HP, +0x10 HP, +0x18 level, +0x1C conditions (1..5 = major status). Checked in a trainer battle |
| Back to the field | ov036 `CallFieldMapEntranceInTransition(gsys, field, 0, 0, 1, 0, 0)` | A trainer battle reopens the field "headless" (scripts fade it in themselves); the friend battle event chains this to fade in |

## Where the code lives

`OS` arena info at `0x027FFDA0` showed the ITCM arena unused: the game's ITCM code ends at
`0x01FF93A0` and nothing writes above it (a map of non-zero 1 KB blocks stayed the same while
walking, in menus and through battles). ITCM is never cached, so writing code and data there from
the emulator is safe, and the comm actors can read friends' positions straight out of it.

| ITCM | What |
|---|---|
| `0x01FFA000` | shared block (`arm/shared.h`): magic, the saved provider, what the game reports, 8 friend slots |
| `0x01FFA300` | a Pokémon to write into the party (trades) |
| `0x01FFA400` | the code (`arm/link.ld`), ~2 KB |
| `0x01FFAF00` | friend battle: the friend's name, then their party at `0x01FFB000`, our party backup at `0x01FFB600`, our party after the battle at `0x01FFBC00` |

Writes into main RAM that the game must see right away (trades, the party restore) are done by the
ARM code, not by BizHawk's memory API, so they go through the ARM9's data cache. The provider pointer
is the one main-RAM word Lua writes, and it is re-checked every frame.

## The friend actors

`FieldCommActor` update (`func_ov036_0218b060`): if the linked position differs from the actor's, it
moves the actor there and sets draw status 3 (walk animation), or 10 (run) when the move is 4+ units
in a frame and the entry's `run` flag is set (we set it). Lua therefore replays each friend's
positions at their real speed (interpolated, 150 ms behind) and the game animates them by itself.

## Talking

Pressing A in front of a comm actor starts no script in the game (it was checked that it doesn't
hang, unlike ORAS where an NPC without a script hung the script runner). Lua sees A pressed while
the field is live and a friend is on the tile in front, and runs the conversation itself.

The conversation is the game's own text box and choice list (`arm/talk.c`): an event that shows a
message (Black 2's text codes: UTF-16, 0xFFFE a new line, a page break as 0xF000 0xBE01 0x0000
0xFFFE), then, if there are choices, the game's list menu beside it, and writes the player's answer
where Lua reads it. The event stays up until Lua says what's next, so one conversation reads like a
script. Lua keeps a queue of messages (`api.gameMessage`, `lua/features/talk.lua`); the talk menu
(Battle, Trade, Live battle, ...) is a list of `api.actions` that features add to.

## Chat keyboard

**Select** on the field opens a quick list (the talk box). **Type a message...** opens the game's
name entry, the screen nicknames use, in its trainer-message mode with up to 10 letters and no
profanity filter (`arm/chat.c`, `setupNameEntry`). Lua holds the field still with an idle event while
the list is up; the event lets go if Lua stops refreshing it (a counter in the chat block), so a
crashed script can't leave the player stuck.

## Trade evolutions

After a trade writes the Pokémon into the party, `arm/evolve.c` asks the game's own check
(`CheckEvolveSpecies`, trade method: trade, trade holding an item, Karrablast/Shelmet, Everstone).
If it evolves, Lua shows "X sent over Y!" and the game's evolution demo (`ShinkaDemoParam`, run as
`fld_trade.c` runs it) plays on that slot. The traded-in Pokémon is put in the Pokédex the way the
in-game trade does it. The core would report both the catch and the evolution as notices, so it
drops those species from its queue for a moment (`quiet()`).

## Friends' bikes and surf

A friend's actor already wears their own player object code, so biking needs nothing more. Surfing
gets the game's surf Pokémon under the actor (field effect 3, `fldeff_namipoke.c`). It runs in its
own task (`arm/ride.c`) because the game keeps one set of 3D objects for the surf Pokémon and its
wake: with two surfers, the game's task would draw both where the last update put them. Ours places
them just before drawing and puts them back where the player's own surf task wants them. A task
whose actor is no longer the friend's is skipped, and a stale one (the field was rebuilt by a battle
or a door) is forgotten, never deleted.

## Watching a battle

Our side is read from the battle's own memory by Lua every frame (`lua/features/watch.lua`, the
structures are in the header comment): the running `GameProc` of the battle, its `BtlMainModule`,
and each side's `BattleParty`. Nothing runs in the game for it, since the field's event provider is
not running during a battle. A friend's battle is only shown while their busy bit and BATTLE frames
keep coming.

## Doors

Every map change seen (ours, and every friend's on any map) is a warp, in both directions: the zone
the mover last stood in, at the spot it left from, leads to the new zone, and the new zone's arrival
spot leads back. The game's own warp list of each zone we're in is learned too. A map change
flagged "no warp" (STATE bit 3: Fly, Teleport, Dig, a whiteout, a cutscene) teaches nothing. Warps
are kept in `lua/b2mmo-warps.txt`, so the labels work from the start next time. Overworld matrices
(0 and 175) share coordinates between their zones, so a route's edge is not a door.

## Testing

`tools/fakefriend.mjs` plays the friend. In BizHawk a test script loads a save state, sets
`B2MMO_CFG = {...}` (settings) and `B2MMO_TEST = function(state) ... end` (called every frame with
`me`, `friends`, `net`, `trade` and the functions `offerTrade`, `acceptTrade`, `startBattle`,
`partyRaw`, `monLabel`), presses buttons with `joypad.set`, takes `client.screenshot`s
(`client.setscreenshotosd(true)` to include the overlay) and `dofile`s `lua/b2mmo.lua`, all under
`EmuHawk.exe --lua=<test>.lua <rom>`.

## Live battles

Both games run the core's friend battle (a trainer battle against the other's party) with themselves
as client 0 (the UI) and the friend as client 1 (the game's AI); `arm/live.c` keeps them in step.
Everything is in pokebw2's `src/ov167` (battle) and checked at run time:

| What | Where | Why |
|---|---|---|
| `BtlAdapter` | ov167 `btl_adapter.c` | per client: +4 reply*, +8 reply bytes, +0xC low nibble replied (high nibble link), +0xD client, +0xE state (1 to send, 3 waiting, 4 replied), +0xF command, +0x14 command data. One-console battles share one adapter between server and client |
| `BattleServer_AllClientsReplied` | ov167 `0x0219F19C` | the server polls it every frame until every client replied. **Replaced**: our client's answers to commands 3 (action), 5/6 (send-in) are queued for the friend; client 1 only counts as replied once the friend's answer for the same step is in, which replaces the AI's (reply pointer/size). Server: clients[4] @0x14, 0xC each (adapter, BattleParty*, ..., clientId @+0xB) |
| `BtlAdapter_SetCmd` | ov167 `0x021D4AEC` | **Replaced** (same code) to save the battle RNG when a command goes out; it's put back once all replied, so the AI thinking or anything client-side can't move it in one game only |
| `buildSeed` | main `0x02044098` | `BtlMain_ProcInit` (ov167, `LR 0x02199A6B`) seeds the battle RNG from entropy with it. A jump at its start (written from the field in `live_battle_setup`, removed on its first call) gives the battle the shared seed and, since ov167 and ov169 are loaded by then, patches the battle code |
| `BattleRandom` / `data_ov167_021dd844` | ov167 `0x021BD0C0`, RNG at `0x021DD84C` | MATHRandContext32 (x, mul 0x5D588B656C078965, add 0x269EC3) |
| `ActionOrder_Sort` | ov167 `0x021A0308` | **Replaced**: entries (16 bytes, client @0xC) host's first, then the game's sort (ties: `BattleRandom(2)` in list order) |
| `SortBySpeed` | ov169 `0x0689D0AC` (runs from VRAM) | **Replaced** the same way; BtlMonSet count @0x42, speed[] @0x36; `BtlServerFlow_CalcSpeed` ov167 `0x021ABD08`. VRAM takes halfword writes only |
| `func_ov167_0219bdfc` | ov167 `0x0219BDFC` | "does the player's side gain EXP?": patched to return FALSE (only caller: `ServerControl_CheckExpGain`) |
| BtlSetup | `+0x10` weather, `+0x74` Config* | weather cleared (each field has its own); Config bit 6 = battle style, set to Set while the battle runs (Shift asks only the player) |
| Code patches | `DC_FlushRange 0x0207B0AC`, `IC_InvalidateRange 0x0207B0E8` | each patched function starts with `bx pc; nop; ldr pc, [pc, #-4]; .word fn` (no register used); the patches go away with the overlays |

Action words (`BattleAction`): action bits 0..3, a move's target position bits 4..6 (the UI sends 6, "the
game picks", in singles; the AI an explicit position), move bits 7..22; a switch: position bits
4..6, battle party slot bits 7..9 (the UI's send-in of slot 1 is `0x83`). Positions alternate between
the clients, so the friend's targets get bit 0 flipped. The whole party goes over (eggs too, in order),
since switches name battle party slots. `test/live2.sh` runs two BizHawk games against each other.

## Not found yet

- The field camera's matrix (labels use a fitted projection: about 1.06 px a unit across and 1.02
  down at the player's depth, growing toward the camera).
