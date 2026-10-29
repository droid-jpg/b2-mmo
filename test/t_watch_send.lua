-- Watching, sending side: battle a fake friend's team (a real trainer battle), press A to attack,
-- and check that our BATTLE frames follow the battle (the fake friend prints what it receives).
-- B2PORT=7783 bash test/up.sh "--name Ann --x 584 --z 184 --path stand --party E:/b2-mmo/scratch/slot2.bin --plugin watch --watch listen"
-- bash test/run.sh test/t_watch_send.lua 400; grep battle test/out/ff1.out
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local watch, annId, lastKey, inBattleSeen, overSeen, doneAt = nil, nil, nil, false, false, nil

local function procChain(s)
  local api = s.api
  local gsys = api.r32(0x021410F4)
  local pm = api.r32(gsys + 8)
  local p = api.r32(pm + 8)
  local t = {}
  for _ = 1, 4 do
    if not api.inRam(p) then break end
    t[#t + 1] = string.format("proc %08X funcs=%08X ov=%d state=%d work=%08X", p, api.r32(p), api.r32(p + 4), api.r32(p + 8), api.r32(p + 0x14))
    p = api.r32(p + 0x18)
  end
  return table.concat(t, " | ")
end

local function summary(b)
  if not b then return "none" end
  local t = {}
  for side = 0, 1 do
    local m = {}
    for _, x in ipairs(b[side]) do m[#m + 1] = string.format("%s L%d %d/%d st%d", s_species(x.species), x.level, x.hp, x.maxHp, x.status) end
    t[#t + 1] = "side" .. side .. ": " .. table.concat(m, ", ")
  end
  return table.concat(t, "  ")
end

K.start({}, function(s, f)
  s_species = s.api.speciesName
  if not watch then for _, ft in ipairs(s.features) do if ft.name == "watch" then watch = ft end end end
  if f == 120 then
    for id, fr in pairs(s.friends) do if fr.name == "Ann" then annId = id end end
    K.log("Ann #" .. tostring(annId) .. " party=" .. tostring(s.friends[annId] and s.friends[annId].party and #s.friends[annId].party))
    K.log("before: " .. procChain(s) .. " battle=" .. summary(watch.readBattle()))
  end
  if f == 150 then s.startBattle(annId) end
  if f > 150 then
    local b = watch.W.mine
    local key = summary(b)
    if key ~= lastKey then
      K.log(string.format("f%d %s frames=%d", f, key, watch.W.frames))
      lastKey = key
      if b then inBattleSeen = true end
      if not b and inBattleSeen then overSeen = true end
    end
    if f % 600 == 0 then K.log(string.format("f%d %s ready=%s", f, procChain(s), tostring(s.me.ready))) end
    -- Attack: A picks Fight and the first move, and goes through the messages
    if f > 600 and not overSeen and f % 16 < 4 then K.press({ A = true }) end
    if f == 900 or f == 1500 then K.shot("send_" .. f) end
    if overSeen and s.me.ready and not doneAt then doneAt = f end
    if (doneAt and f > doneAt + 120) or f > 9000 then
      K.log("over: frames sent " .. watch.W.frames .. ", sent=" .. tostring(watch.W.sent) .. ", ready=" .. tostring(s.me.ready))
      K.shot("send_after")
      local fh = io.open(K.env.out .. "ff1.out", "r")
      local ff = fh and fh:read("a") or ""
      if fh then fh:close() end
      local _, got = ff:gsub("[Bb]attle", "")
      K.check(inBattleSeen, "our battle read from its memory")
      K.check(overSeen and s.me.ready, "battle over, back on the field")
      K.check(watch.W.frames > 0, "BATTLE frames sent: " .. watch.W.frames)
      K.check(got > 0, "the friend received them: " .. got .. " lines")
      K.verdict()
      client.exit()
    end
  end
end)
