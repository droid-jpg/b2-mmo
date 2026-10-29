// Live battles: both players pick their own moves. Each game runs the same battle (the core's friend
// battle, friendBattleEvent in mmo.c: a trainer battle against the friend's party) with itself as
// client 0 and the friend as client 1, and the two games stay in step by trading what each player
// chose (LIVE ACTION frames, sent and received by lua/features/live.lua through MMO_LIVE_AREA).
//
// The battle (overlay 167) is a server with one adapter per client (btl_server.c, btl_adapter.c).
// The server sets a command in every client's adapter (BtlAdapter_SetCmd) and then polls
// BattleServer_AllClientsReplied every frame until each client has left its answer in its adapter.
// Commands 3 (pick an action), 5 and 6 (pick a Pokemon to send in) are answered with one u32
// BattleAction per Pokemon out. We replace that poll: our answers (client 0, the game's UI) are
// queued for the friend, and client 1 (the game's AI, playing the friend's team) only counts as
// answered once the friend's answer for the same step has come in, which then replaces the AI's.
//
// Both games must then play every turn identically:
//   - Same random numbers: the battle seeds its RNG with buildSeed (main ARM9, from entropy) in
//     BtlMain_ProcInit; while armed, our jump at buildSeed's start gives it the shared seed instead.
//     The battle's RNG (BattleRandom) is also put back after every command as the server left it
//     when it sent the command, so whatever a client does meanwhile (the AI thinking, the UI) can't
//     move it in one game only.
//   - The two speed sorts (ActionOrder_Sort for the turn's actions, SortBySpeed for Pokemon) break
//     ties with BattleRandom(2) in list order, and each game lists its own side first. Ours put the
//     host's side first in both games before sorting, so the same coin flip means the same thing.
//   - Things only the player's side gets in a one-console battle are off in both games: EXP (the
//     "does the player gain EXP?" check answers no), the Shift-style "switch?" question (battle
//     style Set while the battle runs), and the field's weather.
//
// Overlay 167 (and 169, which the battle runs from VRAM) are loaded fresh for every battle, so
// their code is patched when the battle seeds its RNG (by then both are loaded): each patched
// function starts with a jump to ours here, and the patches go away with the overlays. The jump
// into buildSeed is ours to undo, which the first call does.
#include "live.h"
#include "features.h"

_Static_assert(sizeof(LiveShared) <= 0x800, "LiveShared must fit MMO_LIVE_AREA");

#define CMD_SELECT_ACTION 3
#define CMD_CHANGE_FAINTED 5
#define CMD_CHANGE_MID_TURN 6
#define JUMP_WORD0 0x46C04778u // bx pc; nop

static u32 isSelect(u32 cmd) {
    return cmd == CMD_SELECT_ACTION || cmd == CMD_CHANGE_FAINTED || cmd == CMD_CHANGE_MID_TURN;
}

static void syncCode(u32 addr) {
    DC_FlushRange((const void *)(addr & ~31u), 64);
    IC_InvalidateRange((const void *)(addr & ~31u), 64);
}

static u32 read32(u32 addr) {
    volatile u16 *p = (volatile u16 *)addr; // halfwords: VRAM takes no byte accesses
    return p[0] | ((u32)p[1] << 16);
}

static void write32(u32 addr, u32 v) {
    volatile u16 *p = (volatile u16 *)addr;
    p[0] = (u16)v;
    p[1] = (u16)(v >> 16);
}

// The function at addr (Thumb, 4-aligned) jumps to fn: bx pc; nop; ldr pc, [pc, #-4]; .word fn
static void writeJump(u32 addr, const void *fn) {
    write32(addr + 8, (u32)fn); // the address first: until the jump is there, the old code runs
    write32(addr + 4, 0xE51FF004);
    write32(addr, JUMP_WORD0);
    syncCode(addr);
}

// ---- The battle's RNG ----

