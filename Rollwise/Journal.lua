-- Rollwise / Journal: saved runs (one per dungeon or raid visit), their decided items, the
-- per-player tally and the export formats.

local _, RW = ...
local Safe, api = RW.Safe, RW.Safe.api

local Journal = {}
RW.Journal = Journal

local KEEP_RUNS = 30
local KEEP_ITEMS = 750
local IDLE_SPLIT = 9000 -- seconds: back in the same place after this long counts as a new run

local function wallclock() return Safe.Plain(api.time()) or 0 end

function Journal.Runs() return RollwiseDB and RollwiseDB.runs or {} end

function Journal.Current()
  local runs = Journal.Runs()
  return runs[#runs]
end

function Journal:Begin(place, manual)
  if not RollwiseDB then return end
  place = place or {}
  local t = wallclock()
  local run = { title = place.title or (manual and "New run" or "Open world"), where = place.where,
    mode = place.mode, opened = t, touched = t, items = {} }
  local runs = RollwiseDB.runs
  runs[#runs + 1] = run
  while #runs > KEEP_RUNS do table.remove(runs, 1) end
  RW.Emit("JOURNAL")
  return run
end

-- On zoning: a different instance (or a long break) starts a new run; an empty run is reused.
function Journal:Locate()
  local name, kind, difficulty, modeName, _, _, _, instanceID = api.GetInstanceInfo()
  kind, instanceID = Safe.Plain(kind), Safe.Plain(instanceID)
  if not instanceID or kind == nil or kind == "none" then return end
  local where = instanceID .. ":" .. tostring(Safe.Plain(difficulty) or 0)
  local title = Safe.Plain(name) or "Instance"
  local mode = Safe.Plain(modeName)
  local run = self.Current()
  if run and run.where == where and wallclock() - (run.touched or 0) < IDLE_SPLIT then return end
  if run and #run.items == 0 then
    run.where, run.title, run.mode, run.opened, run.touched = where, title, mode, wallclock(), wallclock()
    RW.Emit("JOURNAL")
    return
  end
  self:Begin({ where = where, title = title, mode = mode })
end

local bossCache = {}
function Journal.BossName(enc)
  if not enc then return nil end
  if bossCache[enc] == nil then
    local info = Safe.Read(Safe.Plain(Safe.lib("C_LootHistory").GetInfoForEncounter(enc)), { "encounterName" })
    local found = type(info) == "table" and Safe.Plain(info.encounterName)
    bossCache[enc] = (found and found ~= "") and found or false
  end
  return bossCache[enc] or nil
end

------------------------------------------------------------------------------------------------
-- Writing decided items
------------------------------------------------------------------------------------------------

local function snapshot(e, page)
  if e.link then page.link = e.link end
  page.itemID = e.itemID or page.itemID
  page.quality = e.quality or page.quality
  page.icon = e.icon or page.icon
  page.boss = page.boss or e.boss or Journal.BossName(e.enc)
  page.source = e.fromLedger and "history" or "chat"
  page.outcome = e.nobody and "nobody" or "won"
  if e.wanted then page.wanted = true end
  local w = e.winner
  page.winner = w and { name = w.name, cls = w.cls, choice = w.choice, spec = w.spec, roll = w.roll,
    you = RW.Ledger.IsYou(w) or nil } or nil
  local picks = {}
  for _, p in ipairs(e.picks) do
    if p.choice or p.won then
      picks[#picks + 1] = { name = p.name, cls = p.cls, choice = p.choice, spec = p.spec, roll = p.roll,
        won = p.won or nil, you = RW.Ledger.IsYou(p) or nil }
    end
  end
  page.picks = picks
end

local function record(e)
  if e.preview or e.unseen or not RollwiseDB then return end
  local run = Journal.Current() or Journal:Begin()
  local page = e.page
  if not page then
    page = { at = wallclock() }
    e.page = page
    run.items[#run.items + 1] = page
    while #run.items > KEEP_ITEMS do table.remove(run.items, 1) end
  end
  snapshot(e, page)
  run.touched = wallclock()
  RW.Emit("JOURNAL")
end

RW.Watch("DECIDED", record)
RW.Watch("REVISED", function(e) if e.page then record(e) end end)
RW.OnGame("PLAYER_ENTERING_WORLD", function() if RollwiseDB then Journal:Locate() end end)

------------------------------------------------------------------------------------------------
-- Reading it back
------------------------------------------------------------------------------------------------

-- Items a player has won in the current run (pages), not counting `skip`.
function Journal.WinsOf(name, skip)
  local list = {}
  local run = Journal.Current()
  if not (run and name) then return list end
  for _, page in ipairs(run.items) do
    if page ~= skip and page.winner and page.winner.name == name then list[#list + 1] = page end
  end
  return list
end

-- Per-player totals for a run, most loot first.
function Journal.Tally(run)
  local rows, index = {}, {}
  local function row(name, cls)
    local r = index[name]
    if not r then
      r = { name = name, cls = cls, wins = 0, mainWins = 0, offWins = 0, otherWins = 0, needs = 0, rolls = 0, pages = {} }
      index[name] = r
      rows[#rows + 1] = r
    end
    r.cls = r.cls or cls
    return r
  end
  for _, page in ipairs(run and run.items or {}) do
    for _, p in ipairs(page.picks or {}) do
      if p.name then
        local r = row(p.name, p.cls)
        if p.choice and p.choice ~= "pass" then r.rolls = r.rolls + 1 end
        if p.choice == "need" then r.needs = r.needs + 1 end
      end
    end
    local w = page.winner
    if w and w.name then
      local r = row(w.name, w.cls)
      r.wins = r.wins + 1
      r.pages[#r.pages + 1] = page
      if w.choice == "need" and w.spec == "off" then r.offWins = r.offWins + 1
      elseif w.choice == "need" then r.mainWins = r.mainWins + 1
      else r.otherWins = r.otherWins + 1 end
    end
  end
  table.sort(rows, function(a, b)
    if a.wins ~= b.wins then return a.wins > b.wins end
    if a.rolls ~= b.rolls then return a.rolls > b.rolls end
    return a.name < b.name
  end)
  return rows, index
end

-- Group members with nothing won this run.
function Journal.EmptyHanded(run)
  local _, index = Journal.Tally(run)
  local out = {}
  for name, class in pairs(RW.Group()) do
    if not index[name] or index[name].wins == 0 then out[#out + 1] = { name = name, cls = class or nil } end
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  return out
end

------------------------------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------------------------------

local function how(w)
  if not w then return "" end
  local text = RW.UI.ChoiceWord(w.choice, w.spec)
  if w.roll then text = text .. " " .. w.roll end
  return text
end

local function counts(page)
  local n, g, p = 0, 0, 0
  for _, x in ipairs(page.picks or {}) do
    if x.choice == "need" then n = n + 1
    elseif x.choice == "greed" or x.choice == "tmog" then g = g + 1
    elseif x.choice == "pass" then p = p + 1 end
  end
  return n, g, p
end

local function csvCell(v)
  v = tostring(v == nil and "" or v)
  if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

Journal.FORMATS = {
  { key = "text", label = "Text" },
  { key = "csv", label = "CSV" },
  { key = "discord", label = "Discord" },
}

function Journal.Export(run, format)
  if not run then return "" end
  local out = {}
  local function add(s) out[#out + 1] = s end
  local stamp = function(t, f) return date(f, t or 0) end
  if format == "csv" then
    add("date,time,instance,boss,item,item_id,winner,class,choice,spec,roll,needs,greeds,passes")
    for _, page in ipairs(run.items) do
      local w, n, g, p = page.winner or {}, counts(page)
      add(table.concat({ stamp(page.at, "%Y-%m-%d"), stamp(page.at, "%H:%M"), csvCell(run.title), csvCell(page.boss),
        csvCell(Safe.LinkText(page.link)), page.itemID or "", csvCell(w.name), w.cls or "",
        page.outcome == "nobody" and "nobody" or (w.choice or ""), w.spec or "", w.roll or "", n, g, p }, ","))
    end
  elseif format == "discord" then
    add(("**%s**%s  ·  %s"):format(run.title or "Run", run.mode and (" (" .. run.mode .. ")") or "", stamp(run.opened, "%b %d, %H:%M")))
    local lastBoss
    for _, page in ipairs(run.items) do
      if page.boss ~= lastBoss then add("") add("__" .. (page.boss or "Trash") .. "__") lastBoss = page.boss end
      local w = page.winner
      local who = page.outcome == "nobody" and "*everyone passed*" or ("**" .. (w and w.name or "?") .. "** - " .. how(w))
      add(("- %s -> %s"):format(Safe.LinkText(page.link), who))
    end
  else
    add(("%s  -  %s"):format(run.title or "Run", stamp(run.opened, "%Y-%m-%d %H:%M")))
    add("")
    for _, page in ipairs(run.items) do
      local w = page.winner
      local who = page.outcome == "nobody" and "everyone passed" or ((w and w.name or "?") .. " (" .. how(w) .. ")")
      add(("%s  %s  %s: %s"):format(stamp(page.at, "%H:%M"), Safe.LinkText(page.link), page.boss or "-", who))
    end
  end
  return table.concat(out, "\n")
end
