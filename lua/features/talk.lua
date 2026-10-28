-- Black 2 MMO feature: talk. Talking to a friend in the game's own text box and choice list
-- (arm/talk.c shows them), trading by talking, and api.gameMessage for the other features.
--
-- api.gameMessage(text, choices, onAnswer) shows text in the game's message box (ASCII; "\n" a new
-- line, "\f" a new page; long lines wrap, 2 lines a page, A turns pages), then, if choices (a list
-- of up to 8 strings) is given, the game's choice list beside it. onAnswer(i) gets the 1-based
-- choice, or nil when cancelled with B (and, without choices, nil once the player closed the box
-- with A or B). Returns true when it will be shown (queued until the player is free on the field,
-- one message at a time, in order), false if it can't be (no text, or too many waiting).
-- onAnswer runs once the box has closed and the player is free again (so it can start a battle,
-- or ask the next question with api.gameMessage). A 4th argument { keep = true } makes onAnswer
-- run right away while the box is still up, so a message it asks for continues in the same box.
return function(api)
  local A = api.ADDR.talk
  local REQ, SHOWN, STATE, RESULT, COUNT, CLOSE, ANSWERED, TEXT, CHOICES = 0, 4, 8, 0xC, 0x10, 0x14, 0x1C, 0x20, 0x260
  local TEXT_CHARS, CHOICE_CHARS, MAX_CHOICES = 0x120, 0x18, 8
  local WRAP = 34
  local MAGIC = 0x4D4D3242

  local queue, active, seq, deferred = {}, nil, 0, {}

  -- ASCII/UTF-8 text -> the game's characters (UTF-16): 0xFFFE new line, F000 BE01 0000 a new page
  local function codes(s)
    local out = {}
    local ok = pcall(function() for _, c in utf8.codes(s) do out[#out + 1] = c end end)
    if not ok then out = {}; for i = 1, #s do out[#out + 1] = s:byte(i) end end
    for i, c in ipairs(out) do
      if c < 0x20 or c > 0xFFFD then out[i] = 0x3F end
    end
    return out
  end

  local function encode(text)
    local lines = {}
    for page in (text .. "\f"):gmatch("(.-)\f") do
      local first = true
      for raw in (page .. "\n"):gmatch("(.-)\n") do
        local line = ""
        local function push() lines[#lines + 1] = { s = line, page = first }; first = false; line = "" end
        for word in raw:gmatch("%S+") do
          while #word > WRAP do
            if line ~= "" then push() end
            line = word:sub(1, WRAP); word = word:sub(WRAP + 1); push()
          end
          if line == "" then line = word
          elseif #line + 1 + #word <= WRAP then line = line .. " " .. word
          else push(); line = word end
        end
        push()
      end
    end
    local out, onPage = {}, 0
    for i, l in ipairs(lines) do
      if i > 1 then
        if l.page or onPage >= 2 then
          for _, c in ipairs({ 0xF000, 0xBE01, 0x0000, 0xFFFE }) do out[#out + 1] = c end
          onPage = 0
        else
          out[#out + 1] = 0xFFFE
        end
      end
      for _, c in ipairs(codes(l.s)) do out[#out + 1] = c end
      onPage = onPage + 1
    end
    while #out > TEXT_CHARS - 1 do table.remove(out) end
    return out
  end

  local function post(e)
    local t = encode(e.text)
    for i, c in ipairs(t) do api.iw16(A + TEXT + (i - 1) * 2, c) end
    api.iw16(A + TEXT + #t * 2, 0xFFFF)
    local n = e.choices and math.min(#e.choices, MAX_CHOICES) or 0
    for k = 1, n do
      local cs = codes(tostring(e.choices[k]))
      local base = A + CHOICES + (k - 1) * CHOICE_CHARS * 2
      for i = 1, math.min(#cs, CHOICE_CHARS - 1) do api.iw16(base + (i - 1) * 2, cs[i]) end
      api.iw16(base + math.min(#cs, CHOICE_CHARS - 1) * 2, 0xFFFF)
    end
    api.iw32(A + COUNT, n)
    api.iw32(A + CLOSE, 0)
    seq = math.max(seq, api.ir32(A + REQ), api.ir32(A + SHOWN)) % 0x7FFFFFFF + 1
    e.seq, e.n, e.postedAt = seq, n, emu.framecount()
    active = e
    api.iw32(A + REQ, seq) -- last: the game starts on it
  end

  local function gameMessage(text, choices, onAnswer, opts)
    if type(text) ~= "string" or #queue >= 16 then return false end
    if choices ~= nil and type(choices) ~= "table" then choices = nil end
    if choices and #choices == 0 then choices = nil end
    queue[#queue + 1] = { text = text, choices = choices, cb = onAnswer, keep = opts and opts.keep }
    return true
  end

  local function whenFree(fn) deferred[#deferred + 1] = fn end

  local function run(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then console.log("Black 2 MMO talk: " .. tostring(err)) end
  end

  local function tick()
    if api.ir32(api.SH) ~= MAGIC then return end
    local st = api.ir32(A + STATE)
    if active then
      local e = active
      local shown = api.ir32(A + SHOWN)
      if not e.done and api.ir32(A + ANSWERED) == e.seq and (st == 2 or st == 3) then
        e.done = true
        local r = api.is32(A + RESULT)
        local choice = (r >= 0 and r < e.n) and r + 1 or nil
        if e.cb then
          if e.keep and st == 2 then
            run(e.cb, choice)
          else
            whenFree(function() e.cb(choice) end)
          end
        end
        if st == 2 then
          if #queue > 0 then post(table.remove(queue, 1)) -- the next one, in the same box
          else api.iw32(A + CLOSE, 1) end
        end
      end
      if active == e then
        if st == 3 and shown == e.seq then
          active = nil
        elseif shown ~= e.seq and api.me.ready and emu.framecount() - e.postedAt > 240 then
          -- Never shown though the player is free (something else holds the field): give up on it
          active = nil
          api.iw32(A + REQ, shown)
          if e.cb then whenFree(function() e.cb(nil) end) end
        end
      end
    else
      -- Nothing of ours is up: a request left over (a loaded state) must not pop up
      if api.ir32(A + REQ) ~= api.ir32(A + SHOWN) then api.iw32(A + REQ, api.ir32(A + SHOWN)) end
    end
    if not active and api.me.ready then
      if #deferred > 0 then
        local d = deferred
        deferred = {}
        for _, fn in ipairs(d) do run(fn) end
      end
      if not active and #queue > 0 then post(table.remove(queue, 1)) end
    end
  end

  ------------------------------------------------------------------------------------------
  -- Talking to a friend, trading by talking
  ------------------------------------------------------------------------------------------
  local trade = api.trade
  local ts = { wantAccept = nil, prompted = nil }
  -- "Rainbow (Sigilyph) Lv100" in messages; in a choice list (23 characters) just "Rainbow Lv100"
  local function label(raw) return api.monLabel(raw) end
  local function short(raw)
    local l = api.monLabel(raw)
    if #l <= CHOICE_CHARS - 1 then return l end
    local m = api.PKM.decode(raw)
    if m and m.nickname ~= "" then l = string.format("%s Lv%d", m.nickname, m.level) end
    return l:sub(1, CHOICE_CHARS - 1)
  end
  local names = {}
  local function nameOf(id)
    if api.friends[id] then names[id] = api.friends[id].name end
    return names[id] or "Your friend"
  end
  local function gone(id)
    if api.friends[id] then return false end
    gameMessage(nameOf(id) .. " isn't here anymore.")
    return true
  end

  -- Pick one of ours and offer it; accept = they offered first (offer and accept at once)
  local function pickAndOffer(id, accept)
    local party = api.partyRaw()
    if #party == 0 then gameMessage("You have no Pokemon to trade.") return end
    local labels = {}
    for i, raw in ipairs(party) do labels[i] = short(raw) end
    labels[#labels + 1] = "Cancel"
    gameMessage("Which Pokemon will you trade?", labels, function(i)
      if not i or i > #party then
        if accept then api.cancelTrade(false) end
        return
      end
      if gone(id) then return end
      api.offerTrade(id, i)
      local name = nameOf(id)
      if accept and trade.theirRaw then
        ts.wantAccept = id
        api.acceptTrade()
        gameMessage("You offered " .. label(party[i]) .. " for " .. label(trade.theirRaw) .. ".\nWaiting for " .. name .. "...")
      else
        gameMessage("You offered " .. label(party[i]) .. " to " .. name .. ".\nWaiting for " .. name .. "...")
      end
    end, { keep = true })
  end

  local function offerQuestion(id)
    return nameOf(id) .. " offers " .. label(trade.theirRaw) .. ". Trade?"
  end
  local function onOfferAnswer(id)
    return function(i)
      ts.prompted = nil
      if trade.partner ~= id or not trade.theirRaw then return end
      if i == 1 then pickAndOffer(id, true) else api.cancelTrade(false) end
    end
  end

  local function askOffer(id)
    ts.prompted = id
    gameMessage(offerQuestion(id), { "Yes", "No" }, onOfferAnswer(id), { keep = true })
  end

  local function askConfirm(id)
    ts.prompted = id
    gameMessage("You give " .. label(trade.myRaw) .. "\nYou get " .. label(trade.theirRaw) .. ".\fTrade with " .. nameOf(id) .. "?",
      { "Yes", "No" }, function(i)
        ts.prompted = nil
        if trade.partner ~= id or not trade.myRaw or not trade.theirRaw then return end
        if i == 1 then
          ts.wantAccept = id
          api.acceptTrade()
        else
          api.cancelTrade(false)
        end
      end, { keep = true })
  end

  table.insert(api.actions, { label = "Trade", keep = true, run = function(f, id)
    if trade.partner == id and trade.theirRaw and not trade.myRaw then
      ts.prompted = id
      gameMessage(offerQuestion(id), { "Yes", "No" }, onOfferAnswer(id), { keep = true })
    else
      pickAndOffer(id, false)
    end
  end })

  local function onTalk(f, id)
    nameOf(id)
    local pages = { f.name .. ": " .. (f.greet ~= "" and f.greet or "...") }
    for _, fn in ipairs(api.talkInfo) do
      local ok, s = pcall(fn, f, id)
      if ok and type(s) == "string" and s ~= "" then pages[#pages + 1] = s
      elseif ok and type(s) == "table" then for _, l in ipairs(s) do pages[#pages + 1] = tostring(l) end end
    end
    -- An offer of theirs waiting for an answer: ask that instead
    if trade.partner == id and trade.theirRaw and not trade.myRaw and ts.prompted ~= id then
      pages[#pages + 1] = offerQuestion(id)
      ts.prompted = id
      return gameMessage(table.concat(pages, "\f"), { "Yes", "No" }, onOfferAnswer(id), { keep = true })
    end
    local acts, labels = {}, {}
    for _, a in ipairs(api.actions) do
      local ok, avail = true, true
      if a.available then ok, avail = pcall(a.available, f, id) end
      if ok and avail and #acts < MAX_CHOICES - 1 then acts[#acts + 1] = a; labels[#labels + 1] = a.label end
    end
    labels[#labels + 1] = "Cancel"
    pages[#pages + 1] = "What do you want to do?"
    return gameMessage(table.concat(pages, "\f"), labels, function(i)
      local a = i and acts[i]
      if not a then return end
      if gone(id) then return end
      if a.keep then a.run(api.friends[id], id) else whenFree(function() a.run(api.friends[id] or f, id) end) end
    end, { keep = true })
  end

  local onFrame = {}
  onFrame[api.T.TRADE] = function(f, id, fr)
    local op, target = fr:byte(5), fr:byte(6)
    if op == api.TRADE.COMMIT or (op == api.TRADE.CANCEL and target == api.net.myId) then
      ts.wantAccept, ts.prompted = nil, nil
      return
    end
    if target ~= api.net.myId or op ~= api.TRADE.OFFER or fr:byte(7) ~= fr:byte(8) - 1 then return end
    if trade.partner ~= id or not trade.theirRaw then return end
    if trade.myRaw then
      if ts.wantAccept == id then
        api.acceptTrade() -- they offered (again) after we accepted: accept this one
      elseif not trade.accepted and ts.prompted ~= id then
        askConfirm(id)
      end
    elseif ts.prompted ~= id then
      ts.wantAccept = nil
      askOffer(id) -- right away if we're free, else once we are
    end
  end
  onFrame[api.T.LEAVE] = function(f, id)
    if ts.wantAccept == id then ts.wantAccept = nil end
    if ts.prompted == id then ts.prompted = nil end
  end

  api.gameMessage = gameMessage
  api.whenFree = whenFree
  api.iw32(A + REQ, 0)
  api.iw32(A + SHOWN, 0)
  api.iw32(A + STATE, 0)

  return {
    tick = tick,
    onTalk = onTalk,
    onFrame = onFrame,
    -- for tests
    talk = { queue = queue, active = function() return active end, ts = ts },
  }
end
