-- Trade evolutions against the fake friend:
--   B2PORT=7784 bash test/up.sh "--name Ann --x 616 --z 120 --path stand --trade <out>/offer.bin"
--   bash test/run.sh test/t_evolve.lua 480
-- Trades are answered in the game's box (talk.lua asks "You give .. You get .. Trade with Ann?").
-- The test dumps our party, makes the friend's offers from it (tools/pkedit.mjs, or PKEDIT;
-- tools/ff/evolve.mjs for new PIDs) and writes each into offer.bin before
-- offering our slot 2 for it:
--   1. Haunter Lv30            -> the game's scene, Gengar in the party
--   2. Seadra with Dragon Scale -> Kingdra, item gone
--   3. Haunter with Everstone   -> no evolution
--   4. Sigilyph                 -> nothing extra
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local OUT, ROOT = K.env.out, K.env.root
local PKEDIT = os.getenv("PKEDIT") or (ROOT .. "tools/pkedit.mjs")
local EV = 0x01FFF600
local DRAGON_SCALE, EVERSTONE = 235, 229

local function run(cmd)
  local ok = os.execute(cmd .. " >> \"" .. OUT .. "mk.log\" 2>&1")
  K.log("$ " .. cmd .. " -> " .. tostring(ok))
  return ok
end

-- out = slot 2 of our party, edited, with a new PID
local function makeOffer(name, pid, opts)
  local tmp = OUT .. name .. "_tmp.bin"
  run(string.format('node "%s" pick "%sparty.bin" "%s" 2', PKEDIT, OUT, tmp))
  run(string.format('node "%s" edit "%s" "%s" --slot 1 %s', PKEDIT, tmp, tmp, opts))
  run(string.format('node "%stools/ff/evolve.mjs" setpid "%s" "%s%s.bin" %s', ROOT, tmp, OUT, name, pid))
end

local function copy(from, to)
  local a = io.open(from, "rb"); local d = a:read("a"); a:close()
  local b = io.open(to, "wb"); b:write(d); b:close()
end

local CASES = {
  { file = "haunter", into = 94, label = "Haunter -> Gengar" },
  { file = "seadra", into = 230, label = "Seadra + Dragon Scale -> Kingdra", itemGone = true },
  { file = "everstone", into = nil, label = "Haunter + Everstone: no evolution" },
  { file = "plain", into = nil, label = "Sigilyph: nothing" },
}

local step, at, case, friendId, base, fails = "init", 0, 0, nil, nil, 0
local evolvedAt, offerSeen, checkAt
local API
local function ev(o) return API.ir32(EV + o) end
local function check(cond, what)
  K.log((cond and "PASS " or "FAIL ") .. what)
  if not cond then fails = fails + 1 end
end
local function slot2(s) return s.api.PKM.decode(s.partyRaw()[2] or "") end
local function counters() return { checks = ev(0x04), started = ev(0x14), finished = ev(0x18) } end

K.start({ name = "Michael" }, function(s, f)
  API = s.api
  if step == "init" then
    if f == 60 then
      K.log("party: " .. K.party(s))
      K.dumpParty(s, OUT .. "party.bin")
      makeOffer("haunter", "1a2b3c01", "--species 93 --level 30 --item 0")
      makeOffer("seadra", "1a2b3c02", "--species 117 --level 40 --item " .. DRAGON_SCALE)
      makeOffer("everstone", "1a2b3c03", "--species 93 --level 30 --item " .. EVERSTONE)
      makeOffer("plain", "1a2b3c04", "--item 0")
      step, at = "next", f
    end
  elseif step == "next" then
    if f - at < 60 or f < 600 or not s.me.ready or s.net.myId == 0 then return end
    for id in pairs(s.friends) do friendId = id end
    if not friendId then return end
    case = case + 1
    local c = CASES[case]
    if not c then
      K.log("done, " .. fails .. " failures")
      client.exit()
      return
    end
    copy(OUT .. c.file .. ".bin", OUT .. "offer.bin")
    base, evolvedAt, offerSeen = counters(), nil, nil
    K.log("case " .. case .. ": " .. c.label .. "; party " .. K.party(s) .. "; caught " .. API.ir32(API.SH + 0x4C))
    s.offerTrade(friendId, 2)
    step, at = "accept", f
  elseif step == "accept" then
    -- Their offer back makes talk.lua ask "You give .. You get .. Trade with Ann?" in the game's
    -- box: answer it (A through the pages, A on Yes), which accepts the trade
    local n = counters()
    if s.trade.theirRaw and not offerSeen then offerSeen = f; K.log("they offer " .. s.monLabel(s.trade.theirRaw)) end
    if offerSeen then
      local t = f - offerSeen
      if t == 50 and case == 1 then K.shot("c1_confirm") end
      if t > 60 and t % 40 < 3 then K.press({ A = true }) end
    end
    if n.checks > base.checks then
      checkAt = f
      K.log("trade landed and checked: species " .. ev(0x08))
      step, at = "wait", f
    elseif f - at > 1800 then check(false, "trade never landed"); step, at = "next", f end
  elseif step == "wait" then
    local c = CASES[case]
    local n = counters()
    local t = f - at
    if c.into then
      -- "Ann sent over X!" in the game's box, closed with A, then the scene: A now and then for its text
      if t == 30 then K.shot("c" .. case .. "_sentover") end
      if t > 60 and t % 40 < 3 then K.press({ A = true }) end
      if n.started > base.started and n.finished == base.finished then
        if t % 150 == 0 and case <= 2 then K.shot(string.format("c%d_scene_%04d", case, t)) end
        local m = slot2(s)
        if m and m.species == c.into and not evolvedAt then evolvedAt = f; K.log("species changed at frame " .. t) end
        if evolvedAt and (f - evolvedAt == 30 or f - evolvedAt == 100) then K.shot(string.format("c%d_evolved_%d", case, f - evolvedAt)) end
      end
      if n.finished > base.finished and s.me.ready then
        step, at = "after", f
      elseif t > 6000 then check(false, "scene never finished"); step, at = "after", f end
    else
      if t > 240 then step, at = "after", f end
    end
  elseif step == "after" then
    if f - at < 150 then return end
    K.shot("c" .. case .. "_field")
    local c, n, m = CASES[case], counters(), slot2(s)
    K.log("after: party " .. K.party(s) .. "; checks " .. n.checks .. " started " .. n.started .. " finished " .. n.finished ..
      " species " .. ev(0x08) .. " method " .. ev(0x0C) .. " item " .. tostring(m and m.item))
    check(n.checks == base.checks + 1, "one check")
    if c.into then
      check(m and m.species == c.into, "slot 2 is now " .. c.into)
      check(n.started == base.started + 1, "scene started once")
      if c.itemGone then check(m and m.item == 0, "held item used up") end
    else
      check(n.started == base.started, "no scene")
      check(m and m.species ~= 94 and m.species ~= 230, "slot 2 did not evolve")
    end
    if case <= 2 then step, at = "menu", f else step, at = "next", f end
  elseif step == "menu" then
    -- The party screen: X, then Pokemon
    local t = f - at
    if t < 4 then K.press({ X = true })
    elseif (t >= 60 and t < 64) or (t >= 110 and t < 114) then K.press({ A = true })
    elseif t == 260 then K.shot("c" .. case .. "_party")
    elseif (t >= 280 and t < 284) or (t >= 330 and t < 334) or (t >= 380 and t < 384) or (t >= 430 and t < 434) then K.press({ B = true })
    elseif t > 560 then step, at = "next", f end
  end
end)
