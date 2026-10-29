-- Black 2 MMO feature: live battles. Each player plays their own side of a battle against the other.
--
-- Challenge (talk to a friend -> Live battle, or the window): our whole party (PARTY op 3) and a LIVE
-- CHALLENGE with a random seed go to the friend; their game asks "X challenges you to a live
-- battle!". Yes: their party and LIVE ACCEPT come back, and both games start the core's friend battle
-- against the other's team with the live hooks armed (arm/live.c): from then on each answer one
-- player gives the battle (a move, a switch, a send-in) goes to the other as a LIVE ACTION frame, and
-- replaces what the game's AI would have chosen for that player's side. The challenger is the host.
-- If the friend leaves (or calls it off) during the battle, the AI plays their side to the end.
-- Wire format: PROTOCOL.md (PARTY op 3, LIVE). Game side: arm/live.h (MMO_LIVE_AREA).
return function(api)
  local T = api.T
  local L = api.ADDR.live
  local OP = { CHALLENGE = 1, ACCEPT = 2, CANCEL = 3, ACTION = 4 }
  local PARTY_LIVE = 3
  local TIMEOUT = 60000
  -- MMO_LIVE_AREA offsets (arm/live.h)
  local O = { pending = 0x00, host = 0x04, seed = 0x08, partnerGone = 0x0C, inW = 0x10, outR = 0x14, armed = 0x18,
    patched = 0x1C, seeded = 0x20, fellBack = 0x24, desync = 0x28, inR = 0x2C, outW = 0x30, steps01 = 0x34,
    waiting = 0x38, lastOurs = 0x3C, lastTheirs = 0x40, check = 0x44, hpCount = 0x48, hp = 0x4C, steps = 0xB0,
    inQ = 0x100, outQ = 0x200 }
  local QUEUE = 8

  -- phase: nil, "challenging" (we asked), "asked" (they asked us), "starting" (both agreed, waiting
  -- for their party or our field), "battle"
  local live = { phase = nil, with = nil, host = false, seed = 0, deadline = 0, parties = {}, chunks = {},
    inbox = {}, sentArmed = false, outSent = 0, lastWaiting = 0 }
  local M = { live = live }

  local function rd(o) return api.ir32(L + o) end
  local function wr(o, v) api.iw32(L + o, v) end
  local known = {} -- names of friends we had a live battle going with (LEAVE comes after the core forgot them)
  local function nameOf(id)
    local f = api.friends[id]
    if f then known[id] = f.name end
    return known[id] or ("#" .. tostring(id))
  end
  local function liveFrame(op, to, rest) return api.frame(T.LIVE, string.pack("<BB", op, to) .. (rest or "")) end

  local function reset() live.phase, live.with, live.inbox, live.sentArmed = nil, nil, {}, false end

  -- Our whole party as the game has it (eggs too, in order: the battle counts party slots), 6 chunks a Pokemon
  local function sendParty(to)
    local mons = api.partyRaw()
    if #mons == 0 then return false end
    for i, raw in ipairs(mons) do
      raw = raw .. string.rep("\0", 240 - #raw)
      for c = 0, 5 do
        api.queue(api.frame(T.PARTY, string.pack("<BBBB", PARTY_LIVE, to, (i - 1) * 6 + c, #mons) .. raw:sub(c * 40 + 1, c * 40 + 40)))
      end
    end
    return true
  end

  local function cancel(text)
    if live.with then api.send(liveFrame(OP.CANCEL, live.with)) end
    if text then api.addNotice(text) end
    reset()
  end

  local function inBattle() return api.ir32(api.SH + 0x6C) == 1 or rd(O.armed) == 1 end

  function M.challenge(id)
    local f = api.friends[id]
    if not f then api.addNotice("Pick a friend first.") return end
    if live.phase then api.addNotice("You're already busy with a live battle.") return end
    if not api.me.ready or inBattle() then api.addNotice("Get back to walking around first.") return end
    if not sendParty(id) then api.addNotice("Your party isn't loaded yet.") return end
    live.phase, live.with, live.host = "challenging", id, true
    live.seed = math.random(1, 0x7FFFFFFF) ~ (emu.framecount() * 0x9E37) & 0xFFFFFFFF
    live.deadline = api.now() + TIMEOUT
    api.queue(liveFrame(OP.CHALLENGE, id, string.pack("<xxI4", live.seed))) -- after the party (queued)
    api.addNotice("You challenged " .. f.name .. " to a live battle. Waiting for an answer...")
  end

  function M.accept()
    if live.phase ~= "asked" then api.addNotice("Nobody is challenging you right now.") return end
    if not sendParty(live.with) then cancel("Your party isn't loaded yet: live battle called off.") return end
    api.queue(liveFrame(OP.ACCEPT, live.with)) -- after the party (queued)
    live.phase, live.host, live.deadline = "starting", false, api.now() + TIMEOUT
    api.addNotice("Live battle with " .. nameOf(live.with) .. "!")
  end

  function M.decline()
    if live.phase ~= "asked" then return end
    cancel("You declined " .. nameOf(live.with) .. "'s live battle.")
  end

  local function ask(id)
    local name = nameOf(id)
    if api.gameMessage then
      api.gameMessage(name .. " challenges you to a live battle! Battle " .. name .. " now?", { "Yes", "No" }, function(i)
        if live.phase == "asked" and live.with == id then
          if i == 1 then M.accept() else M.decline() end
        end
      end)
    else
      api.addNotice(name .. " challenges you to a live battle! Accept or Decline in the window.")
    end
  end

  -- The friend battle with their whole team and the live hooks armed (the core's battle, see startBattle)
  local function startLive()
    local f, party = api.friends[live.with], live.parties[live.with]
    for i, raw in ipairs(party) do api.iwBytes(api.ADDR.battleParty + (i - 1) * 0xDC, raw:sub(1, 0xDC)) end
    local name = f.name:sub(1, 12)
    for i = 1, #name do api.iw16(api.ADDR.battleName + (i - 1) * 2, name:byte(i)) end
    api.iw16(api.ADDR.battleName + #name * 2, 0xFFFF)
    wr(O.host, live.host and 1 or 0)
    wr(O.seed, live.seed)
    wr(O.partnerGone, 0)
    wr(O.inW, 0)
    wr(O.outR, 0)
    wr(O.pending, 1)
    api.iw32(api.SH + 0x70, f.model == api.OBJ_HEROINE and 363 or 360)
    api.iw32(api.SH + 0x74, #party)
    api.iw32(api.SH + 0x6C, 0)
    api.iw32(api.SH + 0x68, 1)
    api.battle.with = f.name
    local with = f.name
    api.battle.onEnd = function(alive)
      local d = rd(O.desync)
      api.addNotice((alive and "You beat " or "You lost to ") .. with .. "!" ..
        (d > 0 and " (the games went out of step)" or ""))
      reset()
    end
    live.phase, live.inbox, live.sentArmed, live.outSent = "battle", {}, false, 0
  end

  local function onParty(f, id, fr)
    if fr:byte(5) ~= PARTY_LIVE or fr:byte(6) ~= api.net.myId then return end
    local piece, count = fr:byte(7), fr:byte(8)
    if piece == 0 then live.chunks[id] = {} end
    local ch = live.chunks[id] or {}
    live.chunks[id] = ch
    ch[piece] = fr:sub(9, 48)
    if piece == count * 6 - 1 then
      local mons = {}
      for i = 0, count - 1 do
        local parts = {}
        for c = 0, 5 do parts[#parts + 1] = ch[i * 6 + c] or string.rep("\0", 40) end
        mons[#mons + 1] = table.concat(parts):sub(1, 0xDC)
      end
      live.parties[id], live.chunks[id] = mons, nil
    end
  end

  local function onLive(f, id, fr)
    local op, target = fr:byte(5), fr:byte(6)
    if target ~= api.net.myId then return end
    if op == OP.CHALLENGE then
      if live.phase or inBattle() then api.send(liveFrame(OP.CANCEL, id)) return end
      live.phase, live.with, live.seed = "asked", id, string.unpack("<I4", fr, 9)
      live.deadline = api.now() + TIMEOUT
      ask(id)
    elseif live.with ~= id then
      return
    elseif op == OP.ACCEPT then
      if live.phase == "challenging" then
        live.phase, live.deadline = "starting", api.now() + TIMEOUT
        api.addNotice(nameOf(id) .. " accepted your live battle!")
      end
    elseif op == OP.CANCEL then
      if live.phase == "battle" then
        wr(O.partnerGone, 1)
        api.addNotice(nameOf(id) .. " left the battle: their side plays on by itself.")
      elseif live.phase == "challenging" then
        reset()
        api.addNotice(nameOf(id) .. " declined your live battle.")
      elseif live.phase then
        reset()
        api.addNotice(nameOf(id) .. " called the live battle off.")
      end
    elseif op == OP.ACTION and live.phase == "battle" then
      local step, cmd, count, askBits = string.unpack("<H", fr, 7), fr:byte(9), fr:byte(10), fr:byte(11)
      local check = string.unpack("<I4", fr, 13)
      local words = {}
      local n = count == 0xFF and 0 or math.min(count, 5)
      for i = 0, n - 1 do words[#words + 1] = string.unpack("<I4", fr, 17 + i * 4) end
      table.insert(live.inbox, { step = step, cmd = cmd, count = count, ask = askBits, check = check, words = words })
    end
  end

  local function onLeave(f, id)
    if live.with ~= id then return end
    if live.phase == "battle" then
      wr(O.partnerGone, 1)
      api.addNotice(nameOf(id) .. " left: their side plays on by itself.")
    else
      reset()
      api.addNotice("Live battle off: your friend left.")
    end
  end

  -- During the battle: our answers out, theirs in (arm/live.c's queues)
  local function pump()
    if rd(O.armed) ~= 1 then return end
    live.sentArmed = true
    local outW = rd(O.outW)
    local outR = rd(O.outR)
    while outR ~= outW do
      local e = api.irBytes(L + O.outQ + (outR % QUEUE) * 0x20, 0x20)
      local step, cmd, count, check, askBits = string.unpack("<HBBI4B", e)
      local words = e:sub(13, 12 + math.min(count, 5) * 4)
      api.send(liveFrame(OP.ACTION, live.with, string.pack("<HBBBxI4", step, cmd, count, askBits, check) .. words))
      outR = (outR + 1) & 0xFFFFFFFF
      live.outSent = live.outSent + 1
    end
    wr(O.outR, outR)
    local inW = rd(O.inW)
    while #live.inbox > 0 and ((inW - rd(O.inR)) & 0xFFFFFFFF) < QUEUE do
      local a = table.remove(live.inbox, 1)
      local words = ""
      for _, w in ipairs(a.words) do words = words .. string.pack("<I4", w) end
      words = words .. string.rep("\0", 20 - #words)
      api.iwBytes(L + O.inQ + (inW % QUEUE) * 0x20, string.pack("<HBBI4Bxxx", a.step, a.cmd, a.count, a.check, a.ask) .. words)
      inW = (inW + 1) & 0xFFFFFFFF
      wr(O.inW, inW)
    end
    if not api.net.connected and rd(O.partnerGone) == 0 then wr(O.partnerGone, 1) end
  end

  local function tick()
    local t = api.now()
    if live.phase == "challenging" and t > live.deadline then
      cancel(nameOf(live.with) .. " didn't answer your live battle.")
    elseif live.phase == "asked" and t > live.deadline then
      cancel("You didn't answer " .. nameOf(live.with) .. "'s live battle.")
    elseif live.phase == "starting" then
      if not api.friends[live.with] then
        reset()
      elseif live.parties[live.with] and #live.parties[live.with] > 0 and api.me.ready then
        startLive()
      elseif t > live.deadline then
        cancel("The live battle didn't start: " .. nameOf(live.with) .. "'s team never arrived.")
      end
    elseif live.phase == "battle" then
      pump()
    end
  end

  -- "Waiting for Ann..." on the battle screen while their choice is on its way
  local function draw()
    if live.phase ~= "battle" or rd(O.armed) ~= 1 then return end
    local text
    if rd(O.fellBack) == 1 then
      text = nameOf(live.with) .. "'s side: the game plays it"
    elseif rd(O.waiting) == 1 and rd(O.inR) == rd(O.inW) and rd(O.steps01) & 0xFFFF > rd(O.steps01) >> 16 then
      text = "Waiting for " .. nameOf(live.with) .. "..."
    end
    if text then gui.drawText(128, 2, text, 0xFFFFFFFF, 0xA0000000, 9, nil, nil, "center", "top") end
  end

  local function selected()
    local s = api.form.friend and forms.gettext(api.form.friend) or ""
    return tonumber(s:match("#(%d+)$"))
  end

  local function buildForm(formId, y)
    forms.label(formId, "Live battle: you each pick your own moves", 8, y, 360, 18)
    forms.button(formId, "Live battle", function() M.challenge(selected()) end, 8, y + 20, 110, 28)
    forms.button(formId, "Accept", function() M.accept() end, 124, y + 20, 110, 28)
    forms.button(formId, "Decline", function() M.decline() end, 240, y + 20, 118, 28)
    return y + 56
  end

  -- Status for tests and the window
  function M.status()
    local hp = {}
    for i = 0, math.min(rd(O.hpCount), 12) - 1 do
      local v = rd(O.hp + i * 4)
      hp[#hp + 1] = string.format("%d:%d", v >> 16, v & 0xFFFF)
    end
    local s01 = rd(O.steps01)
    return { phase = live.phase, armed = rd(O.armed), patched = rd(O.patched), seeded = rd(O.seeded),
      fellBack = rd(O.fellBack), desync = rd(O.desync), step0 = s01 & 0xFFFF, step1 = s01 >> 16,
      steps = rd(O.steps), waiting = rd(O.waiting), check = rd(O.check), hp = table.concat(hp, " "),
      lastOurs = rd(O.lastOurs), lastTheirs = rd(O.lastTheirs), outSent = live.outSent }
  end

  table.insert(api.actions, { label = "Live battle", run = function(f, id) M.challenge(id) end })

  M.tick, M.draw, M.buildForm = tick, draw, buildForm
  M.onFrame = { [T.PARTY] = onParty, [T.LIVE] = onLive, [T.LEAVE] = onLeave }
  return M
end
