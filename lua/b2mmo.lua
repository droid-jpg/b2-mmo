-- Black 2 MMO: play Pokemon Black 2 online with friends, all in the same Unova.
-- Runs in BizHawk (2.9+) with Pokemon Black 2 (USA). Settings: b2mmo.ini next to this script.
--
-- How it works: this script writes a small piece of ARM code (arm/, built into mmo_code.lua) into
-- the DS's instruction TCM and points the field's per-frame event provider at it. That code tells
-- us where the player is and shows each friend as one of the game's own "other player" actors,
-- which follow the positions we write. Everything else (the network, names over heads, notices,
-- chat and trading) happens here.

local DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
package.path = DIR .. "?.lua;" .. package.path
local CODE = dofile(DIR .. "mmo_code.lua")
local ZONES = dofile(DIR .. "zones.lua")
local SPECIES = dofile(DIR .. "species.lua")
local PKM = dofile(DIR .. "pkm.lua")
local VERSION = "0.1.1"

----------------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------------
local cfg = { name = "Trainer", server = "127.0.0.1", port = "7777", room = "UNOVA", greeting = "Hi! Let's battle sometime!", labels = "1" }
do
  local f = io.open(DIR .. "b2mmo.ini", "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then cfg[k] = v end
    end
    f:close()
  end
end
for k, v in pairs(B2MMO_CFG or {}) do cfg[k] = v end -- tests override settings
cfg.port = tonumber(cfg.port) or 7777
cfg.name = cfg.name:sub(1, 15)

----------------------------------------------------------------------------------------------
-- Memory
----------------------------------------------------------------------------------------------
local SB, IT = "ARM9 System Bus", "Instruction TCM"
local ITCM = 0x01FF8000
local SH = 0x01FFA000
local MAGIC = 0x4D4D3242
local G_GAMESYSTEM = 0x021410F4
local SLOT0, SLOTSZ, NSLOTS = SH + 0x80, 0x30, 8
local OBJ_HERO, OBJ_HEROINE = 231, 240
-- ITCM memory map, as in arm/shared.h
local ADDR = { battleName = 0x01FFD800, battleParty = 0x01FFD840, partyBackup = 0x01FFDD80, afterParty = 0x01FFE2C0,
  talk = 0x01FFE800, live = 0x01FFEC00, watch = 0x01FFF400, evolve = 0x01FFF600, chat = 0x01FFF700, ride = 0x01FFF900 }

local function r8(a) return memory.read_u8(a, SB) end
local function r32(a) return memory.read_u32_le(a, SB) end
local function w32(a, v) memory.write_u32_le(a, v, SB) end
local function ir32(a) return memory.read_u32_le(a - ITCM, IT) end
local function is32(a) return memory.read_s32_le(a - ITCM, IT) end
local function iw32(a, v) memory.write_u32_le(a - ITCM, v & 0xFFFFFFFF, IT) end
local function iw16(a, v) memory.write_u16_le(a - ITCM, v, IT) end
local function inRam(a) return a >= 0x02000000 and a < 0x02400000 end
local function irBytes(a, n)
  local t = memory.read_bytes_as_array(a - ITCM, n, IT)
  local s = {}
  for i = 1, n do s[i] = string.char(t[i]) end
  return table.concat(s)
end
local function iwBytes(a, s) for i = 1, #s do memory.writebyte(a - ITCM + i - 1, s:byte(i), IT) end end
local function readBytes(a, n)
  local t = memory.read_bytes_as_array(a, n, SB)
  local s = {}
  for i = 1, n do s[i] = string.char(t[i]) end
  return table.concat(s)
end

local codeWord = tonumber(CODE.hex:sub(7, 8) .. CODE.hex:sub(5, 6) .. CODE.hex:sub(3, 4) .. CODE.hex:sub(1, 2), 16)

-- (Re)writes our code into ITCM when it isn't there (first run, or the game was reset).
local function ensureCode()
  if ir32(SH) == MAGIC and ir32(CODE.base) == codeWord then return end
  for a = SH, CODE.base + CODE.size + 3, 4 do iw32(a, 0) end
  for i = 0, #CODE.hex / 2 - 1 do
    memory.writebyte(CODE.base + i - ITCM, tonumber(CODE.hex:sub(i * 2 + 1, i * 2 + 2), 16), IT)
  end
  iw32(SH + 0x04, 1)
  iw32(SH, MAGIC)
end

-- Points the field's event provider at our code, remembering the game's for it to call.
local function ensureHook()
  local gs = r32(G_GAMESYSTEM)
  if not inRam(gs) then return end
  local p = r32(gs + 0x10)
  if p ~= CODE.provider and inRam(p) then
    iw32(SH + 0x08, p)
    w32(gs + 0x10, CODE.provider)
  end
end

----------------------------------------------------------------------------------------------
-- Network (the oras-mmo wire protocol: fixed 48-byte frames, see PROTOCOL.md)
----------------------------------------------------------------------------------------------
local FRAME, PROTO = 48, 1
local T = { HELLO = 1, WELCOME = 2, STATE = 3, CHAT = 4, JOIN = 5, LEAVE = 6, ERROR = 7, PING = 8, GREET = 9,
  TALK = 10, BATTLE = 11, TRADE = 12, EVENT = 13, PARTY = 14, LIVE = 15 }
local PARTY = { REQUEST = 1, DATA = 2 }
local TRADE = { OFFER = 1, ACCEPT = 2, CANCEL = 3, COMMIT = 4 }

luanet.load_assembly("System")
local TcpClient = luanet.import_type("System.Net.Sockets.TcpClient")

local net = { client = nil, stream = nil, task = nil, connected = false, myId = 0, inbuf = "", retryAt = 0,
  lastSend = 0, status = "connecting", outq = {} }

local function frame(type, payload)
  local f = string.pack("<BBH", type, 0, PROTO) .. (payload or "")
  if #f < FRAME then f = f .. string.rep("\0", FRAME - #f) end
  return f:sub(1, FRAME)
end
local function cstr(s, from, len)
  local v = s:sub(from + 1, from + len)
  local z = v:find("\0", 1, true)
  return z and v:sub(1, z - 1) or v
end
local function pad(s, n) s = s:sub(1, n); return s .. string.rep("\0", n - #s) end

local function send(f)
  if not net.connected then return end
  local ok = pcall(function() net.stream:Write(f, 0, #f) end)
  if not ok then net.connected = false; net.status = "disconnected" end
end

-- Bulk frames (a party is 36) wait in a queue and go out one every other frame (30 a second): the server
-- drops whatever a player sends past 60 frames a second, and a party missing pieces is broken.
local function queue(f, to) net.outq[#net.outq + 1] = { f = f, to = to } end
local function unqueue(to)
  for i = #net.outq, 1, -1 do if net.outq[i].to == to then table.remove(net.outq, i) end end
end
local function pumpOut()
  if #net.outq > 0 and emu.framecount() % 2 == 0 then send(table.remove(net.outq, 1).f) end
end

local function now() return math.floor(emu.framecount() * 1000 / 60) end

local function startConnect()
  pcall(function() if net.client then net.client:Close() end end)
  net.client = TcpClient()
  net.client.NoDelay = true
  net.task = net.client:ConnectAsync(cfg.server, cfg.port)
  net.connected, net.inbuf, net.status, net.outq = false, "", "connecting to " .. cfg.server, {}
end

----------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------
local friends = {}   -- id -> { name, greet, samples, zone, matrix, model, status, slot, ... }
local notices = {}   -- queued notice strings
local notice = nil   -- { text, untilMs }
local chatLog = {}
local me = { ready = false, zone = 0, matrix = 0, x = 0, y = 0, z = 0, dir = 1, lastTicks = 0, staleFrames = 999,
  lastX = 0, lastZ = 0, seq = 0, noWarpUntil = 0 }
local seen = { badges = nil, party = {} }
local trade = { partner = nil, mySlot = nil, myRaw = nil, theirRaw = nil, theirChunks = {}, accepted = false,
  commitHash = nil }
local form = {}
-- Features (lua/features/*.lua), loaded at the end: see "Features" below for what they get and can hook
local features = {}

local function zoneName(z) return ZONES[z] or ("Zone " .. tostring(z)) end
local function speciesName(s) return SPECIES[s] or ("#" .. tostring(s)) end

local function addNotice(text)
  table.insert(notices, text)
  table.insert(chatLog, text)
  if #chatLog > 200 then table.remove(chatLog, 1) end
  if form.log then
    pcall(function() forms.settext(form.log, table.concat(chatLog, "\r\n")) end)
  end
end

----------------------------------------------------------------------------------------------
-- Our party (read from RAM: the game's party, encrypted)
----------------------------------------------------------------------------------------------
local function partyRaw()
  local p = ir32(SH + 0x44)
  if not inRam(p) then return {} end
  local count = r32(p + 4)
  if count > 6 then return {} end
  local out = {}
  for i = 1, count do out[i] = readBytes(p + 8 + (i - 1) * 0xDC, 0xDC) end
  return out
end

local function monLabel(raw)
  local m = PKM.decode(raw)
  if not m then return "?" end
  if m.isEgg then return "Egg" end
  local sp = speciesName(m.species)
  local nick = m.nickname ~= "" and m.nickname:upper() ~= sp:upper() and (m.nickname .. " (" .. sp .. ")") or sp
  return string.format("%s Lv%d", nick, m.level)
end

----------------------------------------------------------------------------------------------
-- Sending our state
----------------------------------------------------------------------------------------------
local function sendState()
  local status = 0
  if not me.ready then status = status | 1 end
  if me.exState == 1 then status = status | 2 end
  if me.exState == 2 then status = status | 4 end
  if now() < me.noWarpUntil then status = status | 8 end
  local moving = (me.x ~= me.lastX or me.z ~= me.lastZ)
  me.seq = me.seq + 1
  local p = string.pack("<HHfffIIffBBHI", me.zone, me.dir, me.x, me.y, me.z, me.matrix, me.seq, 0, 0,
    moving and 0x10 or 0, status, me.model or 0, now())
  send(frame(T.STATE, p))
  me.lastX, me.lastZ = me.x, me.z
end

----------------------------------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------------------------------
local function friend(id)
  local f = friends[id]
  if not f then
    f = { name = "#" .. id, greet = "", samples = {}, zone = -1, matrix = -1, model = 0, status = 0, slot = nil,
      lastSeen = now(), offset = nil }
    friends[id] = f
  end
  return f
end

local function releaseSlot(f)
  if f.slot then
    iw32(SLOT0 + f.slot * SLOTSZ, 0) -- want = 0: the game deletes the actor
    f.slot = nil
  end
end

local function sendGreet() send(frame(T.GREET, pad(cfg.greeting, 40))) end


-- Our team for a friend who wants to battle it: eggs left out, 6 chunks of 40 bytes a Pokemon
local function sendParty(to)
  unqueue(to) -- a newer request replaces one still going out
  local mons = {}
  for _, raw in ipairs(partyRaw()) do
    local m = PKM.decode(raw)
    if m and not m.isEgg then mons[#mons + 1] = raw end
  end
  if #mons == 0 then send(frame(T.PARTY, string.pack("<BBBB", PARTY.DATA, to, 0, 0))) return end
  for i, raw in ipairs(mons) do
    raw = raw .. string.rep(" ", 240 - #raw)
    for c = 0, 5 do
      queue(frame(T.PARTY, string.pack("<BBBB", PARTY.DATA, to, (i - 1) * 6 + c, #mons) .. raw:sub(c * 40 + 1, c * 40 + 40)), to)
    end
  end
end

local function requestParty(id)
  local f = friends[id]
  if f then f.partyAskedAt = now() end
  send(frame(T.PARTY, string.pack("<BB", PARTY.REQUEST, id)))
end

local function onParty(f, id, fr)
  local op, target = fr:byte(5), fr:byte(6)
  if target ~= net.myId then return end
  if op == PARTY.REQUEST then sendParty(id) return end
  if op ~= PARTY.DATA then return end
  local piece, count = fr:byte(7), fr:byte(8)
  if count == 0 then f.party = {} return end
  if count > 6 or piece >= count * 6 then return end
  if piece == 0 or not f.partyChunks or f.partyCount ~= count then f.partyChunks, f.partyCount = {}, count end
  f.partyChunks[piece] = fr:sub(9, 48)
  if piece == count * 6 - 1 then
    -- Only a whole team of Pokemon that decode (checksum right) replaces the one we have: a broken
    -- Pokemon in a battle crashes the game
    local mons = {}
    for i = 0, count - 1 do
      local parts = {}
      for c = 0, 5 do
        local part = f.partyChunks[i * 6 + c]
        if not part then f.partyChunks = {} return end
        parts[#parts + 1] = part
      end
      local raw = table.concat(parts):sub(1, 0xDC)
      if not PKM.decode(raw) then f.partyChunks = {} return end
      mons[#mons + 1] = raw
    end
    f.party, f.partyChunks = mons, {}
  end
end

local function onTrade(f, id, fr)
  local op, target = fr:byte(5), fr:byte(6)
  if target ~= net.myId then return end
  if op == TRADE.OFFER then
    local chunk, chunks = fr:byte(7), fr:byte(8)
    if trade.partner ~= id then
      trade.partner, trade.mySlot, trade.myRaw, trade.accepted = id, nil, nil, false
    end
    trade.theirChunks[chunk] = fr:sub(9, 48)
    if chunk == chunks - 1 then
      local parts = {}
      for i = 0, chunks - 1 do parts[#parts + 1] = trade.theirChunks[i] or string.rep("\0", 40) end
      local raw = table.concat(parts):sub(1, 0xDC)
      trade.theirChunks, trade.accepted = {}, false
      if PKM.decode(raw) then
        trade.theirRaw = raw
        addNotice(f.name .. " offers " .. monLabel(raw) .. ". Pick yours in the trade window.")
      else
        trade.theirRaw = nil
        addNotice(f.name .. "'s offer arrived broken. Ask them to offer again.")
      end
    end
  elseif op == TRADE.CANCEL then
    if trade.partner == id then
      addNotice(f.name .. " called the trade off.")
      trade.partner, trade.theirRaw, trade.myRaw, trade.mySlot, trade.accepted = nil, nil, nil, nil, false
    end
  elseif op == TRADE.COMMIT then
    trade.commitHash = string.unpack("<I", fr, 9)
  end
end

local function onFrame(fr)
  local type, id = fr:byte(1), fr:byte(2)
  if type == T.WELCOME then
    net.myId = id
    net.status = "online as #" .. id
    addNotice("Connected to " .. cfg.server .. " (room " .. cfg.room .. ").")
    sendGreet()
  elseif type == T.JOIN then
    local f = friend(id)
    f.name = cstr(fr, 4, 16)
    addNotice(f.name .. " joined!")
    sendGreet()
    requestParty(id)
  elseif type == T.LEAVE then
    local f = friends[id]
    if f then
      releaseSlot(f)
      addNotice(f.name .. " left.")
      if trade.partner == id then trade.partner, trade.theirRaw, trade.myRaw = nil, nil, nil end
      friends[id] = nil
    end
  elseif type == T.STATE then
    local f = friend(id)
    local zone, dir, x, y, z, matrix, seq, _, _, anim, status, model, t = string.unpack("<HHfffIIffBBHI", fr, 5)
    if f.zone ~= -1 and zone ~= f.zone and f.status & 8 == 0 and status & 8 == 0 then
      -- (a door or a map edge: not used yet beyond the notice)
    end
    if zone ~= f.zone and f.zone ~= -1 and zone == me.zone then addNotice(f.name .. " arrived.") end
    -- Only Nate's and Rosa's own models: the player's object code is something else on a bike, surfing,
    -- fishing or in a cutscene pose, and a friend's actor made with one of those can crash the game
    if model == OBJ_HERO or model == OBJ_HEROINE then f.model = model end
    f.zone, f.matrix, f.dir, f.anim, f.status, f.lastSeen = zone, matrix, dir, anim, status, now()
    local local_ = now()
    local off = local_ - t
    if not f.offset or off < f.offset or local_ - (f.offsetAt or 0) > 5000 then f.offset, f.offsetAt = off, local_ end
    table.insert(f.samples, { t = t, x = x, y = y, z = z, dir = dir, zone = zone })
    if #f.samples > 40 then table.remove(f.samples, 1) end
  elseif type == T.CHAT then
    local f = friend(id)
    addNotice(f.name .. ": " .. cstr(fr, 4, 40))
  elseif type == T.GREET then
    friend(id).greet = cstr(fr, 4, 40)
  elseif type == T.TALK then
    if fr:byte(5) == net.myId then addNotice(friend(id).name .. " is talking to you!") end
  elseif type == T.TRADE then
    onTrade(friend(id), id, fr)
  elseif type == T.PARTY then
    onParty(friend(id), id, fr)
  elseif type == T.EVENT then
    local f = friend(id)
    local kind, value, species, from = fr:byte(5), fr:byte(6), string.unpack("<H", fr, 7), string.unpack("<H", fr, 9)
    if kind == 1 then addNotice(f.name .. " caught " .. speciesName(species) .. "!")
    elseif kind == 2 then addNotice(f.name .. "'s " .. speciesName(from) .. " evolved into " .. speciesName(species) .. "!")
    elseif kind == 3 then addNotice(f.name .. " earned badge " .. value .. "!") end
  elseif type == T.ERROR then
    local code = fr:byte(5)
    net.status = code == 1 and "room full" or code == 3 and "server version differs" or "server refused"
    addNotice("Server: " .. net.status)
  end
  -- Features see every frame after the above (on LEAVE the friend is already gone: f is nil)
  for _, ft in ipairs(features) do
    local h = ft.onFrame and ft.onFrame[type]
    if h then h(friends[id], id, fr) end
  end
end

local function pumpNet()
  if not net.connected then
    if net.task then
      if net.task.IsCompleted then
        if net.client.Connected then
          net.connected, net.task = true, nil
          net.stream = net.client:GetStream()
          send(frame(T.HELLO, pad(cfg.room:upper(), 12) .. pad(cfg.name, 16)))
          net.status = "joining " .. cfg.room
        else
          net.task, net.retryAt, net.status = nil, now() + 5000, "can't reach " .. cfg.server .. ", retrying"
        end
      end
    elseif now() >= net.retryAt then
      startConnect()
    end
    return
  end
  local ok = pcall(function()
    local n = net.client.Available
    if n > 0 then
      local b = {}
      for i = 1, n do b[i] = string.char(net.stream:ReadByte()) end
      net.inbuf = net.inbuf .. table.concat(b)
    end
  end)
  if not ok or not net.client.Connected then
    net.connected, net.retryAt, net.status = false, now() + 3000, "disconnected, retrying"
    for _, f in pairs(friends) do releaseSlot(f) end
    friends = {}
    return
  end
  while #net.inbuf >= FRAME do
    local fr = net.inbuf:sub(1, FRAME)
    net.inbuf = net.inbuf:sub(FRAME + 1)
    onFrame(fr)
  end
end

----------------------------------------------------------------------------------------------
-- Friends on our map
----------------------------------------------------------------------------------------------
local DELAY = 150

-- Where a friend should be drawn now: their samples replayed DELAY ms late, interpolated.
local function friendPos(f)
  local s = f.samples
  if #s == 0 then return nil end
  local rt = now() - (f.offset or 0) - DELAY
  local a, b = nil, nil
  for i = #s, 1, -1 do
    if s[i].t <= rt then a, b = s[i], s[i + 1]; break end
  end
  if not a then a = s[1] end
  if not b or b.zone ~= a.zone then return a.x, a.y, a.z, a.dir, a.zone end
  local dx, dz = b.x - a.x, b.z - a.z
  if dx * dx + dz * dz > 64 * 64 then return a.x, a.y, a.z, a.dir, a.zone end -- a warp: no sliding
  local k = (rt - a.t) / math.max(1, b.t - a.t)
  return a.x + dx * k, a.y + (b.y - a.y) * k, a.z + dz * k, a.dir, a.zone
end

-- Friends share our map when they're in our zone, or in another zone of the same overworld matrix
-- (0 and 175: the only map matrices made of several zones, which share one set of coordinates;
-- every other matrix is one zone's, and many buildings use the same one).
local SHARED_MATRIX = { [0] = true, [175] = true }
local function sameMap(f, zone)
  return me.ready and (zone == me.zone or (f.matrix == me.matrix and SHARED_MATRIX[me.matrix] == true))
end

local function updateFriends()
  local used = {}
  for _, f in pairs(friends) do if f.slot then used[f.slot] = true end end
  for _, f in pairs(friends) do
    local x, y, z, dir, zone = friendPos(f)
    f.drawX = nil
    if x and sameMap(f, zone) then
      if not f.slot then
        for i = 0, NSLOTS - 1 do if not used[i] then f.slot = i; used[i] = true; break end end
      end
      if f.slot then
        local a = SLOT0 + f.slot * SLOTSZ
        local model = f.model
        if model == 0 then model = OBJ_HERO end
        iw32(a + 0x04, model)
        iw32(a + 0x08, math.floor(x * 4096 + 0.5))
        iw32(a + 0x0C, math.floor(y * 4096 + 0.5))
        iw32(a + 0x10, math.floor(z * 4096 + 0.5))
        iw16(a + 0x14, dir & 3)
        iw32(a + 0x18, 0)
        iw32(a, 1)
        f.drawX, f.drawY, f.drawZ, f.drawDir = x, y, z, dir
      end
    else
      releaseSlot(f)
    end
  end
end

----------------------------------------------------------------------------------------------
-- Our game: position, activity
----------------------------------------------------------------------------------------------
local function readMe()
  local ticks = ir32(SH + 0x0C)
  if ticks ~= me.lastTicks then me.lastTicks, me.staleFrames = ticks, 0 else me.staleFrames = me.staleFrames + 1 end
  local wasReady = me.ready
  -- The field asks for events at 30 fps; a few frames without means a menu, text box, battle or cutscene
  me.ready = ir32(SH + 0x10) == 1 and me.staleFrames < 6
  if ir32(SH + 0x10) == 1 then
    local zone = ir32(SH + 0x30)
    if zone ~= me.zone and me.zone ~= 0 then
      -- Map change: a walk through a door if we were just walking, else (Fly, Dig...) no warp
      if me.staleFrames > 90 then me.noWarpUntil = now() + 5000 end
    end
    me.x, me.y, me.z = is32(SH + 0x20) / 4096, is32(SH + 0x24) / 4096, is32(SH + 0x28) / 4096
    me.dir, me.zone, me.objCode = ir32(SH + 0x2C), zone, ir32(SH + 0x34)
    me.exState, me.matrix = ir32(SH + 0x3C), ir32(SH + 0x40)
    me.model = ir32(SH + 0x38) == 1 and OBJ_HEROINE or OBJ_HERO -- by sex: see the STATE handler
  end
  if not wasReady and me.ready == false and me.staleFrames > 120 then me.noWarpUntil = now() + 5000 end
end

local function badgeCount(b)
  local n = 0
  while b ~= 0 do n = n + (b & 1); b = b >> 1 end
  return n
end

local function checkActivity()
  if not me.ready then return end
  local badges = ir32(SH + 0x48)
  if seen.badges and badges ~= seen.badges and badgeCount(badges) > badgeCount(seen.badges) then
    local n = badgeCount(badges)
    send(frame(T.EVENT, string.pack("<BBHH", 3, n, 0, 0)))
    addNotice("You earned badge " .. n .. "!")
  end
  seen.badges = badges
  for k = 0, 3 do
    local sp = ir32(SH + 0x50 + k * 4)
    if sp ~= 0 then
      iw32(SH + 0x50 + k * 4, 0)
      send(frame(T.EVENT, string.pack("<BBHH", 1, 0, sp, 0)))
    end
  end
  -- Evolutions: the same Pokemon (PID) with another species
  if emu.framecount() % 60 == 0 then
    local now_ = {}
    for _, raw in ipairs(partyRaw()) do
      local m = PKM.decode(raw)
      if m and not m.isEgg then
        local before = seen.party[m.pid]
        if before and before ~= m.species then
          send(frame(T.EVENT, string.pack("<BBHH", 2, 0, m.species, before)))
          addNotice("Your " .. speciesName(before) .. " evolved into " .. speciesName(m.species) .. "!")
        end
        now_[m.pid] = m.species
      end
    end
    seen.party = now_
  end
end

----------------------------------------------------------------------------------------------
-- Talking: A facing a friend's trainer
----------------------------------------------------------------------------------------------
local prevA = false
local DIRV = { [0] = { 0, -1 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 1, 0 } }

local function checkTalk()
  local a = joypad.get()["A"] == true
  local pressed = a and not prevA
  prevA = a
  if not pressed or not me.ready then return end
  local d = DIRV[me.dir & 3]
  local tx, tz = math.floor(me.x / 16) + d[1], math.floor(me.z / 16) + d[2]
  for id, f in pairs(friends) do
    if f.drawX and math.floor(f.drawX / 16) == tx and math.floor(f.drawZ / 16) == tz and math.abs(f.drawY - me.y) < 16 then
      send(frame(T.TALK, string.pack("<B", id)))
      -- Their team (for Battle), at most every 10 s: mashing A would flood the server
      if now() - (f.partyAskedAt or -10000) >= 10000 then requestParty(id) end
      -- A feature can take the conversation over (the game's own text box)
      for _, ft in ipairs(features) do
        if ft.onTalk and ft.onTalk(f, id) then return end
      end
      local g = f.greet ~= "" and f.greet or "..."
      addNotice(f.name .. ": " .. g)
      return
    end
  end
end

----------------------------------------------------------------------------------------------
-- Trading (from the window): offer, accept, then the server commits both at once
----------------------------------------------------------------------------------------------
local function sendOffer(partner, raw)
  local chunks = math.ceil(#raw / 40)
  for c = 0, chunks - 1 do
    send(frame(T.TRADE, string.pack("<BBBB", TRADE.OFFER, partner, c, chunks) .. raw:sub(c * 40 + 1, c * 40 + 40)))
  end
end

local function tradeHash()
  local a, b = trade.myRaw, trade.theirRaw
  if net.myId > trade.partner then a, b = b, a end
  return PKM.fnv(a .. b)
end

local function cancelTrade(silent)
  if trade.partner then send(frame(T.TRADE, string.pack("<BB", TRADE.CANCEL, trade.partner))) end
  if not silent then addNotice("Trade called off.") end
  trade.partner, trade.theirRaw, trade.myRaw, trade.mySlot, trade.accepted, trade.commitHash = nil, nil, nil, nil, false, nil
end

local function finishTrade()
  if not trade.commitHash or not me.ready then return end
  if not trade.myRaw or not trade.theirRaw or trade.commitHash ~= tradeHash() then
    trade.commitHash = nil
    return
  end
  local party = partyRaw()
  if party[trade.mySlot] ~= trade.myRaw then
    addNotice("Your Pokemon changed before the trade finished: trade skipped.")
    cancelTrade(true)
    return
  end
  for i = 0, 0xDB do memory.writebyte(SH + 0x300 + i - ITCM, trade.theirRaw:byte(i + 1), IT) end
  iw32(SH + 0x60, trade.mySlot)
  local partnerName = friends[trade.partner] and friends[trade.partner].name or "your friend"
  addNotice("Traded " .. monLabel(trade.myRaw) .. " to " .. partnerName .. " for " .. monLabel(trade.theirRaw) .. "!")
  trade.partner, trade.theirRaw, trade.myRaw, trade.mySlot, trade.accepted, trade.commitHash = nil, nil, nil, nil, false, nil
end

----------------------------------------------------------------------------------------------
-- Battling a friend's team (their party from PARTY frames; the game's AI plays it)
----------------------------------------------------------------------------------------------
local battle = { with = nil }

local function startBattle(id)
  local f = friends[id]
  if not f then addNotice("Pick a friend first.") return end
  if not me.ready then addNotice("Get back to walking around first.") return end
  if not f.party then
    requestParty(id)
    addNotice("Getting " .. f.name .. "'s team... press Battle again in a moment.")
    return
  end
  if #f.party == 0 then addNotice(f.name .. " has no Pokemon to battle with.") return end
  for i, raw in ipairs(f.party) do
    iwBytes(ADDR.battleParty + (i - 1) * 0xDC, raw:sub(1, 0xDC))
  end
  local name = f.name:sub(1, 12)
  for i = 1, #name do iw16(ADDR.battleName + (i - 1) * 2, name:byte(i)) end
  iw16(ADDR.battleName + #name * 2, 0xFFFF)
  iw32(SH + 0x70, f.model == OBJ_HEROINE and 363 or 360)
  iw32(SH + 0x74, #f.party)
  iw32(SH + 0x6C, 0)
  iw32(SH + 0x68, 1)
  battle.with = f.name
end

local function checkBattle()
  if ir32(SH + 0x6C) ~= 2 then return end
  iw32(SH + 0x6C, 0)
  local count = ir32(ADDR.afterParty + 4)
  local alive = false
  for i = 0, math.min(count, 6) - 1 do
    local m = PKM.decode(irBytes(ADDR.afterParty + 8 + i * 0xDC, 0xDC))
    if m and not m.isEgg and m.hp > 0 then alive = true end
  end
  addNotice((alive and "You beat " or "You lost to ") .. (battle.with or "your friend") .. "'s team! (Your party is back as it was.)")
  battle.with = nil
end

----------------------------------------------------------------------------------------------
-- Drawing: names over heads, notices, the player list
----------------------------------------------------------------------------------------------
-- The field camera looks down at the player (screen 128, ~62 for a head) at a fixed angle;
-- this approximates it (about 1.06 px a unit across at the player's depth, more nearer the camera).
local function project(x, y, z)
  local dx, dy, dz = x - me.x, y - me.y, z - me.z
  local sx = 128 + dx * (1.06 + dz * 0.005)
  local sy = 62 + dz * 1.02 - dy
  return sx, sy
end

local function drawLabels()
  if cfg.labels == "0" or not me.ready then return end
  for _, f in pairs(friends) do
    if f.drawX then
      local sx, sy = project(f.drawX, f.drawY, f.drawZ)
      local text = f.name .. ((f.status & 1 == 1) and " (busy)" or "")
      if sx < 0 or sx > 255 or sy < 0 or sy > 191 then
        local cx, cy = math.max(4, math.min(252, sx)), math.max(8, math.min(184, sy))
        gui.drawText(cx, cy, text, 0xFFFFFFFF, 0xA0000000, 9, nil, nil, sx < 128 and "left" or "right", "middle")
      else
        gui.drawText(sx, sy, text, 0xFFFFFFFF, 0x90000000, 9, nil, nil, "center", "bottom")
      end
    end
  end
end

local function drawNotice()
  local t = now()
  if notice and t > notice.untilMs then notice = nil end
  if not notice and #notices > 0 and me.ready then
    -- 3 s each, quicker while more are waiting
    notice = { text = table.remove(notices, 1), untilMs = t + (#notices > 2 and 1200 or 3000) }
  end
  if notice then
    gui.drawBox(4, 4, 251, 22, 0xFF586068, 0xF0F8F8F8)
    local text = #notice.text > 46 and (notice.text:sub(1, 45) .. "…") or notice.text
    gui.drawText(10, 8, text, 0xFF303030, 0x00000000, 9)
  end
end

local function drawList()
  local keys = input.get()
  if not keys["Tab"] then
    gui.drawText(2, 372, "B2 MMO " .. net.status .. "  (Tab: players)", 0xC0FFFFFF, 0x80000000, 8)
    return
  end
  local lines = { string.format("%s (you): %s", cfg.name, zoneName(me.zone)) }
  for _, f in pairs(friends) do
    lines[#lines + 1] = string.format("%s: %s%s", f.name, f.zone >= 0 and zoneName(f.zone) or "?", (f.status & 1 == 1) and " (busy)" or "")
  end
  gui.drawBox(4, 196, 251, 200 + #lines * 12, 0xFF586068, 0xE0202830)
  for i, l in ipairs(lines) do gui.drawText(8, 186 + i * 12, l, 0xFFFFFFFF, 0x00000000, 10) end
end

----------------------------------------------------------------------------------------------
-- The window: chat, who's online, trading
----------------------------------------------------------------------------------------------
local function friendNames()
  local t = {}
  for id, f in pairs(friends) do t[#t + 1] = f.name .. " #" .. id end
  table.sort(t)
  if #t == 0 then t[1] = "(nobody online)" end
  return t
end

local function partyNames()
  local t = {}
  for i, raw in ipairs(partyRaw()) do t[#t + 1] = i .. ": " .. monLabel(raw) end
  if #t == 0 then t[1] = "(party not loaded)" end
  return t
end

local function who()
  local n = 1
  for _ in pairs(friends) do n = n + 1 end
  addNotice(n .. " online in " .. cfg.room .. ": you and " .. (n - 1) .. " friend" .. (n == 2 and "" or "s"))
  for _, f in pairs(friends) do
    addNotice(f.name .. ": " .. zoneName(f.zone) .. ((f.status & 1 == 1) and " (busy)" or ""))
  end
end

-- Says something in the chat (or runs /who), from the window or a feature
local function say(text)
  if text == nil or text == "" then return end
  if text == "/who" then who() return end
  send(frame(T.CHAT, pad(text, 40)))
  addNotice(cfg.name .. ": " .. text:sub(1, 40))
end

local function sendChat()
  local text = forms.gettext(form.input)
  forms.settext(form.input, "")
  say(text)
end

local function selectedId(dropdown)
  local s = forms.gettext(dropdown) or ""
  return tonumber(s:match("#(%d+)$"))
end

local function offerTrade(partner, slot)
  partner = partner or selectedId(form.friend)
  slot = slot or tonumber((forms.gettext(form.mon) or ""):match("^(%d+):"))
  if not partner or not friends[partner] or not slot then addNotice("Pick a friend and a Pokemon first.") return end
  local raw = partyRaw()[slot]
  if not raw then return end
  if trade.partner and trade.partner ~= partner then cancelTrade(true) end
  trade.partner, trade.mySlot, trade.myRaw, trade.accepted = partner, slot, raw, false
  sendOffer(partner, raw)
  addNotice("You offered " .. monLabel(raw) .. " to " .. friends[partner].name .. ".")
end

local function acceptTrade()
  if not (trade.partner and trade.myRaw and trade.theirRaw) then
    addNotice("Both of you have to offer a Pokemon first.")
    return
  end
  trade.accepted = true
  send(frame(T.TRADE, string.pack("<BBxxI", TRADE.ACCEPT, trade.partner, tradeHash())))
  addNotice("You accepted. Waiting for " .. (friends[trade.partner] and friends[trade.partner].name or "them") .. "...")
end

local function buildForm()
  form.id = forms.newform(380, 720, "Black 2 MMO " .. VERSION, function() form.id = nil end)
  forms.label(form.id, "Chat (/who lists who's online)", 8, 8, 360, 18)
  form.log = forms.textbox(form.id, "", 350, 200, nil, 8, 28, true, false, "Vertical")
  form.input = forms.textbox(form.id, "", 270, 22, nil, 8, 234)
  forms.button(form.id, "Send", sendChat, 284, 232, 74, 26)
  forms.label(form.id, "Trade", 8, 270, 360, 18)
  forms.label(form.id, "With", 8, 294, 60, 18)
  form.friend = forms.dropdown(form.id, friendNames(), 70, 290, 200, 22)
  forms.label(form.id, "Give", 8, 324, 60, 18)
  form.mon = forms.dropdown(form.id, partyNames(), 70, 320, 200, 22)
  forms.button(form.id, "Refresh", function()
    forms.setdropdownitems(form.friend, friendNames())
    forms.setdropdownitems(form.mon, partyNames())
  end, 280, 290, 78, 54)
  forms.button(form.id, "Battle their team", function() startBattle(selectedId(form.friend)) end, 8, 390, 350, 28)
  forms.button(form.id, "Offer", function() offerTrade() end, 8, 354, 110, 28)
  forms.button(form.id, "Accept", acceptTrade, 124, 354, 110, 28)
  forms.button(form.id, "Call off", function() cancelTrade(false) end, 240, 354, 118, 28)
  form.tradeLabel = forms.label(form.id, "", 8, 424, 360, 40)
  -- Features add their controls below, each from the y the previous one stopped at
  local y = 470
  for _, ft in ipairs(features) do
    if ft.buildForm then y = ft.buildForm(form.id, y) or y end
  end
end

local function updateTradeLabel()
  if not form.tradeLabel or emu.framecount() % 30 ~= 0 then return end
  local s = ""
  if trade.partner and friends[trade.partner] then
    s = "With " .. friends[trade.partner].name .. ": you give " .. (trade.myRaw and monLabel(trade.myRaw) or "(pick one)") ..
      ", you get " .. (trade.theirRaw and monLabel(trade.theirRaw) or "(waiting)") .. (trade.accepted and "  [accepted]" or "")
  end
  forms.settext(form.tradeLabel, s)
end

----------------------------------------------------------------------------------------------
-- Features
----------------------------------------------------------------------------------------------
-- Each lua/features/<name>.lua returns function(api) -> a table with any of these hooks:
--   tick()                      every frame, after the core's own work (also while offline)
--   draw()                      every frame, after the core's drawing (gui.* on the screen)
--   onFrame = { [T.X] = fn(f, id, fr) }  every received frame of that type, after the core
--   onTalk(f, id) -> true       A was pressed facing friend f: return true to take it over
--   buildForm(formId, y) -> y   add controls to the window from y down, return the next free y
-- api.actions is what talking to a friend can lead to: { label, run = fn(f, id) }, in order.
-- api.talkInfo holds fn(f, id) -> lines or nil, extra things to say about a friend when talked to.
local FEATURES = { "talk", "live", "watch", "evolve", "doors", "chat", "ride" }
local api = {
  cfg = cfg, T = T, PARTY = PARTY, TRADE = TRADE, ADDR = ADDR, SH = SH, ITCM = ITCM, SB = SB, IT = IT,
  OBJ_HERO = OBJ_HERO, OBJ_HEROINE = OBJ_HEROINE, DIRV = DIRV, PKM = PKM,
  net = net, me = me, friends = friends, trade = trade, battle = battle, form = form,
  r8 = r8, r32 = r32, w32 = w32, ir32 = ir32, is32 = is32, iw32 = iw32, iw16 = iw16, inRam = inRam,
  readBytes = readBytes, irBytes = irBytes, iwBytes = iwBytes,
  frame = frame, send = send, cstr = cstr, pad = pad, now = now, say = say,
  addNotice = addNotice, zoneName = zoneName, speciesName = speciesName, partyRaw = partyRaw, monLabel = monLabel,
  friend = friend, requestParty = requestParty, sameMap = sameMap, project = project,
  startBattle = startBattle, offerTrade = offerTrade, acceptTrade = acceptTrade, cancelTrade = cancelTrade,
  actions = { { label = "Battle", run = function(f, id) startBattle(id) end } },
  talkInfo = {},
}
for _, name in ipairs(FEATURES) do
  local path = DIR .. "features/" .. name .. ".lua"
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    local ok, mod = pcall(dofile, path)
    if ok and type(mod) == "function" then ok, mod = pcall(mod, api) end
    if ok and type(mod) == "table" then
      mod.name = name
      features[#features + 1] = mod
    elseif not ok then
      console.log("Black 2 MMO: feature " .. name .. " failed: " .. tostring(mod))
    end
  end
end

----------------------------------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------------------------------
buildForm()
addNotice("Black 2 MMO " .. VERSION .. ": " .. cfg.name .. " -> " .. cfg.server .. ":" .. cfg.port .. " room " .. cfg.room)
event.onexit(function()
  for _, f in pairs(friends) do releaseSlot(f) end
  pcall(function() net.client:Close() end)
  if form.id then forms.destroy(form.id) end
end)

while true do
  ensureCode()
  ensureHook()
  readMe()
  pumpNet()
  if net.connected and net.myId ~= 0 then
    local interval = (me.x ~= me.lastX or me.z ~= me.lastZ) and 66 or 1000
    if now() - net.lastSend >= interval then sendState(); net.lastSend = now() end
    checkActivity()
    checkTalk()
    finishTrade()
    pumpOut()
  end
  checkBattle()
  updateFriends()
  for _, ft in ipairs(features) do if ft.tick then ft.tick() end end
  gui.clearGraphics()
  drawLabels()
  drawNotice()
  drawList()
  for _, ft in ipairs(features) do if ft.draw then ft.draw() end end
  updateTradeLabel()
  if B2MMO_TEST then B2MMO_TEST({ me = me, friends = friends, net = net, trade = trade, form = form, api = api,
    features = features, offerTrade = offerTrade, acceptTrade = acceptTrade, startBattle = startBattle,
    partyRaw = partyRaw, monLabel = monLabel }) end
  emu.frameadvance()
end
