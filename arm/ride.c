// Black 2 MMO feature: friends biking and surfing (data in MMO_RIDE_AREA, see ride.h).
//
// Biking needs nothing here: the friend's actor is made with their cycling object code by the core.
// A surfing friend gets the game's surf Pokemon (field effect 3, fldeff_namipoke.c) under their
// actor, started the way the player's own is (FldeffNamipoke_Start(..., mode 1): it bobs under
// the actor and lifts it with the outer draw offset) but with ride.c's own task vtable:
//   - the effect has ONE 3D object for the Pokemon and one for its wake, shared by every task.
//     The game's grid task places them in its update and only draws in its draw, so with two
//     surfers (us and a friend) both would be drawn where the last update put them. Ours places
//     them right before drawing, and afterwards puts them back where the player's own task wants
//     them (FldeffNamipoke_PlaceObjects on FieldPlayer_GetRideEffect).
//   - it can tell its tasks from the game's (vtable.draw), so a stale pointer (the field was
//     rebuilt behind a door or a battle) is never deleted by mistake.
//   - it skips update and draw once the actor isn't the friend's any more.
#include "features.h"
#include "ride.h"

static int riderOk(NamipokeTask *w) {
    u32 i = w->params.uid - 0x100;
    FieldActor *a = w->params.actor;
    return i < MMO_SLOTS && MMO_SHARED->slots[i].spawned && MMO_SHARED->slots[i].actor == (u32)a &&
           (*(u32 *)a & 1) != 0; // FieldActor.flags bit 0: in use
}

// Put the shared Pokemon and wake objects back where the player's own surf task placed them
static void restorePlayer(void) {
    Field *field = GSYS_GetField(g_GameSystem);
    if (field == 0) return;
    FieldPlayer *player = Field_GetPlayer(field);
    if (player == 0) return;
    FieldEffectTask *t = FieldPlayer_GetRideEffect(player);
    if (t != 0 && t->active && t->vtable.draw == FldeffNamipoke_DrawGrid) FldeffNamipoke_PlaceObjects(t, t->work);
}

static void rideUpdate(FieldEffectTask *task, void *work) {
    if (!riderOk(work)) return;
    FldeffNamipoke_UpdateGrid(task, work);
    restorePlayer();
}

static void rideDraw(FieldEffectTask *task, void *work) {
    if (!riderOk(work)) return;
    FldeffNamipoke_PlaceObjects(task, work);
    FldeffNamipoke_DrawGrid(task, work);
    restorePlayer();
}

// Whether slot i's task pointer is still one of ours in the field's current effects
static FieldEffectTask *liveTask(FieldEffects *fx, int i) {
    FieldEffectTask *t = (FieldEffectTask *)RIDE->task[i];
    if (t == 0 || fx == 0 || (u32)fx != RIDE->effects) return 0;
    if (!t->active || t->store != fx->taskStore || t->vtable.draw != rideDraw) return 0;
    if (((NamipokeTask *)t->work)->params.actor != (FieldActor *)RIDE->actor[i]) return 0;
    return t;
}

void ride_tick(GameSystem *gsys) {
    MmoShared *sh = MMO_SHARED;
    RideArea *r = RIDE;
    if (!sh->ready) return; // the map isn't up: touch nothing (stale tasks are told apart later)
    Field *field = GSYS_GetField(gsys);
    FieldEffects *fx = Field_GetFieldEffects(field);

    for (int i = 0; i < MMO_SLOTS; i++) {
        MmoSlot *slot = &sh->slots[i];
        FieldActor *actor = (FieldActor *)slot->actor;
        FieldEffectTask *t = liveTask(fx, i);
        int want = r->surf[i] == 1 && slot->spawned && actor != 0 && !slot->hidden;

        if (t != 0 && (!want || (u32)actor != r->actor[i])) {
            FieldEffects_DeleteObject(t);
            r->deleted++;
            if (slot->spawned && (u32)actor == r->actor[i]) {
                VecFx32 zero = { 0, 0, 0 };
                FldAct_SetOuterDrawOffset(actor, &zero); // off the Pokemon, back on the ground
            }
            t = 0;
        }
        if (t == 0) r->task[i] = 0;
        if (t == 0 && want) {
            void *nami = FieldEffects_GetHandleData(fx, FLDEFF_NAMIPOKE);
            if (nami == 0) continue;
            NamipokeTaskParams p;
            p.namipoke = nami;
            p.actor = actor;
            p.uid = 0x100 + i;
            p.zoneId = 0;
            p.dir = slot->dir & 3;
            p.pos.x = slot->x;
            p.pos.y = slot->y;
            p.pos.z = slot->z;
            FieldEffectTaskVTable vt = { sizeof(NamipokeTask), FldeffNamipoke_Init, FldeffNamipoke_Exit, rideUpdate, rideDraw };
            t = FieldEffects_TCBCreate(fx, &vt, &p.pos, 1, &p, 0);
            if (t != 0) {
                r->task[i] = (u32)t;
                r->actor[i] = (u32)actor;
                r->effects = (u32)fx;
                r->created++;
            }
        }
    }
}

void ride_slot(int i, MmoSlot *slot, FieldActor *actor) { (void)i; (void)slot; (void)actor; }
