// Black 2 (USA, IREO rev 0) functions and layouts the mod uses. Addresses and names come from the
// pokebw2 decompilation (github.com/fuddlesworth/pokebw2, config/b2_us/arm9); the overlay ones
// (ov012, ov036) are only valid while the field is up, which is the only time the mod calls them.
#pragma once

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef signed short s16;
typedef signed int s32;
typedef s32 fx32;

typedef struct { fx32 x, y, z; } VecFx32;

typedef struct GameSystem GameSystem;
typedef struct Field Field;
typedef struct MMSys MMSys;
typedef struct FieldPlayer FieldPlayer;
typedef struct FieldActor FieldActor;
typedef struct GameEvent GameEvent;

typedef GameEvent *(*GameEventProvider)(GameSystem *gsys, void *data);

// GameSystem: eventProvider @0x10 is asked for a new event every frame that no event runs.
#define GSYS_PROVIDER_OFF 0x10
#define g_GameSystem (*(GameSystem **)0x021410F4)

// ov036 field_comm_actor.c: the other players' actors. The struct is the game's; we keep ours in ITCM.
typedef struct {
    u32 netId;
    u16 actorDeleted; // set by the actor's move code when the actor system deletes it
    u16 run;          // nonzero: the actor shows its running animation on fast moves
    FieldActor *actor;
} FldCommActEntry;

typedef struct {
    u16 count;
    u16 run;
    MMSys *actorSystem;
    FldCommActEntry *entries;
} FldCommActSys;

#define THUMB(addr, type) ((type)((addr) | 1))

#define GSYS_GetField THUMB(0x02016AF0, Field *(*)(GameSystem *))
#define Field_CheckMapLoadFinished THUMB(0x02180424, u32 (*)(Field *))
#define Field_GetActorSystem THUMB(0x021804B8, MMSys *(*)(Field *))
#define Field_GetPlayer THUMB(0x021804F0, FieldPlayer *(*)(Field *))
#define Field_GetPlayerStateZoneID THUMB(0x021804D8, u16 (*)(Field *))
#define FieldPlayer_GetActor THUMB(0x0219A6A0, FieldActor *(*)(FieldPlayer *))
#define FieldPlayer_GetSex THUMB(0x0219A6DC, u32 (*)(FieldPlayer *))
#define FieldPlayer_DeriveExState THUMB(0x0219AB18, u32 (*)(FieldPlayer *))
#define CopyActorPosAllAdd THUMB(0x0218ED98, void (*)(FieldActor *, VecFx32 *))
#define GetActorFaceDir THUMB(0x02167078, u16 (*)(FieldActor *))
#define FldAct_GetObjCode THUMB(0x02167018, u16 (*)(FieldActor *))
#define FldCommActSys_CreateActor \
    THUMB(0x0218AEB4, void (*)(FldCommActSys *, u32, u16, const u16 *, const VecFx32 *, const u32 *))
#define FldCommActSys_DeleteActor THUMB(0x0218AF08, void (*)(FldCommActSys *, u32))

typedef struct GameData GameData;
typedef struct PokeDexSave PokeDexSave;
#define GSYS_GAMEDATA_OFF 0x1C
#define GetZoneMatrixId THUMB(0x020188D0, u16 (*)(u16))
#define GameData_GetParty THUMB(0x0201735C, void *(*)(GameData *))
#define GameData_GetPokedex THUMB(0x0200D190, PokeDexSave *(*)(GameData *))
#define PokeDex_IsCaught THUMB(0x0200D660, u32 (*)(PokeDexSave *, u16))
// TrainerGameInfoSave: cash @0, badges @4 (bit n = badge n)
#define getTrainerCardDataBlkAddress THUMB(0x02017974, u32 *(*)(GameData *))
#define SPECIES_MAX 649

typedef struct { s16 x, y, z, unk6; } GridPos;
#define FldAct_GetGPos THUMB(0x02167294, void (*)(FieldActor *, GridPos *))
// FALSE sets actor flag 0x80: others walk through it (the game's default for these actors)
#define SetActorCollisionEnabled THUMB(0x02167580, void (*)(FieldActor *, u32))
