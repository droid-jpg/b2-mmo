-- Shared by the BizHawk tests (test/t_*.lua). Usage at the top of a test:
--   local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
-- K.env (root, out, states, port), K.log(s), K.shot(name), K.party(s) and K.start(cfg, fn):
-- loads the field save state (Nimbasa City, zone 64, at x 568 z 200), sets the settings, and runs
-- the client with fn(s, f) called every frame (f = frames since the start). Never save in-game.
local K = {}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
K.env = dofile(here .. "out/env.lua")
local logf = io.open(K.env.out .. "test.log", "w")
function K.log(s) logf:write(tostring(s) .. "\n"); logf:flush() end
TL = K.log
function K.shot(name) client.screenshot(K.env.out .. "shot_" .. name .. ".png") end
function K.party(s)
  local t = {}
  for i, r in ipairs(s.partyRaw()) do t[#t + 1] = i .. "=" .. s.monLabel(r) end
  return table.concat(t, ", ")
end
-- Writes our party (0xDC bytes a Pokemon, as the game stores it) to a file, for fakefriend --party
function K.dumpParty(s, path)
  local fh = io.open(path, "wb")
  for _, r in ipairs(s.partyRaw()) do fh:write(r) end
  fh:close()
end
function K.press(keys) joypad.set(keys) end
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
return K
