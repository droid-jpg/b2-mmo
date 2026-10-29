-- Doors: "Ann is inside" on the door that leads to a friend, warps learned from map changes.
-- The mode comes from the DOORS environment variable (each needs its own fake friend):
--   self    we walk into the house at x 632 (zone 64 -> 585) and back out: both ways learned,
--           not flagged "no warp", saved to the file          (bash test/up.sh "--name Bot --matrix 107 --path stand --x 520 --z 200": a friend
--           on our map while we walk through the door)
--   reload  (after self) the saved warps are there from the start
--   friend  Ann walks into the house: learned, a fading "Ann → inside" note, then "Ann is inside"
--           on the door                                       (up.sh "--name Ann --plugin doors --matrix 107 --path stand --x 600 --z 200 --stay -1")
--   nowarp  the same hop flagged as Fly: nothing learned, no label (add --nowarp)
--   town    Ann leaves by the west edge to the main Nimbasa City (zone 62) and goes into the Musical
--           Theater: "← Ann is in Musical Theater" at the screen edge (the west edge is off screen)
--           (up.sh "--name Ann --plugin doors --matrix 107 --path stand --x 200 --z 200 --stay -1 --route 168,200>62,0,6968,16,7384;6936,6952>77,380,232,0,400")
-- DOORS=friend bash test/run.sh test/t_doors.lua 200
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local mode = os.getenv("DOORS") or "friend"
local file = K.env.out .. "warps_" .. (mode == "reload" and "self" or mode) .. ".txt"
if mode ~= "reload" then os.remove(file) end

local function doorsOf(s)
  for _, ft in ipairs(s.features) do if ft.name == "doors" then return ft end end
end
local function has(d, from, to, x, z)
  for _, w in ipairs(d.warps) do
    if w.from == from and w.to == to and (not x or (math.abs(w.x - x) <= 8 and math.abs(w.z - z) <= 8)) then return w end
  end
end
local function dumpWarps(d)
  K.log("  map changes seen: " .. table.concat(d.seen, ", "))
  for _, w in ipairs(d.warps) do K.log(string.format("  warp %d -> %d at %.0f,%.0f,%.0f", w.from, w.to, w.x, w.y, w.z)) end
end
local pass = true
local function check(ok, what) K.log((ok and "PASS " or "FAIL ") .. what); if not ok then pass = false end end
local function finish() K.log(pass and "ALL PASS" or "SOME FAILED"); client.exit() end

local phase, at, sawNote, labelAt = "go", 0, false, nil
K.start({ doorsGameWarps = "0", warpsFile = file }, function(s, f)
  local me, d = s.me, doorsOf(s)
  if mode == "reload" then
    if f == 30 then
      check(has(d, 64, 585, 632, 184) ~= nil, "64 -> 585 loaded from the file")
      check(has(d, 585, 64, 232, 728) ~= nil, "585 -> 64 loaded from the file")
      dumpWarps(d)
      finish()
    end
    return
  end

  if mode == "self" then
    if phase == "go" then
      if me.x < 617 then K.press({ Right = true }) elseif me.x == 632 then phase = "up" end
    elseif phase == "up" then
      if me.zone ~= 585 then K.press({ Up = true }) end
      if me.zone == 585 and me.ready then
        phase, at = "in", f
        check(s.api.now() >= me.noWarpUntil, "our door walk is not flagged no-warp")
        check(has(d, 64, 585, 632, 184) ~= nil, "our trip taught 64 -> 585 at 632,184")
        check(has(d, 585, 64, 232, 728) ~= nil, "our trip taught 585 -> 64 at 232,728")
      end
    elseif phase == "in" then
      if f > at + 60 then K.press({ Down = true }) end
      if f == at + 150 then K.shot("stuck") end
      if f % 30 == 0 then K.log(string.format("in: f=%d zone=%d x=%.0f z=%.0f ready=%s stale=%d", f, me.zone, me.x, me.z, tostring(me.ready), me.staleFrames)) end
      if me.zone == 64 and me.ready then
        phase, at = "out", f
        check(s.api.now() >= me.noWarpUntil, "walking out is not flagged no-warp")
      end
    elseif phase == "out" then
      if f == at + 200 then
        local fh = io.open(file, "r")
        local text = fh and fh:read("a") or ""
        if fh then fh:close() end
        K.log(text)
        check(text:find("w 64 585 632 16.0 184", 1, true) ~= nil and text:find("w 585 64 232 32.0 728", 1, true) ~= nil, "saved to the file")
        dumpWarps(d)
        finish()
      end
    end
    if f > 3000 then check(false, "timed out in " .. phase); finish() end
    return
  end

  -- Friend modes: watch Ann
  for id, n in pairs(d.notes) do
    if not sawNote and s.api.now() - n.start > 400 then
      sawNote = true
      K.log("note: " .. n.text .. string.format(" at %.0f,%.0f", n.x, n.z))
      K.shot("note")
    end
  end
  local lb = d.labels[1]
  if lb and not labelAt and (mode ~= "town" or lb.text:find("Theater")) then labelAt = f; K.log(string.format("label: %s at %.0f,%.0f screen %.0f,%.0f%s", lb.text, lb.x, lb.z, lb.sx, lb.sy, lb.onScreen and "" or " (off screen)")) end
  if mode == "friend" and labelAt and f == labelAt + 60 then
    K.shot("label")
    check(has(d, 64, 585) ~= nil and has(d, 585, 64, 232, 728) ~= nil, "Ann's walk taught 64 -> 585 and 585 -> 64")
    check(sawNote, "a leaving note was shown")
    check(lb.text == "Ann is inside" and lb.onScreen, "\"Ann is inside\" on screen")
    check(math.abs(lb.x - 632) <= 8 and math.abs(lb.z - 168) <= 8, "the label is on the door tile (the game's warp at 632,168)")
    dumpWarps(d)
    finish()
  elseif mode == "town" and labelAt and f == labelAt + 60 then
    K.shot("town")
    check(lb.text == "Ann is in Musical Theater", "\"Ann is in Musical Theater\"")
    check(math.abs(lb.x - 152) <= 8 and math.abs(lb.z - 224) <= 8, "on the west edge (the game's warp at x 152, z 200..248)")
    dumpWarps(d)
    finish()
  elseif mode == "nowarp" and f == 2400 then
    K.shot("nowarp")
    local fr
    for _, x in pairs(s.friends) do fr = x end
    check(fr ~= nil and fr.zone == 585, "Ann is in the house (zone " .. tostring(fr and fr.zone) .. ")")
    check(#d.warps == 0, "nothing learned (" .. #d.warps .. " warps)")
    check(labelAt == nil, "no label")
    finish()
  end
  if f > 4000 then check(false, "timed out (label " .. tostring(labelAt) .. ")"); dumpWarps(d); finish() end
end)
