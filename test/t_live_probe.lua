-- Probe (exploration): battle the fake friend's team (AI) and watch the battle code's hooks.
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "lib.lua")
local SB = "ARM9 System Bus"
local function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", memory.read_u8(a + i, SB)) end
  return table.concat(t)
end
local regsLogged = false
local function regs()
  local r = emu.getregisters()
  if not regsLogged then
    regsLogged = true
    local ks = {}
    for k, v in pairs(r) do ks[#ks + 1] = k end
    table.sort(ks)
    K.log("regs: " .. table.concat(ks, ","))
  end
  return r
end
local function reg(r, n) return r["ARM9 r" .. n] or r["R" .. n] or r["r" .. n] or 0 end
local started = false
gotSetup = false
local nSet = 0
K.start({}, function(s, f)
  if f == 5 then K.dumpParty(s, K.env.out .. "party.bin"); K.log("party: " .. K.party(s)) end
  if f == 10 then
    K.log("buildSeed " .. hex(0x02044098, 16))
    K.log("ov167 WaitCmd " .. hex(0x021d4b18, 8) .. " AllRep " .. hex(0x0219f19c, 8))
    K.log("vram SortBySpeed " .. hex(0x0689d0ac, 8))
    event.onmemoryexecute(function()
      local r = regs()
      K.log(string.format("f%d buildSeed r0=%08X lr=%08X", emu.framecount(), reg(r, 0), reg(r, 14)))
      K.log("  WaitCmd " .. hex(0x021d4b18, 16) .. " AllRep " .. hex(0x0219f19c, 16))
      K.log("  SetCmd " .. hex(0x021d4aec, 16) .. " AOSort " .. hex(0x021a0308, 16))
      K.log("  SortBySpeed " .. hex(0x0689d0ac, 16))
      K.log("  calc " .. hex(0x021dd844, 32))
      K.log("  expcheck " .. hex(0x0219bdfc, 16))
      K.log("  waitcmd full " .. hex(0x021d4b18, 0x36) .. " setret " .. hex(0x021d4c38, 0x2c))
    end, 0x02044098, "seed", SB)
    event.onmemoryexecute(function()
      local r = regs()
      local ad, data, size = reg(r, 0), reg(r, 1), reg(r, 2)
      nSet = nSet + 1
      if nSet < 80 then
        K.log(string.format("f%d SetReturnData ad=%08X data=%08X size=%d client=%d state=%d cmd=%d words=%s", emu.framecount(), ad, data, size,
          memory.read_u8(ad + 0xD, SB), memory.read_u8(ad + 0xE, SB), memory.read_u8(ad + 0xF, SB), size <= 24 and hex(data, size) or "?") .. " flags=" .. string.format("%02X", memory.read_u8(ad + 0xC, SB)))
        if nSet == 6 then K.log("  calc after init " .. hex(0x021dd844, 32)) end
      end
    end, 0x021d4c38, "setret", SB)
    event.onmemoryexecute(function()
      local r = regs()
      local st = reg(r, 0)
      if not gotSetup then gotSetup = true; K.log(string.format("setup %08X: %s", st, hex(st, 0xC0))); local c = memory.read_u32_le(st + 0x74, SB); K.log(string.format("config %08X = %s", c, hex(c, 4))) end
    end, 0x02017D10, "getparty", SB)
  end
  if f == 60 then
    for id, fr in pairs(s.friends) do K.log("friend " .. id .. " " .. fr.name .. " party=" .. tostring(fr.party and #fr.party)) end
  end
  if f == 120 then
    for id, fr in pairs(s.friends) do if fr.party and #fr.party > 0 then s.startBattle(id); started = true; K.log("battle started with " .. id) end end
    if not started then K.log("no friend party"); client.exit() end
  end
  if f > 600 and f % 20 < 3 then joypad.set({ A = true }) end
  if f == 500 or f == 1500 or f == 2500 then K.shot("p" .. f) end
  if f == 3000 then K.shot("end"); client.exit() end
end)
