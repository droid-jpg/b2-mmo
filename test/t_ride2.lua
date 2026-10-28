-- Surfing friends: two at once (the shared surf Pokemon objects), one leaving while surfing (no
-- leftover), odd object codes (fallback, no crash). (Map changes: t_ride3.lua. Walking into a
-- building with any friend actor on the map hangs the game in the core as of 99bf41f, ride or not.)
-- B2PORT=7787 bash test/up.sh "--name Ann --x 584 --z 232 --path square --size 2 --speed 1 --model 231 --plugin ride --ride surf --ride-leave 25" \
--   "--name Bob --x 520 --z 216 --path line --size 3 --speed 1 --model 240 --plugin ride --ride surf" \
--   "--name Cid --x 616 --z 232 --path stand --model 9999" "--name Dee --x 504 --z 184 --path stand --model 234"
-- bash test/run.sh test/t_ride2.lua 200
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local IT = "Instruction TCM"
local function it32(a) return memory.read_u32_le(a - 0x01FF8000, IT) end
local RIDE = 0x01FFF900
local annGoneAt = nil

local function info(s)
  local t = {}
  for _, fr in pairs(s.friends) do
    if fr.slot then
      local a = 0x01FFA080 + fr.slot * 0x30
      t[#t + 1] = string.format("%s:slot%d model=%d obj=%d spawned=%d surf=%d task=%08X", fr.name, fr.slot, fr.model,
        it32(a + 4), it32(a + 0x1C), it32(RIDE + fr.slot * 4), it32(RIDE + 0x20 + fr.slot * 4))
    else
      t[#t + 1] = fr.name .. ":noslot"
    end
  end
  return table.concat(t, " | ") .. string.format(" || created=%d deleted=%d", it32(RIDE + 0x60), it32(RIDE + 0x64))
end

K.start({ speed = 200 }, function(s, f)
  if f % 60 == 0 then K.log(string.format("f=%d zone=%d x=%.0f z=%.0f ready=%s %s", f, s.me.zone, s.me.x, s.me.z, tostring(s.me.ready), info(s))) end
  if f == 300 then K.shot("a_two_surfing") end
  if f == 330 then K.shot("a_two_surfing2") end
  local ann = false
  for _, fr in pairs(s.friends) do if fr.name == "Ann" then ann = true end end
  if f > 300 and not ann and not annGoneAt then annGoneAt = f; K.log("f=" .. f .. " Ann left: " .. info(s)) end
  if annGoneAt and f == annGoneAt + 40 then K.shot("b_ann_left"); K.log("after leave: " .. info(s)) end
  if annGoneAt and f == annGoneAt + 70 then K.shot("b_ann_left2"); client.exit() end
  if f > 6000 then K.log("timeout"); client.exit() end
end)
