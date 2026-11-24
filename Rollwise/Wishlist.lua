-- Rollwise / Wishlist: items you're hoping for, per character.
--
-- Add: Alt-click any item (chat link, bags, character sheet, loot, a roll card), drag one onto
-- the Wishlist tab, or type /rollwise want and Shift-click a link into the line.
-- When one drops: its card glows, a sound plays, a banner shows, and Rollwise notes when and
-- where you saw it and who got it.

local _, RW = ...
local Safe, api, UI = RW.Safe, RW.Safe.api, RW.UI

local Wishlist = {}
RW.Wishlist = Wishlist

------------------------------------------------------------------------------------------------
-- Storage: RollwiseDB.wish["Name-Realm"][itemID] = record
------------------------------------------------------------------------------------------------

local function owner()
  local name = RW.Me()
  if not name then return nil end
  return name .. "-" .. (Safe.Plain(api.GetRealmName()) or "")
end

local function shelf()
  if not RollwiseDB then return nil end
  local who = owner()
  if not who then return nil end
  RollwiseDB.wish = type(RollwiseDB.wish) == "table" and RollwiseDB.wish or {}
  RollwiseDB.wish[who] = RollwiseDB.wish[who] or {}
  return RollwiseDB.wish[who]
end

local function clock() return Safe.Plain(api.time()) or 0 end

function Wishlist.Get(itemID)
  local s = shelf()
  return s and itemID and s[itemID] or nil
end

function Wishlist.Has(thing) return Wishlist.Get(Safe.ItemID(thing)) ~= nil end

-- A full item link for an ID or a link (the item may still be loading: then a plain one).
local function linkFor(thing)
  thing = Safe.Plain(thing)
  if type(thing) == "string" and thing:find("|Hitem:", 1, true) then return thing end
  local id = Safe.ItemID(thing)
  if not id then return nil end
  local _, link = Safe.lib("C_Item").GetItemInfo(id)
  link = Safe.Plain(link)
  if type(link) == "string" then return link end
  return ("|cffffffff|Hitem:%d::::::::::::|h[item %d]|h|r"):format(id, id)
end

function Wishlist:Add(thing, quiet)
  local s, link = shelf(), linkFor(thing)
  local id = Safe.ItemID(link)
  if not (s and id) then return false end
  if not s[id] then
    s[id] = { link = link, added = clock(), seen = 0 }
    if link:find("[item ", 1, true) then
      s[id].loading = true
      Safe.lib("C_Item").RequestLoadItemDataByID(id)
    end
    if not quiet then RW.Say(UI.Inline("wish", 12) .. " added " .. link .. " to your wishlist") end
  end
  RW.Emit("WISHLIST")
  return true
end

function Wishlist:Remove(id, quiet)
  local s = shelf()
  if not (s and s[id]) then return end
  local link = s[id].link
  s[id] = nil
  if not quiet then RW.Say("removed " .. (link or "item") .. " from your wishlist") end
  RW.Emit("WISHLIST")
end

function Wishlist:Toggle(thing)
  local id = Safe.ItemID(thing)
  if not id then return end
  if Wishlist.Get(id) then self:Remove(id) else self:Add(thing) end
end

function Wishlist:SetGot(id, got)
  local w = Wishlist.Get(id)
  if not w then return end
  w.got = got and (w.got or clock()) or nil
  RW.Emit("WISHLIST")
end

-- Records, still-wanted first, newest first.
function Wishlist.List()
  local out = {}
  for id, w in pairs(shelf() or {}) do
    w.id = id
    out[#out + 1] = w
  end
  table.sort(out, function(a, b)
    if (a.got and 1 or 0) ~= (b.got and 1 or 0) then return not a.got end
    return (a.added or 0) > (b.added or 0)
  end)
  return out
end

function Wishlist.Count()
  local open, total = 0, 0
  for _, w in pairs(shelf() or {}) do
    total = total + 1
    if not w.got then open = open + 1 end
  end
  return open, total
end

-- "3m ago", "2h ago", "4d ago".
function Wishlist.Ago(t)
  if not t or t == 0 then return "never" end
  local d = math.max(0, clock() - t)
  if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
  if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
  return ("%dd ago"):format(math.floor(d / 86400))
end

------------------------------------------------------------------------------------------------
-- When a wished-for item drops
------------------------------------------------------------------------------------------------

local function alert(e)
  local link = e.link or "?"
  local tag = e.preview and " |cff9d9d9d(preview)|r" or ""
  RW.Say(UI.Inline("wish", 12) .. " |cffffd100Wishlist item up for roll:|r " .. link .. tag)
  if RW.Opt("wishBanner") and RaidNotice_AddMessage and RaidWarningFrame then
    local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 }
    pcall(RaidNotice_AddMessage, RaidWarningFrame, "Wishlist: " .. Safe.LinkText(link) .. " is up for roll!", color)
  end
  if RW.Opt("wishSound") then
    local kit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)
    if kit then api.PlaySound(kit, "Master") end
  end
