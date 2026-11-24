-- Rollwise / Core: settings, signals between modules, game events, slash commands.

local _, RW = ...
local Safe, api = RW.Safe, RW.Safe.api

------------------------------------------------------------------------------------------------
-- Settings: one table describes every option and its default.
------------------------------------------------------------------------------------------------

RW.OPTIONS = {
  board = true,        -- roll board on screen
  look = "signature",  -- signature | modern | classic
  motion = true,       -- small animations
  size = 1.0,          -- scale of the board (and docked game windows)
  width = 290,
  fitWidth = true,     -- match the game's roll window width when docked
  rows = 9,            -- lines before the list scrolls
  holdTime = 10,       -- seconds a decided item stays on the board
  flow = "up",         -- up | down
  pinned = true,       -- board can't be dragged
  dock = true,         -- game roll windows ride on top of their cards
  passView = "chips",  -- chips | rows | off
  showDeciding = true,
  specWords = "short", -- short (MS/OS) | long
  lootCount = true,    -- "2" bubble: items already won this run
  countdown = true,
  odds = true,         -- your chance to win
  gear = true,         -- compare with what you wear
  tray = true,         -- strip of recently decided items
  hideMine = false,    -- chat: your own choice lines
  hideOthers = false,  -- chat: other players' choice lines
  hideNumbers = false, -- chat: "Need Roll - 54 ..." lines
  hideResults = false, -- chat: who won / everyone passed
  chatWhere = "everywhere", -- everywhere | instances
  recap = false,       -- one Rollwise line per decided item
  winSound = true,
  wishSound = true,    -- sound when a wishlist item drops
  wishBanner = true,   -- raid-warning style banner when it drops
  wishTooltip = true,  -- wishlist line on item tooltips
  wishRemoveOnWin = false,
}

