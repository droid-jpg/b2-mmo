-- A surfing friend across a field rebuild (a battle against their team tears the field down and
-- makes a new one): the old surf Pokemon task must be forgotten, not deleted, and a new one made.
-- B2PORT=7787 bash test/up.sh "--name Bob --x 600 --z 216 --path line --size 2 --speed 1 --model 240 --plugin ride --ride surf --party test/out/party1.bin"
-- (party1.bin: one Pokemon, 0xDC bytes, e.g. from K.dumpParty)
-- bash test/run.sh test/t_ride3.lua 240
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local IT = "Instruction TCM"
local function it32(a) return memory.read_u32_le(a - 0x01FF8000, IT) end
local RIDE = 0x01FFF900
local started, endedAt, field0 = nil, nil, nil
local function info()
  return string.format("task0=%08X created=%d deleted=%d effects=%08X field=%08X", it32(RIDE + 0x20), it32(RIDE + 0x60),
    it32(RIDE + 0x64), it32(RIDE + 0x68), it32(0x01FFA014))
end
K.start({ speed = 400 }, function(s, f)
  if f % 120 == 0 then K.log(string.format("f=%d ready=%s battleState=%d %s", f, tostring(s.me.ready), it32(0x01FFA06C), info())) end
  if f == 240 then K.shot("1_before"); K.log("before: " .. info()) end
  if f == 260 and not started then
    for id, fr in pairs(s.friends) do started = id; s.startBattle(id) end
  end
  if started and not endedAt then
    if f % 16 < 2 then K.press({ A = true }) end
    if it32(0x01FFA06C) == 2 or (f > 400 and s.me.ready and it32(0x01FFA06C) == 0) then endedAt = f; K.log("f=" .. f .. " battle over: " .. info()) end
  end
  if endedAt and f == endedAt + 200 then K.shot("2_after"); K.log("after: " .. info()) end
  if endedAt and f == endedAt + 230 then K.shot("3_after"); client.exit() end
  if f > 12000 then K.log("timeout " .. info()); K.shot("timeout"); client.exit() end
end)
