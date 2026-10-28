-- Talking in the game's text box: greeting, the choice list, trading by talking (both ways),
-- B and Cancel, 10 talks in a row, and the Battle choice starting the friend battle.
-- touch test/out/party.bin test/out/trade.bin  (the test fills them; fakefriend reads them when asked)
-- B2PORT=7781 bash test/up.sh "--name Ann --x 568 --z 184 --path stand --party E:/b2-wt/talk/test/out/party.bin --trade E:/b2-wt/talk/test/out/trade.bin --plugin talk"
-- bash test/run.sh test/t_talk.lua 400
local K, H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_talk_lib.lua")
local phase, boxState, press, step, check, writes, annId = H.phase, H.boxState, H.press, H.step, H.check, H.writes, H.annId
local advanceTo, waitFor, readThrough, after, talk, closed, choose = H.advanceTo, H.waitFor, H.readThrough, H.after, H.talk, H.closed, H.choose
local writes0, party0

step("setup", function(s, f, t)
  if #s.partyRaw() >= 2 and annId(s) and s.friends[annId(s)].drawX and s.me.ready and t > 120 then
    K.dumpParty(s, K.env.out .. "party.bin")
    local fh = io.open(K.env.out .. "trade.bin", "wb"); fh:write(s.partyRaw()[2]); fh:close()
    party0 = K.party(s)
    K.log("party: " .. party0)
    check(s.api.gameMessage ~= nil, "api.gameMessage is set")
    return true
  end
  if t == 400 then K.log(string.format("setup: party %d ann %s ready %s", #s.partyRaw(), tostring(annId(s)), tostring(s.me.ready))) end
end)
step("face up", function(s, f, t) if t == 0 then press({ Up = true }, 6) end return t > 40 end)
step("talk", talk())
step("greeting", after(50, function() K.shot("greeting") end))
step("to menu", advanceTo(4))
step("menu shot", after(30, function() K.shot("menu") end))
step("trade", choose(1))
step("pick", advanceTo(4))
step("pick shot", after(20, function() K.shot("trade_pick") end))
step("pick first", function(s, f, t) writes0 = writes(); return choose(0)(s, f, t) end)
step("offered", readThrough("trade_offered"))
-- fakefriend answers with its offer and accepts: we're asked to confirm
step("confirm", advanceTo(4))
step("confirm shot", after(20, function() K.shot("trade_confirm") end))
step("yes", choose(0))
step("closed", waitFor(closed))
step("swapped", function(s, f, t)
  if writes() > writes0 then
    K.log("party after trade 1: " .. K.party(s))
    check(K.party(s) ~= party0, "trade 1 (we offered first) changed the party")
    return true
  end
  if t > 600 then check(false, "trade 1 finished"); return true end
end)
step("traded shot", after(30, function() K.shot("trade_done") end))
-- They offer first: the question comes right away, we're free
step("ff offer", function(s) writes0 = writes(); s.api.say("ff offer"); return true end)
step("offer asked", function(s, f, t) if boxState() == 1 then return true end if t > 600 then check(false, "offer prompt shown"); return true end end)
step("offer to menu", advanceTo(4))
step("offer shot", after(20, function() K.shot("offer_prompt") end))
step("offer yes", choose(0))
step("offer pick", advanceTo(4))
step("offer pick 2", choose(1))
step("offer waiting", readThrough("offer_waiting"))
step("offer closed", waitFor(closed))
step("offer swapped", function(s, f, t)
  if writes() > writes0 then
    K.log("party after trade 2: " .. K.party(s))
    check(true, "trade 2 (they offered first) wrote the party")
    return true
  end
  if t > 900 then check(false, "trade 2 finished"); return true end
end)
-- B on the menu, then Cancel
step("talk B", talk())
step("B to menu", advanceTo(4))
step("B", function(s, f, t) if t == 0 then press({ B = true }, 3) end return t > 4 end)
step("B closed", function(s, f, t) if closed(s) then check(true, "B closes the menu"); return true end if t > 300 then check(false, "B closes the menu"); return true end end)
step("talk cancel", talk())
step("cancel to menu", advanceTo(4))
step("cancel", function(s, f, t) return choose(#s.api.actions)(s, f, t) end)
step("cancel closed", function(s, f, t) if closed(s) then check(true, "Cancel closes the menu"); return true end if t > 300 then check(false, "Cancel closes the menu"); return true end end)
step("walkable", function(s, f, t)
  if t == 0 then s.x0 = s.me.x; press({ Right = true }, 20) end
  if t == 60 then check(s.me.x ~= s.x0, "the player can walk after talking"); press({ Left = true }, 20) end
  if t == 120 then press({ Up = true }, 4) end
  return t > 160
end)
-- 10 talks in a row
local n10 = 0
for i = 1, 10 do
  step("talk " .. i, talk())
  step("menu " .. i, advanceTo(4))
  step("close " .. i, function(s, f, t) if t == 0 then press({ B = true }, 3) end
    if t > 4 and closed(s) then n10 = n10 + 1 return true end
    if t > 300 then return true end end)
end
step("10 talks", function(s) check(n10 == 10, "10 talks in a row (" .. n10 .. " closed)"); return true end)
-- Battle
step("talk battle", talk())
step("battle to menu", advanceTo(4))
step("battle", choose(0))
step("battle starts", function(s, f, t)
  local bs = memory.read_u32_le(0x01FFA06C - 0x01FF8000, "Instruction TCM")
  if bs == 1 then check(true, "Battle starts the friend battle"); return true end
  if t > 600 then check(false, "Battle starts the friend battle"); return true end
end)
step("battle shot", after(500, function() K.shot("battle") end))

H.run()
