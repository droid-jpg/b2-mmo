// The part of Black 2 MMO that runs inside the game. It lives in the ARM9's instruction TCM (free
// from 0x01FF93A0 up, never cached, so the Lua side can write code and data there safely) and runs
// once a frame from the field's event provider, which the Lua side points at mmo_provider.
//
// It does what Lua can't: calls the game's functions. Each frame it reports where the player is
// and keeps one of the game's own "other player" actors (move code 0x44, the actors the game uses
// for players in a wireless session) per friend that Lua asks for. Those actors follow the
// position, direction and hidden flag in their slot every frame by themselves, so Lua only writes
// the slot and the friend walks, runs and turns smoothly.
#include "game.h"
#include "shared.h"
#include "features.h"

static FldCommActEntry sEntries[MMO_SLOTS];
static FldCommActSys sActSys;
static u8 sCaught[(SPECIES_MAX + 8) / 8];
static u32 sCaughtScanned;

// Every 2 s (60 field frames): count caught Pokemon and queue the ones that are new for Lua.
static void scanPokedex(MmoShared *sh, GameData *gd) {
    if ((sh->ticks % 60) != 0) return;
    PokeDexSave *dex = GameData_GetPokedex(gd);
    u32 count = 0, queued = 0;
    for (u32 sp = 1; sp <= SPECIES_MAX; sp++) {
        u32 bit = 1u << (sp & 7);
        if (!PokeDex_IsCaught(dex, sp)) continue;
        count++;
        if (!(sCaught[sp >> 3] & bit)) {
            sCaught[sp >> 3] |= bit;
            if (sCaughtScanned) {
                for (u32 k = queued; k < 4; k++) {
                    if (sh->caughtNew[k] == 0) { sh->caughtNew[k] = sp; queued = k + 1; break; }
                }
            }
        }
    }
    sh->caughtCount = count;
    sCaughtScanned = 1;
}

static void dropSlot(MmoSlot *slot, int i) {
    FldCommActEntry *e = &sEntries[i];
    if (e->actor != 0) {
        // Deleted by the game already (actorDeleted): FldCommActSys only clears the entry
        FldCommActSys_DeleteActor(&sActSys, i);
    }
    slot->spawned = 0;
    slot->actor = 0;
}

static void tick(GameSystem *gsys) {
    MmoShared *sh = MMO_SHARED;
    Field *field = GSYS_GetField(gsys);

    sh->ticks++;
    sh->field = (u32)field;
    if (field == 0 || !Field_CheckMapLoadFinished(field)) {
        sh->ready = 0;
        return;
    }

    MMSys *mm = Field_GetActorSystem(field);
    FieldPlayer *player = Field_GetPlayer(field);
    FieldActor *me = FieldPlayer_GetActor(player);
    VecFx32 pos;

    CopyActorPosAllAdd(me, &pos);
    sh->myX = pos.x;
    sh->myY = pos.y;
    sh->myZ = pos.z;
    sh->myDir = GetActorFaceDir(me);
    sh->myZone = Field_GetPlayerStateZoneID(field);
    sh->myObjCode = FldAct_GetObjCode(me);
    sh->mySex = FieldPlayer_GetSex(player);
    sh->myExState = FieldPlayer_DeriveExState(player);
    sh->myMatrix = GetZoneMatrixId((u16)sh->myZone);

    GameData *gd = *(GameData **)((u8 *)gsys + GSYS_GAMEDATA_OFF);
    sh->party = (u32)GameData_GetParty(gd);
    sh->badges = getTrainerCardDataBlkAddress(gd)[1];
    scanPokedex(sh, gd);
    if (sh->writeSlot >= 1 && sh->writeSlot <= 6) {
        // Done by the CPU, not by the emulator's memory poke, so the data cache stays right
        u8 *dst = (u8 *)sh->party + 8 + (sh->writeSlot - 1) * 0xDC;
        for (int i = 0; i < 0xDC; i++) dst[i] = sh->writeData[i];
        sh->writeSlot = 0;
        sh->writes++;
    }

    if (sActSys.actorSystem != mm) {
        // A new actor system (first run, or after a reset): the old actors went with the old one
        for (int i = 0; i < MMO_SLOTS; i++) {
            sEntries[i].actor = 0;
            sEntries[i].actorDeleted = 0;
            sh->slots[i].spawned = 0;
            sh->slots[i].actor = 0;
        }
        sActSys.count = MMO_SLOTS;
        sActSys.run = 1;
        sActSys.actorSystem = mm;
        sActSys.entries = sEntries;
    }
    sh->mmSys = (u32)mm;
    sh->ready = 1;

    GridPos myTile;
    FldAct_GetGPos(me, &myTile);

    for (int i = 0; i < MMO_SLOTS; i++) {
        MmoSlot *slot = &sh->slots[i];
        FldCommActEntry *e = &sEntries[i];

        if (slot->spawned && (e->actor == 0 || e->actorDeleted)) {
            dropSlot(slot, i); // the game deleted it (it does on some map changes)
        }
        if (slot->spawned && (!slot->want || slot->objCode != slot->shownObjCode)) {
            dropSlot(slot, i);
        }
        if (!slot->spawned && slot->want && slot->objCode != 0) {
            // FldCommActSys_CreateActor takes the first free entry; make sure that is this one
            for (int j = 0; j < i; j++) {
                if (sEntries[j].actor == 0) sEntries[j].actor = (FieldActor *)1;
            }
            FldCommActSys_CreateActor(&sActSys, i, slot->objCode, &slot->dir, (const VecFx32 *)&slot->x,
                                      &slot->hidden);
            for (int j = 0; j < i; j++) {
                if (sEntries[j].actor == (FieldActor *)1) sEntries[j].actor = 0;
            }
            if (e->actor != 0) {
                slot->spawned = 1;
                slot->actor = (u32)e->actor;
                slot->shownObjCode = slot->objCode;
                sh->spawns++;
            }
        }
        if (slot->spawned) {
            // Friends block the way like any trainer, except while one shares our tile (we'd be stuck)
            GridPos t;
            FldAct_GetGPos(e->actor, &t);
            SetActorCollisionEnabled(e->actor, t.x != myTile.x || t.z != myTile.z);
            ride_slot(i, slot, e->actor);
        }
    }
}

