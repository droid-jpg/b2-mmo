-- Smoke test: the client starts, connects, a fake friend shows up next to us and walks.
-- bash test/up.sh "--name Ann --x 584 --z 184 --path square"; bash test/run.sh test/t_smoke.lua 120
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
K.start({}, function(s, f)
  if f == 240 then
    local n = 0
    for id, fr in pairs(s.friends) do
      n = n + 1
      K.log(string.format("friend #%d %s zone=%d slot=%s draw=%s,%s", id, fr.name, fr.zone, tostring(fr.slot), tostring(fr.drawX), tostring(fr.drawZ)))
    end
    K.log("me ready=" .. tostring(s.me.ready) .. " zone=" .. s.me.zone .. " friends=" .. n .. " net=" .. s.net.status)
    K.log("features: " .. #s.features)
    K.log("party: " .. K.party(s))
    K.shot("smoke")
  end
  if f == 250 then client.exit() end
end)
