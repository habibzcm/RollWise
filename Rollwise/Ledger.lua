-- Rollwise / Ledger: the live model. One entry per item being rolled on.
--
-- An entry moves through stages:
--   open      the game's roll window for it is up
--   waiting   the window closed (you chose, or you can't roll); results are still coming
--   decided   a winner, or nobody; it stays on the board for a little while
--   settled   off the board, into the recent tray
--
-- Facts come from the game's loot history first. Each history roll carries a state, and the
-- state is where main spec and off spec come from: the game decides which one a Need counts
-- as, Rollwise just shows it. Chat lines are only used for entries the history doesn't list.

local _, RW = ...
local Safe, api = RW.Safe, RW.Safe.api
local HIDDEN = Safe.HIDDEN
local History = Safe.lib("C_LootHistory")

local Ledger = { live = {}, tray = {}, serial = 0 }
RW.Ledger = Ledger

local TRAY_SIZE = 8
local NO_RESULT_GRACE = 25   -- seconds past the deadline before giving up on a result
local ORPHAN_AGE = 300

local function now() return Safe.Plain(api.GetTime()) or 0 end

local function windowKnown(rollID)
  for _, e in ipairs(Ledger.live) do
    if e.rollID == rollID then return true end
  end
  return false
end

local function asLink(v)
  v = Safe.Plain(v)
  if type(v) == "string" and v ~= "" then return v end
end

local function positive(v)
  v = Safe.Plain(v)
  return (type(v) == "number" and v > 0) and v or nil
end
Ledger.Now = now

function RW.After(delay, fn)
  local timer = C_Timer and C_Timer.After
  local run = function() local ok, err = pcall(fn) if not ok then RW.Note("timer", err) end end
  if timer then timer(delay, run) else run() end
end

------------------------------------------------------------------------------------------------
-- Choices, tiers, groups
------------------------------------------------------------------------------------------------

-- The game's EncounterLootDropRollState values, read from its enum when it has one.
local FROM_STATE = {}
for name, meaning in pairs({ NeedMainSpec = { 0, "need", "main" }, NeedOffSpec = { 1, "need", "off" },
    Transmog = { 2, "tmog" }, Greed = { 3, "greed" }, Pass = { 5, "pass" } }) do
  local enum = Enum and Enum.EncounterLootDropRollState
  local value = enum and enum[name]
  if value == nil then value = meaning[1] end
  FROM_STATE[value] = { meaning[2], meaning[3] }
end
-- NoRoll and anything new: still deciding.

function Ledger.Decode(state)
  local hit = FROM_STATE[Safe.Plain(state)]
  if hit then return hit[1], hit[2] end
end

-- The game's order: main spec Need, off spec Need, transmog, Greed. Lower is stronger.
function Ledger.Tier(p)
  local c = p.choice
  if c == "need" then return p.spec == "off" and 2 or 1 end
  if c == "tmog" then return 3 end
  if c == "greed" then return 4 end
end

-- Display groups, strongest first. "need" is a Need whose spec isn't known (chat only).
Ledger.GROUPS = { "main", "need", "off", "tmog", "greed" }
Ledger.GROUP_TITLE = { main = "Need · main spec", need = "Need", off = "Need · off spec", tmog = "Transmog", greed = "Greed" }

local KNOWN_SPEC = { main = true, off = true }
function Ledger.GroupOf(p)
  if p.choice == "need" then return KNOWN_SPEC[p.spec] and p.spec or "need" end
  if p.choice == "tmog" or p.choice == "greed" then return p.choice end
end

function Ledger.IsYou(p)
  if p == nil then return false end
  return p.you == true or (p.name ~= nil and p.name == RW.Me())
end

------------------------------------------------------------------------------------------------
-- Entries and seats
------------------------------------------------------------------------------------------------

local function create(link)
  Ledger.serial = Ledger.serial + 1
  local e = { serial = Ledger.serial, link = link, itemID = Safe.ItemID(link), picks = {},
    stage = "waiting", born = now() }
  Ledger.live[#Ledger.live + 1] = e
  return e
end
Ledger.Create = create

-- The pick for a player on this entry, added if new.
function Ledger.Seat(e, name, class, you)
  if you then name = name or RW.Me() or YOU or "You" end
  for _, p in ipairs(e.picks) do
    if (name and p.name == name) or (you and p.you) then
      if you then p.you = true end
      p.cls = p.cls or class
      return p
    end
  end
  local p = { name = name, cls = class or RW.ClassOf(name), you = you or nil }
  if you and not p.cls then p.cls = RW.MyClass() end
  e.picks[#e.picks + 1] = p
  return p
end

-- Best live entry for an item: an exact link beats the same item ID; then the oldest.
local function bestLive(itemID, link, accept)
  local best, bestScore
  for _, e in ipairs(Ledger.live) do
    if e.itemID and e.itemID == itemID and accept(e) then
      local score = (link and e.link == link and 0 or 10000) + e.serial
      if not bestScore or score < bestScore then best, bestScore = e, score end
    end
  end
  return best
end

local function pending(e) return e.stage == "open" or e.stage == "waiting" end

local function claimedBy(enc, key)
  for _, e in ipairs(Ledger.live) do
    if e.enc == enc and e.key == key then return e end
  end
end

function Ledger:Changed() RW.Emit("LEDGER") end

------------------------------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------------------------------

function Ledger:Decide(e)
  if e.stage == "decided" then RW.Emit("REVISED", e) return end
  if e.stage == "settled" or not (e.winner or e.nobody) then return end
  e.stage = "decided"
  e.decidedAt = now()
  RW.Emit("DECIDED", e)
end

function Ledger.Leader(e)
  if e.winner then return e.winner end
  if e.leaderName then
    for _, p in ipairs(e.picks) do if p.name == e.leaderName then return p end end
  end
  local best, bestTier
  for _, p in ipairs(e.picks) do
    local tier = Ledger.Tier(p)
    if tier and p.roll and (not best or tier < bestTier or (tier == bestTier and p.roll > best.roll)) then
      best, bestTier = p, tier
    end
  end
  return best
end

-- Your chance to win, 0..1, from what is known so far. Nil when you haven't chosen.
function Ledger.Odds(e)
  local me
  for _, p in ipairs(e.picks) do if Ledger.IsYou(p) then me = p end end
  if not me or not me.choice then return nil end
  if e.winner then return me.won and 1 or 0 end
  if e.nobody then return 0 end
  local mine = Ledger.Tier(me)
  if not mine then return 0 end
  local rivals, unknown, beaten, tied = 0, me.roll == nil, 0, 0
  for _, p in ipairs(e.picks) do
    if p ~= me then
      local tier = Ledger.Tier(p)
      if tier and tier < mine then return 0 end
      if tier == mine then
        rivals = rivals + 1
        if p.roll == nil then unknown = true
        elseif me.roll and p.roll > me.roll then beaten = beaten + 1
        elseif me.roll and p.roll == me.roll then tied = tied + 1 end
      end
    end
  end
  if not unknown then
    if beaten > 0 then return 0 end
    return 1 / (tied + 1)
  end
  return 1 / (rivals + 1)
end

-- Sections for display: { { group, picks }, ... } strongest first, plus passes and deciding.
function Ledger.Sections(e)
  local byGroup, passed, deciding = {}, {}, {}
  for _, p in ipairs(e.picks) do
    local g = Ledger.GroupOf(p)
    if g then
      byGroup[g] = byGroup[g] or {}
      table.insert(byGroup[g], p)
    elseif p.choice == "pass" then
      passed[#passed + 1] = p
    else
      deciding[#deciding + 1] = p
    end
  end
  local sections = {}
  local function highFirst(a, b)
    local wa, wb = a.won and 1 or 0, b.won and 1 or 0
    if wa == wb then
      local diff = (a.roll or 0) - (b.roll or 0)
      if diff == 0 then return (a.name or "") < (b.name or "") end
      return diff > 0
    end
    return wa > wb
  end
  for _, g in ipairs(Ledger.GROUPS) do
    if byGroup[g] then
      table.sort(byGroup[g], highFirst)
      sections[#sections + 1] = { group = g, picks = byGroup[g] }
    end
  end
  local byName = function(a, b) return (a.name or "") < (b.name or "") end
  table.sort(passed, byName)
  table.sort(deciding, byName)
  return sections, passed, deciding
end

function Ledger.Tally(e)
  local t = { need = 0, main = 0, off = 0, greed = 0, tmog = 0, pass = 0, deciding = 0 }
  for _, p in ipairs(e.picks) do
    local c = p.choice or "deciding"
    t[c] = t[c] + 1
    if c == "need" and p.spec then t[p.spec] = t[p.spec] + 1 end
  end
  return t
end

------------------------------------------------------------------------------------------------
-- Reading the game's loot history
------------------------------------------------------------------------------------------------

local DROP_FIELDS = { "lootListKey", "itemHyperlink", "playerRollState", "currentLeader", "isTied",
  "winner", "allPassed", "rollInfos", "startTime" }
local ROLL_FIELDS = { "playerName", "playerClass", "isSelf", "state", "isWinner", "roll" }
local WHO_FIELDS = { "playerName", "playerClass", "isSelf" }

local function readRoll(raw)
  local r = Safe.Read(raw, ROLL_FIELDS)
  if type(r) ~= "table" then return nil, true end
  local you = Safe.Plain(r.isSelf) == true
  local name = Safe.Person(r.playerName)
  if you and name then RW.LearnMe(name) end
  if not name and not you then return nil, true end
  local choice, spec = Ledger.Decode(r.state)
  local roll = Safe.Plain(r.roll)
  return {
    name = name or RW.Me() or "You",
    cls = Safe.Plain(r.playerClass),
    you = you or nil,
    choice = choice, spec = spec,
    roll = tonumber(roll),
    won = Safe.Plain(r.isWinner) == true or nil,
    veiled = (r.state == HIDDEN or r.roll == HIDDEN) or nil,
  }, false
end

function Ledger:Absorb(e, raw)
  local d = Safe.Read(raw, DROP_FIELDS)
  if type(d) ~= "table" then e.veiled = true return end
  local link = asLink(d.itemHyperlink)
  if link then
    e.link, e.itemID = link, Safe.ItemID(link) or e.itemID
  end
  e.fromLedger = true
  e.boss = e.boss or RW.Journal.BossName(e.enc)

  local incoming, missing = {}, d.rollInfos == HIDDEN
  for _, raw in ipairs(Safe.Items(Safe.Plain(d.rollInfos))) do
    local p, lost = readRoll(raw)
    if p then incoming[#incoming + 1] = p end
    missing = missing or lost
  end
  e.veiled = missing or nil
  if #incoming > 0 then
    for _, p in ipairs(incoming) do
      for _, old in ipairs(e.picks) do
        if old.name == p.name or (p.you and old.you) then
          p.roll = p.roll or old.roll
          p.cls = p.cls or old.cls
          if not p.choice then p.choice, p.spec = old.choice, old.spec end
        end
      end
      p.cls = p.cls or RW.ClassOf(p.name)
    end
    e.picks = incoming
    e.listed = true
  end

  local myChoice, mySpec = Ledger.Decode(d.playerRollState)
  if myChoice then
    local me = Ledger.Seat(e, RW.Me(), nil, true)
    if not me.choice then me.choice, me.spec = myChoice, mySpec end
  end

  local lead = Safe.Read(Safe.Plain(d.currentLeader), WHO_FIELDS)
  e.leaderName = type(lead) == "table" and Safe.Person(lead.playerName) or nil
  e.tied = Safe.Plain(d.isTied) == true or nil

  if d.winner == HIDDEN then e.veiled = true end
  local w = Safe.Read(Safe.Plain(d.winner), WHO_FIELDS)
  local wName = type(w) == "table" and Safe.Person(w.playerName) or nil
  local wYou = type(w) == "table" and Safe.Plain(w.isSelf) == true
  e.winner = nil
  for _, p in ipairs(e.picks) do
    if p.won or (wName and p.name == wName) or (wYou and p.you) then p.won = true e.winner = p end
  end
  if not e.winner and (wName or wYou) then
    local p = Ledger.Seat(e, wName, Safe.Plain(w.playerClass), wYou)
    p.won = true
    e.winner = p
  end
  e.nobody = Safe.Plain(d.allPassed) == true or nil
  self:Decide(e)
end

-- The history drop that best fits an entry that has none yet: same item, not finished, not
-- taken by another entry, and started closest to now.
function Ledger:FindHistory(e)
  local clock = Safe.Plain(History.GetLootHistoryTime())
  local best, bestCost
  for _, fight in ipairs(Safe.Items(Safe.Plain(History.GetAllEncounterInfos()))) do
    local info = Safe.Read(fight, { "encounterID" })
    local enc = type(info) == "table" and Safe.Plain(info.encounterID) or nil
    if enc then
      for _, raw in ipairs(Safe.Items(Safe.Plain(History.GetSortedDropsForEncounter(enc)))) do
        local d = Safe.Read(raw, { "lootListKey", "itemHyperlink", "winner", "allPassed", "startTime" })
        local key = type(d) == "table" and Safe.Plain(d.lootListKey) or nil
        local finished = type(d) == "table" and (d.winner ~= nil or Safe.Plain(d.allPassed) == true)
        if key and not finished and not claimedBy(enc, key) then
          local link = Safe.Plain(d.itemHyperlink)
          local exact = type(link) == "string" and link == e.link
          if exact or Safe.ItemID(link) == e.itemID then
            local started = Safe.Plain(d.startTime)
            local cost = (exact and 0 or 1e6) + ((clock and started) and math.abs(clock - started) or 1e3)
            if not bestCost or cost < bestCost then best, bestCost = { enc = enc, key = key, raw = raw }, cost end
          end
        end
      end
    end
  end
  return best
end

function Ledger:OnHistory(enc, key)
  enc, key = Safe.Plain(enc), Safe.Plain(key)
  if not (enc and key) then return end
  local raw = History.GetSortedInfoForDrop(enc, key)
  if raw == nil or raw == HIDDEN then return end
  local e = claimedBy(enc, key)
  if not e then
    local d = Safe.Read(raw, { "itemHyperlink", "winner", "allPassed" })
    if type(d) ~= "table" then return end
    local link = asLink(d.itemHyperlink)
    e = bestLive(Safe.ItemID(link), link, function(x) return x.enc == nil and pending(x) end)
    if not e then
      if d.winner ~= nil or Safe.Plain(d.allPassed) == true then return end -- already over: not news
      e = create(link)
      e.spectator = true -- rolling for others; you have no window for it
      RW.Emit("APPEARED", e)
    end
    e.enc, e.key = enc, key
  end
  self:Absorb(e, raw)
  self:Changed()
end

------------------------------------------------------------------------------------------------
-- The game's roll windows
------------------------------------------------------------------------------------------------

local function seatGroup(e)
  if e.listed or #e.picks > 0 or not Safe.Plain(api.IsInGroup()) then return end
  for name, class in pairs(RW.Group()) do
    Ledger.Seat(e, name, class or nil, name == RW.Me())
  end
  Ledger:Changed()
end

function Ledger:OnWindow(rollID, millis)
  rollID = Safe.Plain(rollID)
  if rollID == nil or windowKnown(rollID) then return end
  local link = asLink(api.GetLootRollItemLink(rollID))
  local id = Safe.ItemID(link)
  local e = bestLive(id, link, function(x) return x.rollID == nil and pending(x) end)
  if not e then
    e = create(link)
    local hit = self:FindHistory(e)
    if hit then
      e.enc, e.key = hit.enc, hit.key
      self:Absorb(e, hit.raw)
    end
  end
  e.spectator = nil
  e.rollID = rollID
  if pending(e) then e.stage = "open" end
  local ms = positive(millis) or positive(api.GetLootRollTimeLeft(rollID)) or 60000
  e.duration = ms / 1000
  e.deadline = now() + e.duration
  local icon, _, _, quality, bindsOnPickup = api.GetLootRollItemInfo(rollID)
  e.icon = Safe.Plain(icon) or e.icon
  e.quality = Safe.Plain(quality) or e.quality
  local bop = Safe.Plain(bindsOnPickup)
  if bop ~= nil then e.bop = bop and true or false end
  RW.After(0.8, function() seatGroup(e) end)
  RW.Emit("APPEARED", e)
  self:Changed()
end

function Ledger:OnWindowGone(rollID)
  rollID = Safe.Plain(rollID)
  for _, e in ipairs(self.live) do
    if rollID == nil or e.rollID == rollID then
      if e.stage == "open" then e.stage = "waiting" end
    end
  end
  self:Changed()
end

------------------------------------------------------------------------------------------------
-- Chat lines (decoded by Chatter)
------------------------------------------------------------------------------------------------

-- info: { what = "choice"|"number"|"result"|"nobody", choice, who, you, link, roll }
function Ledger:OnChat(info)
  local id = Safe.ItemID(info.link)
  if not id then return end
  local t = now()
  local e = bestLive(id, info.link, function(x)
    if x.listed or x.preview then return false end
    return pending(x) or (x.stage == "decided" and t - (x.decidedAt or t) < 15)
  end)
  if not e then return end
  e.viaChat = true
  if info.what == "nobody" then
    e.nobody = true
  else
    local p = Ledger.Seat(e, info.who, nil, info.you)
    if info.what == "result" then
      p.won = true
      e.winner = p
    else
      if info.choice and (p.choice == nil or info.what == "number") then
        if p.choice ~= info.choice then p.spec = nil end
        p.choice = info.choice
      end
      if info.roll then p.roll = info.roll end
    end
  end
  self:Decide(e)
  self:Changed()
end

------------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------------

-- isUp(e): is the game's window for this entry still on screen (Cards knows).
function Ledger:Tick(hovering, isUp)
  local t, moved = now(), false
  local hold = RW.Opt("holdTime") or 10
  for i = #self.live, 1, -1 do
    local e = self.live[i]
    if pending(e) then
      if e.stage == "open" and e.deadline and t > e.deadline + 2 and not isUp(e) then e.stage = "waiting" moved = true end
      if e.deadline and t > e.deadline + NO_RESULT_GRACE then
        e.stage, e.unseen, e.decidedAt = "decided", true, t
        moved = true
      elseif not e.deadline and t - e.born > ORPHAN_AGE then
        table.remove(self.live, i)
        moved = true
      end
    elseif e.stage == "decided" then
      if hovering then e.decidedAt = math.max(e.decidedAt or t, t) end
      if t - (e.decidedAt or t) > hold and not isUp(e) then
        e.stage = "settled"
        table.remove(self.live, i)
        if not e.preview and not e.unseen then
          table.insert(self.tray, e)
          while #self.tray > TRAY_SIZE do table.remove(self.tray, 1) end
          RW.Emit("TRAY_SHOW")
        end
        moved = true
      end
    end
  end
  return moved
end

function Ledger:Dismiss(e)
  if e then e.dismissed = true
  else for _, x in ipairs(self.live) do x.dismissed = true end end
  self:Changed()
end

function Ledger:Recall(e)
  for _, x in ipairs(self.live) do if x == e then x.dismissed = nil x.decidedAt = now() + 15 self:Changed() return end end
  for i, x in ipairs(self.tray) do
    if x == e then table.remove(self.tray, i) break end
  end
  e.stage, e.dismissed, e.decidedAt = "decided", nil, now() + 15
  table.insert(self.live, e)
  table.sort(self.live, function(a, b) return a.serial < b.serial end)
  self:Changed()
end

------------------------------------------------------------------------------------------------
-- Game events
------------------------------------------------------------------------------------------------

RW.OnGame("START_LOOT_ROLL", function(rollID, millis) Ledger:OnWindow(rollID, millis) end)
RW.OnGame("CANCEL_LOOT_ROLL", function(rollID) Ledger:OnWindowGone(rollID) end)
RW.OnGame("CANCEL_ALL_LOOT_ROLLS", function() Ledger:OnWindowGone(nil) end)
RW.OnGame("LOOT_HISTORY_UPDATE_DROP", function(enc, key) Ledger:OnHistory(enc, key) end)

-- Windows that are already up when the UI loads (a /reload in the middle of a roll).
RW.OnGame("PLAYER_ENTERING_WORLD", function()
  RW.Me()
  local ids = Safe.Plain(api.GetActiveLootRollIDs())
  for _, rollID in ipairs(type(ids) == "table" and ids or {}) do Ledger:OnWindow(rollID) end
end)