static void saveRand(void) {
    LiveShared *L = LIVE;
    for (int i = 0; i < 6; i++) L->rand[i] = LIVE_CALC_RAND[i];
    L->randSaved = 1;
}

static void restoreRand(void) {
    LiveShared *L = LIVE;
    for (int i = 0; i < 6; i++) LIVE_CALC_RAND[i] = L->rand[i];
    L->randSaved = 0;
}

// ---- Both teams: the checksum and the HP list, the host's team first ----

static u8 *clientParty(u8 *server, u32 client) {
    return *(u8 **)(server + 0x14 + client * 0xC + 4);
}

static void snapshot(u8 *server) {
    LiveShared *L = LIVE;
    u32 h = 2166136261u, n = 0;
    for (u32 k = 0; k < 2; k++) {
        u8 *party = clientParty(server, L->host ? k : 1 - k);
        if (party == 0) continue;
        u32 count = party[0x18];
        for (u32 j = 0; j < count && j < 6; j++) {
            u8 *mon = ((u8 **)party)[j];
            u32 v = (u32)*(u16 *)(mon + 0xC) << 16 | *(u16 *)(mon + 0x10);
            for (int b = 0; b < 4; b++) h = (h ^ ((v >> (b * 8)) & 0xFF)) * 16777619u;
            if (n < 12) L->hp[n++] = v;
        }
    }
    L->hpCount = n;
    L->check = h;
}

// ---- Replacements for the battle's functions ----

// BtlAdapter_SetCmd: the same, and the battle's RNG is remembered as the server left it.
static void liveSetCmd(u8 *ad, u32 cmd, const u8 *data, u32 size) {
    if (LIVE->armed && !LIVE->randSaved) saveRand();
    ad[0xE] = 1;
    ad[0xF] = (u8)cmd;
    *(u16 *)(ad + 0x10) = (u16)cmd;
    *(u16 *)(ad + 0x12) = (u16)size;
    for (u32 i = 0; i < size; i++) ad[0x14 + i] = data[i];
    *(u32 *)(ad + 4) = 0;
    *(u32 *)(ad + 8) = 0;
    ad[0xC] &= 0xF0;
}

static u8 sAsk; // what the step being answered asks of each side, for our ACTION frame

// A command was just sent to client ad (state 1 -> 3)
static void sent(u8 *server, u8 *ad) {
    LiveShared *L = LIVE;
    u32 cmd = ad[0xF], client = ad[0xD];
    if (!isSelect(cmd) || client > 1) return;
    L->fresh |= 1u << client;
    if (client != 0) return;
    snapshot(server);
    L->myCheck[L->step0 & 63] = L->check;
    // Who has to choose: everyone for an action; for a send-in, the sides with a position in the list
    // (positions alternate between the clients: even ours, odd the friend's)
    u32 ask = 3;
    if (cmd != CMD_SELECT_ACTION) {
        ask = 0;
        u32 n = *(u16 *)(ad + 0x12);
        for (u32 i = 0; i < n && i < 6; i++) ask |= (ad[0x14 + i] & 1) ? 2 : 1;
    }
    sAsk = (u8)ask;
}

// The friend's answer as our game sees it: their opponent's positions are ours and vice versa.
static u32 mirror(u32 w) {
    if ((w & 0xF) == 1 && ((w >> 4) & 7) < 6) w ^= 0x10;
    return w;
}

