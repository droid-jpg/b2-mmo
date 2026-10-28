// Black 2 MMO feature: live (data in MMO_LIVE_AREA, see shared.h).
#include "features.h"

void live_tick(GameSystem *gsys) { (void)gsys; }
GameEvent *live_event(GameSystem *gsys) { (void)gsys; return 0; }
void live_battle_setup(GameEvent *battle, void *setup) { (void)battle; (void)setup; }
void live_battle_end(void) {}
