-- The two games of test/live2.sh (t_live_a.lua, t_live_b.lua): one challenges, the other answers
-- Yes in the game's text box, both play their side with the touch screen to the end. Each logs
-- "STEP n check hp" for every step it asked (both host-first), which live2.sh compares.
return function(K, opt)
  local feat, lastStep, shots, endAt, ended, challenged, lastLog = nil, -1, 0, nil, false, false, 0
  K.start({ name = opt.name, speed = 300 }, function(s, f)
    feat = feat or K.feature(s, "live")
    if f == 1 then
      local o = s.api.addNotice
      s.api.addNotice = function(t)
        K.log("notice: " .. t)
        if t:find("^You beat") or t:find("^You lost") then ended = true end
        o(t)
      end
      K.log(opt.name .. " party: " .. K.party(s) .. string.format(" hash %08X", s.api.PKM.fnv(table.concat(s.partyRaw()))))
    end
    local other
    for id, fr in pairs(s.friends) do if fr.name == opt.other then other = id end end
    if opt.host and not challenged and other and f > 300 then
      challenged = true
      K.log("f" .. f .. " challenging " .. opt.other .. " #" .. other)
      feat.challenge(other)
    end
    if not opt.host and feat.live.phase == "asked" and f % 40 == 0 then
      if not challenged then challenged = true; K.log("f" .. f .. " asked"); K.shot("ask") end
      joypad.set({ A = true }) -- Yes
    end
    local st = feat.status()
    if st.step0 ~= lastStep then
      if lastStep >= 0 and st.armed == 1 then
        K.log(string.format("STEP %d check %08X hp [%s]", lastStep, st.check, st.hp))
      end
      lastStep = st.step0
      K.log(K.line(st, f))
      if st.armed == 1 and shots < 8 then shots = shots + 1; K.shot("turn" .. shots) end
    end
    if f - lastLog >= 1800 then
      lastLog = f
      K.log(string.format("f%d phase=%s armed=%d waiting=%d steps=%d", f, tostring(st.phase), st.armed, st.waiting, st.steps))
      if st.armed == 1 then K.shot("f" .. f) end
    end
    K.drive(st, f, opt.host)
    if ended and not endAt then
      endAt = f + 300
      K.log(string.format("battle over at f%d: steps=%d desync=%d fellBack=%d", f, st.steps, st.desync, st.fellBack))
    end
    if endAt and f == endAt then
      K.log("after: " .. K.party(s) .. string.format(" hash %08X", s.api.PKM.fnv(table.concat(s.partyRaw()))) ..
        " live phase=" .. tostring(feat.live.phase) .. " armed=" .. st.armed)
      K.shot("after")
      client.exit()
    end
    if f > 40000 and not ended then K.log("stopping"); K.shot("stop"); client.exit() end
    if f > 60000 then K.log("timeout"); K.shot("timeout"); client.exit() end
  end)
end