// Client ad left an answer: may the server use it?
static u32 replied(u8 *ad) {
    LiveShared *L = LIVE;
    if (!(ad[0xC] & 0xF)) return 0;
    u32 cmd = ad[0xF], client = ad[0xD];
    if (!isSelect(cmd) || client > 1 || !(L->fresh & (1u << client))) return 1;
    if (client == 0) {
        if (!L->fellBack && L->outW - L->outR >= LIVE_QUEUE) return 0; // Lua hasn't sent the last ones yet
        L->fresh &= ~1u;
        LiveAct *a = &L->outQ[L->outW % LIVE_QUEUE];
        u32 size = *(u32 *)(ad + 8);
        const u32 *w = *(const u32 **)(ad + 4);
        u32 n = (w != 0 && size <= 20) ? size / 4 : 0;
        a->step = L->step0++;
        a->cmd = (u8)cmd;
        a->count = (u8)n;
        a->check = L->myCheck[a->step & 63];
        a->ask = sAsk;
        for (u32 i = 0; i < n; i++) a->words[i] = w[i];
        L->lastOurs = n ? w[0] : 0;
        if (!L->fellBack) L->outW++;
        return 1;
    }
    if (L->partnerGone) L->fellBack = 1;
    if (!L->fellBack) {
        if (L->inR == L->inW) {
            L->waiting = 1;
            return 0; // the friend is still choosing
        }
        LiveAct *a = &L->inQ[L->inR % LIVE_QUEUE];
        if (a->step < L->step1) {
            L->inR++; // an old one (sent twice): look again next frame
            return 0;
        }
        L->inR++;
        L->waiting = 0;
        if (a->step != L->step1 || a->cmd != cmd) {
            // Out of step: the AI plays their side from here on, so the battle at least goes on
            L->desync++;
            L->fellBack = 1;
        } else {
            u32 mine = L->myCheck[a->step & 63];
            if (a->check != 0 && mine != 0 && a->check != mine) L->desync++;
            if (a->count != LIVE_AI_PICKS) {
                u32 n = a->count <= 5 ? a->count : 5;
                for (u32 i = 0; i < n; i++) L->answer1[i] = mirror(a->words[i]);
                *(u32 **)(ad + 4) = n ? L->answer1 : 0;
                *(u32 *)(ad + 8) = n * 4;
            }
        }
    }
    const u32 *w = *(const u32 **)(ad + 4);
    L->lastTheirs = (w != 0 && *(u32 *)(ad + 8) >= 4) ? w[0] : 0;
    L->step1++;
    L->steps++;
    L->fresh &= ~2u;
    return 1;
}

// BattleServer_AllClientsReplied(server): TRUE once every client has answered the last command.
static u32 liveAllReplied(u8 *server) {
    LiveShared *L = LIVE;
    u32 all = 1;
    for (u32 i = 0; i < 4; i++) {
        u8 *e = server + 0x14 + i * 0xC;
        if (e[0xB] == 0xFF) continue;
        u8 *ad = *(u8 **)e;
        if (!L->armed || (ad[0xC] & 0xF0) != 0) {
            if (!BtlAdapter_WaitCmd(ad)) all = 0;
            continue;
        }
        if (ad[0xE] == 1) {
            ad[0xE] = 3;
            sent(server, ad);
        }
        if (ad[0xE] == 3 && replied(ad)) ad[0xE] = 4;
        if (ad[0xE] != 4) all = 0;
    }
    if (all && L->randSaved) restoreRand();
    return all;
}

static u32 hostClient(void) { return LIVE->host || !LIVE->armed ? 0 : 1; }

// Pokemon id -> client: 0..5 client 0, 12..17 client 1, 6..11 client 2, 18..23 client 3
static u32 clientOfMon(const u8 *mon) {
    u32 id = mon[0x19];
    return id < 6 ? 0 : id < 12 ? 2 : id < 18 ? 1 : 3;
}

// ActionOrder_Sort(entries, count): by key (priority and speed), ties by coin flip, with the
// host's entries first. Entries are 16 bytes: BattleMon*, action, key, u8 client.
static void liveSortActions(u32 *e, u32 count) {
    u32 hc = hostClient(), keep = 0;
    for (u32 i = 0; i < count; i++) {
        if ((e[i * 4 + 3] & 0xFF) != hc) continue;
        for (u32 j = i; j > keep; j--) {
            for (u32 k = 0; k < 4; k++) {
                u32 t = e[j * 4 + k];
                e[j * 4 + k] = e[(j - 1) * 4 + k];
                e[(j - 1) * 4 + k] = t;
            }
        }
        keep++;
    }
    for (u32 i = 0; i < count; i++) {
        for (u32 j = i + 1; j < count; j++) {
            if (e[i * 4 + 2] <= e[j * 4 + 2] && (e[i * 4 + 2] != e[j * 4 + 2] || BattleRandom(2) != 0)) {
                for (u32 k = 0; k < 4; k++) {
                    u32 t = e[i * 4 + k];
                    e[i * 4 + k] = e[j * 4 + k];
                    e[j * 4 + k] = t;
                }
            }
        }
    }
}

