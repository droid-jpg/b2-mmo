-- Through a door and back with friends on the map: walk into the building north-east of the start
-- (x 632, z 168 -> zone 585), wait, walk back out, and check the friends are shown again.
-- B2PORT=7787 bash test/up.sh "--name Ann --x 584 --z 232 --path square --size 2 --speed 1 --model 231" \
--   "--name Bob --x 520 --z 216 --path line --size 3 --speed 1 --model 240 --plugin ride --ride surf"
-- bash test/run.sh test/t_door.lua 150
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local IT = "Instruction TCM"
local function it32(a) return memory.read_u32_le(a - 0x01FF8000, IT) end
local phase, at, zone0, lastTicks, stall = "wait", 0, nil, 0, 0
local regsLogged = false

local function friendsInfo(s)
  local t = {}
  for _, fr in pairs(s.friends) do
    local a = fr.slot and (0x01FFA080 + fr.slot * 0x30)
    t[#t + 1] = string.format("%s:%s", fr.name, a and string.format("slot%d spawned=%d actor=%08X", fr.slot, it32(a + 0x1C), it32(a + 0x20)) or "noslot")
  end
  return table.concat(t, " ")
end

-- CPU exceptions (the BIOS vectors): log where they came from
local exLogged = 0
for _, v in ipairs({ { 0xFFFF0004, "undef" }, { 0xFFFF000C, "prefetch abort" }, { 0xFFFF0010, "data abort" } }) do
  pcall(event.onmemoryexecute, function()
    if exLogged < 3 then
      exLogged = exLogged + 1
      local r = emu.getregisters()
      local t = {}
      for i = 0, 15 do t[#t + 1] = string.format("r%d=%08X", i, r["ARM9 r" .. i] or 0) end
      K.log("EXCEPTION " .. v[2] .. " " .. table.concat(t, " "))
    end
  end, v[1], "ex" .. v[1], "ARM9 System Bus")
end

K.start({ speed = 200 }, function(s, f)
  local ticks = it32(0x01FFA00C)
  if ticks == lastTicks then stall = stall + 1 else stall = 0 end
  lastTicks = ticks
  if f % 60 == 0 then K.log(string.format("f=%d %s zone=%d x=%.0f z=%.0f ready=%s ticks=%d spawns=%d rideC=%d rideD=%d %s", f, phase, s.me.zone, s.me.x, s.me.z, tostring(s.me.ready), ticks, it32(0x01FFA01C), it32(0x01FFF960), it32(0x01FFF964), friendsInfo(s))) end
  if stall > 300 and stall % 100 == 0 and stall < 600 then
    local r = emu.getregisters()
    if not regsLogged then
      local keys = {}
      for k in pairs(r) do keys[#keys + 1] = k end
      table.sort(keys)
      K.log("regs: " .. table.concat(keys, ","))
      regsLogged = true
    end
    local SB = "ARM9 System Bus"
    local g = memory.read_u32_le(0x021410F4, SB)
    local ev = memory.read_u32_le(g + 0x18, SB)
    local chain = {}
    while ev ~= 0 and #chain < 6 do
      chain[#chain + 1] = string.format("cb=%08X st=%d data=%08X", memory.read_u32_le(ev + 4, SB), memory.read_u32_le(ev + 8, SB), memory.read_u32_le(ev + 12, SB))
      ev = memory.read_u32_le(ev, SB)
    end
    K.log(string.format("field=%08X proc=%08X events: %s", memory.read_u32_le(g + 0x20, SB), memory.read_u32_le(g + 0x0C, SB), table.concat(chain, " <- ")))
    K.log(string.format("stall pc=%08X lr=%08X r0=%08X r1=%08X", r["ARM9 r15"] or -1, r["ARM9 r14"] or -1, r["ARM9 r0"] or -1, r["ARM9 r1"] or -1))
  end
  if stall == 600 then K.shot("stall"); K.log("STALLED"); client.exit() end

  if phase == "wait" and f == 300 then K.shot("1_outside"); phase, at, zone0 = "right", f, s.me.zone end
  if phase == "right" then
    K.press({ Right = true })
    if s.me.x >= 620 then phase, at = "up", f end
  elseif phase == "up" then
    K.press({ Up = true })
    if s.me.zone ~= zone0 and s.me.ready then phase, at = "inside", f; K.log("f=" .. f .. " inside zone " .. s.me.zone) end
    if f - at > 600 then K.log("no door"); client.exit() end
  elseif phase == "inside" then
    if f == at + 60 then K.shot("2_inside"); K.log("inside: " .. friendsInfo(s)) end
    if f > at + 90 then K.press({ Down = true }) end
    if s.me.zone == zone0 and s.me.ready and f > at + 90 then phase, at = "out", f; K.log("f=" .. f .. " back out") end
    if f - at > 900 then K.log("couldn't get out"); K.shot("stuck_inside"); client.exit() end
  elseif phase == "out" then
    if f < at + 20 then K.press({ Down = true }) end
    if f == at + 200 then K.shot("3_back_out"); K.log("back out: " .. friendsInfo(s)) end
    if f == at + 240 then K.shot("4_back_out"); K.log("PASS"); client.exit() end
  end
  if f > 8000 then K.log("timeout"); client.exit() end
end)
