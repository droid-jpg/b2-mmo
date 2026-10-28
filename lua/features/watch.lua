-- Black 2 MMO feature: watching a friend's battle (BATTLE frames, type 11).
--
-- Sending: while our game is in a battle (wild, trainer, a friend's team), both sides' Pokemon are
-- read from the battle's own memory every frame and sent as BATTLE frames on every change and
-- every 2 s; a frame with count 0 says the battle is over. The ARM code doesn't run in battles
-- (the field's event provider is down), so this is all Lua reading RAM:
--   g_GameSystem (*0x021410F4) +0x08 GameProcManager -> +0x08 the running GameProc (walk ->parent)
--   GameProc: +0x00 functions (== 0x021D6CE0, the battle's BtlMain proc table in ov167),
--             +0x08 state (2 = main), +0x14 work = BtlMainModule
--   BtlMainModule +0x46C playerClientId, +0xC8 pokeCons[0] (the clients' view, as on screen):
--     BtlPokeCon +0x04 + client * 0x1C: BattleParty { BattleMon *mons[6]; u8 count } (slot 0 = out)
--   BattleMon +0x0C species, +0x0E max HP, +0x10 HP, +0x18 level, +0x1C conditions[]
--     (conditions 1..5: paralysis, sleep, freeze, burn, poison when bits 0..2 are non-zero)
--
-- Receiving: each friend's latest battle is kept while their busy bit is set and frames keep
-- coming. Talking to a friend in a battle says what each side has out (a notice, and an
-- api.talkInfo line for the in-game talk box), and until their battle ends, you walk away or
-- press B, the bottom screen shows both teams with HP bars.
return function(api)
  local T = api.T
  local G_GAMESYSTEM = 0x021410F4
  local BTL_PROC_FUNCS = 0x021D6CE0
  local PROC_STATE_MAIN = 2
  local MM_POKECON0, MM_PLAYER_CLIENT = 0xC8, 0x46C
  local BP_SPECIES, BP_MAXHP, BP_HP, BP_LEVEL, BP_COND = 0x0C, 0x0E, 0x10, 0x18, 0x1C
  local FRESH_MS = 6000

  local W = { sent = nil, sentAt = 0, frames = 0, watching = nil, prevB = false, mine = nil }

  ----------------------------------------------------------------------------------------------
  -- Our battle, read from RAM
  ----------------------------------------------------------------------------------------------
  local function findBattleModule()
    local gsys = api.r32(G_GAMESYSTEM)
    if not api.inRam(gsys) then return nil end
    local pm = api.r32(gsys + 0x08)
    if not api.inRam(pm) then return nil end
    local proc = api.r32(pm + 0x08)
    for _ = 1, 4 do
      if not api.inRam(proc) then return nil end
      if api.r32(proc) == BTL_PROC_FUNCS then
        if api.r32(proc + 0x08) ~= PROC_STATE_MAIN then return nil end
        local mm = api.r32(proc + 0x14)
        if api.inRam(mm) and api.inRam(api.r32(mm)) then return mm end
        return nil
      end
      proc = api.r32(proc + 0x18)
    end
    return nil
  end

  local function readMon(bp)
    local species = memory.read_u16_le(bp + BP_SPECIES, api.SB)
    local maxHp = memory.read_u16_le(bp + BP_MAXHP, api.SB)
    local hp = memory.read_u16_le(bp + BP_HP, api.SB)
    local level = api.r8(bp + BP_LEVEL)
    if species == 0 or species > 721 or maxHp == 0 or hp > maxHp or level == 0 or level > 100 then return nil end
    local status = 0
    for i = 1, 5 do
      if api.r32(bp + BP_COND + i * 4) & 7 ~= 0 then status = i; break end
    end
    return { species = species, hp = hp, maxHp = maxHp, level = level, status = status }
  end

  -- { [0] = our side's Pokemon, [1] = the opponent's }, entry 1 the one out; nil if not in a battle
  local function readBattle()
    local mm = findBattleModule()
    if not mm then return nil end
    local me = api.r8(mm + MM_PLAYER_CLIENT)
    if me > 1 then me = 0 end
    local out = {}
    for side = 0, 1 do
      local client = side == 0 and me or (1 - me)
      local party = mm + MM_POKECON0 + 4 + client * 0x1C
      local count = api.r8(party + 0x18)
      if count == 0 or count > 6 then return nil end
      local mons = {}
      for i = 0, count - 1 do
        local bp = api.r32(party + i * 4)
        if not api.inRam(bp) then return nil end
        local m = readMon(bp)
        if not m then return nil end -- not the layout we know (or being freed): send nothing
        mons[#mons + 1] = m
      end
      out[side] = mons
    end
    return out
  end

  local function battleKey(b)
    if not b then return "" end
    local t = {}
    for side = 0, 1 do
      for _, m in ipairs(b[side]) do t[#t + 1] = string.format("%d:%d/%d:%d:%d", m.species, m.hp, m.maxHp, m.level, m.status) end
      t[#t + 1] = "|"
    end
    return table.concat(t, ",")
  end

  local function sendBattle(b)
    for side = 0, 1 do
      local mons = b[side]
      local p = string.pack("<BB", side, #mons)
      for _, m in ipairs(mons) do p = p .. string.pack("<HHHB", m.species, m.hp, m.maxHp, m.level) end
      api.send(api.frame(T.BATTLE, p))
    end
    W.frames = W.frames + 2
  end

  local function tickSend()
    local b = readBattle()
    W.mine = b
    if not (api.net.connected and api.net.myId ~= 0) then return end
    if b then
      local key = battleKey(b)
      if key ~= W.sent or api.now() - W.sentAt >= 2000 then
        sendBattle(b)
        W.sent, W.sentAt = key, api.now()
      end
    elseif W.sent then
      api.send(api.frame(T.BATTLE, string.pack("<BB", 0, 0))) -- count 0: over
      W.frames = W.frames + 1
      W.sent = nil
    end
  end

  ----------------------------------------------------------------------------------------------
  -- Friends' battles
  ----------------------------------------------------------------------------------------------
  local function onBattle(f, id, fr)
    if not f then return end
    local side, count = fr:byte(5), fr:byte(6)
    if side > 1 or count > 6 then return end
    if count == 0 then f.watch = nil; return end
    f.watch = f.watch or { sides = {} }
    local mons = {}
    for i = 0, count - 1 do
      local sp, hp, maxHp, lv = string.unpack("<HHHB", fr, 7 + i * 7)
      mons[#mons + 1] = { species = sp, hp = hp, maxHp = maxHp, level = lv }
    end
    f.watch.sides[side] = mons
    f.watch.time = api.now()
  end

  local function inBattle(f)
    local w = f and f.watch
    return w and w.sides[0] and w.sides[1] and api.now() - w.time < FRESH_MS and (f.status & 1) == 1
  end

  local function monShort(m) return string.format("%s %d/%d", api.speciesName(m.species), m.hp, m.maxHp) end

  local function battleLine(f)
    if not inBattle(f) then return nil end
    return f.name .. " is battling: " .. monShort(f.watch.sides[0][1]) .. " vs " .. monShort(f.watch.sides[1][1])
  end
  table.insert(api.talkInfo, function(f, id) return battleLine(f) end)

  local function onTalk(f, id)
    local line = battleLine(f)
    if line then
      -- The notice box fits about 46 characters: leave the HP to the bottom screen if it's too long
      if #line > 46 then
        line = f.name .. " is battling: " .. api.speciesName(f.watch.sides[0][1].species) .. " vs " ..
          api.speciesName(f.watch.sides[1][1].species)
      end
      api.addNotice(line)
      W.watching = id
    end
    return false -- the core still says their greeting
  end

  local function tickWatch()
    for _, f in pairs(api.friends) do
      if f.watch and not inBattle(f) and ((f.status & 1) == 0 or api.now() - f.watch.time >= FRESH_MS) then f.watch = nil end
    end
    local b = joypad.get()["B"] == true
    local pressedB = b and not W.prevB
    W.prevB = b
    local id = W.watching
    if not id then return end
    local f = api.friends[id]
    if not f or not inBattle(f) or pressedB then W.watching = nil; return end
    -- Walked away: more than 3 tiles from them (or they're off our map)
    if not f.drawX or math.abs(f.drawX - api.me.x) > 48 or math.abs(f.drawZ - api.me.z) > 48 then W.watching = nil end
  end

  ----------------------------------------------------------------------------------------------
  -- Drawing (bottom screen: y 192..383)
  ----------------------------------------------------------------------------------------------
  local function hpColor(hp, max)
    local r = hp / math.max(1, max)
    if r > 0.5 then return 0xFF40D060 elseif r > 0.2 then return 0xFFF0C030 else return 0xFFE04040 end
  end

  local function drawTeam(x, y, title, mons)
    gui.drawText(x, y, title, 0xFFFFE080, 0x00000000, 10)
    y = y + 14
    for i, m in ipairs(mons) do
      local fainted = m.hp == 0
      local name = string.format("%s Lv%d", api.speciesName(m.species), m.level)
      gui.drawText(x, y, (i == 1 and "> " or "  ") .. name, fainted and 0xFF808080 or 0xFFFFFFFF, 0x00000000, 9)
      local bw = 70
      gui.drawBox(x + 8, y + 12, x + 8 + bw, y + 16, 0xFF101010, 0xFF404040)
      local w = math.floor(bw * m.hp / math.max(1, m.maxHp) + 0.5)
      if w > 0 then gui.drawBox(x + 8, y + 12, x + 8 + w, y + 16, hpColor(m.hp, m.maxHp), hpColor(m.hp, m.maxHp)) end
      gui.drawText(x + 82, y + 8, fainted and "fainted" or string.format("%d/%d", m.hp, m.maxHp), 0xFFD0D0D0, 0x00000000, 8)
      y = y + 22
    end
  end

  local function drawPanel()
    local f = W.watching and api.friends[W.watching]
    if not f or not inBattle(f) then return end
    if input.get()["Tab"] then return end
    gui.drawBox(2, 194, 253, 368, 0xFF586068, 0xE8202830)
    gui.drawText(8, 197, f.name .. "'s battle", 0xFFFFFFFF, 0x00000000, 11)
    gui.drawText(248, 199, "B: stop watching", 0xFFA0A0A0, 0x00000000, 8, nil, nil, "right")
    drawTeam(8, 216, f.name, f.watch.sides[0])
    drawTeam(132, 216, "Opponent", f.watch.sides[1])
  end

  -- The Tab player list (drawn by the core in pairs() order, one line each from y 198): mark who's battling
  local function drawListMarks()
    if not input.get()["Tab"] then return end
    local i = 1
    for _, f in pairs(api.friends) do
      i = i + 1
      if inBattle(f) then
        gui.drawText(247, 186 + i * 12, "(in a battle)", 0xFFFFC060, 0xE0202830, 10, nil, nil, "right")
      end
    end
  end

  return {
    W = W, readBattle = readBattle, inBattle = inBattle, battleLine = battleLine,
    tick = function() tickSend(); tickWatch() end,
    draw = function() drawPanel(); drawListMarks() end,
    onFrame = { [T.BATTLE] = onBattle },
    onTalk = onTalk,
  }
end