// SortBySpeed(BtlMonSet *set, flow): Pokemon by speed, ties by coin flip, the host's first.
// BtlMonSet: BattleMon *mons[6] @0, u16 damage[6] @0x18, u16 speed[6] @0x36, u8 count @0x42.
static void swapMons(u8 *set, u32 a, u32 b) {
    u32 *mons = (u32 *)set;
    u16 *dmg = (u16 *)(set + 0x18), *spd = (u16 *)(set + 0x36);
    u32 m = mons[a];
    mons[a] = mons[b];
    mons[b] = m;
    u16 d = dmg[a];
    dmg[a] = dmg[b];
    dmg[b] = d;
    u16 s = spd[a];
    spd[a] = spd[b];
    spd[b] = s;
}

static void liveSortSpeed(u8 *set, void *flow) {
    u32 count = set[0x42];
    if (count <= 1) return;
    u32 *mons = (u32 *)set;
    u16 *spd = (u16 *)(set + 0x36);
    for (u32 i = 0; i < count; i++) spd[i] = BtlServerFlow_CalcSpeed(flow, (void *)mons[i], 1);
    u32 hc = hostClient(), keep = 0;
    for (u32 i = 0; i < count; i++) {
        if (clientOfMon((u8 *)mons[i]) != hc) continue;
        for (u32 j = i; j > keep; j--) swapMons(set, j, j - 1);
        keep++;
    }
    for (u32 i = 0; i < count; i++) {
        for (u32 j = i + 1; j < count; j++) {
            if (spd[j] > spd[i] || (spd[j] == spd[i] && BattleRandom(2) != 0)) swapMons(set, i, j);
        }
    }
}

// ---- Patching ----

typedef struct {
    u32 addr;
    u32 orig; // the function's first word, to be sure it's the code we know
    const void *fn;
    u32 bit;
} Patch;

static u32 patchBattle(void) {
    static const Patch patches[] = {
        { LIVE_ALL_REPLIED, 0x1C06B5F8, (const void *)liveAllReplied, LIVE_PATCH_REPLIED },
        { LIVE_SET_CMD, 0x1C04B510, (const void *)liveSetCmd, LIVE_PATCH_SETCMD },
        { LIVE_ACTION_SORT, 0xB087B5F0, (const void *)liveSortActions, LIVE_PATCH_SORT },
        { LIVE_SPEED_SORT, 0xB083B5F0, (const void *)liveSortSpeed, LIVE_PATCH_SPEED },
    };
    LiveShared *L = LIVE;
    for (u32 i = 0; i < sizeof patches / sizeof patches[0]; i++) {
        const Patch *p = &patches[i];
        u32 w = read32(p->addr);
        if (w == p->orig) writeJump(p->addr, p->fn);
        if (read32(p->addr) == JUMP_WORD0) L->patched |= p->bit;
    }
    // The player's side gains no EXP: the check returns FALSE (movs r0, #0; bx lr)
    if (read32(LIVE_EXP_CHECK) == LIVE_EXP_CHECK_ORIG) {
        write32(LIVE_EXP_CHECK, 0x47702000);
        syncCode(LIVE_EXP_CHECK);
    }
    if (read32(LIVE_EXP_CHECK) == 0x47702000) L->patched |= LIVE_PATCH_EXP;
    return L->patched;
}

