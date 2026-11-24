-- Rollwise / Tray: a strip of the last items that left the board. Hover one for its rolls,
-- click it to put its card back for a moment. It shows for a while after an item settles,
-- and again with /rollwise recent.

local _, RW = ...
local UI, Ledger, Cards = RW.UI, RW.Ledger, RW.Cards

local Tray = {}
RW.Tray = Tray

local SIZE, GAP, LINGER = 22, 3, 90

local strip = CreateFrame("Frame", nil, Cards.board)
strip:SetHeight(SIZE + 4)
strip:Hide()
local label = UI.Text(strip, "GameFontDisableSmall")
label:SetPoint("LEFT", 0, 0)
label:SetText("Recent")
local slots = {}
local visibleUntil = 0

local function rollsTooltip(tip, e)
  tip:SetHyperlink(e.link)
  tip:AddLine(" ")
  local sections, passed = Ledger.Sections(e)
  for _, s in ipairs(sections) do
    for _, p in ipairs(s.picks) do
      local left = UI.Inline(p.choice) .. " " .. UI.Colored(p.name, p.cls)
      local spec = UI.SpecWord(p.spec)
      if spec ~= "" then left = left .. "  " .. spec end
      tip:AddDoubleLine(left, (p.won and "|cffffd100" or "|cffd0d0d0") .. (p.roll or "-") .. "|r")
    end
  end
  if #passed > 0 then
    local names = {}
    for _, p in ipairs(passed) do names[#names + 1] = p.name end
    tip:AddLine(UI.Inline("pass", 11) .. " " .. table.concat(names, ", "), 0.6, 0.6, 0.6, true)
  end
  if e.nobody then tip:AddLine("Everyone passed.", 0.6, 0.6, 0.6) end
  tip:AddLine(" ")
  tip:AddLine("Click: show the card again", 0.5, 0.8, 1)
end

local function slot(i)
  if slots[i] then return slots[i] end
  local b = UI.Glyph(strip, SIZE)
  b.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.ring = b:CreateTexture(nil, "OVERLAY")
  b.ring:SetPoint("TOPLEFT", -2, 2)
  b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  b.ring:SetTexture("Interface\\Common\\WhiteIconFrame")
  b.mark = UI.Icon(b, 11, "OVERLAY")
  b.mark:SetPoint("BOTTOMRIGHT", 3, -3)
  UI.Paint(b.mark, "crown")
  b:SetScript("OnClick", function(self)
    if UI.WantsLink() then UI.LinkToChat(self.entry.link) else Ledger:Recall(self.entry) end
  end)
  UI.Tip(b, function(tip, self) if self.entry then rollsTooltip(tip, self.entry) end end)
  slots[i] = b
  return b
end

function Tray.IsHovered() return strip:IsShown() and strip:IsMouseOver() end

function Tray.Refresh(boardHeight)
  local items = Ledger.tray
  local show = RW.Opt("tray") and RW.Opt("board") and #items > 0
    and (Ledger.Now() < visibleUntil or strip:IsMouseOver())
  strip:SetShown(show and true or false)
  if not show then return end
  local up = RW.Opt("flow") ~= "down"
  strip:ClearAllPoints()
  local lift = (boardHeight or 0)
  if up then strip:SetPoint("BOTTOM", Cards.board, "BOTTOM", 0, lift)
  else strip:SetPoint("TOP", Cards.board, "TOP", 0, -lift) end
  local x = label:GetStringWidth() + 6
  for i = #items, 1, -1 do
    local e = items[i]
    local b = slot(#items - i + 1)
    b.entry = e
    b.art:SetTexture(e.icon or RW.Safe.ItemFacts(e.link).icon or 134400)
    local r, g, bl = UI.QualityRGB(e.quality)
    b.ring:SetVertexColor(r, g, bl)
    b.mark:SetShown(e.winner ~= nil and Ledger.IsYou(e.winner))
    b:ClearAllPoints()
    b:SetPoint("LEFT", strip, "LEFT", x, 0)
    b:Show()
    x = x + SIZE + GAP
  end
  for i = #items + 1, #slots do slots[i]:Hide() end
  strip:SetWidth(x)
end

RW.Watch("TRAY_SHOW", function()
  visibleUntil = Ledger.Now() + LINGER
  Cards:Dirty()
end)
RW.Watch("BOARD_DRAWN", function(height)
  local ok, err = pcall(Tray.Refresh, height)
  if not ok then RW.Note("tray", err) end
end)

-- Re-check now and then so the strip can fade out on its own.
local wait = 0
strip:SetScript("OnUpdate", function(_, elapsed)
  wait = wait + (elapsed or 0)
  if wait > 1 then wait = 0 Tray.Refresh(Cards.lastHeight) end
end)
RW.Watch("BOARD_DRAWN", function(height) Cards.lastHeight = height end)
