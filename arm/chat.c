// Black 2 MMO feature: chat typed in the game. Lua (lua/features/chat.lua) sees the chat button and
// asks here (MMO_CHAT_AREA, arm/chat.h); the event below opens the game's own keyboard, the name
// entry that nicknames use, and leaves what was typed for Lua to send.
#include "features.h"
#include "chat.h"

typedef struct {
    GameSystem *gsys;
    NameEntryParam *param;
} ChatWork;

static u32 chatEvent(GameEvent *event, u32 *state, void *data) {
    volatile ChatArea *c = CHAT;
    ChatWork *w = data;
    GameSystem *gsys = w->gsys;

    switch (*state) {
    case 0: // holding the field still (Lua's menu), until Lua wants the keyboard or lets go
        if (c->req == 1 && c->keep != 0) {
            c->keep--; // so a Lua script that stopped can't leave the player stuck
            c->state = 1;
            return 0;
        }
        if (c->req != 2) {
            c->req = 0;
            c->state = 0;
            return 1;
        }
        {
            MmoShared *sh = MMO_SHARED;
            GameData *gd = *(GameData **)((u8 *)gsys + GSYS_GAMEDATA_OFF);
            u32 len = c->maxLen;
            if (len == 0 || len > CHAT_TEXT_MAX) len = CHAT_TEXT_MAX;
            NameEntryParam *p = setupNameEntry(HEAPID_GAMEEVENT, c->mode ? c->mode : NAME_ENTRY_TRAINER_MESSAGE,
                                               sh->mySex, 0, len, 0,
                                               getTrainerGameInfoAddress(GameData_GetSaveControl(gd)));
            p->checks = 3; // any digits, no profanity filter: it's a chat
            p->unk30 = CGearName_GetFromSave(GameData_GetSaveControl(gd));
            w->param = p;
            c->req = 0;
            c->state = 2;
            GameEvent_ChainNext(event, ReturnToField_CreateNameInEvent(gsys, GSYS_GetField(gsys), p, 1));
            *state = 1;
        }
        return 0;
    default: { // the keyboard closed and the field is back
        NameEntryParam *p = w->param;
        const u16 *s = GFL_StrBufGetStringPtr(p->name);
        u32 i = 0;
        for (; i < CHAT_TEXT_MAX && s[i] != 0xFFFF; i++) c->text[i] = s[i];
        c->text[i] = 0xFFFF;
        c->canceled = p->canceled;
        NameEntryParam_Free(p);
        c->state = 0;
        c->done++;
        return 1;
    }
    }
}

void chat_tick(GameSystem *gsys) { (void)gsys; }

GameEvent *chat_event(GameSystem *gsys) {
    volatile ChatArea *c = CHAT;
    if (c->req != 1 && c->req != 2) return 0;
    GameEvent *ev = GameEvent_Create(gsys, 0, chatEvent, sizeof(ChatWork));
    ChatWork *w = GameEvent_GetData(ev);
    w->gsys = gsys;
    w->param = 0;
    c->started++;
    return ev;
}
