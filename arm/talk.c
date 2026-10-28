// Black 2 MMO feature: talk. Messages and choice lists in the game's own text box (see talk.h).
// One event shows a message, then waits for A/B or a choice from the list, writes the answer and
// keeps the box up until Lua says what's next: another message (shown in the same box, so a
// conversation flows like a script's) or close. If Lua says nothing for 3 s, the box closes.
#include "features.h"
#include "talk.h"

#define PAD_A 1
#define PAD_B 2
#define WAIT_LUA_FRAMES 90

typedef struct {
    GameSystem *gsys;
    FieldMsgBG *msg;
    InfoMsgWin *win;
    StrBuf *str;
    ListMenuUI *menu;
    u32 timer;
    u8 request[0x20];
} TalkWork;

enum { ST_OPEN, ST_PRINT, ST_TEXT, ST_KEY, ST_MENU, ST_LUA };

static void openMenu(TalkWork *w, TalkArea *t) {
    u32 heap = *(u16 *)w->msg; // FieldMsgBG.heapId
    u32 n = t->count > TALK_MAX_CHOICES ? TALK_MAX_CHOICES : t->count;
    ListMenuOption *opts = InitListMenuOptionHeap(n, heap);
    StrBuf *tmp = GFL_StrBufCreate(TALK_CHOICE_CHARS + 1, heap);
    for (u32 i = 0; i < n; i++) {
        t->choices[i][TALK_CHOICE_CHARS - 1] = 0xFFFF;
        GFL_StrBufLoadString(tmp, t->choices[i]);
        AppendListMenuOption(opts, tmp, i, heap);
    }
    GFL_StrBufFree(tmp);
    for (int i = 0; i < 0x20; i++) w->request[i] = SCRIPT_LIST_MENU_REQUEST[i];
    u32 width = CalcListMenuWidth(w->msg, opts, 12, 0);
    u32 rows = n > 6 ? 6 : n;
    u32 height = CalcListMenuHeight(rows, 13, 1, n > 6);
    // Right side, just above the message window (rows 19..22, framed from 18)
    ListMenuRequest_Set(w->request, n, 30 - width, 17 - height, width, height);
    w->menu = ListMenuUI_Create(w->msg, w->request, opts, 0, 0, 0, 0, 1);
}

static u32 talkEvent(GameEvent *event, u32 *state, void *data) {
    (void)event;
    TalkWork *w = data;
    TalkArea *t = TALK;

    t->phase = *state;
    switch (*state) {
    case ST_OPEN:
        w->msg = Field_GetMsgBGSys(GSYS_GetField(w->gsys));
        w->str = GFL_StrBufCreate(TALK_TEXT_CHARS + 1, *(u16 *)w->msg);
        w->win = MsgBGPrinter_CreatePlainWin(w->msg, 0, 0, 1, 19, 30, 4);
        *state = ST_PRINT;
        // fallthrough
    case ST_PRINT:
        t->shown = t->req;
        t->state = 1;
        t->text[TALK_TEXT_CHARS - 1] = 0xFFFF;
        GFL_StrBufLoadString(w->str, t->text);
        MsgBGPrinter_PlainWinPrintStream(w->win, 8, 0, w->str);
        *state = ST_TEXT;
        return 0;
    case ST_TEXT:
        if (!MsgBGPrinter_PlainWinMain(w->win)) return 0;
        if (t->count > 0) {
            openMenu(w, t);
            *state = ST_MENU;
        } else {
            *state = ST_KEY;
        }
        return 0;
    case ST_KEY:
        MsgBGPrinter_PlainWinDrawCursor(w->win);
        if (!(GCTX_HIDGetPressedKeys() & (PAD_A | PAD_B))) return 0;
        t->result = -1;
        break;
    case ST_MENU: {
        s32 r = ListMenuUI_Update(w->menu);
        if (r == -1) return 0;
        MsgBGPrinter_DeleteMenuFunc(w->menu);
        w->menu = 0;
        t->result = r < 0 ? -1 : r;
        break;
    }
    case ST_LUA:
        if (t->req != t->shown) {
            MsgBGPrinter_ClearPlainWin(w->win);
            *state = ST_PRINT;
            return 0;
        }
        if (!t->close && ++w->timer < WAIT_LUA_FRAMES) return 0;
        t->close = 0;
        MsgBGPrinter_DeletePlainWin(w->win);
        GFL_StrBufFree(w->str);
        t->state = 3;
        t->phase = 0;
        return 1;
    }
    // Answered: Lua decides what's next
    t->answered = t->shown;
    t->close = 0;
    t->state = 2;
    w->timer = 0;
    *state = ST_LUA;
    return 0;
}

void talk_tick(GameSystem *gsys) { (void)gsys; }

GameEvent *talk_event(GameSystem *gsys) {
    TalkArea *t = TALK;
    if (t->req == t->shown || t->req == 0) return 0;
    t->events++;
    GameEvent *ev = GameEvent_Create(gsys, 0, talkEvent, sizeof(TalkWork));
    TalkWork *w = GameEvent_GetData(ev);
    w->gsys = gsys;
    w->timer = 0;
    w->menu = 0;
    return ev;
}
