// Hooks the core (mmo.c) calls into each feature's own file (arm/<feature>.c). A feature keeps
// its data in its own ITCM block (MMO_*_AREA in shared.h) and its game addresses in arm/<feature>.h.
#pragma once
#include "game.h"
#include "shared.h"

// Every frame on the field, after the core's tick (sh->ready says whether the map is up)
void talk_tick(GameSystem *gsys);
void live_tick(GameSystem *gsys);
void watch_tick(GameSystem *gsys);
void evolve_tick(GameSystem *gsys);
void chat_tick(GameSystem *gsys);
void ride_tick(GameSystem *gsys);

// Asked in turn, when no event runs and the core has none to start: return an event to start one
GameEvent *talk_event(GameSystem *gsys);
GameEvent *live_event(GameSystem *gsys);
GameEvent *evolve_event(GameSystem *gsys);
GameEvent *chat_event(GameSystem *gsys);

// Friend battles (friendBattleEvent): once the game's battle is set up with the friend's party and
// name, before it starts; and when it's over, before our party is put back
void live_battle_setup(GameEvent *battle, void *setup);
void live_battle_end(void);

// Each frame for each friend's actor that exists (after the core moved it)
void ride_slot(int i, MmoSlot *slot, FieldActor *actor);
