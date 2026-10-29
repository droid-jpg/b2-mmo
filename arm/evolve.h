// Trade evolutions: the game's own trade-evolution check on a Pokemon a trade just put in the party,
// then the game's own evolution scene (ov284 shinka_demo) on that party slot, as a field event.
#pragma once
#include "game.h"
#include "shared.h"

// MMO_EVOLVE_AREA (0x100 bytes), shared with lua/features/evolve.lua
typedef struct {
    u32 req;         // 0x00 Lua: party slot + 1 a trade just wrote: check it (game zeroes it)
    u32 checks;      // 0x04 game: +1 per check done
    u32 species;     // 0x08 game: what the last check says it evolves into, 0 = it doesn't
    u32 method;      // 0x0C game: the evolution's method (EVO_METHOD_*: 5 trade, 6 with item, 7 for a species)
    u32 go;          // 0x10 Lua: party slot + 1: start the evolution scene on it (game zeroes it)
    u32 started;     // 0x14 game: +1 per scene started
    u32 finished;    // 0x18 game: +1 per evolution event over (back on the field, or nothing to do)
    u32 reserved;    // 0x1C
    u8 partner[0xDC];// 0x20 Lua: the Pokemon we gave for it (Karrablast <-> Shelmet look at it)
} EvolveArea;

#define EVOLVE_AREA ((EvolveArea *)MMO_EVOLVE_AREA)

// include/demo/shinka_demo.h: the evolution demo's param
typedef struct {
    GameData *gameData;
    void *party;     // PokeParty
    u16 species;     // evolves into
    u8 partyIndex;
    u8 method;       // EVO_METHOD_*: the demo takes the held item for 6 (trade holding an item)
    u32 unkC;        // 1 from the field (fld_trade.c): pushes and restores the field music
    u32 canCancel;   // FALSE after a trade
} ShinkaDemoParam;

#define EVO_CHECK_TRADE 1
#define HEAPID_GAMEEVENT 4
#define OVERLAY_SHINKA_DEMO 284
#define SHINKA_DEMO_PROC_FUNCTIONS ((const void *)0x021E7D9C) // ov284, loaded by the proc system

// pml/evolution.h: the species pkm evolves into in this mode, or 0. For EVO_CHECK_TRADE a3 is the
// PartyPkm it was traded for; an Everstone stops it (shinka_check.c)
#define CheckEvolveSpecies \
    THUMB(0x02020788, u16 (*)(void *, void *, u32, u32, u8, u32 *, u32))
#define PokeParty_GetPkm THUMB(0x0201FF08, void *(*)(void *, u32))
#define PokeParty_GetPkmCount THUMB(0x0201FDF8, int (*)(void *))
#define GameData_GetSeason THUMB(0x020173AC, u8 (*)(GameData *))
// field_event.c: fade the field out, run the proc (loading its overlay), reopen the field, fade in
#define EventFieldSubprocessTransition_Create \
    THUMB(0x020195C0, GameEvent *(*)(GameSystem *, Field *, s32, const void *, void *))
// save/pokedex.h: seen, and seen + caught (with its language), as fld_trade.c registers a trade
#define PokeDex_RegistPkm THUMB(0x0200D72C, void (*)(PokeDexSave *, void *))
#define addPkmToDex THUMB(0x0200D568, void (*)(PokeDexSave *, void *))
#define PokeParty_GetParam THUMB(0x0201CCF8, u32 (*)(void *, u32, void *))
#define PKM_PARAM_SPECIES 0x05
#define PKM_PARAM_IS_EGG 0x4C
