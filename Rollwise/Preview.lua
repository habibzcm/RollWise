-- Rollwise / Preview: /rollwise preview plays a scripted roll on the real board, one scenario at a
-- time, so you can see every rule the game uses. Each run plays the next scenario.

local _, RW = ...
local Ledger = RW.Ledger

local Preview = { turn = 0 }
RW.Preview = Preview

local ITEMS = {
  { id = 12640, name = "Lionheart Helm", quality = 4 },
  { id = 18803, name = "Finkle's Lava Dredger", quality = 4 },
  { id = 18832, name = "Brutality Blade", quality = 4 },
}

local PEOPLE = {
  { "Brannoc", "WARRIOR" }, { "Ysolde", "PALADIN" }, { "Kettrin", "HUNTER" }, { "Morwe", "ROGUE" },
  { "Aldane", "PRIEST" }, { "Tuvok", "SHAMAN" }, { "Seraphe", "MAGE" }, { "Grell", "WARLOCK" },
  { "Oaken", "DRUID" }, { "Hildra", "WARRIOR" }, { "Pell", "PALADIN" }, { "Vashi", "HUNTER" },
  { "Corwin", "ROGUE" }, { "Lisset", "PRIEST" }, { "Durotan", "SHAMAN" }, { "Emberly", "MAGE" },
  { "Nox", "WARLOCK" }, { "Fennick", "DRUID" }, { "Ravel", "WARRIOR" }, { "Ilsa", "PRIEST" },
  { "Jorvik", "HUNTER" }, { "Quenna", "MAGE" }, { "Tabor", "PALADIN" }, { "Sable", "ROGUE" },
}

-- Each scenario: a title, a one-line lesson, and the script for you and the others.
-- A script line: { who (index into PEOPLE, or "you"), choice, spec, roll, delay }.
local SCENARIOS = {
  {
    title = "Off spec takes it",
    lesson = "Nobody Needs for main spec, so the best off spec Need wins.",
    cast = 5,
    script = {
      { 2, "need", "off", 58, 1.2 }, { 3, "need", "off", 81, 2.0 }, { "you", "greed", nil, 97, 2.6 },
      { 5, "pass", nil, nil, 1.6 }, { 7, "greed", nil, 40, 3.1 },
    },
  },
  {
    title = "Greed for gold",
    lesson = "No Needs at all: the highest Greed roll wins. Here that's you.",
    cast = 5,
    script = {
      { 1, "greed", nil, 33, 0.9 }, { "you", "greed", nil, 88, 1.8 }, { 4, "greed", nil, 71, 2.2 },
      { 6, "pass", nil, nil, 1.3 }, { 8, "greed", nil, 12, 3.0 },
    },
  },
  {
    title = "No takers",
    lesson = "Everyone passes: the item goes to nobody.",
    cast = 5,
    script = {
      { 1, "pass", nil, nil, 0.8 }, { 3, "pass", nil, nil, 1.5 }, { "you", "pass", nil, nil, 2.0 },
      { 5, "pass", nil, nil, 2.4 }, { 9, "pass", nil, nil, 3.2 },
    },
  },
  {
    title = "Busy raid",
    lesson = "A full raid: Needs are grouped by spec, passes and late deciders fold into one line each.",
    cast = 25,
  },
}

local function itemLink(it)
  local _, _, _, hex = RW.UI.QualityRGB(it.quality)
  return ("%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(hex, it.id, it.name)
end

-- A busy raid: everyone's choice comes from their class and a fixed number sequence, so the
-- scenario is the same every time.
local WANTS_BLADE = { WARRIOR = "main", ROGUE = "main", PALADIN = "off", HUNTER = "off" }
local function raidScript(size)
  local script, seed = {}, 17
  local function nextNumber() seed = (seed * 73 + 41) % 997 return seed end
  for i = 1, math.min(size - 1, #PEOPLE) do
    local class = PEOPLE[i][2]
    local n = nextNumber()
    local line = { i, nil, nil, n % 100 + 1, 0.4 + (n % 40) / 10 }
    if WANTS_BLADE[class] and n % 3 ~= 0 then line[2], line[3] = "need", WANTS_BLADE[class]
    elseif n % 5 == 0 then line[2] = nil -- still deciding when time runs out
    elseif n % 2 == 0 then line[2] = "greed"
    else line[2] = "pass" end
    if line[2] ~= nil then script[#script + 1] = line end
  end
  script[#script + 1] = { "you", "greed", nil, 64, 2.2 }
  return script
end

function Preview:Play(arg)
  for i = #Ledger.live, 1, -1 do
    if Ledger.live[i].preview then table.remove(Ledger.live, i) end
  end
  local scenario
  if arg == "raid" then
    scenario = SCENARIOS[4]
  else
    self.turn = self.turn % #SCENARIOS + 1
    scenario = SCENARIOS[self.turn]
  end
  local item = scenario.cast > 5 and ITEMS[3] or ITEMS[(self.turn - 1) % 2 + 1]
  local e = Ledger.Create(itemLink(item))
  e.preview, e.quality, e.bop = scenario.title, item.quality, true
  e.icon = RW.Safe.ItemFacts(item.id).icon or 134400
  e.boss = "Preview: " .. scenario.title
  e.duration = 8
  e.deadline = Ledger.Now() + e.duration
  e.stage = "open"
  RW.Emit("APPEARED", e)

  local me = Ledger.Seat(e, RW.Me() or "You", RW.MyClass(), true)
  local script = scenario.script or raidScript(scenario.cast)
  local seats = { you = me }
  for _, line in ipairs(script) do
    if line[1] ~= "you" then
      local who = PEOPLE[line[1]]
      seats[line[1]] = Ledger.Seat(e, who[1], who[2])
    end
  end
  -- Raid extras who never choose.
  if scenario.cast > 5 then
    for i = 1, math.min(scenario.cast - 1, #PEOPLE) do
      if not seats[i] then Ledger.Seat(e, PEOPLE[i][1], PEOPLE[i][2]) end
    end
  end

  for _, line in ipairs(script) do
    local seat = seats[line[1]]
    RW.After(line[5], function()
      if e.stage ~= "open" then return end
      seat.choice, seat.spec = line[2], line[3]
      if seat == me then e.stage = "waiting" end
      Ledger:Changed()
    end)
  end
  RW.After(e.duration, function()
    for _, line in ipairs(script) do
      local seat = seats[line[1]]
      if seat.choice and seat.choice ~= "pass" then seat.roll = line[4] end
    end
    local best = Ledger.Leader(e)
    if best then best.won = true e.winner = best else e.nobody = true end
    e.stage = "waiting"
    Ledger:Decide(e)
    Ledger:Changed()
  end)
  Ledger:Changed()
  RW.Say(("preview |cffffd100%s|r: %s"):format(scenario.title, scenario.lesson))
end
