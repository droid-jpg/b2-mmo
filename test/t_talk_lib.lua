-- Helpers for test/t_talk*.lua: a list of steps run one after the other, buttons, the talk box state.
-- local K, H = dofile(here .. "t_talk_lib.lua"); H.step(name, fn(s, f, t) -> done); H.run()
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local TA = 0x01FFE800
local function tr32(off) return memory.read_u32_le(TA + off - 0x01FF8000, "Instruction TCM") end
local function phase() return tr32(0x3E0) end
local function boxState() return tr32(0x08) end

-- A list of steps, each a function(s, f) returning true when done; buttons are held for a few frames
local hold, holdUntil = nil, 0
local function press(keys, n) hold, holdUntil = keys, emu.framecount() + (n or 4) end
local steps, si, stepStart, wait = {}, 1, 0, 0
local function step(name, fn) steps[#steps + 1] = { name = name, fn = fn } end
local fails = 0
local function check(ok, what) K.log((ok and "OK   " or "FAIL ") .. what); if not ok then fails = fails + 1 end end

local function writes() return memory.read_u32_le(0x01FFA064 - 0x01FF8000, "Instruction TCM") end
local function annId(s) for id, fr in pairs(s.friends) do if fr.drawX then return id end end return nil end

-- Presses A every 20 frames while text prints, until the choice list (4) or the A/B wait (3) shows
-- (and 45 frames more: the game's list menus take input once their cursor is up, 20 game frames)
local function advanceTo(want)
  local since
  return function(s, f, t)
    if t == 0 then since = nil end
    if phase() == want then
      since = since or t
      if t - since >= 45 then return true end
    else
      since = nil
    end
    if phase() == 2 and t % 20 == 0 then press({ A = true }, 2) end
  end
end
local function waitFor(cond, n) return function(s, f, t) return t >= (n or 0) and cond(s) end end
-- Reads a message to its end (A through the pages), screenshots its last page, then closes it with A;
-- done once the box is closed or the next message shows its choice list
local function readThrough(name)
  local since, shotDone, shown0
  return function(s, f, t)
    if t == 0 then since, shotDone, shown0 = nil, false, tr32(4) end
    if shotDone and tr32(4) ~= shown0 then return true end -- moved on to the next message
    if phase() == 4 or (t > 10 and boxState() == 3) then return true end
    if phase() == 3 then
      since = since or t
      if t - since == 30 and not shotDone then K.shot(name); shotDone, shown0 = true, tr32(4); press({ A = true }, 3) end
      if t - since > 60 then since = nil end
    elseif phase() == 2 and t % 20 == 0 then
      press({ A = true }, 2)
    end
  end
end
local function after(n, fn) return function(s, f, t) if t >= n then if fn then fn(s) end return true end end end
local function talk() return function(s, f, t)
  if t == 0 then press({ A = true }, 3) end
  return t > 2 and boxState() == 1
end end
local function closed(s) return boxState() == 3 and s.me.ready end
local function shot(name) return function() K.shot(name); return true end end
local function choose(downs) return function(s, f, t)
  -- t 0..: Down x downs, then A
  if t % 12 == 0 then
    local k = t // 12
    if k < downs then press({ Down = true }, 3) elseif k == downs then press({ A = true }, 3) else return true end
  end
end end
local function run(cfg)
  K.start(cfg or { name = "Michael" }, function(s, f)
    if hold and emu.framecount() < holdUntil then joypad.set(hold) else hold = nil end
    local st = steps[si]
    if not st then
      K.log(fails == 0 and "PASS" or ("FAILED " .. fails))
      client.exit()
      return
    end
    if stepStart == 0 then stepStart = f end
    local t = f - stepStart
    if st.fn(s, f, t) then
      K.log(string.format("[%d] %s (phase %d state %d)", f, st.name, phase(), boxState()))
      si = si + 1
      stepStart = 0
    elseif t > 2000 then
      K.log("TIMEOUT in step " .. st.name .. " phase " .. phase() .. " state " .. boxState())
      K.shot("timeout")
      client.exit()
    end
  end)
end
return K, { tr32 = tr32, phase = phase, boxState = boxState, press = press, step = step, check = check,
  writes = writes, annId = annId, advanceTo = advanceTo, waitFor = waitFor, readThrough = readThrough,
  after = after, talk = talk, closed = closed, choose = choose, run = run }
