-- Friends biking and surfing: a fake friend walks a square switching walk -> bike -> surf -> walk;
-- we log their model/status and the ride block, and take screenshots in each form. Then we get on
-- our own bike (Y) to see what our STATE sends.
-- B2PORT=7787 bash test/up.sh "--name Ann --x 584 --z 184 --path square --size 3 --speed 2 --model 231 --plugin ride --ride bike:6,surf:6,walk:5"
-- bash test/run.sh test/t_ride.lua 200
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local IT = "Instruction TCM"
local function it32(a) return memory.read_u32_le(a - 0x01FF8000, IT) end
local RIDE = 0x01FFF900
local lastModel, changedAt, shots, nshot = nil, 0, 0, 0
local yAt = nil

local function rideInfo()
  local t = {}
  for i = 0, 1 do t[#t + 1] = string.format("s%d surf=%d task=%08X actor=%08X", i, it32(RIDE + i * 4), it32(RIDE + 0x20 + i * 4), it32(RIDE + 0x40 + i * 4)) end
  return table.concat(t, " ") .. string.format(" created=%d deleted=%d", it32(RIDE + 0x60), it32(RIDE + 0x64))
end

local seen = { bike = false, surf = false, surfOff = false }
K.start({ speed = 200 }, function(s, f)
  local fr
  for _, x in pairs(s.friends) do fr = x end
  if fr and fr.slot then
    local a = 0x01FFA080 + fr.slot * 0x30
    local spawned, shown = it32(a + 0x1C) == 1, it32(a + 0x24)
    local task = it32(RIDE + 0x20 + fr.slot * 4)
    if spawned and (fr.model == 232 or fr.model == 241) and shown == fr.model then seen.bike = true end
    if spawned and fr.status & 4 ~= 0 and it32(RIDE + fr.slot * 4) == 1 and task ~= 0 then seen.surf = true end
    if seen.surf and spawned and fr.status & 4 == 0 and task == 0 and f - changedAt > 30 then seen.surfOff = true end
    if fr.model ~= lastModel then
      K.log(string.format("f=%d friend model %s -> %d status=%d", f, tostring(lastModel), fr.model, fr.status))
      lastModel, changedAt, shots = fr.model, f, 0
    end
    if f % 60 == 0 then
      K.log(string.format("f=%d model=%d status=%d slot obj=%d shown=%d spawned=%d actor=%08X | %s", f, fr.model, fr.status,
        it32(a + 4), it32(a + 0x24), it32(a + 0x1C), it32(a + 0x20), rideInfo()))
    end
    if f < 2400 and shots < 4 and f - changedAt >= 60 + shots * 25 then
      shots = shots + 1
      nshot = nshot + 1
      K.shot(string.format("%02d_m%d_%d", nshot, fr.model, shots))
    end
  end
  -- Our own bike
  if f >= 2400 and f < 2404 then K.press({ Y = true }) end
  if f == 2400 then K.log("me before Y: obj=" .. tostring(s.me.objCode) .. " ex=" .. tostring(s.me.exState)) end
  if f >= 2520 and f < 2560 then K.press({ Left = true }) end
  if f == 2540 then K.shot("me_bike") end
  if f == 2600 then
    K.log("me after Y: obj=" .. tostring(s.me.objCode) .. " ex=" .. tostring(s.me.exState) .. " ready=" .. tostring(s.me.ready))
    K.shot("me_bike2")
  end
  if f == 2620 then
    K.check(seen.bike, "friend on a bike shown with the cycling object code")
    K.check(seen.surf, "surfing friend got a surf Pokemon task")
    K.check(seen.surfOff, "surf Pokemon removed when the friend walks again")
    K.check(s.me.objCode == 232 or s.me.objCode == 241, "our own bike: object code " .. tostring(s.me.objCode))
    K.verdict()
    client.exit()
  end
end)
