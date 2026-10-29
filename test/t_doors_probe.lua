-- Probe (dev aid): lists the loaded zone's warps (EventData from GameData), then walks into the
-- door at x 632 z 168 (Nimbasa City -> zone 585) and back out, logging where we are and how long
-- the field stopped asking for events around the map change.
-- bash test/run.sh test/t_doors_probe.lua 120
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local SB = "ARM9 System Bus"
local function r16(a) return memory.read_u16_le(a, SB) end
local function r32(a) return memory.read_u32_le(a, SB) end
local function dump(s)
  local gs = r32(0x021410F4)
  local gd = r32(gs + 0x1C)
  local ed = r32(gd + 0x158) -- GameData_GetEventData (0x02017240): movs r1,#0x56; lsls r1,#2; ldr r0,[r0,r1]
  K.log(string.format("EventData %08X zone=%d warps=%d", ed, r16(ed + 0x10), r16(ed + 0x16)))
  local w = r32(ed + 0x24)
  for i = 0, r16(ed + 0x16) - 1 do
    local a = w + i * 20
    K.log(string.format("warp %d: zone=%d idx=%d tt=%d rail=%d x=%d y=%d z=%d w=%d h=%d", i, r16(a), r16(a + 2),
      memory.read_u8(a + 5, SB), r16(a + 6), r16(a + 8), r16(a + 10), r16(a + 12), r16(a + 14), r16(a + 16)))
  end
  K.log(string.format("me zone=%d x=%.1f y=%.1f z=%.1f matrix=%d", s.me.zone, s.me.x, s.me.y, s.me.z, s.me.matrix))
end
local phase, lastZone = (os.getenv("PROBE") or "right"), nil
local _p, _l, maxStale, inAt = "right", nil, 0, nil
K.start({}, function(s, f)
  local me = s.me
  if f == 60 then dump(s) end
  if f < 60 then return end
  maxStale = math.max(maxStale, me.staleFrames)
  if lastZone and me.zone ~= lastZone then
    K.log(string.format("f=%d ZONE %d -> %d at x=%.1f z=%.1f (stale max %d, noWarp %s)", f, lastZone, me.zone, me.x, me.z,
      maxStale, tostring(s.api.now() < me.noWarpUntil)))
    dump(s)
    if phase == "up" then phase, inAt = "inside", f end
  end
  if me.staleFrames == 0 then maxStale = 0 end
  lastZone = me.zone
  if f % 20 == 0 and phase ~= "up" or f % 4 == 0 and phase == "up" then K.log(string.format("f=%d %s zone=%d x=%.1f z=%.1f stale=%d ready=%s", f, phase, me.zone, me.x, me.z, me.staleFrames, tostring(me.ready))) end
  if phase == "west" then
    K.press({ Left = true })
    if me.zone ~= 64 then phase = "westin"; inAt = f end
  elseif phase == "westin" then
    if f == inAt + 30 then K.shot("west") end
    if f > inAt + 40 then client.exit() end
  elseif phase == "right" then
    if me.x < 617 then K.press({ Right = true }) elseif me.x == 632 then phase = "up" end
  elseif phase == "up" then
    K.press({ Up = true })
  elseif phase == "inside" then
    if f == inAt + 40 then K.shot("inside") end
    if f == inAt + 100 or f == inAt + 30 then
      -- The running game event chain (GameSystem+0x18: parent, callback, state, data)
      local regs = emu.getregisters()
      local pcs = {}
      for k, v in pairs(regs) do if k:find("15") or k:find("PC") or k:find("14") then pcs[#pcs + 1] = k .. "=" .. string.format("%08X", v) end end
      table.sort(pcs)
      K.log("regs: " .. table.concat(pcs, " "))
      local ev = r32(r32(0x021410F4) + 0x18)
      while ev ~= 0 and ev >= 0x02000000 and ev < 0x02400000 do
        K.log(string.format("event %08X cb=%08X state=%d data=%08X", ev, r32(ev + 4), r32(ev + 8), r32(ev + 12)))
        ev = r32(ev)
      end
      for i = 0, 7 do
        local a = 0x01FFA080 + i * 0x30
        local t = {}
        for k = 0, 11 do t[#t + 1] = string.format("%08X", memory.read_u32_le(a + k * 4 - 0x01FF8000, "Instruction TCM")) end
        K.log("slot " .. i .. ": " .. table.concat(t, " "))
      end
    end
    if f > inAt + 60 then K.press({ Down = true }) end
    if me.zone == 64 and f > inAt + 60 then phase = "out"; inAt = f end
  elseif phase == "out" then
    if f == inAt + 60 then K.shot("out") end
    if f > inAt + 80 then client.exit() end
  end
  if f > 3000 then client.exit() end
end)
