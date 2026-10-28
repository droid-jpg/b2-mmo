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
    u32 reserved[6];  // 0x68
    MmoSlot slots[MMO_SLOTS]; // 0x80
    u8 pad[0x300 - 0x200];
    u8 writeData[0xDC]; // 0x300 Lua: a Pokemon as the party stores it (encrypted, 0xDC bytes)
} MmoShared;
