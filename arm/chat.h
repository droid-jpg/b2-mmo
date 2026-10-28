// Black 2 MMO feature: typing chat in the game, on the game's own keyboard (the name entry,
// overlay 280). Lua asks for it in MMO_CHAT_AREA; chat_event starts an event that opens the
// keyboard (or just holds the field still while Lua shows its own preset menu).
#pragma once
#include "game.h"
#include "shared.h"

#define CHAT_TEXT_MAX 10 // the name entry's limit: NameBox.text is u16[11]

typedef struct {
    u32 req;      // 0x00 Lua: 1 = hold the field (an idle event) while Lua's menu is up, 2 = open the
                  //      keyboard (also from the hold), 0 in the hold = let the field go
    u32 state;    // 0x04 game: 0 none, 1 holding, 2 keyboard open
    u32 done;     // 0x08 game: +1 each time the keyboard closed (text/canceled are then valid)
    u32 canceled; // 0x0C game: 1 = the player backed out (or left it empty)
    u32 mode;     // 0x10 Lua: the name entry mode (its prompt and icon), NAME_ENTRY_*
    u32 maxLen;   // 0x14 Lua: letters, 1..CHAT_TEXT_MAX
    u32 started;  // 0x18 game: +1 each event started
    u32 keep;     // 0x1C Lua: frames the hold may still last; Lua refreshes it while its menu is up
    u16 text[CHAT_TEXT_MAX + 2]; // 0x20 game: what was typed, game character codes, 0xFFFF-terminated
} ChatArea;

#define CHAT ((volatile ChatArea *)MMO_CHAT_AREA)

// app/name_entry.h: what the name entry is given (0x38 bytes)
typedef struct {
    u32 mode;
    u16 gender;
    u16 unk6;
    void *pkm;
    void *unkC;
    void *unk10;
    u32 unk14;
    u32 maxLength;
    u32 canceled;  // 1 when the name is left as it was (B, or nothing typed)
    void *name;    // StrBuf
    void *saveTask;
    void *gameInfo;
    u32 checks;    // 1 = allow more than 4 digits, 2 = skip the profanity check
    u16 *unk30;    // the C-Gear phrase (CGearName_GetFromSave), the third preset of modes 7 and 14
    u32 unk34;
} NameEntryParam;

#define HEAPID_GAMEEVENT 4
#define NAME_ENTRY_TRAINER_MESSAGE 14 // "What's your message to the participating Trainer(s)?"

// ov012 namein_setup.c: allocates the param and an 11-letter StrBuf for the name
#define setupNameEntry THUMB(0x021659EC, NameEntryParam *(*)(u32, u32, u32, u32, u32, const void *, void *))
#define NameEntryParam_Free THUMB(0x02165AE8, void (*)(NameEntryParam *))
// ov036 shortcut_menu.c: the event that runs the name entry (overlay 280) and comes back to the field
#define ReturnToField_CreateNameInEvent THUMB(0x021BF890, GameEvent *(*)(GameSystem *, Field *, NameEntryParam *, u32))
#define GameData_GetSaveControl THUMB(0x02017934, void *(*)(GameData *))
#define getTrainerGameInfoAddress THUMB(0x0200C838, void *(*)(void *))
// The C-Gear phrase in the save: mode 14 offers it as one of its three preset messages (unk30)
#define CGearName_GetFromSave THUMB(0x020114F0, u16 *(*)(void *))
#define GFL_StrBufGetStringPtr THUMB(0x020486F0, const u16 *(*)(void *))
