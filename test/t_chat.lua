-- Chat from inside the game: SELECT opens the quick-chat list, a preset is sent, B backs out,
-- "Type a message..." opens the game's keyboard, typed with the D-pad and A, and the text reaches the fake
-- friend; OK with nothing typed sends nothing; the player walks again afterwards.
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
local function openMenu()
  check(waitFor(function() return s.me.ready end, 300), "field ready before SELECT")
  tap({ Select = true })
  return waitFor(function() return s.api.chat.phase == "menu" and chatState() == 1 end, 60)
end

local function script()
  local c = s.api.chat
  wait(60)
  K.log("gameMessage: " .. tostring(s.api.gameMessage ~= nil))

  -- 1. A preset: SELECT, Down, A = "Follow me!"
  check(openMenu(), "SELECT opens the list (state 1 = field held)")
  local z0 = s.me.z
  tap({ Down = true })
  K.shot("menu")
  tap({ A = true })
  check(c.lastSaid == "Follow me!" and c.phase == "idle", "preset sent: " .. tostring(c.lastSaid))
  check(waitFor(function() return s.me.ready end, 60), "field back after the preset")
  check(s.me.z == z0, "the player didn't move while the list was up")

  -- 2. B backs out: nothing sent
  wait(30)
  local sent = c.sent
  check(openMenu(), "SELECT opens the list again")
  tap({ B = true })
  check(c.sent == sent and c.phase == "idle", "B sends nothing")
  check(waitFor(function() return s.me.ready end, 60), "field back after B")

  -- 3. Type a message on the game's keyboard
  wait(30)
  check(openMenu(), "SELECT opens the list for typing")
  tap({ Up = true }) -- wraps to "Type a message..."
  tap({ A = true })
  check(waitFor(function() return chatState() == 2 end, 60), "keyboard requested (state 2)")
  wait(200) -- the fade into the name entry
  K.shot("kb_open")
  typeText("HI ANN 42")
  wait(20)
  wait(20)
  K.shot("kb_typed")
  tap({ Start = true }); tap({ A = true })
  check(waitFor(function() return c.phase == "idle" end, 600), "keyboard closed")
  K.log("typed codes: " .. tostring(c.lastCodes) .. " -> '" .. tostring(c.lastText) .. "' canceled=" .. tostring(c.lastCanceled))
  check(c.lastText == "HI ANN 42" and c.lastSaid == "HI ANN 42", "typed text sent: " .. tostring(c.lastSaid))
  check(waitFor(function() return s.me.ready end, 300), "field back after the keyboard")
  wait(20)
  K.shot("field_after")

  -- 4. The keyboard with nothing typed: OK sends nothing
  wait(30)
  sent = c.sent
  check(openMenu(), "SELECT opens the list for an empty message")
  tap({ Up = true })
  tap({ A = true })
  wait(260)
  tap({ Start = true }); tap({ A = true })
  check(waitFor(function() return c.phase == "idle" end, 600), "empty keyboard closed")
  check(c.lastCanceled == true and c.sent == sent, "empty message sends nothing (canceled=" .. tostring(c.lastCanceled) .. ")")
  check(waitFor(function() return s.me.ready end, 300), "field back after the empty keyboard")

  -- 5. /who from the list (a notice, nothing on the wire)
  wait(30)
  check(openMenu(), "SELECT opens the list for /who")
  tap({ Up = true }); tap({ Up = true })
  tap({ A = true })
  check(c.lastSaid == "/who", "/who picked")

  -- 6. The player walks again
  wait(30)
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
  local n = 0
  for _ in got:gmatch("chat #%d+ Michael:") do n = n + 1 end
  check(n == 2, "friend got exactly 2 chats (B, empty and /who sent nothing): " .. n)
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
