// Talking in the game's own text box: the game addresses talk.c uses, and its ITCM block.
// lua/features/talk.lua writes a message (and a list of choices) into MMO_TALK_AREA; talk_event
// starts an event that shows it with the field's message functions, the ones script commands use
// (the info window of s0038_InfoMsg, the list menu of s00B0_ListMenuShow), and writes back the answer.
#pragma once
#include "game.h"

typedef struct FieldMsgBG FieldMsgBG;
typedef struct InfoMsgWin InfoMsgWin;
typedef struct ListMenuUI ListMenuUI;
typedef struct StrBuf StrBuf;
typedef struct { StrBuf *text; s32 value; } ListMenuOption;

// ov036 field.c / field_msgbg.c (only while the field is up)
#define Field_GetMsgBGSys THUMB(0x02180490, FieldMsgBG *(*)(Field *))
// (sys, msgData, frameType 0 = TALKMSG_WIN_FRAME_NORMAL, x, y, width, height) in tiles
#define MsgBGPrinter_CreatePlainWin THUMB(0x02188A54, InfoMsgWin *(*)(FieldMsgBG *, void *, u32, u16, u16, u16, u16))
#define MsgBGPrinter_DeletePlainWin THUMB(0x02188AB0, void (*)(InfoMsgWin *))
#define MsgBGPrinter_ClearPlainWin THUMB(0x02188AE8, void (*)(InfoMsgWin *))
#define MsgBGPrinter_PlainWinPrintStream THUMB(0x02188BA4, void (*)(InfoMsgWin *, u16, u16, StrBuf *))
#define MsgBGPrinter_PlainWinMain THUMB(0x02188BDC, u32 (*)(InfoMsgWin *))       // TRUE once printed
#define MsgBGPrinter_PlainWinDrawCursor THUMB(0x02188C90, void (*)(InfoMsgWin *)) // the wait-for-A arrow
#define InitListMenuOptionHeap THUMB(0x02187F04, ListMenuOption *(*)(u32, u32))
#define AppendListMenuOption THUMB(0x02187F48, void (*)(ListMenuOption *, StrBuf *, u32, u32))
#define CalcListMenuWidth THUMB(0x02187FB0, u32 (*)(FieldMsgBG *, ListMenuOption *, u32, u32))
#define CalcListMenuHeight THUMB(0x02187FD0, u32 (*)(u32, u32, u32, u32))
#define ListMenuRequest_Set THUMB(0x02187FF4, void (*)(void *, u16, u16, u16, u16, u16))
// (sys, request, options, cursorCallback, work, listTop, cursorRow, cancelable)
#define ListMenuUI_Create THUMB(0x02187E6C, ListMenuUI *(*)(FieldMsgBG *, void *, ListMenuOption *, void *, void *, u16, u16, u32))
#define ListMenuUI_Update THUMB(0x02187EC8, s32 (*)(ListMenuUI *)) // value, -1 nothing yet, -2 cancelled (B)
#define MsgBGPrinter_DeleteMenuFunc THUMB(0x02187EA0, void (*)(ListMenuUI *)) // frees the options too
// ov012 scrcmd_work.c: the script list menu's ListMenuRequest (0x20 bytes: fontSizeX 12, rowHeight 13, lineSpacing 1)
#define SCRIPT_LIST_MENU_REQUEST ((const u8 *)0x0216C9C0)
// arm9
#define GFL_StrBufCreate THUMB(0x02048530, StrBuf *(*)(u32, u32))
#define GFL_StrBufFree THUMB(0x02048564, void (*)(StrBuf *))
#define GCTX_HIDGetPressedKeys THUMB(0x0203DEFC, u32 (*)(void))

#define TALK_MAX_CHOICES 8
#define TALK_TEXT_CHARS 0x120   // u16 game characters, 0xFFFF-terminated
#define TALK_CHOICE_CHARS 0x18

// MMO_TALK_AREA (0x01FFE800, 0x400 bytes). lua/features/talk.lua uses the same offsets.
typedef struct {
    u32 req;      // 0x00 Lua: seq of the message to show (a new value = a new message)
    u32 shown;    // 0x04 game: seq of the message shown last
    u32 state;    // 0x08 game: 0 idle, 1 showing, 2 answered (box still up, waiting for Lua), 3 closed
    s32 result;   // 0x0C game: the choice (0-based), -1 = B / dismissed
    u32 count;    // 0x10 Lua: choices with the message (0 = just text, wait for A/B)
    u32 close;    // 0x14 Lua: 1 = close the box (after an answer); game zeroes it
    u32 events;   // 0x18 game: talk events started
    u32 answered; // 0x1C game: seq of the message the result is for
    u16 text[TALK_TEXT_CHARS];                          // 0x20
    u16 choices[TALK_MAX_CHOICES][TALK_CHOICE_CHARS];   // 0x260
    u32 phase;    // 0x3E0 game: the event's step (2 printing, 3 waiting for A/B, 4 choice list, 5 waiting for Lua)
} TalkArea;

#define TALK ((TalkArea *)MMO_TALK_AREA)
