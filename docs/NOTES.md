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

Pressing A in front of a comm actor does nothing in the game (no script runs; it was checked that it
doesn't hang, unlike ORAS where an NPC without a script hung the script runner). Lua sees A pressed
while the field is live and a friend is on the tile in front, and does the rest as notices.

## Testing

`tools/fakefriend.mjs` plays the friend. In BizHawk a test script loads a save state, sets
`B2MMO_CFG = {...}` (settings) and `B2MMO_TEST = function(state) ... end` (called every frame with
`me`, `friends`, `net`, `trade` and the functions `offerTrade`, `acceptTrade`, `startBattle`,
`partyRaw`, `monLabel`), presses buttons with `joypad.set`, takes `client.screenshot`s
(`client.setscreenshotosd(true)` to include the overlay) and `dofile`s `lua/b2mmo.lua`, all under
`EmuHawk.exe --lua=<test>.lua <rom>`.

## Not found yet

- The field camera's matrix (labels use a fitted projection: about 1.06 px a unit across and 1.02
  down at the player's depth, growing toward the camera).
- Battle sync for live battles: Black 2's battle runs in overlay 167 (`BtlSetup` → `data_ov167_021d6ce0`);
  the client/server split is there (`BtlServer`, `BtlClient`, `BtlAdapter`), as in ORAS.
