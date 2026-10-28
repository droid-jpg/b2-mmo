// Black 2 MMO feature: trade evolutions (data in MMO_EVOLVE_AREA, see evolve.h).
//
// After a trade writes a Pokemon into the party (mmo.c, writeSlot), Lua asks for a check (req);
// the received Pokemon goes in the Pokedex (seen and caught) as the in-game trade does.
// The check is the game's own (CheckEvolveSpecies, EVO_CHECK_TRADE: trade, trade holding an item,
// Karrablast <-> Shelmet, Everstone). Lua then shows "X sent over Y!" and asks for the scene (go):
// the game's evolution demo on that slot, run the way fld_trade.c runs it from the field. The demo
// changes the species, takes the held item for a trade-with-item evolution and fills the Pokedex.
#include "features.h"
#include "evolve.h"

typedef struct {
    GameSystem *gsys;
    u32 slot;
} EvolveWork;

static ShinkaDemoParam sParam;
// We put a traded-in Pokemon in the Pokedex, and the demo the species it evolves into; the core
// would report either as a catch. For a while after each, drop that species from the core's catch
// queue (the trade and the evolution have their own notices). [0] the trade, [1] the evolution.
static u32 sQuietTicks[2];
static u16 sQuietSpecies[2];

static void quiet(int i, u16 species) {
    sQuietSpecies[i] = species;
    sQuietTicks[i] = 90; // the core scans the Pokedex every 60 ticks
}

// What the game's in-game trade does with the Pokemon it gives you (fld_trade.c): seen and caught
static void registerTrade(GameSystem *gsys, u32 slot) {
    GameData *gd = *(GameData **)((u8 *)gsys + GSYS_GAMEDATA_OFF);
    void *party = GameData_GetParty(gd);
    if (slot >= (u32)PokeParty_GetPkmCount(party)) return;
    void *pkm = PokeParty_GetPkm(party, slot);
    if (PokeParty_GetParam(pkm, PKM_PARAM_IS_EGG, 0)) return;
    quiet(0, (u16)PokeParty_GetParam(pkm, PKM_PARAM_SPECIES, 0));
    PokeDexSave *dex = GameData_GetPokedex(gd);
    PokeDex_RegistPkm(dex, pkm);
    addPkmToDex(dex, pkm);
}

static u16 checkSlot(GameSystem *gsys, u32 slot, u32 *method) {
    GameData *gd = *(GameData **)((u8 *)gsys + GSYS_GAMEDATA_OFF);
    void *party = GameData_GetParty(gd);
    *method = 0;
    if (slot >= (u32)PokeParty_GetPkmCount(party)) return 0;
    return CheckEvolveSpecies(party, PokeParty_GetPkm(party, slot), EVO_CHECK_TRADE, (u32)EVOLVE_AREA->partner,
                              GameData_GetSeason(gd), method, HEAPID_GAMEEVENT);
}

void evolve_tick(GameSystem *gsys) {
    MmoShared *sh = MMO_SHARED;
    EvolveArea *ev = EVOLVE_AREA;
    // After the core's tick: the trade's party write is in once writeSlot is back to 0
    if (ev->req >= 1 && ev->req <= 6 && sh->writeSlot == 0 && sh->ready) {
        u32 method;
        registerTrade(gsys, ev->req - 1);
        ev->species = checkSlot(gsys, ev->req - 1, &method);
        ev->method = method;
        ev->req = 0;
        ev->checks++;
    }
    for (int i = 0; i < 2; i++) {
        if (sQuietTicks[i] == 0) continue;
        sQuietTicks[i]--;
        for (int k = 0; k < 4; k++) {
            if (sh->caughtNew[k] == sQuietSpecies[i]) sh->caughtNew[k] = 0;
        }
    }
}

static u32 evolveEvent(GameEvent *event, u32 *state, void *data) {
    EvolveWork *w = data;
    EvolveArea *ev = EVOLVE_AREA;
    if (*state == 0) {
        u32 method;
        u16 species = checkSlot(w->gsys, w->slot, &method);
        if (species != 0) {
            GameData *gd = *(GameData **)((u8 *)w->gsys + GSYS_GAMEDATA_OFF);
            sParam.gameData = gd;
            sParam.party = GameData_GetParty(gd);
            sParam.species = species;
            sParam.partyIndex = (u8)w->slot;
            sParam.method = (u8)method;
            sParam.unkC = 1;
            sParam.canCancel = 0;
            GameEvent_ChainNext(event, EventFieldSubprocessTransition_Create(
                                           w->gsys, GSYS_GetField(w->gsys), OVERLAY_SHINKA_DEMO,
                                           SHINKA_DEMO_PROC_FUNCTIONS, &sParam));
            ev->started++;
            *state = 1;
            return 0;
        }
    } else {
        quiet(1, sParam.species);
    }
    ev->finished++;
    return 1;
}

GameEvent *evolve_event(GameSystem *gsys) {
    EvolveArea *ev = EVOLVE_AREA;
    if (ev->go < 1 || ev->go > 6) return 0;
    u32 slot = ev->go - 1;
    ev->go = 0;
    GameEvent *e = GameEvent_Create(gsys, 0, evolveEvent, sizeof(EvolveWork));
    EvolveWork *w = GameEvent_GetData(e);
    w->gsys = gsys;
    w->slot = slot;
    return e;
}