static void unhookSeed(void) {
    LiveShared *L = LIVE;
    if (read32(LIVE_BUILD_SEED) != JUMP_WORD0) return;
    write32(LIVE_BUILD_SEED + 8, L->seedOrig[2]);
    write32(LIVE_BUILD_SEED + 4, L->seedOrig[1]);
    write32(LIVE_BUILD_SEED, L->seedOrig[0]);
    syncCode(LIVE_BUILD_SEED);
    L->patched &= ~LIVE_PATCH_SEED;
}

static void liveSeed(u32 *ctx);

static void hookSeed(void) {
    LiveShared *L = LIVE;
    if (read32(LIVE_BUILD_SEED) == JUMP_WORD0) return;
    for (u32 i = 0; i < 3; i++) L->seedOrig[i] = read32(LIVE_BUILD_SEED + i * 4);
    if (L->seedOrig[0] != LIVE_BUILD_SEED_ORIG) return; // not the code we know: no live battle
    writeJump(LIVE_BUILD_SEED, (const void *)liveSeed);
    L->patched |= LIVE_PATCH_SEED;
}

// Our jump at buildSeed(MATHRandContext32 *ctx): the battle's call (from BtlMain_ProcInit, in
// overlay 167) gets the shared seed and patches the battle; any other call the game's own seed.
static void liveSeed(u32 *ctx) {
    LiveShared *L = LIVE;
    u32 from = (u32)__builtin_return_address(0);
    unhookSeed();
    if (!L->armed || from < 0x02199000 || from >= 0x021E0000) {
        ((void (*)(u32 *))(LIVE_BUILD_SEED | 1))(ctx);
        if (L->armed) hookSeed(); // still waiting for the battle's call
        return;
    }
    // MATH_InitRand32: x = seed, mul = 0x5D588B656C078965, add = 0x269EC3
    ctx[0] = L->seed;
    ctx[1] = L->seed ^ 0x4C495645;
    ctx[2] = 0x6C078965;
    ctx[3] = 0x5D588B65;
    ctx[4] = 0x269EC3;
    ctx[5] = 0;
    L->seeded = 1;
    if ((patchBattle() & (LIVE_PATCH_REPLIED | LIVE_PATCH_SETCMD)) != (LIVE_PATCH_REPLIED | LIVE_PATCH_SETCMD)) {
        L->fellBack = 1; // can't take answers from the friend: their AI plays
    }
}

// ---- The core's hooks ----

void live_tick(GameSystem *gsys) { (void)gsys; }

GameEvent *live_event(GameSystem *gsys) {
    (void)gsys;
    return 0;
}

// BtlSetup: +0x10 the field's weather, +0x74 Config* (u16 bits; bit 6 battle style, 1 = Set)
void live_battle_setup(GameEvent *battle, void *setup) {
    LiveShared *L = LIVE;
    (void)battle;
    if (!L->pending) return;
    L->pending = 0;
    u8 *zero = (u8 *)&L->armed;
    for (u32 i = 0; i < 0xB8 - 0x18; i++) zero[i] = 0;
    L->version = LIVE_VERSION;
    u8 *s = setup;
    s[0x10] = 0; // no weather (each player's field has its own)
    u16 *config = *(u16 **)(s + 0x74);
    if (config != 0) {
        L->configPtr = (u32)config;
        L->configWas = (*config >> 6) & 1;
        *config |= 1 << 6;
    }
    PokeParty_RecoverAll(BtlSetup_GetParty(setup, 0)); // both teams at full strength, as theirs is
    L->armed = 1;
    hookSeed();
    if (!(L->patched & LIVE_PATCH_SEED)) L->fellBack = 1;
}

void live_battle_end(void) {
    LiveShared *L = LIVE;
    if (!L->armed) return;
    unhookSeed();
    if (L->configPtr != 0) {
        u16 *config = (u16 *)L->configPtr;
        *config = (u16)((*config & ~(1 << 6)) | (L->configWas << 6));
        L->configPtr = 0;
    }
    L->armed = 0;
}