end

RW.Watch("APPEARED", function(e)
  if e.wanted ~= nil or not e.itemID then return end
  local w = Wishlist.Get(e.itemID)
  e.wanted = w ~= nil
  if not w then return end
  if not e.preview then
    w.seen = (w.seen or 0) + 1
    w.lastSeen = clock()
    local run = RW.Journal.Current()
    w.lastWhere = e.boss or (run and run.title) or nil
    RW.Emit("WISHLIST")
  end
  alert(e)
  RW.Ledger:Changed()
end)

RW.Watch("DECIDED", function(e)
  if not e.wanted or e.preview then return end
  local w = Wishlist.Get(e.itemID)
  if not w then return end
  if e.nobody then
    w.lastWinner = nil
    w.lastOutcome = "nobody"
  elseif e.winner then
    w.lastWinner, w.lastWinnerClass, w.lastOutcome = e.winner.name, e.winner.cls, "won"
    if RW.Ledger.IsYou(e.winner) then
      w.got = clock()
      RW.Say(UI.Inline("wish", 12) .. " |cff4cff4cYou got|r " .. (e.link or "it") .. " |cff4cff4cfrom your wishlist!|r")
      if RW.Opt("wishRemoveOnWin") then Wishlist:Remove(e.itemID, true) end
    end
  end
  if e.page then e.page.wanted = true end
  RW.Emit("WISHLIST")
end)

------------------------------------------------------------------------------------------------
-- Adding: Alt-click any item, /rollwise want <link>
------------------------------------------------------------------------------------------------

local function altOnly()
  return IsAltKeyDown and IsAltKeyDown() and not (IsShiftKeyDown and IsShiftKeyDown())
    and not (IsControlKeyDown and IsControlKeyDown())
end

-- The game calls HandleModifiedItemClick for modified clicks on item buttons and item links.
if hooksecurefunc and type(HandleModifiedItemClick) == "function" then
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if not RW.ready or not altOnly() then return end
    link = Safe.Plain(link)
    if type(link) == "string" and link:find("|Hitem:", 1, true) then Wishlist:Toggle(link) end
  end)
end

-- Items added by ID before the game had loaded them get their real link once it arrives.
RW.OnGame("GET_ITEM_INFO_RECEIVED", function(itemID)
  local w = Wishlist.Get(Safe.Plain(itemID))
  if not (w and w.loading) then return end
  local _, link = Safe.lib("C_Item").GetItemInfo(itemID)
  link = Safe.Plain(link)
  if type(link) == "string" then
    w.link, w.loading = link, nil
    RW.Emit("WISHLIST")
  end
end)

function Wishlist.Command(rest)
  rest = rest or ""
  local found = false
  for link in rest:gmatch("|c%x+|Hitem:.-|h|r") do
    Wishlist:Add(link)
    found = true
  end
  if not found then
    for id in rest:gmatch("%d+") do Wishlist:Add(tonumber(id)) found = true end
  end
  if not found then
    RW.Say("type |cffffd100/rollwise want|r and Shift-click an item into the line, or hover any item and press your Rollwise wishlist key.")
  end
end

------------------------------------------------------------------------------------------------
-- Tooltip line on any wished-for item
------------------------------------------------------------------------------------------------

local function describe(tip, id)
  if not RW.ready or not RW.Opt("wishTooltip") then return end
  local w = Wishlist.Get(id)
  if not w then return end
  local line
  if w.got then
    line = "|cff4cff4cGot it|r " .. Wishlist.Ago(w.got)
  elseif (w.seen or 0) == 0 then
    line = "not seen yet"
  else
    line = ("seen %d time%s, last %s"):format(w.seen, w.seen == 1 and "" or "s", Wishlist.Ago(w.lastSeen))
    if w.lastWinner then line = line .. ", went to " .. UI.Colored(w.lastWinner, w.lastWinnerClass) end
  end
  tip:AddLine(UI.Inline("wish", 12) .. " " .. RW.BRAND .. " wishlist: |cffd0d0d0" .. line .. "|r", 1, 1, 1)
  tip:Show()
