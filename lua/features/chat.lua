-- Black 2 MMO feature: chat from inside the game, for a player with only the DS buttons.
--
-- SELECT on the field (the field itself does nothing with SELECT) opens a quick-chat list: a few
-- preset lines, "/who", and "Type a message..." which opens the game's own keyboard (the name
-- entry that nicknames use, up to 10 letters) through arm/chat.c. What was typed is sent with
-- api.say, like the window's chat box; B or an empty name sends nothing.
--
-- The list is the game's own text box and choice list when the talk feature provides
-- api.gameMessage; otherwise a small list drawn on the bottom screen (D-pad, A, B) while an idle
-- game event holds the field still, so the game doesn't move the player under it.
--
-- Also: the last few chat lines stay on the bottom screen for a while.
local PRESETS = { "Hi!", "Follow me!", "Wait for me!", "Battle?", "Trade?", "/who" }
local TYPE_LABEL = "Type a message..."
local BUTTON = "Select"
local HOLD_FRAMES = 30 -- the hold event lets go if Lua stops refreshing it for this many field frames
local MAX_LEN = 10
local MODE = 14 -- NAME_ENTRY_TRAINER_MESSAGE: "What's your message to the participating Trainer(s)?"

-- Black 2 text codes that aren't plain ASCII, as the keyboard types them
local CHARMAP = {
  [0x2026] = "...", [0x201C] = '"', [0x201D] = '"', [0x2018] = "'", [0x2019] = "'",
  [0x246D] = "(M)", [0x246E] = "(F)", [0x00D7] = "x", [0x00F7] = "/", [0x3000] = " ",
  [0xFF01] = "!", [0xFF1F] = "?",
}

