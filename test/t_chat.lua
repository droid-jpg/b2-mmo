-- Chat from inside the game: SELECT opens the quick-chat list (the game's own choice list through
-- api.gameMessage, or the bottom-screen fallback), a preset is sent, B backs out, "Type a message..."
-- opens the game's keyboard, typed with the D-pad and A, and the text reaches the fake friend; OK with
-- nothing typed sends nothing; the fallback list works; the player walks again afterwards.
-- B2PORT=7786 bash test/up.sh "--name Ann --x 584 --z 184 --path stand"; bash test/run.sh test/t_chat.lua 240
-- (fakefriend prints every chat it gets to test/out/ff1.out, which the end of this test reads)
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")

local co, s, fails = nil, nil, 0
local function check(ok, what) K.log((ok and "PASS " or "FAIL ") .. what); if not ok then fails = fails + 1 end end
local function wait(n) for _ = 1, n do coroutine.yield() end end
local function tap(keys, n) for _ = 1, n or 4 do K.press(keys); coroutine.yield() end; wait(8) end
local function waitFor(cond, max)
  for _ = 1, max do if cond() then return true end; coroutine.yield() end
  return false
end
-- The keyboard by its buttons: the cursor starts on A; the letters page is 13 columns (A-J, a blank,
-- ',' '.'), rows A-J, K-T, U-Z, a row of spaces, 0-9. START jumps to OK.
local cur = { 0, 0 }
local function moveTo(col, row)
  while cur[2] < row do tap({ Down = true }); cur[2] = cur[2] + 1 end
  while cur[2] > row do tap({ Up = true }); cur[2] = cur[2] - 1 end
  while cur[1] < col do tap({ Right = true }); cur[1] = cur[1] + 1 end
  while cur[1] > col do tap({ Left = true }); cur[1] = cur[1] - 1 end
end
local function key(col, row) moveTo(col, row); tap({ A = true }) end
local function letter(ch) local i = ch:upper():byte() - 65; key(i % 10, i // 10) end
local function digit(d) key(d, 4) end
local function space() key(cur[1], 3) end
local function typeText(text)
  cur = { 0, 0 }
  for ch in text:gmatch(".") do
    if ch == " " then space() elseif ch:match("%d") then digit(tonumber(ch)) else letter(ch) end
  end
end

local function chatState() return s.api.ir32(s.api.ADDR.chat + 4) end
-- SELECT, then wait until the list is up: the game's choice list (talk's api.gameMessage: the field
-- is no longer free, and the list takes input ~40 frames after it opens) or the bottom-screen fallback
local function openMenu()
  check(waitFor(function() return s.me.ready end, 300), "field ready before SELECT")
  tap({ Select = true })
  local c = s.api.chat
  local ok = waitFor(function()
    return (c.phase == "menu" and chatState() == 1) or (c.phase == "gameMessage" and not s.me.ready)
  end, 120)
  if ok and c.phase == "gameMessage" then wait(70) end
  return ok
end
-- Down n times, then A (or B): presets are 1 Hi!, 2 Follow me!, ... 6 /who, 7 Type a message...
local function pick(n, button)
  for _ = 2, n do tap({ Down = true }) end
  K.shot(button == "B" and "list_b" or ("list_" .. n))
  tap({ [button or "A"] = true })
  -- The answer comes once the box closed and the field is free (or at once in the fallback)
  return waitFor(function() return s.api.chat.phase ~= "gameMessage" and s.api.chat.phase ~= "menu" end, 300)
end

local function typing(text, shotName)
  local c = s.api.chat
  check(waitFor(function() return chatState() == 2 end, 120), "keyboard requested (state 2)")
  wait(200) -- the fade into the name entry
  if text ~= "" then K.shot(shotName .. "_open"); typeText(text); wait(20); K.shot(shotName .. "_typed") end
  tap({ Start = true }); tap({ A = true })
  check(waitFor(function() return c.phase == "idle" end, 600), "keyboard closed")
  K.log("typed codes: " .. tostring(c.lastCodes) .. " -> '" .. tostring(c.lastText) .. "' canceled=" .. tostring(c.lastCanceled))
  check(waitFor(function() return s.me.ready end, 300), "field back after the keyboard")
