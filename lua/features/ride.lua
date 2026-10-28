-- Black 2 MMO feature: friends biking and surfing. See "Features" in lua/b2mmo.lua for the hooks and the api.
--
-- A friend's actor already wears their own player object code (the core writes their STATE model
-- into the slot), so a biking friend shows the game's cycling form by itself. This file:
--   - tells the in-game code (arm/ride.c, MMO_RIDE_AREA) which slots surf (STATE status bit 2),
--     and it puts the game's surf Pokemon under them;
--   - only lets the player's own object codes through (231..248: Nate's and Rosa's forms); any
--     other code a friend sends falls back to their walking form, so an odd code never reaches
--     the game's actor system.
return function(api)
  local RIDE = api.ADDR.ride
  local SLOT0, SLOTSZ, NSLOTS = api.SH + 0x80, 0x30, 8
  local HERO, HEROINE = api.OBJ_HERO, api.OBJ_HEROINE

  -- field_player.c PLAYER_SPRITE_MAP: walk, cycle, surf/dive, then six more forms, for each sex
  local function playerSex(code)
    if code >= HERO and code < HEROINE then return 0 end
    if code >= HEROINE and code <= HEROINE + 8 then return 1 end
    return nil
  end

  return {
    tick = function()
      local surf = {}
      for _, f in pairs(api.friends) do
        if f.slot then
          local code = f.model
          local sex = playerSex(code)
          if sex then
            f.rideSex = sex
          elseif code ~= 0 then
            -- Not one of the player's forms: show their walking form (the sex we last saw, or Nate)
            api.iw32(SLOT0 + f.slot * SLOTSZ + 0x04, (f.rideSex == 1) and HEROINE or HERO)
          end
          if f.status & 4 ~= 0 then surf[f.slot] = 1 end
        end
      end
      for i = 0, NSLOTS - 1 do api.iw32(RIDE + i * 4, surf[i] or 0) end
    end,
  }
end