local onChange = {}
function RW.OnOption(fn) onChange[#onChange + 1] = fn end

function RW.Opt(key)
  local saved = RollwiseDB and RollwiseDB.options
  if saved and saved[key] ~= nil then return saved[key] end
  return RW.OPTIONS[key]
end

function RW.SetOpt(key, value)
  if not RollwiseDB then return end
  if value == RW.OPTIONS[key] then value = nil end
  RollwiseDB.options[key] = value
  for _, fn in ipairs(onChange) do pcall(fn, key) end
end

------------------------------------------------------------------------------------------------
-- Signals (module to module) and game events
------------------------------------------------------------------------------------------------

local listeners = {}
function RW.Watch(signal, fn)
  listeners[signal] = listeners[signal] or {}
  table.insert(listeners[signal], fn)
end
function RW.Emit(signal, ...)
  local list = listeners[signal]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then RW.Note("signal " .. signal, err) end
  end
end

local hub = CreateFrame("Frame")
local gameHandlers = {}
function RW.OnGame(event, fn)
  if not gameHandlers[event] then
    gameHandlers[event] = {}
    pcall(hub.RegisterEvent, hub, event)
  end
  table.insert(gameHandlers[event], fn)
end
hub:SetScript("OnEvent", function(_, event, ...)
  local list = gameHandlers[event]
  for i = 1, #(list or {}) do
    local ok, err = pcall(list[i], ...)
    if not ok then RW.Note(event, err) end
  end
end)

------------------------------------------------------------------------------------------------
-- Messages and the problem notebook (/rollwise diag)
------------------------------------------------------------------------------------------------

RW.BRAND = "|cff4fc3f7Roll|r|cffffd100wise|r"

function RW.Say(text)
  local frame = DEFAULT_CHAT_FRAME
  if frame then frame:AddMessage(RW.BRAND .. ": " .. tostring(text)) end
end

RW.notebook = {}
function RW.Note(where, what)
  local book = RW.notebook
  book[#book + 1] = ("[%s] %s: %s"):format(date and date("%H:%M:%S") or "?", tostring(where), tostring(what))
  if #book > 40 then table.remove(book, 1) end
end

------------------------------------------------------------------------------------------------
-- You and your group
------------------------------------------------------------------------------------------------

local myself
function RW.Me()
  local name = Safe.Person(api.UnitName("player"))
  if name then myself = name end
  return myself
end
function RW.LearnMe(name) if name then myself = name end end

function RW.MyClass() return Safe.Plain(select(2, api.UnitClass("player"))) end

-- { name = class } for everyone in your group whose name the game shows.
function RW.Group()
  local members = {}
  local function add(unit)
    local name = Safe.Person(api.UnitName(unit))
    if name then members[name] = Safe.Plain(select(2, api.UnitClass(unit))) or members[name] or false end
  end
  add("player")
  local size = Safe.Plain(api.GetNumGroupMembers()) or 0
  local prefix = Safe.Plain(api.IsInRaid()) and "raid" or "party"
  local last = prefix == "raid" and size or size - 1
  for i = 1, last do add(prefix .. i) end
  return members
end

function RW.ClassOf(name)
  local class = name and RW.Group()[name]
  return class or nil
end

------------------------------------------------------------------------------------------------
-- Load
------------------------------------------------------------------------------------------------

RW.OnGame("ADDON_LOADED", function(name)
  if name ~= RW.addon then return end
  -- Anything saved by a pre-release test build is in an older shape: start clean.
  if type(RollwiseDB) ~= "table" or RollwiseDB.schema ~= 2 then RollwiseDB = {} end
  RollwiseDB.options = type(RollwiseDB.options) == "table" and RollwiseDB.options or {}
  RollwiseDB.runs = type(RollwiseDB.runs) == "table" and RollwiseDB.runs or {}
  RollwiseDB.schema = 2
  local saved = RollwiseDB.options.look
  if saved ~= nil and not RW.UI.LOOKS[saved] then RollwiseDB.options.look = nil end
  local meta = Safe.lib("C_AddOns").GetAddOnMetadata(RW.addon, "Version")
  RW.version = Safe.Plain(meta) or "1.0.0"
  RW.ready = true
  RW.Emit("READY")
end)

------------------------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------------------------

local COMMANDS = {
  { "", "open the journal", function() RW.Window:Toggle("journal") end },
  { "settings", "settings", function() RW.Window:Open("settings") end },
  { "players", "who has won what this run", function() RW.Window:Open("players") end },
  { "preview", "play a preview roll (add 'raid' for a 25-player one)", function(arg) RW.Preview:Play(arg) end },
  { "move", "unpin the board so you can drag it", function()
      RW.SetOpt("pinned", false)
      RW.Say("drag the blue handle, then /rollwise pin")
    end },
  { "pin", "pin the board in place", function() RW.SetOpt("pinned", true) end },
  { "home", "board back to its default spot and size", function()
      RollwiseDB.anchor = nil
      RW.SetOpt("size", RW.OPTIONS.size)
      RW.Emit("ANCHOR")
    end },
  { "want", "add items to your wishlist (Shift-click links after it)", function(rest) RW.Wishlist.Command(rest) end },
  { "wishlist", "open your wishlist", function() RW.Window:Open("wishlist") end },
  { "recent", "show the recent items tray", function() RW.Emit("TRAY_SHOW") end },
  { "split", "start a new journal run now", function()
      RW.Journal:Begin(nil, true)
      RW.Say("new run started")
    end },
  { "diag", "problem report for bug reports", function()
      RW.Say(("v%s  history:%s  secrets:%s  rollframes:%s"):format(tostring(RW.version),
        tostring(C_LootHistory ~= nil), tostring(issecretvalue ~= nil), tostring(GroupLootContainer ~= nil)))
      for _, line in ipairs(RW.notebook) do RW.Say("|cff999999" .. line .. "|r") end
    end },
}

local function usage()
  RW.Say("commands")
  for _, c in ipairs(COMMANDS) do
    local word = c[1] == "" and "" or (" " .. c[1])
    RW.Say(("  |cffffd100/rollwise%s|r  %s"):format(word, c[2]))
  end
end

SLASH_ROLLWISE1, SLASH_ROLLWISE2 = "/rollwise", "/rwise"
SlashCmdList.ROLLWISE = function(input)
  input = input or ""
  local verb, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
  verb = (verb or ""):lower()
  -- most commands take one lowercase word; "want" gets the raw rest (item links)
  local arg = verb == "want" and rest or ((rest or ""):lower():match("%S+"))
  for _, c in ipairs(COMMANDS) do
    if c[1] == verb then
      if RW.ready then c[3](arg) end
      return
    end
  end
  usage()
end

-- Addons button by the minimap.
function Rollwise_Compartment(_, button)
  if button == "RightButton" then RW.Window:Open("settings") else RW.Window:Toggle("journal") end
end
function Rollwise_CompartmentHover(_, owner)
  RW.UI.TipAt(owner, function(tip)
    tip:SetText(RW.BRAND)
    tip:AddLine("Click: journal   Right-click: settings", 1, 1, 1)
  end)
end
function Rollwise_CompartmentLeave() GameTooltip:Hide() end