end

------------------------------------------------------------------------------------------------
-- The item under the mouse: any tooltip that shows an item (the game's, AtlasLoot's, the
-- auction house...) is remembered until that tooltip hides.
------------------------------------------------------------------------------------------------

local hover
local watchedTips = {}

local function noteHover(tip, id)
  if not tip then return end
  local link
  if tip.GetItem then
    local ok, _, l = pcall(tip.GetItem, tip)
    link = ok and Safe.Plain(l) or nil
  end
  hover = { tip = tip, id = id, link = type(link) == "string" and link or nil }
  if not watchedTips[tip] and tip.HookScript then
    watchedTips[tip] = true
    pcall(tip.HookScript, tip, "OnHide", function(self) if hover and hover.tip == self then hover = nil end end)
  end
end

function Wishlist.Hovered()
  if hover and hover.tip and hover.tip.IsShown and hover.tip:IsShown() then return hover.link or hover.id end
  if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then
    local _, link = GameTooltip:GetItem()
    link = Safe.Plain(link)
    if type(link) == "string" then return link end
  end
end

-- Key binding (Options > Keybindings > AddOns > Rollwise), see Bindings.xml.
BINDING_HEADER_ROLLWISE = "Rollwise"
BINDING_NAME_ROLLWISE_WISH = "Add / remove the item under the mouse on your wishlist"
function Rollwise_WishHovered()
  if not RW.ready then return end
  local target = Wishlist.Hovered()
  if not target then RW.Say("point at an item first, then press the key.") return end
  Wishlist:Toggle(target)
end

function Wishlist.BoundKey()
  local key = Safe.Plain(Safe.api.GetBindingKey("ROLLWISE_WISH"))
  return type(key) == "string" and key or nil
end

-- Binds a key only if nothing else uses it.
function Wishlist.QuickBind(key)
  if Safe.Plain(Safe.api.InCombatLockdown()) then RW.Say("keys can't be changed in combat.") return false end
  local action = Safe.Plain(Safe.api.GetBindingAction(key))
  if type(action) == "string" and action ~= "" and action ~= "ROLLWISE_WISH" then
    RW.Say(("%s is already used (%s). Pick a key in Options > Keybindings > AddOns > Rollwise."):format(key, action))
    return false
  end
  Safe.api.SetBinding(key, "ROLLWISE_WISH")
  local set = Safe.Plain(Safe.api.GetCurrentBindingSet())
  if set then Safe.api.SaveBindings(set) end
  RW.Say(("wishlist key set to %s: point at any item and press it."):format(key))
  RW.Emit("WISHLIST")
  return true
end

------------------------------------------------------------------------------------------------
-- Collecting: while the Wishlist tab is open, Shift-clicking any item adds it. Item links from
-- the game and most addons (AtlasLoot included) go through the same "link it to chat" call.
------------------------------------------------------------------------------------------------

Wishlist.collecting = false

local function collect(link)
  if not (RW.ready and Wishlist.collecting) then return end
  link = Safe.Plain(link)
  if type(link) == "string" and link:find("|Hitem:", 1, true) then Wishlist:Add(link) end
end

if hooksecurefunc then
  if type(ChatEdit_InsertLink) == "function" then hooksecurefunc("ChatEdit_InsertLink", collect) end
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
    hooksecurefunc(ChatFrameUtil, "InsertLink", collect)
  end
  if type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if IsShiftKeyDown and IsShiftKeyDown() then collect(link) end
    end)
  end
end

local hooked = false
local function hookTooltips()
  if hooked then return end
  hooked = true
  local processor = TooltipDataProcessor
  local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
  if processor and processor.AddTooltipPostCall and itemType then
    processor.AddTooltipPostCall(itemType, function(tip, data)
      local id = type(data) == "table" and Safe.Plain(data.id) or nil
      if id then
        noteHover(tip, id)
        pcall(describe, tip, id)
      end
    end)
    return
  end
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        local id = Safe.ItemID(link)
        if id then
          noteHover(self, id)
          pcall(describe, self, id)
        end
      end)
    end
  end
end
RW.Watch("READY", hookTooltips)
