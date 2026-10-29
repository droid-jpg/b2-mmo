-- api.gameMessage on its own (a choice, B, no choices), long text over several pages (api.talkInfo),
-- and a friend who leaves while you talk to them (no hang, you can walk on).
-- touch test/out/party.bin test/out/trade.bin
-- B2PORT=7781 bash test/up.sh "--name Ann --x 568 --z 184 --path stand --party E:/b2-wt/talk/test/out/party.bin --plugin talk"
-- bash test/run.sh test/t_talk_leave.lua 300
local K, H = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_talk_lib.lua")
local phase, boxState, press, step, check, annId = H.phase, H.boxState, H.press, H.step, H.check, H.annId
local advanceTo, readThrough, after, talk, closed, choose = H.advanceTo, H.readThrough, H.after, H.talk, H.closed, H.choose

local answers = {}
local readyAtAnswer
step("setup", function(s, f, t)
  if annId(s) and s.me.ready and t > 120 then
    table.insert(s.api.talkInfo, function(fr, id)
      return fr.name .. " is in " .. s.api.zoneName(fr.zone) .. ". This is a long line to see the text wrap " ..
        "over lines and pages in the game's own box, like a script's message."
    end)
    return true
  end
end)
-- gameMessage: three choices, pick the second
step("message", function(s)
  local ok = s.api.gameMessage("Hello from api.gameMessage!\nPick one.", { "One", "Two", "Three" }, function(i)
    answers[#answers + 1] = i or "nil"; readyAtAnswer = s.me.ready
  end)
  check(ok == true, "gameMessage returns true")
  return true
end)
step("message to menu", advanceTo(4))
step("message shot", after(10, function() K.shot("api_choices") end))
step("pick two", choose(1))
step("message closed", function(s, f, t) return closed(s) and #answers >= 1 end)
step("answer", function(s)
  check(answers[1] == 2, "onAnswer(2) for the second choice (got " .. tostring(answers[1]) .. ")")
  check(readyAtAnswer == true, "onAnswer runs once the player is free")
  return true
end)
-- B on choices -> nil; no choices -> nil after A
step("message B", function(s) s.api.gameMessage("Press B.", { "Yes", "No" }, function(i) answers[#answers + 1] = i or "nil" end) return true end)
step("B to menu", advanceTo(4))
step("B", function(s, f, t) if t == 0 then press({ B = true }, 3) end return t > 4 end)
step("B closed", function(s, f, t) return closed(s) and #answers >= 2 end)
step("plain", function(s) s.api.gameMessage("Just text.", nil, function(i) answers[#answers + 1] = i or "nil" end) return true end)
step("plain read", readThrough("api_plain"))
step("plain closed", function(s, f, t) return closed(s) and #answers >= 3 end)
step("answers", function()
  check(answers[2] == "nil" and answers[3] == "nil", "B and no-choice messages answer nil (" .. tostring(answers[2]) .. ", " .. tostring(answers[3]) .. ")")
  return true
end)
-- Two queued at once: shown one after the other
step("queue", function(s)
  s.api.gameMessage("First of two.", nil, function() answers[#answers + 1] = "first" end)
  s.api.gameMessage("Second of two.", nil, function() answers[#answers + 1] = "second" end)
  return true
end)
step("first read", readThrough("api_first"))
step("second read", readThrough("api_second"))
step("queue closed", function(s, f, t) return t > 20 and closed(s) and #answers >= 5 end)
step("queue answers", function() check(answers[4] == "first" and answers[5] == "second", "queued messages in order"); return true end)
-- Long text, then the friend leaves while the menu is up
step("face up", function(s, f, t) if t == 0 then press({ Up = true }, 6) end return t > 40 end)
step("talk", talk())
local page = 0
step("pages", function(s, f, t)
  if phase() == 4 then return true end
  if t % 40 == 20 and phase() == 2 then page = page + 1; K.shot("page" .. page); press({ A = true }, 2) end
end)
step("menu", after(45))
step("leave", function(s) s.api.say("ff leave"); return true end)
step("left", function(s, f, t) return t > 60 and not annId(s) end)
step("battle", choose(0))
step("gone message", readThrough("gone"))
step("closed", function(s, f, t)
  if closed(s) then check(true, "the box closes after the friend left"); return true end
  if t > 600 then check(false, "the box closes after the friend left"); return true end
end)
step("walk", function(s, f, t)
  if t == 0 then s.x0 = s.me.x; press({ Right = true }, 20) end
  if t == 60 then check(s.me.x ~= s.x0, "the player can walk on"); return true end
end)
H.run()
