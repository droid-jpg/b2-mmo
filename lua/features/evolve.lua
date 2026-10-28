-- Black 2 MMO feature: trade evolutions. See "Features" in lua/b2mmo.lua for the hooks and the api.
--
-- A trade put a Pokemon in our party (onTradeDone): the in-game code (arm/evolve.c) asks the game's
-- own check whether it evolves by trade. If it does: "X sent over Y!" (in the game's text box when
-- api.gameMessage is there, else a notice), then the game's evolution scene on that slot.
-- The core's own evolution notice (same PID, new species) tells us and our friends what it became.
local EV = 0x01FFF600 -- MMO_EVOLVE_AREA (arm/evolve.h)
local REQ, CHECKS, SPECIES, METHOD, GO, STARTED, FINISHED, PARTNER = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x20

return function(api)
  -- pending: { slot, pid, species, label, from, checks, state = "check" | "message" | "scene" }
  local pending = nil

  local function go()
    if not pending or pending.state ~= "message" then return end
    pending.state, pending.finished = "scene", api.ir32(EV + FINISHED)
    api.iw32(EV + GO, pending.slot)
  end

  local function onTradeDone(slot, theirRaw, myRaw, partner)
    local m = api.PKM.decode(theirRaw)
    if not m or m.isEgg then return end
    api.iwBytes(EV + PARTNER, myRaw:sub(1, 0xDC))
    pending = { slot = slot, pid = m.pid, species = m.species, label = api.monLabel(theirRaw),
      from = api.friends[partner] and api.friends[partner].name or "Your friend",
      checks = api.ir32(EV + CHECKS), state = "check", at = api.now() }
    api.iw32(EV + REQ, slot)
  end

  local function tick()
    if not pending then return end
    -- The core reports an evolution when a PID it knows shows another species: make sure it knows this one
    if pending.state ~= "done" and api.seen.party[pending.pid] == nil then api.seen.party[pending.pid] = pending.species end
    if pending.state == "check" then
      if api.ir32(EV + CHECKS) == pending.checks then return end
      local into = api.ir32(EV + SPECIES)
      if into == 0 then pending = nil return end
      pending.into, pending.state, pending.at = into, "message", api.now()
      local text = pending.from .. " sent over " .. pending.label .. "!"
      if not (api.gameMessage and api.gameMessage(text, nil, go)) then
        api.addNotice(text)
        go()
      end
    elseif pending.state == "message" then
      -- The message's answer starts the scene; don't hang on a box that never answers
      if api.now() - pending.at > 60000 then go() end
    elseif pending.state == "scene" then
      if api.ir32(EV + FINISHED) ~= pending.finished then pending.state, pending.at = "done", api.now() end
    elseif pending.state == "done" then
      -- Keep the PID known until the core's next party scan has seen the new species
      if api.seen.party[pending.pid] ~= pending.species or api.now() - pending.at > 10000 then pending = nil end
    end
  end

  return { onTradeDone = onTradeDone, tick = tick }
end
