// Friends on a bike or surfing: the game addresses and structs arm/ride.c uses, and its ITCM block.
//
// A friend's actor is made with their own player object code (core, mmo.c), so a friend on a bike
// already shows the cycling form (Nate 232, Rosa 241; field_player.c PLAYER_SPRITE_MAP) and a
// surfing friend the swim form (233, 242). The surf Pokemon under a surfing player is a separate
// field effect (effect 3, ov036 fldeff_namipoke.c); ride.c starts one for each surfing friend.
#pragma once
#include "game.h"
#include "shared.h"

// MMO_RIDE_AREA (0x01FFF900, 0x100 bytes). lua/features/ride.lua writes surf[], the game the rest.
typedef struct {
    u32 surf[MMO_SLOTS];  // 0x00 Lua: 1 = the friend in slot i surfs (STATE status bit 2)
    u32 task[MMO_SLOTS];  // 0x20 game: their surf Pokemon's FieldEffectTask*, 0 = none
    u32 actor[MMO_SLOTS]; // 0x40 game: the actor that task follows
    u32 created;          // 0x60 game: surf Pokemon started so far
    u32 deleted;          // 0x64 game: surf Pokemon ended so far
    u32 effects;          // 0x68 game: the FieldEffects* the tasks belong to
} RideArea;
#define RIDE ((RideArea *)MMO_RIDE_AREA)

// ov036 field_effect.c
typedef struct FieldEffectTask FieldEffectTask;
typedef void (*FieldEffectTaskFunc)(FieldEffectTask *task, void *work);
typedef struct {
    u32 workSize;
    FieldEffectTaskFunc init, del, update, draw;
} FieldEffectTaskVTable;
struct FieldEffectTask {
    u32 active;
    u32 param1;
    void *param2;
    VecFx32 pos;
    u8 work[0xA0];
    FieldEffectTaskVTable vtable; // a copy of the one it was made with
    void *store;
    void *tcb;
};
typedef struct {
    u32 count;
    u16 heapId;
    Field *field;
    void *arc;
    void *handles;
    u16 taskCount;
    u8 season, isExterior;
    void *tcbMgrWork;
    void *tcbMgr;
    void *taskStore; // 0x20
} FieldEffects;

// fldeff_namipoke.c: what a surf Pokemon task starts from, and its work
typedef struct {
    void *namipoke; // effect 3's data (FieldEffects_GetHandleData(effects, 3))
    FieldActor *actor;
    u16 uid;        // only stored: ride.c puts 0x100 + the slot there
    u16 zoneId;
    u16 dir;
    VecFx32 pos;
} NamipokeTaskParams;
typedef struct {
    u32 unk0, unk4;
    u8 unk8, mode, hideWake;
    u16 dir;
    fx32 bob, bobSpeed;
    u16 objIdx;
    NamipokeTaskParams params; // 0x1C
    u8 wake[0x38];
} NamipokeTask;

#define FLDEFF_NAMIPOKE 3
#define Field_GetFieldEffects THUMB(0x0218050C, FieldEffects *(*)(Field *))
#define FieldPlayer_GetRideEffect THUMB(0x0219A5C4, FieldEffectTask *(*)(FieldPlayer *))
#define FieldEffects_GetHandleData THUMB(0x021A37AC, void *(*)(FieldEffects *, u32))
#define FieldEffects_TCBCreate \
    THUMB(0x021A38B8, FieldEffectTask *(*)(FieldEffects *, const FieldEffectTaskVTable *, const VecFx32 *, u32, void *, u32))
#define FieldEffects_DeleteObject THUMB(0x021A3A70, void (*)(FieldEffectTask *))
// The grid surf Pokemon task's functions (NAMIPOKE_TASK_VTABLE is static: ride.c makes its own)
#define FldeffNamipoke_Init THUMB(0x021A4588, FieldEffectTaskFunc)
#define FldeffNamipoke_Exit THUMB(0x021A45F8, FieldEffectTaskFunc)
#define FldeffNamipoke_PlaceObjects THUMB(0x021A45FC, FieldEffectTaskFunc)
#define FldeffNamipoke_UpdateGrid THUMB(0x021A4710, FieldEffectTaskFunc)
#define FldeffNamipoke_DrawGrid THUMB(0x021A4924, FieldEffectTaskFunc)
// ov012 fldmmdl.c: the offset the surf Pokemon lifts its rider by
#define FldAct_SetOuterDrawOffset THUMB(0x0216734C, void (*)(FieldActor *, const VecFx32 *))
