// Live battles: the data block the game and lua/features/live.lua share (MMO_LIVE_AREA), and the
// battle code the in-game part replaces. See arm/live.c for how it works.
#pragma once
#include "game.h"
#include "shared.h"

#define LIVE_QUEUE 8 // entries per queue (a power of 2)

// One answer of a player to the battle: what the LIVE ACTION frame carries (PROTOCOL.md).
typedef struct {
    u16 step;     // counts the players' choices from 0 in a battle
    u8 cmd;       // the battle's command: 3 pick an action, 5/6 pick a Pokemon to send in
    u8 count;     // action words (0..6); LIVE_AI_PICKS: the receiver's AI picks for the sender
    u32 check;    // FNV-1a over species/HP of both teams (host's first) when the step was asked
    u8 ask;       // bit 0: the sender's side had to choose, bit 1: the receiver's side
    u8 pad[3];
    u32 words[5]; // the BattleAction words as the sender's game wrote them
} LiveAct; // 0x20 bytes

#define LIVE_AI_PICKS 0xFF

typedef struct {
    // Lua writes these
    u32 pending;      // 0x00 1: the next friend battle is a live one (live_battle_setup clears it)
    u32 host;         // 0x04 1: we challenged (our side goes first where the battle breaks ties)
    u32 seed;         // 0x08 the battle's random seed, the same in both games
    u32 partnerGone;  // 0x0C 1: the friend left or gave up: their side's AI plays on
    u32 inW;          // 0x10 friend's answers written to inQ (entry inW % LIVE_QUEUE is next)
    u32 outR;         // 0x14 our answers Lua has sent
    // The game writes these
    u32 armed;        // 0x18 1 from the battle's setup until it ends
    u32 patched;      // 0x1C LIVE_PATCH_* bits: the battle code patches in place
    u32 seeded;       // 0x20 1 once the battle took the shared seed
    u32 fellBack;     // 0x24 1: the AI plays the friend's side now
    u32 desync;       // 0x28 steps whose check differed from ours (or whose command did)
    u32 inR;          // 0x2C friend's answers used
    u32 outW;         // 0x30 our answers queued in outQ
    u16 step0, step1; // 0x34 our next step, the friend's next step
    u32 waiting;      // 0x38 1 while the battle waits for the friend's answer
    u32 lastOurs;     // 0x3C our last action word
    u32 lastTheirs;   // 0x40 the friend's last action word as used
    u32 check;        // 0x44 our check at the last step we asked
    u32 hpCount;      // 0x48 entries in hp
    u32 hp[12];       // 0x4C species << 16 | HP of both teams (host's first) at the last step asked
    u32 configWas;    // 0x7C the battle style bit before we set it
    u32 configPtr;    // 0x80 Config* whose style we changed (0: none)
    u32 randSaved;    // 0x84 1: rand holds the battle RNG as the last command found it
    u32 rand[6];      // 0x88 MATHRandContext32 (x, mul, add)
    u32 fresh;        // 0xA0 bit c: client c got a select command we haven't taken its answer for
    u32 seedOrig[3];  // 0xA4 buildSeed's first 12 bytes while our jump replaces them
    u32 steps;        // 0xB0 select steps both sides answered (for tests)
    u32 version;      // 0xB4 LIVE_VERSION once the game has armed
    u8 pad[0x100 - 0xB8];
    LiveAct inQ[LIVE_QUEUE];  // 0x100 Lua: the friend's answers, in step order
    LiveAct outQ[LIVE_QUEUE]; // 0x200 game: ours, for Lua to send
    u32 myCheck[64];          // 0x300 our check per step (step % 64)
    u32 answer1[6];           // 0x400 the friend's answer as the battle reads it
} LiveShared;

#define LIVE ((LiveShared *)MMO_LIVE_AREA)
#define LIVE_VERSION 1

#define LIVE_PATCH_SEED 1     // buildSeed (main): the shared seed, then the battle patches
#define LIVE_PATCH_REPLIED 2  // BattleServer_AllClientsReplied
#define LIVE_PATCH_SETCMD 4   // BtlAdapter_SetCmd
#define LIVE_PATCH_SORT 8     // ActionOrder_Sort
#define LIVE_PATCH_SPEED 0x10 // SortBySpeed (ov169, in VRAM)
#define LIVE_PATCH_EXP 0x20   // func_ov167_0219bdfc ("does the player's side gain EXP?")

// --- Game addresses (pokebw2: config/b2_us/arm9/symbols.txt and overlays/ov167, ov169) ---
// Main ARM9, always loaded
#define LIVE_BUILD_SEED 0x02044098        // buildSeed(MATHRandContext32 *): seeds an RNG from entropy
#define LIVE_BUILD_SEED_ORIG 0xB0A7B5F0   // its first word (push {r4-r7, lr}; sub sp, #0x9C)
#define DC_FlushRange ((void (*)(const void *, u32))0x0207B0AC)      // ARM
#define IC_InvalidateRange ((void (*)(const void *, u32))0x0207B0E8) // ARM
// Overlay 167 (the battle), loaded at a fixed address while a battle runs
#define LIVE_ALL_REPLIED 0x0219F19C       // BattleServer_AllClientsReplied(server)
#define LIVE_SET_CMD 0x021D4AEC           // BtlAdapter_SetCmd(adapter, cmd, data, size)
#define LIVE_ACTION_SORT 0x021A0308       // ActionOrder_Sort(entries, count)
#define LIVE_EXP_CHECK 0x0219BDFC         // func_ov167_0219bdfc(mainModule): EXP for the player?
#define LIVE_EXP_CHECK_ORIG 0x1C05B570
#define BtlAdapter_WaitCmd THUMB(0x021D4B18, u32 (*)(u8 *))
#define BattleRandom THUMB(0x021BD0C0, u32 (*)(u32))
#define BtlServerFlow_CalcSpeed THUMB(0x021ABD08, u16 (*)(void *, void *, u32))
#define LIVE_CALC_RAND ((u32 *)0x021DD84C) // data_ov167_021dd844.rand: what BattleRandom draws from
// Overlay 169, which the battle runs from VRAM (LCDC)
#define LIVE_SPEED_SORT 0x0689D0AC        // SortBySpeed(BtlMonSet *, flow)

// BtlServer: clients[4] @0x14, 0xC each: adapter*, BattleParty*, u8 numMons, numCoverPos, isAttached, clientId
// BtlAdapter: +4 reply*, +8 reply bytes, +0xC low nibble replied / high nibble link, +0xD client,
//             +0xE state (1 to send, 3 waiting, 4 replied), +0xF command, +0x10 u16 cmd, +0x12 u16 size, +0x14 data
// BattleParty: BattleMon *mons[6], u8 count @0x18. BattleMon: species @0xC, HP @0x10, mon id @0x19.
