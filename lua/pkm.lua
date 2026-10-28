-- Gen 5 Pokemon data as the party stores it: 0xDC bytes, PID @0, checksum @6, four 32-byte blocks
-- @8 encrypted with the checksum and shuffled by the PID, party stats @0x88 encrypted with the PID.
local M = {}

local ORDER = {
  "ABCD", "ABDC", "ACBD", "ACDB", "ADBC", "ADCB", "BACD", "BADC", "BCAD", "BCDA", "BDAC", "BDCA",
  "CABD", "CADB", "CBAD", "CBDA", "CDAB", "CDBA", "DABC", "DACB", "DBAC", "DBCA", "DCAB", "DCBA",
}

local function u16(s, o) return s:byte(o + 1) | (s:byte(o + 2) << 8) end
local function u32(s, o) return u16(s, o) | (u16(s, o + 2) << 16) end

-- XOR the u16 words of s[from, to) with the game's LCG seeded with seed.
local function crypt(s, from, to, seed)
  local out = {}
  for o = from, to - 1, 2 do
    seed = (seed * 0x41C64E6D + 0x6073) & 0xFFFFFFFF
    local w = u16(s, o) ~ (seed >> 16)
    out[#out + 1] = string.char(w & 0xFF, w >> 8)
  end
  return table.concat(out)
end

-- Decodes raw (0xDC bytes, as in RAM). Returns nil for an empty or broken slot.
function M.decode(raw)
  if not raw or #raw < 0xDC then return nil end
  local pid = u32(raw, 0)
  local check = u16(raw, 6)
  if pid == 0 and check == 0 then return nil end
  local blocks = crypt(raw, 8, 0x88, check)
  local sum = 0
  for o = 0, 0x7F, 2 do sum = (sum + u16(blocks, o)) & 0xFFFF end
  if sum ~= check then return nil end
  local order = ORDER[((pid >> 13) & 31) % 24 + 1]
  local function block(letter)
    local i = order:find(letter) - 1
    return blocks:sub(i * 32 + 1, i * 32 + 32)
  end
  local a, b, c = block("A"), block("B"), block("C")
  local stats = crypt(raw, 0x88, 0xDC, pid)
  local nick = {}
  for o = 0, 20, 2 do
    local ch = u16(c, o)
    if ch == 0xFFFF or ch == 0 then break end
    nick[#nick + 1] = ch < 0x80 and string.char(ch) or utf8.char(ch)
  end
  local ivs = u32(b, 0x10)
  return {
    pid = pid,
    species = u16(a, 0),
    item = u16(a, 2),
    isEgg = (ivs >> 30) & 1 == 1,
    nickname = table.concat(nick),
    level = stats:byte(5),
    hp = u16(stats, 6),
    maxHp = u16(stats, 8),
  }
end

-- FNV-1a over a string, as the server and the other games hash trade offers.
function M.fnv(s)
  local h = 0x811C9DC5
  for i = 1, #s do h = ((h ~ s:byte(i)) * 0x01000193) & 0xFFFFFFFF end
  return h
end

return M
