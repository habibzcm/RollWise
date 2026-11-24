-- Rollwise / Chatter: understands the game's loot roll messages, optionally hides some of them,
-- and can print a one-line recap per item.
--
-- How a message is understood:
--   1. Every hyperlink in the line (item, player, loot history) is swapped for a numbered
--      token, so item names can never confuse the matching.
--   2. Each of the game's own message templates (from its global strings, so any language
--      works) is split into fixed pieces and blanks.
--   3. A template matches when its fixed pieces appear in order. If several match, the one
--      with the most fixed text wins ("You won: %s" beats "%s won: %s").

local _, RW = ...
local Safe, api = RW.Safe, RW.Safe.api

local Chatter = {}
RW.Chatter = Chatter

-- Template name -> { what, choice, blanks }. blanks name what each %s / %d holds, by position.
local TEMPLATES = {
  LOOT_ROLL_WON = { "result", nil, { "who", "item" } },
  LOOT_ROLL_YOU_WON = { "result", nil, { "item" }, true },
  LOOT_ROLL_ALL_PASSED = { "nobody", nil, { "item" } },
  LOOT_ROLL_ROLLED_NEED = { "number", "need", { "roll", "item", "who" } },
  LOOT_ROLL_ROLLED_GREED = { "number", "greed", { "roll", "item", "who" } },
  LOOT_ROLL_ROLLED_TRANSMOG = { "number", "tmog", { "roll", "item", "who" } },
  LOOT_ROLL_ROLLED_DE = { "number", "greed", { "roll", "item", "who" } },
  LOOT_ROLL_NEED = { "choice", "need", { "who", "item" } },
  LOOT_ROLL_GREED = { "choice", "greed", { "who", "item" } },
  LOOT_ROLL_TRANSMOG = { "choice", "tmog", { "who", "item" } },
  LOOT_ROLL_DISENCHANT = { "choice", "greed", { "who", "item" } },
  LOOT_ROLL_PASSED = { "choice", "pass", { "who", "item" } },
  LOOT_ROLL_PASSED_AUTO = { "choice", "pass", { "who", "item" } },
  LOOT_ROLL_PASSED_AUTO_FEMALE = { "choice", "pass", { "who", "item" } },
  LOOT_ROLL_NEED_SELF = { "choice", "need", { "item" }, true },
  LOOT_ROLL_GREED_SELF = { "choice", "greed", { "item" }, true },
  LOOT_ROLL_TRANSMOG_SELF = { "choice", "tmog", { "item" }, true },
  LOOT_ROLL_DISENCHANT_SELF = { "choice", "greed", { "item" }, true },
  LOOT_ROLL_PASSED_SELF = { "choice", "pass", { "item" }, true },
  LOOT_ROLL_PASSED_SELF_AUTO = { "choice", "pass", { "item" }, true },
}