static void copyBytes(u8 *dst, const u8 *src, u32 n) {
    for (u32 i = 0; i < n; i++) dst[i] = src[i];
}

typedef struct {
    GameSystem *gsys;
    u32 cash;
} FriendBattleWork;

// A battle against a friend's team: the game's trainer battle (Nate or Rosa, single, no blackout)
// with their Pokemon and name swapped in, then our party and cash put back as they were.
static u32 friendBattleEvent(GameEvent *event, u32 *state, void *data) {
    MmoShared *sh = MMO_SHARED;
    FriendBattleWork *w = data;
    GameSystem *gsys = w->gsys;
    GameData *gd = *(GameData **)((u8 *)gsys + GSYS_GAMEDATA_OFF);
    u8 *party = GameData_GetParty(gd);
    u32 *info = getTrainerCardDataBlkAddress(gd);

    switch (*state) {
    case 0: {
        Field *field = GSYS_GetField(gsys);
        copyBytes(MMO_PARTY_BACKUP, party, MMO_PARTY_BYTES);
        w->cash = info[0];
        GameEvent *battle = EventTrainerBattleCall_Create(gsys, field, 0, 0, sh->battleTrainer, 0, 1);
        void *setup = *(void **)((u8 *)GameEvent_GetData(battle) + 8);
        u8 *foe = BtlSetup_GetParty(setup, 1);
        u32 count = sh->battleCount > 6 ? 6 : sh->battleCount;
        ((u32 *)foe)[1] = count;
        copyBytes(foe + 8, MMO_BATTLE_PARTY, count * 0xDC);
        for (u32 i = count * 0xDC; i < 6 * 0xDC; i++) foe[8 + i] = 0; // the trainer's own leftovers
        PokeParty_RecoverAll(foe);
        // The trainers' names: BtlSetup holds party[4] then 4 PlayerInfo*, 4 bytes, trainers[4], names[4]
        void **parties = 0;
        for (u32 off = 0; off < 0x40; off += 4) {
            if (*(void **)((u8 *)setup + off) == foe) { parties = (void **)((u8 *)setup + off - 4); break; }
        }
        if (parties != 0) {
            void **trainers = (void **)((u8 *)parties + 0x24);
            void **names = (void **)((u8 *)parties + 0x34);
            if (trainers[1] != 0 && ((void **)trainers[1])[5] != 0) GFL_StrBufLoadString(((void **)trainers[1])[5], MMO_BATTLE_NAME);
            if (names[1] != 0) GFL_StrBufLoadString(names[1], MMO_BATTLE_NAME);
        }
        live_battle_setup(battle, setup);
        sh->battleState = 1;
        GameEvent_ChainNext(event, battle);
        (*state)++;
        return 0;
    }
    case 1:
        live_battle_end();
        copyBytes(MMO_AFTER_PARTY, party, MMO_PARTY_BYTES);
        copyBytes(party, MMO_PARTY_BACKUP, MMO_PARTY_BYTES);
        info[0] = w->cash;
        GameEvent_ChainNext(event, CallFieldMapEntranceInTransition(gsys, GSYS_GetField(gsys), 0, 0, 1, 0, 0));
        (*state)++;
        return 0;
    default:
        sh->battleState = 2;
        return 1;
    }
}

GameEvent *mmo_provider(GameSystem *gsys, void *data) {
    MmoShared *sh = MMO_SHARED;
    GameEventProvider orig = (GameEventProvider)sh->origProvider;

    if (sh->magic == MMO_MAGIC) {
        tick(gsys);
        talk_tick(gsys);
        live_tick(gsys);
        watch_tick(gsys);
        evolve_tick(gsys);
        chat_tick(gsys);
        ride_tick(gsys);
        if (sh->battleReq && sh->ready && sh->battleCount > 0) {
            sh->battleReq = 0;
            GameEvent *ev = GameEvent_Create(gsys, 0, friendBattleEvent, sizeof(FriendBattleWork));
            ((FriendBattleWork *)GameEvent_GetData(ev))->gsys = gsys;
            return ev;
        }
        GameEvent *ev = 0;
        if (sh->ready) {
            if (ev == 0) ev = talk_event(gsys);
            if (ev == 0) ev = live_event(gsys);
            if (ev == 0) ev = evolve_event(gsys);
            if (ev == 0) ev = chat_event(gsys);
        }
        if (ev != 0) return ev;
    }
    return orig != 0 ? orig(gsys, data) : 0;
}
