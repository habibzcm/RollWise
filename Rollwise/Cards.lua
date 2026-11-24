-- Rollwise / Cards: the roll board. One card per item, picks grouped by how strong they are
-- (main spec Need, off spec Need, transmog, Greed), each with a roll bar. The game's own roll
-- window can ride on top of its card.

local _, RW = ...
local Safe, api, UI, Ledger = RW.Safe, RW.Safe.api, RW.UI, RW.Ledger

local Cards = { pool = {}, used = 0 }
RW.Cards = Cards

local PAD, STRIP_H, BAND_H, LINE_H, HEAD_H, CHIP_H, CLOCK_H, GEAR_H = 6, 30, 20, 17, 14, 13, 3, 14
local SPACING = 8

local GROUP_RGB = {
  main = { 1.00, 0.78, 0.10 }, off = { 0.50, 0.70, 1.00 }, need = { 0.90, 0.90, 0.90 },
  tmog = { 0.80, 0.50, 1.00 }, greed = { 0.45, 0.85, 0.45 },
}

------------------------------------------------------------------------------------------------
-- Board anchor
------------------------------------------------------------------------------------------------

local board = CreateFrame("Frame", "RollwiseBoard", UIParent)
board:SetSize(290, 2)
board:SetFrameStrata("HIGH")
board:SetMovable(true)
board:SetClampedToScreen(true)
if board.SetDontSavePosition then board:SetDontSavePosition(true) end
Cards.board = board

local handle = CreateFrame("Button", nil, board, "BackdropTemplate")
handle:SetHeight(20)
handle:RegisterForDrag("LeftButton")
handle:RegisterForClicks("RightButtonUp")
UI.Skin(handle, UI.LOOKS.signature)
handle.rwFlat.fill:SetColorTexture(0.05, 0.28, 0.52, 0.95)
handle.label = UI.Text(handle, "GameFontHighlightSmall", "CENTER")
handle.label:SetPoint("CENTER")
handle.label:SetText("Rollwise board  ·  drag me  ·  right-click to pin")
handle:Hide()

local function remember()
  local ui = UIParent:GetEffectiveScale()
  local k = board:GetEffectiveScale() / (ui > 0 and ui or 1)
  local cx = board:GetCenter()
  local top, bottom = board:GetTop(), board:GetBottom()
  if not (cx and top and bottom) then return end
  RollwiseDB.anchor = { cx = cx * k, top = top * k, bottom = bottom * k }
end

handle:SetScript("OnDragStart", function() board:StartMoving() end)
handle:SetScript("OnDragStop", function()
  board:StopMovingOrSizing()
  remember()
  Cards:Anchor()
end)
handle:SetScript("OnClick", function() RW.SetOpt("pinned", true) end)

function Cards:Anchor()
  local size = RW.Opt("size") or 1
  board:SetScale(size)
  board:ClearAllPoints()
  local up = RW.Opt("flow") ~= "down"
  local spot = RollwiseDB and RollwiseDB.anchor
  if spot and spot.cx then
    if up then board:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", spot.cx / size, spot.bottom / size)
    else board:SetPoint("TOP", UIParent, "BOTTOMLEFT", spot.cx / size, spot.top / size) end
  elseif up then
    board:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 300 / size)
  else
    board:SetPoint("TOP", UIParent, "TOP", 0, -180 / size)
  end
  handle:ClearAllPoints()
  if up then handle:SetPoint("TOP", board, "BOTTOM", 0, -2) else handle:SetPoint("BOTTOM", board, "TOP", 0, 2) end
  handle:SetWidth(260)
  handle:SetShown(not RW.Opt("pinned"))
  self:Dirty()
end

------------------------------------------------------------------------------------------------
-- The game's roll windows: docking and giving back
------------------------------------------------------------------------------------------------

local home = {}    -- window -> { points = {...}, scale = n }: where the game last put it
local docked = {}  -- window -> true while Rollwise has placed it

