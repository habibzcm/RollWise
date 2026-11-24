-- Rollwise / Safe
-- Inside instances the modern client may hand addons "secret" values it doesn't want them to
-- read. Rollwise never drops those silently: they become HIDDEN, so the board can say
-- "hidden by the game" instead of pretending nothing happened.

local ADDON, RW = ...
Rollwise = RW
RW.addon = ADDON or "Rollwise"

local Safe = {}
RW.Safe = Safe

local secretTest = issecretvalue or function() return false end

-- A function value: it can never be mistaken for a string, number or table from the game.
local HIDDEN = function() end
Safe.HIDDEN = HIDDEN

function Safe.Wrap(v)
  if secretTest(v) then return HIDDEN end
  return v
end

-- The value when it's readable, otherwise nil.
function Safe.Plain(v)
  if v == HIDDEN or secretTest(v) then return nil end
  return v
end

function Safe.IsHidden(v) return v == HIDDEN or secretTest(v) end

local function collect(success, ...)
  if success ~= true then return end
  local count = select("#", ...)
  if count == 0 then return end
  if count == 1 then return Safe.Wrap((...)) end
  local list = { ... }
  for i = 1, count do list[i] = Safe.Wrap(list[i]) end
  return unpack(list, 1, count)
end

-- Safe.api.UnitName("player") etc.: looked up on first use, never errors, hidden values
-- come back as HIDDEN.
local function proxy(lookup)
  return setmetatable({}, { __index = function(cache, name)
    local fn = lookup(name)
    local guarded
    if type(fn) == "function" then
      guarded = function(...) return collect(pcall(fn, ...)) end
    else
      guarded = function() return nil end
    end
    rawset(cache, name, guarded)
    return guarded
  end })
end

Safe.api = proxy(function(name) return _G[name] end)

local libs = {}
-- Safe.lib("C_LootHistory").GetSortedInfoForDrop(...)
function Safe.lib(space)
  libs[space] = libs[space] or proxy(function(name)
    local t = _G[space]
    return type(t) == "table" and t[name] or nil
  end)
  return libs[space]
end

-- Copies chosen fields of a game table into a fresh table of our own.
function Safe.Read(t, fields)
  if secretTest(t) then return HIDDEN end
  if type(t) ~= "table" then return nil end
  local copy = {}
  for _, field in ipairs(fields) do
    local ok, v = pcall(function() return t[field] end)
    if ok then copy[field] = Safe.Wrap(v) end
  end
  return copy
end

-- The items of a game array, each one wrapped.
function Safe.Items(t)
  if secretTest(t) or type(t) ~= "table" then return {} end
  local items, i = {}, 1
  while true do
    local ok, v = pcall(function() return t[i] end)
    if not ok or v == nil then break end
    items[i] = Safe.Wrap(v)
    i = i + 1
  end
  return items
end

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------

-- Visible text of a string with WoW escape codes (colours, links, textures) taken out.
function Safe.Visible(s)
  if type(s) ~= "string" then return nil end
  local out, i, len = {}, 1, #s
  while i <= len do
    local bar = s:find("|", i, true)
    if not bar then out[#out + 1] = s:sub(i) break end
    out[#out + 1] = s:sub(i, bar - 1)
    local code = s:sub(bar + 1, bar + 1)
    if code == "c" then i = bar + 10
    elseif code == "r" or code == "h" then i = bar + 2
    elseif code == "H" then
      local close = s:find("|h", bar + 2, true)
      i = close and close + 2 or len + 1
    elseif code == "T" or code == "A" then
      local close = s:find("|" .. code:lower(), bar + 2, true)
      i = close and close + 2 or len + 1
    elseif code == "|" then out[#out + 1] = "|" i = bar + 2
    else out[#out + 1] = "|" i = bar + 1 end
  end
  return table.concat(out)
end

-- A player's short name: the last word of the visible text, brackets and realm removed.
function Safe.Person(s)
  s = Safe.Visible(Safe.Plain(s))
  if not s then return nil end
  local dash = s:find("-", 1, true) -- names never contain one: the realm starts here
  if dash then s = s:sub(1, dash - 1) end
  s = s:gsub("[%[%]]", " ")
  local last
  for word in s:gmatch("[^%s:]+") do last = word end
  return last
end

------------------------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------------------------

local item = Safe.lib("C_Item")

function Safe.ItemID(thing)
  thing = Safe.Plain(thing)
  if type(thing) == "number" then return thing end
  if type(thing) ~= "string" then return nil end
  local id = Safe.Plain(item.GetItemInfoInstant(thing))
  if type(id) == "number" then return id end
  local at = thing:find("item:", 1, true)
  if not at then return nil end
  local stop = thing:find(":", at + 5, true) or thing:find("|", at + 5, true) or (#thing + 1)
  return tonumber(thing:sub(at + 5, stop - 1))
end

-- Facts about an item: { id, icon, slot (equip location), kind, level, quality, name }.
function Safe.ItemFacts(thing)
  local facts = { id = Safe.ItemID(thing) }
  if not facts.id then return facts end
  local _, kind, sub, slot, icon = item.GetItemInfoInstant(thing)
  facts.kind = Safe.Plain(sub) or Safe.Plain(kind)
  facts.slot = Safe.Plain(slot)
  facts.icon = Safe.Plain(icon) or Safe.Plain(item.GetItemIconByID(facts.id))
  facts.quality = Safe.Plain(item.GetItemQualityByID(facts.id))
  local lvl = Safe.Plain(item.GetDetailedItemLevelInfo(thing))
  if type(lvl) ~= "number" then
    local info = { Safe.lib("C_Item").GetItemInfo(thing) }
    lvl = Safe.Plain(info[4])
  end
  facts.level = type(lvl) == "number" and lvl or nil
  return facts
end

function Safe.LinkText(link)
  link = Safe.Plain(link)
  if not (type(link) == "string") then return "?" end
  local open = link:find("[", 1, true)
  local close = link:find("]", (open or 0) + 1, true)
  if open and close then return link:sub(open + 1, close - 1) end
  return Safe.Visible(link) or link
end