-- "Need Roll - %d for %s by %s" -> pieces { "Need Roll - ", " for ", " by ", "" },
-- slots { 1, 2, 3 } (which blank each gap fills; %2$s style reorders them).
function Chatter.Split(template)
  if type(template) ~= "string" or template == "" then return nil end
  local pieces, slots, buf = {}, {}, {}
  local i, len = 1, #template
  while i <= len do
    local ch = template:sub(i, i)
    if ch ~= "%" then
      buf[#buf + 1] = ch
      i = i + 1
    elseif template:byte(i + 1) == 37 then -- "%%" is a literal percent
      buf[#buf + 1] = "%"
      i = i + 2
    else
      local j, index = i + 1, nil
      local digit = template:byte(j)
      if digit and digit >= 48 and digit <= 57 and template:sub(j + 1, j + 1) == "$" then
        index = digit - 48
        j = j + 2
      end
      local conv = template:sub(j, j)
      if conv ~= "s" and conv ~= "d" then
        buf[#buf + 1] = ch -- not a blank after all
        i = i + 1
      else
        pieces[#pieces + 1] = table.concat(buf)
        buf = {}
        slots[#slots + 1] = index or (#slots + 1)
        i = j + 1
      end
    end
  end
  pieces[#pieces + 1] = table.concat(buf)
  local fixed = 0
  for _, piece in ipairs(pieces) do fixed = fixed + #piece end
  return { pieces = pieces, slots = slots, fixed = fixed }
end

-- Walks the fixed pieces through the line. Returns the blanks, or nil.
function Chatter.Fit(shape, line)
  local pieces, slots = shape.pieces, shape.slots
  local pos = 1
  if pieces[1] ~= "" then
    local a, b = line:find(pieces[1], 1, true)
    if not a then return nil end
    pos = b + 1
  end
  local blanks = {}
  for k = 1, #slots do
    local piece = pieces[k + 1]
    local value
    if piece == "" then
      if k < #slots then return nil end -- two blanks in a row can't be told apart
      value = line:sub(pos)
      pos = #line + 1
    else
      local a, b = line:find(piece, pos, true)
      if not a then return nil end
      value = line:sub(pos, a - 1)
      pos = b + 1
    end
    blanks[slots[k]] = value
  end
  -- Anything left over must be trimmings (a full stop, spaces).
  if pos <= #line and line:sub(pos):find("[%w]") then return nil end
  return blanks
end

local shapes
local function allShapes()
  if shapes then return shapes end
  shapes = {}
  for key, spec in pairs(TEMPLATES) do
    local shape = Chatter.Split(Safe.Plain(_G[key]))
    if shape then
      shape.key, shape.what, shape.choice, shape.names, shape.you = key, spec[1], spec[2], spec[3], spec[4]
      shapes[#shapes + 1] = shape
    end
  end
  return shapes
end
Chatter.Reset = function() shapes = nil end

-- Swaps hyperlinks for tokens. Returns the tokenized line and the links by token number.
local function tokenize(line)
  local links, out, pos = {}, {}, 1
  while true do
    local start = line:find("|H", pos, true)
    if not start then break end
    local textEnd = line:find("|h", start + 2, true)
    local close = textEnd and line:find("|h", textEnd + 2, true)
    if not close then break end
    -- take the colour code before the link and the |r after it along
    local from, to = start, close + 1
    if line:sub(start - 10, start - 9) == "|c" then from = start - 10 end
    if line:sub(to + 1, to + 2) == "|r" then to = to + 2 end
    out[#out + 1] = line:sub(pos, from - 1)
    links[#links + 1] = line:sub(from, to)
    out[#out + 1] = "\001" .. #links .. "\002"
    pos = to + 1
  end
  out[#out + 1] = line:sub(pos)
  return table.concat(out), links
end

local function untoken(text, links)
  return (text:gsub("\001(%d+)\002", function(n) return links[tonumber(n)] or "" end))
end

local memo, memoOrder = {}, {}

-- What a loot line means: { what, choice, who, you, link, roll }, or false.
function Chatter.Read(line)
  line = Safe.Plain(line)
  local usable = type(line) == "string" and line:find("|Hitem:", 1, true) ~= nil
  if not usable then return false end
  local known = memo[line]
  if known ~= nil then return known end
  local text, links = tokenize(line)
  local best, bestBlanks
  for _, shape in ipairs(allShapes()) do
    local blanks = Chatter.Fit(shape, text)
    if blanks and (not best or shape.fixed > best.fixed) then best, bestBlanks = shape, blanks end
  end
  local result = false
  if best then
    result = { what = best.what, choice = best.choice, you = best.you or nil, key = best.key }
    for slot, label in ipairs(best.names) do
      local raw = untoken(bestBlanks[slot] or "", links)
      if label == "item" then result.link = raw:match("^%s*(.-)%s*$")
      elseif label == "who" then result.who = Safe.Person(raw)
      elseif label == "roll" then result.roll = tonumber((Safe.Visible(raw) or ""):match("%d+")) end
    end
    if result.who and result.who == RW.Me() then result.you = true end
  end
  memo[line] = result
  memoOrder[#memoOrder + 1] = line
  if #memoOrder > 150 then memo[table.remove(memoOrder, 1)] = nil end
  return result
end

------------------------------------------------------------------------------------------------
-- Hiding lines
------------------------------------------------------------------------------------------------

local function inScope()
  if RW.Opt("chatWhere") ~= "instances" then return true end
  return Safe.Plain(api.IsInInstance()) == true
end

function Chatter.Hides(line)
  local info = Chatter.Read(line)
  if not info or not inScope() then return false end
  if info.what == "result" or info.what == "nobody" then return RW.Opt("hideResults") and true or false end
  if info.what == "number" then return RW.Opt("hideNumbers") and true or false end
  if info.you then return RW.Opt("hideMine") and true or false end
  return RW.Opt("hideOthers") and true or false
end

-- Presets shown in settings.
Chatter.PRESETS = {
  { key = "all", label = "Show everything", set = { hideMine = false, hideOthers = false, hideNumbers = false, hideResults = false } },
  { key = "results", label = "Results only", set = { hideMine = true, hideOthers = true, hideNumbers = true, hideResults = false } },
  { key = "none", label = "Nothing", set = { hideMine = true, hideOthers = true, hideNumbers = true, hideResults = true } },
}

function Chatter.ApplyPreset(key)
  for _, preset in ipairs(Chatter.PRESETS) do
    if preset.key == key then
      for option, value in pairs(preset.set) do RW.SetOpt(option, value) end
    end
  end
end

function Chatter.CurrentPreset()
  for _, preset in ipairs(Chatter.PRESETS) do
    local same = true
    for option, value in pairs(preset.set) do if RW.Opt(option) ~= value then same = false end end
    if same then return preset.key end
  end
end

local function lootFilter(_, _, line)
  local ok, hide = pcall(Chatter.Hides, line)
  return ok and hide == true
end

-- Newer clients keep the filter registry in ChatFrameUtil; older ones as a global function.
local registry = ChatFrameUtil
local addFilter = registry and registry.AddMessageEventFilter
addFilter = addFilter or ChatFrame_AddMessageEventFilter
if addFilter then pcall(addFilter, "CHAT_MSG_LOOT", lootFilter) end

RW.OnGame("CHAT_MSG_LOOT", function(line)
  local info = Chatter.Read(line)
  if info and info.link then RW.Ledger:OnChat(info) end
end)

------------------------------------------------------------------------------------------------
-- Recap line
------------------------------------------------------------------------------------------------

RW.Watch("DECIDED", function(e)
  if e.preview or not RW.Opt("recap") then return end
  local t = RW.Ledger.Tally(e)
  local link = e.link or "?"
  local body
  if e.nobody then
    body = link .. "  |cff9d9d9dno takers|r"
  elseif e.winner then
    local w = e.winner
    body = ("%s  %s  %s"):format(link, RW.UI.Colored(w.name, w.cls), "|cffd0d0d0" .. RW.UI.ChoiceWord(w.choice, w.spec) .. (w.roll and (" " .. w.roll) or "") .. "|r")
  else
    return
  end
  RW.Say(("%s   |cff808080[%dN %dG %dP]|r"):format(body, t.need, t.greed + t.tmog, t.pass))
end)