end

local function script()
  local c = s.api.chat
  wait(60)
  local gm = s.api.gameMessage
  K.log("gameMessage: " .. tostring(gm ~= nil))

  -- 1. A preset from the list: "Follow me!"
  local z0 = s.me.z
  check(openMenu(), "SELECT opens the list (" .. c.phase .. ")")
  K.shot("menu")
  check(pick(2), "list answered")
  check(c.lastSaid == "Follow me!" and c.phase == "idle", "preset sent: " .. tostring(c.lastSaid))
  check(waitFor(function() return s.me.ready end, 120), "field back after the preset")
  check(s.me.z == z0, "the player didn't move while the list was up")

  -- 2. B backs out: nothing sent
  wait(30)
  local sent = c.sent
  check(openMenu(), "SELECT opens the list again")
  check(pick(1, "B"), "list closed with B")
  check(c.sent == sent and c.phase == "idle", "B sends nothing")
  check(waitFor(function() return s.me.ready end, 120), "field back after B")

  -- 3. Type a message on the game's keyboard (opens after the box closed)
  wait(30)
  check(openMenu(), "SELECT opens the list for typing")
  check(pick(7), "picked Type a message...")
  check(c.phase == "keyboard", "keyboard phase after the list: " .. c.phase)
  typing("HI ANN 42", "kb")
  check(c.lastText == "HI ANN 42" and c.lastSaid == "HI ANN 42", "typed text sent: " .. tostring(c.lastSaid))
  wait(20)
  K.shot("field_after")

  -- 4. The keyboard with nothing typed: OK sends nothing
  wait(30)
  sent = c.sent
  check(openMenu(), "SELECT opens the list for an empty message")
  check(pick(7), "picked Type a message... again")
  typing("", "kb_empty")
  check(c.lastCanceled == true and c.sent == sent, "empty message sends nothing (canceled=" .. tostring(c.lastCanceled) .. ")")

  -- 5. /who from the list (a notice, nothing on the wire)
  wait(30)
  check(openMenu(), "SELECT opens the list for /who")
  check(pick(6), "picked /who")
  check(c.lastSaid == "/who", "/who picked")

  -- 6. The fallback list on the bottom screen (no api.gameMessage): "Wait for me!"
  if gm then
    wait(30)
    s.api.gameMessage = nil
    check(openMenu(), "fallback: SELECT opens the bottom-screen list (" .. c.phase .. ")")
    check(pick(3), "fallback: list answered")
    check(c.lastSaid == "Wait for me!", "fallback: preset sent: " .. tostring(c.lastSaid))
    s.api.gameMessage = gm
  end

  -- 7. The player walks again
  wait(30)
  check(waitFor(function() return s.me.ready end, 120), "field free before walking")
  local zb = s.me.z
  for _ = 1, 40 do K.press({ Down = true }); coroutine.yield() end
  wait(30)
  check(s.me.z > zb, string.format("player walks after chatting (z %d -> %d)", zb, s.me.z))
  K.shot("walked")

  -- What the fake friend got
  wait(60)
  local fh = io.open(K.env.out .. "ff1.out", "r")
  local got = fh and fh:read("a") or ""
  if fh then fh:close() end
  for line in got:gmatch("[^\n]*chat #[^\n]*") do K.log("ff1: " .. line) end
  check(got:find("Michael: Follow me!", 1, true) ~= nil, "friend got the preset")
  check(got:find("Michael: HI ANN 42", 1, true) ~= nil, "friend got the typed message")
  local n, want = 0, gm and 3 or 2
  for _ in got:gmatch("chat #%d+ Michael:") do n = n + 1 end
  check(n == want, "friend got exactly " .. want .. " chats (B, empty and /who sent nothing): " .. n)
  K.log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
end

K.start({}, function(state, f)
  s = state
  if not co then co = coroutine.create(script) end
  if coroutine.status(co) == "suspended" then
    local ok, err = coroutine.resume(co)
    if not ok then K.log("test error: " .. tostring(err)); client.exit() end
  else
    client.exit()
  end
end)
