-- Watching, receiving side: a fake friend one tile above us plays made-up battles (tools/ff/watch.mjs).
-- We face up and talk to her: the notice says what each side has out and the bottom screen shows
-- both teams with HP bars until her battle ends; in her next battle B stops watching.
-- B2PORT=7783 bash test/up.sh "--name Ann --x 568 --z 184 --path stand --plugin watch"
-- bash test/run.sh test/t_watch.lua 120
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local watch, annId, fakeTab = nil, nil, false
-- The Tab player list reads the host keyboard: pretend Tab is held for one screenshot
local realGet = input.get
input.get = function() local t = realGet(); if fakeTab then t.Tab = true end return t end

local function state(s, f, what)
  local ann = s.friends[annId]
  local w = ann and ann.watch
  local sides = "none"
  if w and w.sides[0] and w.sides[1] then
    local function side(t) local r = {} for _, m in ipairs(t) do r[#r + 1] = s.api.speciesName(m.species) .. " " .. m.hp .. "/" .. m.maxHp end return table.concat(r, ", ") end
    sides = side(w.sides[0]) .. " vs " .. side(w.sides[1])
  end
  K.log(string.format("f%d %s: status=%s battle=[%s] line=%s talkInfo=%s watching=%s", f, what, tostring(ann and ann.status), sides,
    tostring(ann and watch.battleLine(ann)), tostring(ann and s.api.talkInfo[#s.api.talkInfo](ann, annId)), tostring(watch.W.watching)))
end

local wasBattling, talks, talkAt, talkN, over1 = false, 0, nil, nil, nil
K.start({ speed = 100 }, function(s, f)
  if not watch then for _, ft in ipairs(s.features) do if ft.name == "watch" then watch = ft end end end
  if not annId then for id, fr in pairs(s.friends) do if fr.name == "Ann" then annId = id end end end
  if f >= 30 and f < 34 then K.press({ Up = true }) end -- face her
  local ann = annId and s.friends[annId]
  local battling = ann and watch.inBattle(ann) or false
  if battling ~= wasBattling then state(s, f, battling and "her battle started" or "her battle ended"); wasBattling = battling end
  -- Talk once she's battling (first battle: watch it to the end; second: press B)
  if battling and not watch.W.watching and talks < 2 and (not talkAt or f > talkAt + 60) then
    talks = talks + 1
    talkAt, talkN = f + 30, talks
  end
  if talkAt and f >= talkAt and f < talkAt + 4 then K.press({ A = true }) end
  if talkAt and f == talkAt + 10 then state(s, f, "talked " .. talkN); K.shot("talk" .. talkN) end
  if talkN == 1 and talkAt and f == talkAt + 300 then state(s, f, "watching"); K.shot("watch_hp") end
  if talkN == 1 and talkAt and f > talkAt and (f - talkAt) % 60 == 0 and f < talkAt + 600 then K.shot("n" .. (f - talkAt)) end
  if talkN == 1 and talkAt and f == talkAt + 360 then fakeTab = true end
  if talkN == 1 and talkAt and f == talkAt + 362 then K.shot("tab"); fakeTab = false end
  if talkN == 1 and not battling and talkAt and f > talkAt + 30 and not over1 then over1 = f end
  if over1 and f == over1 + 30 then state(s, f, "after her battle"); K.shot("over") end
  if talkN == 2 and f == talkAt + 120 then K.press({ B = true }) end
  if talkN == 2 and f == talkAt + 130 then state(s, f, "pressed B"); K.shot("pressed_b") end
  if (talkN == 2 and f > talkAt + 140) or f > 3600 then client.exit() end
end)
