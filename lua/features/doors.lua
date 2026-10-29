-- Black 2 MMO feature: doors. "Ann is inside" on the door that leads to a friend, and where friends went.
--
-- Every map change seen (ours, and every friend's on any map) teaches a warp: zone A at the spot
-- the mover last stood leads to zone B, and B at the spot they arrived leads back to A. The game's
-- own warp list of each zone we're in (read by the core into me.zoneWarps) is learned too. A friend
-- on another map then gets a steady label on the door or map edge of our map that leads toward
-- them, up to 4 doors deep: "Ann is inside" (a building of this place, or the building right
-- through that door) or "Cal, Dee are in Route 4". Fly, Teleport, Dig, Escape Rope, whiteouts and
-- cutscene warps aren't warps: the mover flags them (STATE status bit 3) and they teach nothing.
-- When a friend leaves our map a fading "Ann → Pokémon Center" note stays where they left from.
-- Warps are kept in lua/b2mmo-warps.txt, so doors are labelled from the start next time.
return function(api)
  local me, friends, cfg, T = api.me, api.friends, api.cfg, api.T
  local DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"):gsub("features[/\\]$", "")
  local FILE = cfg.warpsFile or (DIR .. "b2mmo-warps.txt")
  local MAX_WARPS, SAME, DEPTH = 256, 40, 4      -- 40 units = 2.5 tiles: one door
  local NOTE_MS, STALE_MS = 3000, 10000
  local SHARED = { [0] = true, [175] = true }     -- overworld matrices: their zones share coordinates

  local M = { warps = {}, notes = {}, labels = {}, learned = 0 }
  local warps, notes = M.warps, M.notes
  local zoneMatrix = {}   -- zone -> map matrix, as seen in STATE frames and our own game
  local clock, dirty, savedAt = 0, false, 0
  local last = {}         -- friend id -> their last STATE { zone, matrix, x, y, z, status }
  local mine = nil        -- our last field spot { zone, matrix, x, y, z }
  local gameWarpsOf = nil -- the zone whose game warp list we learned last

  -- A graph node: one zone, or a whole overworld matrix (its zones join without warps)
  local function node(zone)
    local m = zoneMatrix[zone]
    if m and SHARED[m] then return "m" .. m end
    return zone
  end

  local function learn(from, to, x, y, z)
    if from == to or x ~= x or z ~= z then return end
    clock = clock + 1
    for _, w in ipairs(warps) do
      if w.from == from and w.to == to and math.abs(w.x - x) < SAME and math.abs(w.z - z) < SAME then
        w.used = clock
        return w
      end
    end
    local w = { from = from, to = to, x = x, y = y, z = z, used = clock }
    if #warps >= MAX_WARPS then
      local old = 1
      for i, o in ipairs(warps) do if o.used < warps[old].used then old = i end end
      table.remove(warps, old)
    end
    warps[#warps + 1] = w
    M.learned = M.learned + 1
    dirty = true
    return w
  end

  -- A map change seen: zone a at (ax, ay, az) -> zone b arriving at (bx, by, bz)
  local function learnBoth(a, am, ax, ay, az, b, bm, bx, by, bz)
    if am == bm and SHARED[am] then return end -- across a route boundary: not a door
    learn(a, b, ax, ay, az)
    learn(b, a, bx, by, bz)
  end

  local function noteMatrix(zone, matrix)
    if zone and matrix and zoneMatrix[zone] ~= matrix then zoneMatrix[zone] = matrix; dirty = true end
  end

  ------------------------------------------------------------------------------------------
  -- The file: "w from to x y z" and "m zone matrix" lines
  ------------------------------------------------------------------------------------------
  local function load()
    local fh = io.open(FILE, "r")
    if not fh then return end
    for line in fh:lines() do
      local a, b, x, y, z = line:match("^w (%d+) (%d+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
      if a then
        learn(tonumber(a), tonumber(b), tonumber(x), tonumber(y), tonumber(z))
      else
        local zn, m = line:match("^m (%d+) (%d+)")
        if zn then zoneMatrix[tonumber(zn)] = tonumber(m) end
      end
    end
    fh:close()
    M.learned, dirty = 0, false
  end

  local function save()
    local fh = io.open(FILE, "w")
    if not fh then return end
    fh:write("# Black 2 MMO: doors and map edges seen (w from to x y z), zone map matrices (m zone matrix)\n")
    table.sort(warps, function(p, q) return p.used < q.used end)
    for _, w in ipairs(warps) do fh:write(string.format("w %d %d %g %.1f %g\n", w.from, w.to, w.x, w.y, w.z)) end
    local zs = {}
    for zn in pairs(zoneMatrix) do zs[#zs + 1] = zn end
    table.sort(zs)
    for _, zn in ipairs(zs) do fh:write(string.format("m %d %d\n", zn, zoneMatrix[zn])) end
    fh:close()
    dirty = false
  end
  load()

  ------------------------------------------------------------------------------------------
  -- Finding the door toward a zone
  ------------------------------------------------------------------------------------------
  -- The warp from our map that leads toward `target` in the fewest doors (the most recently seen
  -- on a tie), or nil.
  local function warpToward(from, target)
    local goal = node(target)
    local start = node(from)
    if start == goal then return nil end
    local frontier, seen = { { n = start, hop = nil } }, { [start] = true }
    for _ = 1, DEPTH do
      local nextF, best = {}, nil
      for _, it in ipairs(frontier) do
        for _, w in ipairs(warps) do
          if node(w.from) == it.n then
            local hop = it.hop or w
            local to = node(w.to)
            if to == goal then
              if not best or hop.used > best.used then best = hop end
            elseif not seen[to] then
              seen[to] = true
              nextF[#nextF + 1] = { n = to, hop = hop }
            end
          end
        end
      end
      if best then return best end
      if #nextF == 0 then return nil end
      frontier = nextF
    end
    return nil
  end

  local function place(zone) return api.zoneName(zone) end

  -- Inside: a building of our place ("Nimbasa City Pokémon Center" from "Nimbasa City"), or the
  -- building right through the door. Not another outdoor part of the same town.
  local function isInside(zone, matrix, door)
    if SHARED[matrix] or matrix == me.matrix then return false end
    if door.to == zone then return true end
    local here, there = place(me.zone), place(zone)
    return there:sub(1, #here) == here
  end

  -- Where to draw a door's label: the game's own warp tile when it is that door (the learned spot
  -- is the tile in front of it), else the learned spot
  local function spotOf(w)
    if w.from == me.zone then
      for _, g in ipairs(me.zoneWarps or {}) do
        local cx, cz = g.x + (g.w - 1) * 8, g.z + (g.h - 1) * 8
        if g.to == w.to and math.abs(cx - w.x) <= 48 and math.abs(cz - w.z) <= 48 then return cx, g.y, cz end
      end
    end
    return w.x, w.y, w.z
  end

  local function onMyMap(zone, matrix)
    return zone == me.zone or (matrix == me.matrix and SHARED[matrix] == true)
  end

  ------------------------------------------------------------------------------------------
  -- Hooks
  ------------------------------------------------------------------------------------------
  M.onFrame = {
    [T.STATE] = function(f, id, fr)
      local zone, _, x, y, z, matrix, _, _, _, _, status = string.unpack("<HHfffIIffBBHI", fr, 5)
      noteMatrix(zone, matrix)
      local l = last[id]
      if l and l.zone ~= zone then
        if l.status & 8 == 0 and status & 8 == 0 then
          learnBoth(l.zone, l.matrix, l.x, l.y, l.z, zone, matrix, x, y, z)
        end
        -- Left our map: a note where they stood
        if me.ready and onMyMap(l.zone, l.matrix) and not onMyMap(zone, matrix) then
          -- "Ann → Pokémon Center" (our town's name left out), "Ann → inside", "Ann → Route 4"
          local here, there = place(me.zone), place(zone)
          local where = there
          if #there > #here + 1 and there:sub(1, #here + 1) == here .. " " then where = there:sub(#here + 2)
          elseif there == here and not SHARED[matrix] and matrix ~= me.matrix then where = "inside" end
          notes[id] = { text = (f and f.name or ("#" .. id)) .. " → " .. where, x = l.x, y = l.y, z = l.z,
            zone = me.zone, start = api.now() }
        end
      end
      last[id] = { zone = zone, matrix = matrix, x = x, y = y, z = z, status = status }
    end,
    [T.LEAVE] = function(_, id) last[id] = nil; notes[id] = nil end,
  }

  function M.tick()
    if me.ready then
      noteMatrix(me.zone, me.matrix)
      if mine and mine.zone ~= me.zone and api.now() >= me.noWarpUntil then
        learnBoth(mine.zone, mine.matrix, mine.x, mine.y, mine.z, me.zone, me.matrix, me.x, me.y, me.z)
      end
      mine = { zone = me.zone, matrix = me.matrix, x = me.x, y = me.y, z = me.z }
      -- The game's own warps of this zone (spots are the warp tiles' centres)
      if me.zoneWarps and gameWarpsOf ~= me.zone and cfg.doorsGameWarps ~= "0" then
        gameWarpsOf = me.zone
        for _, g in ipairs(me.zoneWarps) do
          learn(me.zone, g.to, g.x + (g.w - 1) * 8, g.y, g.z + (g.h - 1) * 8)
        end
      end
    end
    if dirty and api.now() - savedAt > 2000 then savedAt = api.now(); save() end
  end

  local function drawBox(text, sx, sy, fg, bg)
    gui.drawText(sx, sy, text, fg, bg, 9, nil, nil, "center", "bottom")
  end

  function M.draw()
    M.labels = {}
    if cfg.labels == "0" or not me.ready then return end
    local t = api.now()
    -- Leaving notes: drift up and fade
    for id, n in pairs(notes) do
      local age = t - n.start
      if age > NOTE_MS then
        notes[id] = nil
      elseif n.zone == me.zone then
        local sx, sy = api.project(n.x, n.y, n.z)
        local k = 1 - age / NOTE_MS
        local a = math.floor(255 * k)
        drawBox(n.text, sx, sy - 8 - age / 150, (a << 24) | 0xFFFFFF, (math.floor(0xC0 * k) << 24) | 0x182030)
      end
    end
    -- Friends behind doors, grouped by door
    local byDoor, order = {}, {}
    for id, f in pairs(friends) do
      local l = last[id]
      if l and not f.drawX and not onMyMap(l.zone, l.matrix) and t - (f.lastSeen or 0) < STALE_MS and not notes[id] then
        local w = warpToward(me.zone, l.zone)
        if w then
          if not byDoor[w] then byDoor[w] = {}; order[#order + 1] = w end
          table.insert(byDoor[w], { name = f.name, zone = l.zone, matrix = l.matrix })
        end
      end
    end
    for _, w in ipairs(order) do
      local list = byDoor[w]
      table.sort(list, function(p, q) return p.name < q.name end)
      local names, inside = {}, true
      for _, e in ipairs(list) do
        names[#names + 1] = e.name
        if not isInside(e.zone, e.matrix, w) then inside = false end
      end
      local text = table.concat(names, ", ") .. (#list > 1 and " are " or " is ") ..
        (inside and "inside" or ("in " .. place(list[1].zone)))
      local x, y, z = spotOf(w)
      local sx, sy = api.project(x, y, z)
      local lb = { text = text, x = x, z = z, sx = sx, sy = sy, onScreen = sx >= 0 and sx <= 255 and sy >= 10 and sy <= 191 }
      M.labels[#M.labels + 1] = lb
      if lb.onScreen then
        drawBox(text, sx, sy, 0xFFFFE890, 0xB0182030)
      else
        -- Off screen: at the edge, with an arrow toward it
        local arrow = sy < 10 and "↑ " or sy > 191 and "↓ " or sx < 0 and "← " or "→ "
        local cx, cy = math.max(4, math.min(252, sx)), math.max(18, math.min(184, sy))
        gui.drawText(cx, cy, arrow .. text, 0xFFFFE890, 0xB0182030, 9, nil, nil,
          sx < 0 and "left" or sx > 255 and "right" or "center", "middle")
      end
    end
  end

  M.warpToward = warpToward
  M.save = save
  return M
end
