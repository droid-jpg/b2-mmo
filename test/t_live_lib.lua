-- Shared by the live battle tests (t_live*.lua): lib.lua's helpers for a test whose output folder
-- may be test/out2 (the second game of test/live2.sh), and the battle driver.
-- Usage: LIVE_OUT = "out2/" (optional); local K = dofile(<test dir> .. "t_live_lib.lua")
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local K = {}
K.env = dofile(here .. (LIVE_OUT or "out/") .. "env.lua")
local logf = io.open(K.env.out .. "test.log", "w")
function K.log(s) logf:write(tostring(s) .. "\n"); logf:flush() end
TL = K.log
function K.shot(name) client.screenshot(K.env.out .. "shot_" .. name .. ".png") end
function K.party(s)
  local t = {}
  for i, r in ipairs(s.partyRaw()) do t[#t + 1] = i .. "=" .. s.monLabel(r) end
  return table.concat(t, ", ")
end
function K.dumpParty(s, path)
  local fh = io.open(path, "wb")
  for _, r in ipairs(s.partyRaw()) do fh:write(r) end
  fh:close()
end
function K.feature(s, name)
  for _, ft in ipairs(s.features) do if ft.name == name then return ft end end
end
function K.start(cfg, fn, state)
  savestate.load(K.env.states .. (state or "field2.State"))
  client.setscreenshotosd(true)
  client.speedmode(cfg.speed or 400)
  B2MMO_CFG = { name = cfg.name or "Michael", room = "TEST", server = "127.0.0.1", port = tostring(K.env.port) }
  for k, v in pairs(cfg) do if k ~= "speed" then B2MMO_CFG[k] = v end end
  local f0 = emu.framecount()
  B2MMO_TEST = function(s)
    local ok, err = pcall(fn, s, emu.framecount() - f0)
    if not ok then K.log("test error: " .. tostring(err)); client.exit() end
  end
  local ok, err = pcall(dofile, K.env.root .. "lua/b2mmo.lua")
  K.log("client stopped: " .. tostring(err))
  client.exit()
end

-- Touches the bottom screen at x, y (its own pixels, 256 x 192)
local function touch(x, y)
  joypad.setanalog({ ["Touch X"] = x, ["Touch Y"] = y })
  joypad.set({ Touch = true })
end

-- Plays our side: every 48 frames touch FIGHT, then a move (the first one, or Outrage once the
-- Kyurem in front has used most of its first move's PP), then A for the texts and send-ins.
-- st = the live feature's status(); host = our team comes first in st.hp.
function K.drive(st, f, host)
  if st.armed ~= 1 then return end
  local c = f % 48
  local front = st.hp:match(host and "^(%d+):" or "^%S+ %S+ (%d+):")
  local slot = { 63, 53 }
  if front == "646" and st.step0 >= 5 then slot = { 63, 101 } end
  if c < 3 then touch(128, 95)
  elseif c >= 16 and c < 19 then touch(slot[1], slot[2])
  elseif c >= 32 and c < 35 then joypad.set({ A = true }) end
end

-- One line of the battle as this game sees it, when our step count changed
function K.line(st, f)
  return string.format("f%d step0=%d step1=%d patched=%X seeded=%d fell=%d desync=%d check=%08X hp=[%s] ours=%08X theirs=%08X",
    f, st.step0, st.step1, st.patched, st.seeded, st.fellBack, st.desync, st.check, st.hp, st.lastOurs, st.lastTheirs)
end
return K
