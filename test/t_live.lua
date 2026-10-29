-- Live battle against the fake friend (one game). We challenge; the friend (tools/ff/live.mjs)
-- accepts and answers every step with its first move, or sends in its next Pokemon; we touch FIGHT
-- and a move. Mode (test/out/live_mode.txt): "normal" (to the end), "decline" (the friend refuses),
-- "leave" (the friend disconnects mid-battle: the AI plays on), "guest" (the friend challenges us).
--   B2PORT=7782 bash test/up.sh "--name Ann --x 584 --z 184 --path stand --party test/out/party.bin --plugin live --live-accept"
--   bash test/run.sh test/t_live.lua 300
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_live_lib.lua")
local mode = "normal"
do local fh = io.open(K.env.out .. "live_mode.txt", "r"); if fh then mode = fh:read("*l") or mode; fh:close() end end
local feat, lastStep, shots, endAt, ended, asked = nil, -1, 0, nil, false, false
K.start({ name = "Michael" }, function(s, f)
  feat = feat or K.feature(s, "live")
  if f == 1 then
    local o = s.api.addNotice
    s.api.addNotice = function(t) K.log("notice: " .. t); if t:find("^You beat") or t:find("^You lost") then ended = true end; o(t) end
    K.log("mode " .. mode .. " party: " .. K.party(s) .. string.format(" hash %08X", s.api.PKM.fnv(table.concat(s.partyRaw()))))
  end
  if f == 90 and mode ~= "guest" then
    local id = next(s.friends)
    K.log("challenging #" .. tostring(id))
    feat.challenge(id)
  end
  if mode == "guest" and feat.live.phase == "asked" then
    if not asked then asked = true; K.log("asked at f" .. f) end
    if f % 40 == 0 then K.shot("ask"); joypad.set({ A = true }) end
  end
  if f <= 90 then return end
  local st = feat.status()
  if st.step0 ~= lastStep then
    lastStep = st.step0
    K.log(K.line(st, f))
    if st.armed == 1 and shots < 4 then shots = shots + 1; K.shot("turn" .. shots) end
  end
  if f % 1200 == 0 then
    K.log(string.format("f%d phase=%s armed=%d waiting=%d steps=%d", f, tostring(st.phase), st.armed, st.waiting, st.steps))
    if st.armed == 1 then K.shot("f" .. f) end
  end
  if mode == "decline" and f == 600 then
    K.log("phase after decline: " .. tostring(st.phase) .. " battleReq=" .. s.api.ir32(s.api.SH + 0x68))
    K.shot("decline")
    client.exit()
  end
  K.drive(st, f, mode ~= "guest")
  if ended and not endAt then
    endAt = f + 300
    K.log(string.format("battle over at f%d: steps=%d desync=%d fellBack=%d", f, st.steps, st.desync, st.fellBack))
  end
  if endAt and f == endAt then
    K.log("after: " .. K.party(s) .. string.format(" hash %08X", s.api.PKM.fnv(table.concat(s.partyRaw()))) .. " live phase=" .. tostring(feat.live.phase) .. " armed=" .. st.armed)
    K.shot("after")
    client.exit()
  end
  if f > 40000 then K.log("timeout"); K.shot("timeout"); client.exit() end
end)
