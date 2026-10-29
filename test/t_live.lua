-- Live battle against the fake friend (one game). The friend (tools/ff/live.mjs) answers every step
-- with its first move, aimed at us, or sends in its next Pokemon; we play with the buttons
-- (t_live_lib.lua K.drive). The mode comes from the LIVE environment variable:
--   normal  we challenge, Ann accepts; played to the end (a knock-out and a send-in on the way)
--   decline we challenge, Ann refuses
--   leave   Ann disconnects after 2 steps: the game's AI plays her side to the end
--   guest   Ann challenges us; we answer Yes in the game's text box
-- B2PORT=7782 bash test/up.sh "--name Ann --x 584 --z 184 --path stand --party <party> --plugin live <args>"
--   normal: --live-accept   decline: (none)   leave: --live-accept --live-leave 2   guest: --live-challenge 2
-- LIVE=normal bash test/run.sh test/t_live.lua 300
-- <party> is our own party (the test writes test/out/party.bin at the start; a mirror match).
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_live_lib.lua")
local mode = os.getenv("LIVE") or "normal"
local feat, lastStep, shots, endAt, endNotice = nil, -1, 0, nil, nil
local hash0, sawArmed, sawTheirMove, sawSwitch, sawAsk, maxSteps, maxPatched = nil, false, false, false, false, 0, 0
local notes = {}
local function hasNote(p) for _, t in ipairs(notes) do if t:find(p) then return true end end return false end
local function partyHash(s) return s.api.PKM.fnv(table.concat(s.partyRaw())) end

K.start({ name = "Michael" }, function(s, f)
  feat = feat or K.feature(s, "live")
  if f == 1 then
    local o = s.api.addNotice
    s.api.addNotice = function(t)
      K.log("notice: " .. t)
      notes[#notes + 1] = t
      if t:find("^You beat") or t:find("^You lost") then endNotice = t end
      o(t)
    end
    hash0 = partyHash(s)
    K.dumpParty(s, K.env.out .. "party.bin")
    K.log(string.format("mode %s party: %s hash %08X", mode, K.party(s), hash0))
  end
  if f == 90 and mode ~= "guest" then
    local id = next(s.friends)
    K.log("challenging #" .. tostring(id))
    feat.challenge(id)
  end
  if mode == "guest" and feat.live.phase == "asked" then
    if not sawAsk then sawAsk = true; K.log("asked at f" .. f) end
    if f % 40 == 0 then K.shot("ask"); joypad.set({ A = true }) end -- Yes
  end
  if f <= 90 then return end
  local st = feat.status()
  if st.armed == 1 then
    sawArmed = true
    maxSteps = math.max(maxSteps, st.steps)
    maxPatched = maxPatched | st.patched
    if st.lastTheirs & 0xF == 1 and (st.lastTheirs >> 4) & 7 == 0 then sawTheirMove = true end
    if st.lastTheirs & 0xF == 3 or st.lastOurs & 0xF == 3 then sawSwitch = true end
  end
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
    K.check(hasNote("declined your live battle"), "Ann's refusal is shown")
    K.check(feat.live.phase == nil, "no live battle pending")
    K.check(s.api.ir32(s.api.SH + 0x68) == 0 and s.api.ir32(s.api.SH + 0x6C) == 0, "no battle started")
    K.check(not sawArmed, "the live hooks were never armed")
    K.shot("decline")
    K.verdict()
    client.exit()
  end
  K.drive(st, f, mode ~= "guest")
  if endNotice and not endAt then
    endAt = f + 300
    K.log(string.format("battle over at f%d: steps=%d desync=%d fellBack=%d", f, st.steps, st.desync, st.fellBack))
    K.check(sawArmed and st.seeded == 1, "the battle took the shared seed")
    K.check(maxPatched & 0x3E == 0x3E, string.format("all battle patches in place (%X)", maxPatched))
    K.check(st.desync == 0, "every check Ann sent matched ours")
    K.check(maxSteps >= 3, "at least 3 steps answered by both sides (" .. maxSteps .. ")")
    if mode == "leave" then
      K.check(hasNote("Ann left: their side plays on"), "Ann leaving is shown")
      K.check(st.fellBack == 1, "the AI took Ann's side over")
    else
      K.check(st.fellBack == 0, "Ann's side was hers to the end")
      K.check(sawTheirMove, "Ann's move replaced the AI's, aimed at us")
      K.check(sawSwitch, "a knock-out and a send-in")
    end
    if mode == "guest" then K.check(sawAsk, "the challenge was asked in the game's text box") end
  end
  if endAt and f == endAt then
    K.log("after: " .. K.party(s) .. string.format(" hash %08X", partyHash(s)))
    K.check(partyHash(s) == hash0, "our party is back as it was (byte for byte)")
    K.check(st.armed == 0 and feat.live.phase == nil, "live battle disarmed")
    K.check(endNotice == "You beat Ann!" or endNotice == "You lost to Ann!", "result shown: " .. tostring(endNotice))
    K.check(s.me.ready, "back on the field")
    K.shot("after")
    K.verdict()
    client.exit()
  end
  if f > 40000 then K.check(false, "battle over in time"); K.shot("timeout"); K.verdict(); client.exit() end
end)