local function gameWindows()
  local list = {}
  local holder = GroupLootContainer
  if not (holder and holder.GetChildren) then return list end
  for _, child in ipairs({ holder:GetChildren() }) do
    if type(child) == "table" and child.rollID ~= nil then list[#list + 1] = child end
  end
  return list
end

local function windowFor(e)
  if not e.rollID then return nil end
  for _, w in ipairs(gameWindows()) do
    if w:IsShown() and Safe.Plain(w.rollID) == e.rollID then return w end
  end
end

function Cards.IsUp(e) return e.preview == nil and windowFor(e) ~= nil end

local function noteHome(w)
  local points = {}
  for i = 1, (w:GetNumPoints() or 0) do points[i] = { w:GetPoint(i) } end
  home[w] = { points = points, scale = w:GetScale() }
end

local busy = false
local function dock(w, card, up)
  if not home[w] then noteHome(w) end
  busy = true
  local parent = w:GetParent()
  local base = parent and parent:GetEffectiveScale() or 1
  local want = board:GetEffectiveScale() / (base > 0 and base or 1)
  if math.abs(w:GetScale() - want) > 0.001 then w:SetScale(want) end
  w:ClearAllPoints()
  if up then w:SetPoint("BOTTOM", card, "TOP", 0, 1) else w:SetPoint("TOP", card, "BOTTOM", 0, -1) end
  docked[w] = true
  busy = false
end

local function undock(w)
  local spot = home[w]
  docked[w], home[w] = nil, nil
  if not spot then return end
  busy = true
  w:SetScale(spot.scale or 1)
  w:ClearAllPoints()
  for _, p in ipairs(spot.points) do pcall(w.SetPoint, w, unpack(p)) end
  busy = false
end

------------------------------------------------------------------------------------------------
-- Lines inside a card
------------------------------------------------------------------------------------------------

local function newPickLine(card)
  local l = CreateFrame("Button", nil, card)
  l:SetHeight(LINE_H)
  l.bar = l:CreateTexture(nil, "BACKGROUND", nil, 1)
  l.bar:SetPoint("TOPLEFT", 0, -1)
  l.bar:SetPoint("BOTTOMLEFT", 0, 1)
  l.shade = UI.Fill(l, "BACKGROUND", 1, 1, 1, 0)
  l.edge = l:CreateTexture(nil, "ARTWORK", nil, 2)
  l.edge:SetTexture(UI.WHITE)
  l.edge:SetWidth(2)
  l.edge:SetPoint("TOPLEFT", 0, -1)
  l.edge:SetPoint("BOTTOMLEFT", 0, 1)
  l.pill = l:CreateTexture(nil, "BACKGROUND", nil, 3)
  l.pill:SetTexture(UI.WHITE)
  l.pill:SetPoint("TOPRIGHT", -1, -2)
  l.pill:SetPoint("BOTTOMRIGHT", -1, 2)
  l.pill:SetWidth(30)
  l.shine = l:CreateTexture(nil, "OVERLAY", nil, 7)
  l.shine:SetSize(46, LINE_H)
  l.shine:SetPoint("LEFT", l, "LEFT", -46, 0)
  UI.Gradient(l.shine, "HORIZONTAL", { 1, 0.86, 0.35, 0 }, { 1, 0.86, 0.35, 0.45 })
  l.shine:Hide()
  local hover = l:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
  l.choice = UI.Icon(l, 14)
  l.choice:SetPoint("LEFT", 2, 0)
  l.class = UI.Icon(l, 12)
  l.class:SetPoint("LEFT", l.choice, "RIGHT", 3, 0)
  l.roll = UI.Text(l, "GameFontHighlight", "CENTER")
  l.roll:SetPoint("CENTER", l.pill, "CENTER", 0, 0)
  l.roll:SetWidth(30)
  l.lock = UI.Icon(l, 12, "OVERLAY")
  l.lock:SetPoint("RIGHT", -8, 0)
  UI.Paint(l.lock, "hidden")
  l.crown = UI.Icon(l, 12, "OVERLAY")
  l.crown:SetPoint("RIGHT", l.pill, "LEFT", -2, 0)
  UI.Paint(l.crown, "crown")
  l.count = UI.Text(l, "GameFontNormalSmall", "CENTER")
  l.count:SetPoint("RIGHT", l.crown, "LEFT", -3, 0)
  l.count:SetWidth(16)
  l.countBg = l:CreateTexture(nil, "ARTWORK")
  l.countBg:SetSize(14, 14)
  l.countBg:SetPoint("CENTER", l.count, "CENTER")
  l.countBg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  l.countBg:SetVertexColor(0.25, 0.20, 0.05, 0.9)
  l.name = UI.Text(l, "GameFontHighlightSmall")
  l.name:SetPoint("LEFT", l.class, "RIGHT", 4, 0)
  l.name:SetPoint("RIGHT", l.count, "LEFT", -4, 0)
  UI.Tip(l, function(tip, self)
    local p, e = self.pick, self.entry
    if not p then return end
    tip:SetText(UI.Colored(p.name, p.cls) .. (Ledger.IsYou(p) and "  |cff9d9d9d(you)|r" or ""))
    tip:AddDoubleLine(UI.Inline(p.choice) .. " " .. UI.ChoiceWord(p.choice, p.spec, true), p.roll ~= nil and ("%d"):format(p.roll) or "", 1, 1, 1, 1, 0.82, 0)
    if p.veiled then tip:AddLine("Part of this pick is hidden by the game right now.", 0.7, 0.7, 0.7, true) end
    if p.choice == "need" and p.spec == nil and not e.preview then
      tip:AddLine("Main / off spec unknown: this came from chat, not the game's loot history.", 0.6, 0.6, 0.6, true)
    end
    if self.outranked then tip:AddLine("Can't win: a stronger pick is in.", 1, 0.45, 0.45) end
    local wins = RW.Journal.WinsOf(p.name, e.page)
    if #wins > 0 then
      tip:AddLine(" ")
      tip:AddLine(("Already won this run (%d)"):format(#wins), 1, 0.82, 0)
      for _, page in ipairs(wins) do tip:AddLine("  " .. (page.link or "?"), 1, 1, 1) end
    end
  end)
  l.kind = "pick"
  return l
end

local function newHeadLine(card)
  local l = CreateFrame("Frame", nil, card)
  l:SetHeight(HEAD_H)
  l.tag = l:CreateTexture(nil, "ARTWORK")
  l.tag:SetTexture(UI.WHITE)
  l.tag:SetSize(3, 9)
  l.tag:SetPoint("LEFT", 1, 0)
  l.text = UI.Text(l, "GameFontNormalSmall")
  l.text:SetPoint("LEFT", 8, 0)
  l.rule = l:CreateTexture(nil, "ARTWORK")
  l.rule:SetHeight(1)
  l.rule:SetPoint("LEFT", l.text, "RIGHT", 6, 0)
  l.rule:SetPoint("RIGHT", -2, 0)
  l.kind = "head"
  return l
end

local function borrowLine(card, kind)
  card.lines[kind] = card.lines[kind] or {}
  local store = card.lines[kind]
  card.cursor[kind] = (card.cursor[kind] or 0) + 1
  local l = store[card.cursor[kind]]
  if not l then
    l = kind == "pick" and newPickLine(card) or newHeadLine(card)
    store[card.cursor[kind]] = l
  end
  l:Show()
  return l
end

local function hideUnused(card)
  for kind, store in pairs(card.lines) do
    for i = (card.cursor[kind] or 0) + 1, #store do store[i]:Hide() store[i].pick = nil end
  end
end

------------------------------------------------------------------------------------------------
-- A card
------------------------------------------------------------------------------------------------

local function buildCard()
  local c = CreateFrame("Frame", nil, board, "BackdropTemplate")
  c:EnableMouse(true)
  c:EnableMouseWheel(true)
  c.lines, c.cursor, c.scroll = {}, {}, 0

  -- item strip
  c.strip = CreateFrame("Frame", nil, c)
  c.strip:SetHeight(STRIP_H)
  c.icon = CreateFrame("Button", nil, c.strip)
  c.icon:SetSize(26, 26)
  c.icon:SetPoint("LEFT", 1, 0)
  c.icon.art = UI.Icon(c.icon, 26)
  c.icon.art:SetAllPoints()
  c.icon.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.icon.ring = c.icon:CreateTexture(nil, "OVERLAY")
  c.icon.ring:SetPoint("TOPLEFT", -2, 2)
  c.icon.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  c.icon.ring:SetTexture("Interface\\Common\\WhiteIconFrame")
  c.icon:SetScript("OnClick", function()
    local e = c.entry
    if not e then return end
    if IsAltKeyDown and IsAltKeyDown() then
      RW.Wishlist:Toggle(e.link)
    elseif UI.WantsLink() then
      UI.LinkToChat(e.link)
    end
  end)
  UI.Tip(c.icon, function(tip)
    if c.entry and type(c.entry.link) == "string" then tip:SetHyperlink(c.entry.link) end
    tip:AddLine("Alt-click: add to / remove from your wishlist", 0.5, 0.8, 1)
  end)

  -- wishlist glow: a gold frame just outside the card that breathes
  c.wishGlow = c:CreateTexture(nil, "BACKGROUND", nil, -7)
  c.wishGlow:SetTexture(UI.WHITE)
  c.wishGlow:SetVertexColor(1, 0.80, 0.10, 0.55)
  c.wishGlow:SetPoint("TOPLEFT", -3, 3)
  c.wishGlow:SetPoint("BOTTOMRIGHT", 3, -3)
  c.wishGlow:Hide()
  local okGlow, breathe = pcall(c.wishGlow.CreateAnimationGroup, c.wishGlow)
  if okGlow and breathe then
    local a = breathe:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.9)
    if breathe.SetLooping then breathe:SetLooping("BOUNCE") end
    c.wishBreathe = breathe
  end
  c.wishStar = UI.Icon(c, 16, "OVERLAY")
  c.wishStar:SetPoint("CENTER", c, "TOPLEFT", 4, -4)
  UI.Paint(c.wishStar, "wish")
  c.wishStar:Hide()
  c.clock = UI.Text(c.strip, "NumberFontNormal", "RIGHT")
  c.clock:SetPoint("RIGHT", -2, 0)
  c.title = UI.Text(c.strip, "GameFontNormal")
  c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, -1)
  c.title:SetPoint("RIGHT", c.clock, "LEFT", -6, 0)
  c.detail = UI.Text(c.strip, "GameFontDisableSmall")
  c.detail:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 6, 1)
  c.detail:SetPoint("RIGHT", c.clock, "LEFT", -6, 0)

  c.gear = UI.Text(c, "GameFontHighlightSmall")

  -- status band
  c.band = CreateFrame("Frame", nil, c)
  c.band:SetHeight(BAND_H)
  c.band.fill = UI.Fill(c.band, "BACKGROUND")
  c.accent = c:CreateTexture(nil, "OVERLAY")
  c.accent:SetHeight(2)
  c.accent:SetPoint("TOPLEFT", 1, -1)
  c.accent:SetPoint("TOPRIGHT", -1, -1)
  c.close = UI.Glyph(c.band, 15, "Interface\\Buttons\\UI-StopButton", function() Ledger:Dismiss(c.entry) end)
  c.close:SetPoint("RIGHT", -3, 0)
  c.fold = UI.Glyph(c.band, 13, nil, function()
    if c.entry then c.entry.folded = not c.entry.folded Cards:Dirty() end
  end)
  c.fold:SetPoint("RIGHT", c.close, "LEFT", -4, 0)
  c.menu = UI.Glyph(c.band, 14, "Interface\\Buttons\\UI-OptionsButton", function(_, button)
    RW.Window:Open(button == "RightButton" and "journal" or "settings")
  end)
  c.menu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.menu:SetPoint("RIGHT", c.fold, "LEFT", -4, 0)
  UI.Tip(c.menu, function(tip) tip:SetText("Rollwise") tip:AddLine("Click: settings   Right-click: journal", 1, 1, 1) end)
  c.odds = UI.Text(c.band, "GameFontNormalSmall", "RIGHT")
  c.odds:SetPoint("RIGHT", c.menu, "LEFT", -6, 0)
  c.status = UI.Text(c.band, "GameFontHighlightSmall")
  c.status:SetPoint("LEFT", 4, 0)
  c.status:SetPoint("RIGHT", c.odds, "LEFT", -6, 0)
  UI.Tip(c.band, function(tip)
    local e = c.entry
    if not e then return end
    local t = Ledger.Tally(e)
    tip:SetText("Picks so far")
    tip:AddDoubleLine(UI.Inline("need") .. " Need", t.need, 1, 1, 1, 1, 1, 1)
    if t.main + t.off > 0 then
      tip:AddDoubleLine("    " .. UI.SpecWord("main"), t.main, 1, 1, 1, 1, 1, 1)
      tip:AddDoubleLine("    " .. UI.SpecWord("off"), t.off, 1, 1, 1, 1, 1, 1)
    end
    if t.tmog > 0 then tip:AddDoubleLine(UI.Inline("tmog") .. " Transmog", t.tmog, 1, 1, 1, 1, 1, 1) end
    tip:AddDoubleLine(UI.Inline("greed") .. " Greed", t.greed, 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine(UI.Inline("pass") .. " Pass", t.pass, 1, 1, 1, 1, 1, 1)
    if t.deciding > 0 then tip:AddDoubleLine(UI.Inline("deciding") .. " Deciding", t.deciding, 0.8, 0.8, 0.8, 1, 1, 1) end
    tip:AddLine(" ")
    tip:AddLine("Strongest first: main spec Need, off spec Need, transmog, Greed. Within a group the highest roll wins. Which spec a Need counts for is the game's call.", 0.65, 0.65, 0.65, true)
    if e.veiled then tip:AddLine("Some of this roll is hidden by the game right now.", 0.9, 0.6, 0.3, true) end
  end, "ANCHOR_TOP")

  c.passChips = UI.Text(c, "GameFontDisableSmall")
  c.decidingChips = UI.Text(c, "GameFontDisableSmall")
  c.more = UI.Text(c, "GameFontDisableSmall", "RIGHT")

  c.timer = CreateFrame("StatusBar", nil, c)
  c.timer:SetHeight(CLOCK_H)
  c.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  c.timer:SetMinMaxValues(0, 1)
  UI.Fill(c.timer, "BACKGROUND", 0, 0, 0, 0.45)

  c:SetScript("OnMouseWheel", function(self, step)
    self.scroll = math.max(0, self.scroll - step)
    Cards:Dirty()
  end)
  return c
end

-- "label a, b, c +3" trimmed to the width.
local function chipLine(fs, icon, people, width)
  if #people == 0 then fs:Hide() return false end
  fs:Show()
  local names, shown = {}, 0
  for i, p in ipairs(people) do
    names[#names + 1] = p.name or "?"
    local rest = #people - i
    fs:SetText(icon .. " " .. table.concat(names, ", ") .. (rest > 0 and ("  +" .. rest) or ""))
    if fs:GetStringWidth() > width and i > 1 then
      names[#names] = nil
      break
    end
    shown = i
  end
  local rest = #people - shown
  fs:SetText(icon .. " " .. table.concat(names, ", ") .. (rest > 0 and ("  |cffb0b0b0+" .. rest .. "|r") or ""))
  return true
end

-- Where an item goes, by the game's slot names (looked up with GetInventorySlotInfo).
local WEARS_IN = {
  HEAD = "HeadSlot", NECK = "NeckSlot", SHOULDER = "ShoulderSlot", CHEST = "ChestSlot", ROBE = "ChestSlot",
  WAIST = "WaistSlot", LEGS = "LegsSlot", FEET = "FeetSlot", WRIST = "WristSlot", HAND = "HandsSlot",
  CLOAK = "BackSlot", FINGER = "Finger0Slot Finger1Slot", TRINKET = "Trinket0Slot Trinket1Slot",
  WEAPON = "MainHandSlot SecondaryHandSlot", ["2HWEAPON"] = "MainHandSlot", WEAPONMAINHAND = "MainHandSlot",
  WEAPONOFFHAND = "SecondaryHandSlot", SHIELD = "SecondaryHandSlot", HOLDABLE = "SecondaryHandSlot",
  RANGED = "RangedSlot", RANGEDRIGHT = "RangedSlot", THROWN = "RangedSlot", RELIC = "RangedSlot",
}

local function slotsFor(equipLoc)
  local names = type(equipLoc) == "string" and WEARS_IN[equipLoc:gsub("^INVTYPE_", "")]
  if not names then return nil end
  local ids = {}
  for slotName in names:gmatch("%S+") do
    local id = Safe.Plain(api.GetInventorySlotInfo(slotName))
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  return #ids > 0 and ids or nil
end

-- "Yours: [Old Helm] 52  +6 ilvl" against the weakest item you'd replace.
local function gearNote(e, facts)
  if not RW.Opt("gear") or not facts.level then return nil end
  local slots = slotsFor(facts.slot)
  if not slots then return nil end
  local weakest, weakestLink
  for _, slot in ipairs(slots) do
    local link = Safe.Plain(api.GetInventoryItemLink("player", slot))
    local level = type(link) == "string" and Safe.ItemFacts(link).level or 0
    if not weakest or level < weakest then weakest, weakestLink = level, link end
  end
  local diff = facts.level - (weakest or 0)
  local change = diff > 0 and ("|cff4cff4c+%d ilvl|r"):format(diff) or (diff < 0 and ("|cffff6060%d ilvl|r"):format(diff) or "|cffb0b0b0same ilvl|r")
  local yours = weakestLink and (Safe.LinkText(weakestLink) .. " " .. weakest) or "empty slot"
  return ("|cff9d9d9dYours:|r %s   %s"):format(yours, change)
end

local function fillPick(l, p, e, strongest)
  l.pick, l.entry = p, e
  UI.Paint(l.choice, p.choice)
  UI.ClassIcon(l.class, p.cls)
  l.name:SetText(UI.Colored(p.name, p.cls) .. (Ledger.IsYou(p) and " |cff7fb2ff•|r" or ""))
  local rgb = GROUP_RGB[Ledger.GroupOf(p) or "need"] or GROUP_RGB.need
  local tier = Ledger.Tier(p)
  l.outranked = (tier and strongest and tier > strongest and p.roll) and true or false
  local width = l:GetWidth() or 200
  local key = (e.serial or 0) .. ":" .. tostring(p.name)
  if l.barKey ~= key then l.barKey, l.barNow, l.shined = key, nil, nil end
  if type(l.barNow) ~= "number" then l.barNow = nil end
  if p.roll ~= nil then
    l.bar:Show()
    local strength = l.outranked and 0.10 or 0.30
    UI.Gradient(l.bar, "HORIZONTAL", { rgb[1], rgb[2], rgb[3], strength * 0.25 }, { rgb[1], rgb[2], rgb[3], strength })
    Cards.GrowBar(l, math.max(2, (width - 34) * p.roll / 100))
  else
    l.bar:Hide()
    l.barNow = nil
  end
  local flat = UI.Look().flat
  l.pill:SetShown(flat and p.roll ~= nil or false)
  if p.won then l.pill:SetVertexColor(1, 0.80, 0.15, 0.28) else l.pill:SetVertexColor(0, 0, 0, 0.40) end
  if p.won then l.edge:Show() l.edge:SetVertexColor(1, 0.80, 0.15, 1)
  elseif Ledger.IsYou(p) then l.edge:Show() l.edge:SetVertexColor(0.31, 0.76, 0.97, 1)
  else l.edge:Hide() end
  if p.won and not l.shined and UI.Motion() then
    l.shined = true
    Cards.Shine(l, width)
  end
  local done = e.stage == "decided" or e.stage == "settled"
  if p.won then l.roll:SetText("|cffffd100" .. (p.roll or "") .. "|r")
  elseif p.roll and l.outranked then l.roll:SetText("|cff6a6a6a" .. p.roll .. "|r")
  elseif p.roll then l.roll:SetText((not done and Ledger.Leader(e) == p) and ("|cffffffff" .. p.roll .. "|r") or ("|cffc9c9c9" .. p.roll .. "|r"))
  else l.roll:SetText(p.veiled and "" or "|cff5a5a5a·|r") end
  l.lock:SetShown(p.veiled and not p.roll and true or false)
  l.crown:SetShown(p.won == true)
  local count = RW.Opt("lootCount") and #RW.Journal.WinsOf(p.name, e.page) or 0
  l.count:SetText(count > 0 and tostring(count) or "")
  l.countBg:SetShown(count > 0)
  if p.won then l.shade:SetColorTexture(1, 0.8, 0.15, 0.16)
  elseif Ledger.IsYou(p) then l.shade:SetColorTexture(0.3, 0.55, 1, 0.10)
  else l.shade:SetColorTexture(1, 1, 1, 0) end
end

function Cards.Wanted(c, on)
  if c.wishShown == on then return end
  c.wishShown = on
  c.wishGlow:SetShown(on)
  c.wishStar:SetShown(on)
  if type(c.wishBreathe) == "table" then
    if on and UI.Motion() then c.wishBreathe:Play() else c.wishBreathe:Stop() end
  end
end

-- Roll bars fill toward their value instead of jumping.
function Cards.GrowBar(l, goal)
  if not UI.Motion() then
    l.barNow = goal
    l.bar:SetWidth(goal)
    return
  end
  l.barGoal = goal
  if type(l.barNow) ~= "number" then l.barNow = 1 end
  l.bar:SetWidth(l.barNow)
  if l.growing == true then return end
  l.growing = true
  l:SetScript("OnUpdate", function(self, elapsed)
    local step = math.min(1, (elapsed or 0.016) * 9)
    local now = self.barNow + (self.barGoal - self.barNow) * step
    if math.abs(self.barGoal - now) < 0.6 then
      now = self.barGoal
      self.growing = false
      self:SetScript("OnUpdate", nil)
    end
    self.barNow = now
    self.bar:SetWidth(math.max(1, now))
  end)
end

-- A gold glint that sweeps across the winner's line once.
function Cards.Shine(l, width)
  local group = l.shine.sweep
  if type(group) ~= "table" then
    local ok, made = pcall(l.shine.CreateAnimationGroup, l.shine)
    if not ok or not made then return end
    group = made
  end
  if type(l.shine.sweep) ~= "table" then l.shine.sweep = group end
  local sweep = l.shine.sweep
  if type(sweep.move) ~= "table" then
    sweep.move = sweep:CreateAnimation("Translation")
    sweep.move:SetDuration(0.75)
    if sweep.move.SetSmoothing then sweep.move:SetSmoothing("IN_OUT") end
    sweep:SetScript("OnFinished", function() l.shine:Hide() end)
  end
  sweep.move:SetOffset(width + 46, 0)
  l.shine:Show()
  sweep:Stop()
  sweep:Play()
end

local function statusFor(e, t)
  if e.nobody then return "|cff9d9d9dEveryone passed|r" end
  if e.winner then
    if Ledger.IsYou(e.winner) then return "|cff4cff4cYou won it!|r" end
    return UI.Colored(e.winner.name, e.winner.cls) .. " |cffffd100wins|r"
  end
  if e.unseen then return "|cff9d9d9dThe game kept the result hidden|r" end
  if e.spectator then return "|cffb0b0b0Others are rolling|r" end
  if t.deciding > 0 and RW.Opt("showDeciding") then return ("|cffd0d0d0Waiting on %d|r"):format(t.deciding) end
  local lead = Ledger.Leader(e)
  if lead and lead.roll then return UI.Colored(lead.name, lead.cls) .. " |cffd0d0d0leads|r" end
  return "|cffd0d0d0Rolling|r"
end

function Cards.Paint(c, e, window, width)
  local look = UI.Look()
  if c.look ~= RW.Opt("look") then
    UI.Skin(c)
    if look.flat then UI.Gradient(c.band.fill, "HORIZONTAL", look.band, look.bandFade)
    else c.band.fill:SetTexture(nil) c.band.fill:SetColorTexture(unpack(look.band)) end
    c.look = RW.Opt("look")
  end
  if c.entry ~= e then
    c.entry, c.scroll = e, 0
    local enter = UI.Motion() and UI.Entrance(c, -10)
    if enter then enter:Stop() enter:Play() end
  end
  c.accent:SetShown(look.flat and true or false)
  if look.flat then
    local qr, qg, qb = UI.QualityRGB(e.quality or Safe.ItemFacts(e.link).quality)
    UI.Gradient(c.accent, "HORIZONTAL", { qr, qg, qb, 0.95 }, { qr, qg, qb, 0.05 })
  end
  c.cursor = {}
  c:SetWidth(width)
  local inner = width - PAD * 2
  local y = -PAD
  local facts = Safe.ItemFacts(e.link)

  -- item strip (the docked game window already shows the item)
  c.strip:SetShown(window == nil)
  if not window then
    c.strip:ClearAllPoints()
    c.strip:SetPoint("TOPLEFT", PAD, y)
    c.strip:SetPoint("TOPRIGHT", -PAD, y)
    c.icon.art:SetTexture(e.icon or facts.icon or 134400)
    local r, g, b, hex = UI.QualityRGB(e.quality or facts.quality)
    c.icon.ring:SetVertexColor(r, g, b)
    c.title:SetText(hex .. Safe.LinkText(e.link) .. "|r")
    local bits = {}
    if facts.level then bits[#bits + 1] = "ilvl " .. facts.level end
    if facts.kind then bits[#bits + 1] = facts.kind end
    if e.bop == false then bits[#bits + 1] = "|cffff7070BoE|r" end
    if e.boss then bits[#bits + 1] = e.boss end
    c.detail:SetText(table.concat(bits, "  ·  "))
    y = y - STRIP_H - 2
  end

  local note = (not e.spectator) and gearNote(e, facts) or nil
  c.gear:SetShown(note ~= nil)
  if note then
    c.gear:ClearAllPoints()
    c.gear:SetPoint("TOPLEFT", PAD + 2, y)
    c.gear:SetPoint("RIGHT", -PAD, 0)
    c.gear:SetText(note)
    y = y - GEAR_H
  end

  -- status band
  c.band:ClearAllPoints()
  c.band:SetPoint("TOPLEFT", PAD - 2, y)
  c.band:SetPoint("TOPRIGHT", -PAD + 2, y)
  y = y - BAND_H - 3
  local t = Ledger.Tally(e)
  local status = statusFor(e, t)
  if e.wanted then status = UI.Inline("wish", 12) .. " |cffffd100Wishlist|r  " .. status end
  c.status:SetText(status)
  Cards.Wanted(c, e.wanted == true)
  local odds = RW.Opt("odds") and Ledger.Odds(e) or nil
  if odds == nil or e.winner or e.nobody then c.odds:SetText("")
  else
    local pct = math.floor(odds * 100 + 0.5)
    local hex = pct >= 50 and "ff4cff4c" or (pct > 0 and "ffffd100" or "ff9d9d9d")
    c.odds:SetText(("|c%sYou %d%%|r"):format(hex, pct))
  end
  c.fold.art:SetTexture(e.folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

  -- grouped picks
  local sections, passed, deciding = Ledger.Sections(e)
  local strongest
  for _, s in ipairs(sections) do
    for _, p in ipairs(s.picks) do
      local tier = Ledger.Tier(p)
      if p.roll and tier and (not strongest or tier < strongest) then strongest = tier end
    end
  end
  if RW.Opt("passView") == "rows" and #passed > 0 then
    sections[#sections + 1] = { group = "pass", picks = passed }
    passed = {}
  end
  local flat = {}
  for _, s in ipairs(sections) do
    flat[#flat + 1] = { head = s.group, count = #s.picks }
    for _, p in ipairs(s.picks) do flat[#flat + 1] = { pick = p } end
  end

  if not e.folded then
    local room = RW.Opt("rows") or 9
    local maxScroll = math.max(0, #flat - room)
    if c.scroll > maxScroll then c.scroll = maxScroll end
    for i = c.scroll + 1, math.min(#flat, c.scroll + room) do
      local item = flat[i]
      if item.head then
        local l = borrowLine(c, "head")
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", PAD, y)
        l:SetPoint("TOPRIGHT", -PAD, y)
        local rgb = GROUP_RGB[item.head] or { 0.6, 0.6, 0.6 }
        local title = item.head == "pass" and "Pass" or Ledger.GROUP_TITLE[item.head]
        l.text:SetText(("%s  |cff9d9d9d%d|r"):format(title:upper(), item.count))
        l.text:SetTextColor(rgb[1], rgb[2], rgb[3])
        l.tag:Show()
        l.tag:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        l.rule:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.18)
        y = y - HEAD_H
      else
        local l = borrowLine(c, "pick")
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", PAD, y)
        l:SetPoint("TOPRIGHT", -PAD, y)
        l:SetWidth(inner)
        fillPick(l, item.pick, e, strongest)
        y = y - LINE_H
      end
    end
    if #flat == 0 then
      local l = borrowLine(c, "head")
      l:ClearAllPoints()
      l:SetPoint("TOPLEFT", PAD, y)
      l:SetPoint("TOPRIGHT", -PAD, y)
      l.text:SetText(e.veiled and "Picks hidden by the game" or "No picks yet")
      l.text:SetTextColor(0.6, 0.6, 0.6)
      l.tag:Hide()
      l.rule:SetColorTexture(0, 0, 0, 0)
      y = y - HEAD_H
    end
    c.more:SetShown(#flat > room)
    if #flat > room then
      c.more:ClearAllPoints()
      c.more:SetPoint("TOPRIGHT", -PAD - 2, y)
      local below = #flat - room - c.scroll
      c.more:SetText(below > 0 and ("%d more  (scroll)"):format(below) or "top  (scroll up)")
      y = y - CHIP_H
    end
    local chipW = inner - 4
    if RW.Opt("passView") == "chips" then
      c.passChips:ClearAllPoints()
      c.passChips:SetPoint("TOPLEFT", PAD + 2, y - 1)
      if chipLine(c.passChips, UI.Inline("pass", 11), passed, chipW) then y = y - CHIP_H end
    else
      c.passChips:Hide()
    end
    if RW.Opt("showDeciding") and (e.stage == "open" or e.stage == "waiting") then
      c.decidingChips:ClearAllPoints()
      c.decidingChips:SetPoint("TOPLEFT", PAD + 2, y - 1)
      if chipLine(c.decidingChips, UI.Inline("deciding", 11), deciding, chipW) then y = y - CHIP_H end
    else
      c.decidingChips:Hide()
    end
  else
    c.more:Hide()
    c.passChips:Hide()
    c.decidingChips:Hide()
  end
  hideUnused(c)

  local ticking = RW.Opt("countdown") and e.deadline and (e.stage == "open" or e.stage == "waiting")
  c.timer:SetShown(ticking and true or false)
  if ticking then
    y = y - 3
    c.timer:ClearAllPoints()
    c.timer:SetPoint("TOPLEFT", PAD, y)
    c.timer:SetPoint("TOPRIGHT", -PAD, y)
    y = y - CLOCK_H
  end
  c:SetHeight(PAD - y)
  Cards.Tick(c)
end

-- Per-frame bits: clock text, timer bar, the fade before a card leaves.
function Cards.Tick(c)
  local e = c.entry
  if not e then return end
  local t = Ledger.Now()
  local left = e.deadline and (e.deadline - t) or 0
  if e.deadline and left > 0 and (e.stage == "open" or e.stage == "waiting") then
    c.clock:SetText(("%d"):format(math.ceil(left)))
    local share = math.min(1, math.max(0, left / (e.duration or 60)))
    c.timer:SetValue(share)
    c.timer:SetStatusBarColor(0.3 + 0.7 * (1 - share), 0.35 + 0.5 * share, 0.9 * share)
  else
    c.clock:SetText("")
  end
  if e.stage == "decided" and e.decidedAt and not Cards.hovering then
    local remaining = (RW.Opt("holdTime") or 10) - (t - e.decidedAt)
    c:SetAlpha(math.min(1, math.max(0.2, remaining / 1.5)))
  else
    c:SetAlpha(1)
  end
end

------------------------------------------------------------------------------------------------
-- Laying out the board
------------------------------------------------------------------------------------------------

local dirty = true
function Cards:Dirty() dirty = true end

function Cards:Render()
  dirty = false
  local on = RW.Opt("board")
  local docking = on and RW.Opt("dock")
  local up = RW.Opt("flow") ~= "down"
  local placed, offset, slot = {}, 0, 0
  for _, e in ipairs(Ledger.live) do
    local window = docking and windowFor(e) or nil
    if window then Cards.windowWidth = window:GetWidth() end
    local width = (RW.Opt("fitWidth") and Cards.windowWidth) or RW.Opt("width") or 290
    width = math.min(460, math.max(220, width))
    if on and (not e.dismissed or window) then
      slot = slot + 1
      local c = self.pool[slot] or buildCard()
      self.pool[slot] = c
      local extra = window and (window:GetHeight() + 1) or 0
      if e.dismissed then
        c:Hide()
        c.entry = nil
        c:SetSize(width, 1)
      else
        Cards.Paint(c, e, window, width)
        c:Show()
      end
      c:ClearAllPoints()
      if up then c:SetPoint("BOTTOM", board, "BOTTOM", 0, offset)
      else c:SetPoint("TOP", board, "TOP", 0, -(offset + extra)) end
      if window then dock(window, c, up) placed[window] = true end
      offset = offset + c:GetHeight() + extra + SPACING
      board:SetWidth(width)
    end
  end
  for i = slot + 1, #self.pool do self.pool[i]:Hide() self.pool[i].entry = nil end
  for w in pairs(docked) do
    if not placed[w] then undock(w) end
  end
  RW.Emit("BOARD_DRAWN", offset)
end

-- The game lays its windows out again whenever one opens or closes. Right after it does,
-- note where it put each one (that's where they go back to) and dock them again.
local function afterGameLayout()
  if busy then return end
  for _, w in ipairs(gameWindows()) do
    docked[w] = nil
    noteHome(w)
  end
  Cards:Render()
end
if hooksecurefunc then
  for _, fname in ipairs({ "GroupLootContainer_Update", "GroupLootContainer_AddFrame", "GroupLootContainer_RemoveFrame" }) do
    if type(_G[fname]) == "function" then hooksecurefunc(fname, afterGameLayout) end
  end
end

local clockFrame = CreateFrame("Frame")
local sinceTick = 0
clockFrame:SetScript("OnUpdate", function(_, elapsed)
  sinceTick = sinceTick + (elapsed or 0)
  if sinceTick < 0.2 and not dirty then return end
  local hovering = false
  for _, c in ipairs(Cards.pool) do
    if c:IsShown() and c:IsMouseOver() then hovering = true break end
  end
  hovering = hovering or (RW.Tray and RW.Tray.IsHovered())
  Cards.hovering = hovering
  if sinceTick >= 0.2 then
    sinceTick = 0
    local ok, moved = pcall(Ledger.Tick, Ledger, hovering, Cards.IsUp)
    if ok and moved then dirty = true end
    for _, c in ipairs(Cards.pool) do if c:IsShown() then Cards.Tick(c) end end
  end
  if dirty then
    local ok, err = pcall(Cards.Render, Cards)
    if not ok then RW.Note("render", err) end
  end
end)

RW.Watch("LEDGER", function() Cards:Dirty() end)
-- Wishlist changed: re-check live items (no alert for items already on the board).
RW.Watch("WISHLIST", function()
  for _, e in ipairs(Ledger.live) do
    if e.itemID then e.wanted = RW.Wishlist.Get(e.itemID) ~= nil end
  end
  Cards:Dirty()
end)
RW.Watch("DECIDED", function(e)
  if e.preview or not RW.Opt("winSound") or not (e.winner and Ledger.IsYou(e.winner)) then return end
  local kit = SOUNDKIT and (SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.READY_CHECK)
  if kit then RW.Safe.api.PlaySound(kit, "Master") end
end)
RW.Watch("ANCHOR", function() Cards:Anchor() end)
RW.Watch("READY", function() Cards:Anchor() end)
RW.OnOption(function(key)
  if key == "size" or key == "flow" or key == "pinned" then Cards:Anchor() end
  if key == "look" then for _, c in ipairs(Cards.pool) do c.look = nil end end
  Cards:Dirty()
end)