return function(api)
  local A = api.ADDR.chat
  local OFF = { req = 0x00, state = 0x04, done = 0x08, canceled = 0x0C, mode = 0x10, maxLen = 0x14,
    started = 0x18, keep = 0x1C, text = 0x20 }
  local function get(k) return api.ir32(A + OFF[k]) end
  local function set(k, v) api.iw32(A + OFF[k], v) end

  local chat = { phase = "idle", sel = 1, doneSeen = 0, prev = {}, recent = {}, lastText = nil, lastCodes = nil,
    sent = 0 }
  for k, off in pairs(OFF) do if k ~= "text" and k ~= "done" and k ~= "started" then api.iw32(A + off, 0) end end
  chat.doneSeen = get("done")
  api.chat = chat -- tests look at it

  local items = {}
  for _, p in ipairs(PRESETS) do items[#items + 1] = p end
  items[#items + 1] = TYPE_LABEL

  -- Game character codes -> text to send
  local function decode()
    local out, codes = {}, {}
    for i = 0, MAX_LEN do
      local c = memory.read_u16_le(A + OFF.text + i * 2 - api.ITCM, api.IT)
      if c == 0xFFFF then break end
      codes[#codes + 1] = string.format("%04X", c)
      if c >= 0x20 and c < 0x7F then out[#out + 1] = string.char(c)
      elseif CHARMAP[c] then out[#out + 1] = CHARMAP[c]
      elseif c >= 0xA0 and c < 0x2000 then out[#out + 1] = utf8.char(c)
      else out[#out + 1] = "?" end
    end
    chat.lastCodes = table.concat(codes, " ")
    return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
  end

  local function remember(line)
    table.insert(chat.recent, { text = line, at = api.now() })
    while #chat.recent > 4 do table.remove(chat.recent, 1) end
  end

  local function say(text)
    if text == nil or text == "" then return end
    chat.sent = chat.sent + 1
    chat.lastSaid = text
    if text ~= "/who" then remember(api.cfg.name .. ": " .. text) end
    api.say(text)
  end

  local function openKeyboard()
    set("mode", chat.mode or MODE)
    set("maxLen", MAX_LEN)
    chat.doneSeen = get("done")
    set("req", 2)
    chat.phase = "keyboard"
  end

  local function choose(i)
    local label = i and items[i]
    if label == TYPE_LABEL then openKeyboard() return end
    set("req", 0)
    chat.phase = "idle"
    if label then say(label) end
  end

  local function holdMenu()
    chat.phase = "menu"
    set("keep", HOLD_FRAMES)
    set("req", 1)
  end

  local function open()
    chat.sel = 1
    -- The game's own text box and choice list (the talk feature). onAnswer runs once the box has
    -- closed and the player is free again, so "Type a message..." can start the keyboard from there.
    if api.gameMessage then
      chat.phase = "gameMessage"
      local ok = api.gameMessage("What do you want to say?", items, function(i)
        if chat.phase == "gameMessage" then choose(i) end
      end)
      if ok ~= false then return end
    end
    holdMenu()
  end

  local function edge(pad, k)
    local down = pad[k] == true
    local was = chat.prev[k]
    chat.prev[k] = down
    return down and not was
  end

  local function tick()
    local pad = joypad.get()
    local pressed = {}
    for _, k in ipairs({ BUTTON, "Up", "Down", "A", "B" }) do pressed[k] = edge(pad, k) end

    if chat.phase == "idle" then
      if pressed[BUTTON] and api.me.ready then open() end
    elseif chat.phase == "menu" then
      set("keep", HOLD_FRAMES)
      if get("state") ~= 1 then
        -- Not held yet (or the game let go): give up if the field went on without us
        chat.waitFrames = (chat.waitFrames or 0) + 1
        if chat.waitFrames > 120 then set("req", 0); chat.phase = "idle"; chat.waitFrames = 0 end
        return
      end
      chat.waitFrames = 0
      if pressed.Up then chat.sel = (chat.sel - 2) % #items + 1 end
      if pressed.Down then chat.sel = chat.sel % #items + 1 end
      if pressed.A then choose(chat.sel)
      elseif pressed.B or pressed[BUTTON] then choose(nil) end
    elseif chat.phase == "keyboard" then
      if get("done") ~= chat.doneSeen then
        chat.doneSeen = get("done")
        chat.phase = "idle"
        local text = decode()
        chat.lastText = text
        chat.lastCanceled = get("canceled") ~= 0
        if not chat.lastCanceled and text ~= "" then say(text) end
      end
    elseif chat.phase == "gameMessage" then
      -- onAnswer moves us on; if the game went back to the field without an answer, stop waiting
      if api.me.ready and get("req") == 0 then
        chat.gmFrames = (chat.gmFrames or 0) + 1
        if chat.gmFrames > 600 then chat.phase = "idle"; chat.gmFrames = 0 end
      else
        chat.gmFrames = 0
      end
    end
  end

  local function draw()
    -- The bottom screen (y 192..383): the quick-chat list
    if chat.phase == "menu" and get("state") == 1 then
      local x, y, w = 40, 214, 176
      local h = 18 + #items * 15
      gui.drawBox(x, y, x + w, y + h, 0xFF586068, 0xF0F8F8F8)
      gui.drawText(x + 8, y + 3, "Say what? (A: send, B: back)", 0xFF707070, 0x00000000, 9)
      for i, label in ipairs(items) do
        local ly = y + 4 + i * 15
        if i == chat.sel then gui.drawBox(x + 4, ly - 1, x + w - 4, ly + 13, 0xFFE05030, 0xFFFCE0D8) end
        gui.drawText(x + 12, ly, (i == chat.sel and "> " or "  ") .. label, 0xFF303030, 0x00000000, 10)
      end
      return
    end
    -- The last chat lines, for 8 s after the newest, on the bottom screen while on the field
    local t = api.now()
    local last = chat.recent[#chat.recent]
    if last and t - last.at < 8000 and api.me.ready then
      local n = #chat.recent
      local y0 = 368 - n * 13
      gui.drawBox(2, y0 - 3, 253, 369, 0x00000000, 0xA0101820)
      for i, l in ipairs(chat.recent) do
        local text = #l.text > 44 and (l.text:sub(1, 43) .. "...") or l.text
        gui.drawText(6, y0 + (i - 1) * 13, text, t - l.at < 8000 and 0xFFFFFFFF or 0xFFA0A0A0, 0x00000000, 9)
      end
    end
  end

  return {
    tick = tick,
    draw = draw,
    onFrame = {
      [api.T.CHAT] = function(f, id, fr)
        if f then remember(f.name .. ": " .. api.cstr(fr, 4, 40)) end
      end,
    },
    buildForm = function(formId, y)
      forms.label(formId, "In game: SELECT on the field opens quick chat and the keyboard", 8, y, 360, 18)
      return y + 22
    end,
  }
end
