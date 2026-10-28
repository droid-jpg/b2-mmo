// The block the in-game code and the Lua script share, at the start of the mod's ITCM area.
// lua/b2mmo.lua reads and writes it by these offsets: keep both in step (MMO_VERSION).
#pragma once
#include "game.h"

#define MMO_SHARED ((MmoShared *)0x01FFA000)
#define MMO_MAGIC 0x4D4D3242 // "B2MM"
#define MMO_VERSION 1
#define MMO_SLOTS 8

// One friend shown on this map. Lua writes want/objCode/x..hidden; the game's actor reads
// x/y/z, dir and hidden every frame through pointers.
typedef struct {
    u32 want;         // 0x00 Lua: 1 = show this friend
    u32 objCode;      // 0x04 Lua: their model (their own player actor's object code)
    fx32 x, y, z;     // 0x08 Lua: world position (fx32, 16 units a tile), y is height
    u16 dir;          // 0x14 Lua: facing, 0 up 1 down 2 left 3 right
    u16 pad;
    u32 hidden;       // 0x18 Lua: 1 hides the actor (friend busy)
    u32 spawned;      // 0x1C game: the actor exists
    u32 actor;        // 0x20 game: FieldActor*
    u32 shownObjCode; // 0x24 game: the model the actor was made with
    u32 reserved[2];
} MmoSlot; // 0x30 bytes

typedef struct {
    u32 magic;        // 0x00 Lua writes MMO_MAGIC once the code is in place
    u32 version;      // 0x04
    u32 origProvider; // 0x08 Lua: the field's provider that mmo_provider replaced and calls
    u32 ticks;        // 0x0C game: +1 every frame mmo_provider runs (stalls while an event runs)
    u32 ready;        // 0x10 game: field up and map loaded this tick
    u32 field;        // 0x14 game: Field*
    u32 mmSys;        // 0x18 game: MMSys*
    u32 spawns;       // 0x1C game: actors made so far
    fx32 myX, myY, myZ; // 0x20 game: player position
    u32 myDir;        // 0x2C
    u32 myZone;       // 0x30
    u32 myObjCode;    // 0x34
    u32 mySex;        // 0x38
    u32 myExState;    // 0x3C 0 walk, 1 bike, 2 surf, ... (FieldPlayer_DeriveExState)
    u32 myMatrix;     // 0x40 the zone's map matrix: zones of one matrix share coordinates
    u32 party;        // 0x44 PokeParty* (capacity @0, count @4, 6 x 0xDC encrypted Pokemon @8)
    u32 badges;       // 0x48 bit n = badge n
    u32 caughtCount;  // 0x4C Pokemon caught (Pokedex), 0 until the first scan
    u32 caughtNew[4]; // 0x50 game: species caught since the last scan; Lua reads and zeroes them
    u32 writeSlot;    // 0x60 Lua: party slot + 1 to overwrite with writeData (a trade); game zeroes it
    u32 writes;       // 0x64 game: +1 per party write done
    u32 battleReq;    // 0x68 Lua: 1 = battle the team in battleParty now (cleared when it starts)
    u32 battleState;  // 0x6C game: 1 battling, 2 over (afterParty holds the party as it ended)
    u32 battleTrainer;// 0x70 Lua: trainer id the battle is set up from (360 Nate, 363 Rosa)
    u32 battleCount;  // 0x74 Lua: Pokemon in battleParty
    u32 reserved[2];  // 0x78
    MmoSlot slots[MMO_SLOTS]; // 0x80
    u8 pad[0x300 - 0x200];
    u8 writeData[0xDC]; // 0x300 Lua: a Pokemon as the party stores it (encrypted, 0xDC bytes)
} MmoShared;

// ITCM memory map (0x01FFA000..0x02000000; the game's own ITCM code ends at 0x01FF93A0):
//   0x01FFA000 this shared block      0x01FFA400 code + bss, up to MMO_CODE_END (arm/link.ld)
//   0x01FFD800 friend battle buffers  0x01FFE800 one block per feature, laid out in arm/<feature>.h
// lua/b2mmo.lua has the same addresses in ADDR: keep both in step.
#define MMO_CODE_END 0x01FFD800
#define MMO_BATTLE_NAME ((u16 *)0x01FFD800)  // Lua: the friend's name, 0xFFFF-terminated (16 max)
#define MMO_BATTLE_PARTY ((u8 *)0x01FFD840)  // Lua: their party, battleCount x 0xDC
#define MMO_PARTY_BACKUP ((u8 *)0x01FFDD80)  // game: our party (8 + 6 x 0xDC) before the battle
#define MMO_AFTER_PARTY ((u8 *)0x01FFE2C0)   // game: our party as the battle left it
#define MMO_PARTY_BYTES (8 + 6 * 0xDC)

#define MMO_TALK_AREA 0x01FFE800   // 0x400 talking in the game's text box, its choice list
#define MMO_LIVE_AREA 0x01FFEC00   // 0x800 live battles
#define MMO_WATCH_AREA 0x01FFF400  // 0x200 watching a friend's battle
#define MMO_EVOLVE_AREA 0x01FFF600 // 0x100 trade evolutions
#define MMO_CHAT_AREA 0x01FFF700   // 0x200 typing chat in the game
#define MMO_RIDE_AREA 0x01FFF900   // 0x100 friends on a bike or surfing
                                   // 0x01FFFA00..0x02000000 spare
