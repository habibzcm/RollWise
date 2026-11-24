-- Rollwise / Widgets: every frame Rollwise builds goes through these few makers, so the look
-- stays consistent and the game-template fallbacks live in one place.

local _, RW = ...
local Safe = RW.Safe

local UI = {}
RW.UI = UI

local MEDIA = "Interface\\AddOns\\" .. RW.addon .. "\\media\\"
UI.MEDIA = MEDIA
UI.ICON = MEDIA .. "icon"

-- Frame from a game template if this client has it, else from the fallback template.
function UI.Make(kind, parent, template, fallback, name)
  if template then
    local built, frame = pcall(CreateFrame, kind, name, parent, template)
    if built and frame then return frame end
  end
  return CreateFrame(kind, name, parent, fallback)
end

-- Tooltips: build(tooltip, owner) fills it in.
function UI.TipAt(owner, build, anchor)
  local tip = GameTooltip
  tip:SetOwner(owner or UIParent, anchor or "ANCHOR_RIGHT")
  local ok, err = pcall(build, tip, owner)
  if not ok then RW.Note("tooltip", err) end
  tip:Show()
end

function UI.Tip(frame, build, anchor)
  frame:HookScript("OnEnter", function(self) UI.TipAt(self, build, anchor) end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.Text(parent, font, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

function UI.Fill(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r or 0, g or 0, b or 0, a or 0)
  return t
end

function UI.Icon(parent, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size, size)
  return t
end

-- Panel looks.
UI.LOOKS = {
  -- Rollwise's own look: a flat dark panel, hairline border, soft shadow, quality accent.
  signature = { flat = true, fill = { 0.030, 0.038, 0.060, 0.95 }, line = { 0.16, 0.27, 0.45, 0.95 },
    glow = { 1, 1, 1, 0.05 }, band = { 0.10, 0.20, 0.38, 0.90 }, bandFade = { 0.05, 0.09, 0.17, 0.10 },
    atlas = true },
  modern = { bg = "Interface\\Tooltips\\UI-Tooltip-Background", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, inset = 3, fill = { 0.02, 0.04, 0.10, 0.93 }, line = { 0.31, 0.54, 0.85, 1 },
    band = { 0.12, 0.26, 0.48, 0.50 }, atlas = true },
  classic = { bg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edge = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16, inset = 4, fill = { 1, 1, 1, 0.97 }, line = { 1, 1, 1, 1 },
    band = { 0.50, 0.36, 0.06, 0.32 }, atlas = false },
}
function UI.Look() return UI.LOOKS[RW.Opt("look")] or UI.LOOKS.signature end

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.WHITE = WHITE

-- Two-colour gradient on a texture (modern API first, older one second, flat colour last).
function UI.Gradient(tex, direction, a, b)
  tex:SetTexture(WHITE)
  if CreateColor and tex.SetGradient then
    local ok = pcall(tex.SetGradient, tex, direction, CreateColor(a[1], a[2], a[3], a[4] or 1), CreateColor(b[1], b[2], b[3], b[4] or 1))
    if ok then return end
  end
  if tex.SetGradientAlpha then
    local ok = pcall(tex.SetGradientAlpha, tex, direction, a[1], a[2], a[3], a[4] or 1, b[1], b[2], b[3], b[4] or 1)
    if ok then return end
  end
  tex:SetVertexColor((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, ((a[4] or 1) + (b[4] or 1)) / 2)
end

-- The flat panel parts: shadow, fill, inner sheen and a hairline border.
local function flatParts(frame)
  if type(frame.rwFlat) == "table" then return frame.rwFlat end
  local parts = { shadow = {}, edges = {} }
  for i = 1, 3 do
    local s = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    s:SetTexture(WHITE)
    s:SetVertexColor(0, 0, 0, 0.16 - i * 0.04)
    s:SetPoint("TOPLEFT", -i, i - 1)
    s:SetPoint("BOTTOMRIGHT", i, -i - 2)
    parts.shadow[i] = s
  end
  parts.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  parts.fill:SetAllPoints()
  parts.sheen = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
  parts.sheen:SetPoint("TOPLEFT", 1, -1)
  parts.sheen:SetPoint("TOPRIGHT", -1, -1)
  parts.sheen:SetHeight(24)
  for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                          { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local e = frame:CreateTexture(nil, "BORDER", nil, 7)
    e:SetTexture(WHITE)
    e:SetPoint(side[1])
    e:SetPoint(side[2])
    if side[3] then e:SetHeight(1) else e:SetWidth(1) end
    parts.edges[i] = e
  end
  frame.rwFlat = parts
  return parts
end

local function showFlat(parts, shown)
  for _, s in ipairs(parts.shadow) do s:SetShown(shown) end
  for _, e in ipairs(parts.edges) do e:SetShown(shown) end
  parts.fill:SetShown(shown)
  parts.sheen:SetShown(shown)
end

function UI.Skin(frame, look)
  look = look or UI.Look()
  if look.flat then
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local parts = flatParts(frame)
    showFlat(parts, true)
    parts.fill:SetColorTexture(unpack(look.fill))
    UI.Gradient(parts.sheen, "VERTICAL", { 1, 1, 1, 0 }, look.glow)
    for _, e in ipairs(parts.edges) do e:SetVertexColor(unpack(look.line)) end
    return
  end
  if type(frame.rwFlat) == "table" then showFlat(frame.rwFlat, false) end
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ edgeFile = look.edge, bgFile = look.bg, edgeSize = look.edgeSize,
    tile = true, tileSize = 16, insets = { left = look.inset, right = look.inset, top = look.inset, bottom = look.inset } })
  frame:SetBackdropColor(unpack(look.fill))
  frame:SetBackdropBorderColor(unpack(look.line))
end

------------------------------------------------------------------------------------------------
-- Art for each choice
------------------------------------------------------------------------------------------------

local CHOICE_ART = {
  need = { "lootroll-icon-need", "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
  greed = { "lootroll-icon-greed", "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
  tmog = { "lootroll-icon-transmog", "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
  pass = { "lootroll-icon-pass", "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
  deciding = { nil, "Interface\\RaidFrame\\ReadyCheck-Waiting" },
  hidden = { nil, "Interface\\LFGFrame\\UI-LFG-ICON-LOCK" },
  crown = { nil, "Interface\\GroupFrame\\UI-Group-LeaderIcon" },
  wish = { nil, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
}

local atlasCache = {}
local function atlasExists(name)
  if not name then return false end
  if atlasCache[name] == nil then
    atlasCache[name] = Safe.lib("C_Texture").GetAtlasInfo(name) ~= nil
  end
  return atlasCache[name]
end
UI.AtlasExists = atlasExists

function UI.Paint(tex, what)
  local art = CHOICE_ART[what or "deciding"]
  if not art then tex:Hide() return end
  tex:Show()
  tex:SetTexCoord(0, 1, 0, 1)
  if UI.Look().atlas and atlasExists(art[1]) then tex:SetAtlas(art[1]) else tex:SetTexture(art[2]) end
end

function UI.Inline(what, size)
  local art = CHOICE_ART[what or "deciding"]
  size = size or 13
  if not art then return "" end
  if UI.Look().atlas and atlasExists(art[1]) then return ("|A:%s:%d:%d|a"):format(art[1], size, size) end
  return ("|T%s:%d:%d|t"):format(art[2], size, size)
end

-- Class emblem: the modern atlas when there is one, else a cut of the old class sheet.
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function UI.ClassIcon(tex, class)
  local wanted = type(class) == "string" and class or nil
  tex:SetShown(wanted ~= nil)
  if not wanted then return end
  local emblem = ("classicon-%s"):format(string.lower(wanted))
  if atlasExists(emblem) then
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAtlas(emblem)
    return
  end
  local cut = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[wanted]
  tex:SetShown(cut ~= nil)
  if cut then
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(unpack(cut, 1, 4))
  end
end

function UI.Colored(name, class)
  if not name then return "|cff9d9d9d?|r" end
  local c = type(class) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if not c then return "|cffe6e6e6" .. name .. "|r" end
  local hex = c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
  return "|c" .. hex .. name .. "|r"
end

function UI.QualityRGB(q)
  local swatch = q ~= nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] or nil
  if not swatch then return 0.9, 0.9, 0.9, "|cffe6e6e6" end
  return swatch.r, swatch.g, swatch.b, swatch.hex or "|cffffffff"
end

------------------------------------------------------------------------------------------------
-- Words for choices
------------------------------------------------------------------------------------------------

UI.SPEC_HEX = { main = "ffffd100", off = "ff7fb2ff" }

function UI.SpecWord(spec)
  if spec ~= "main" and spec ~= "off" then return "" end
  local long = RW.Opt("specWords") == "long"
  local word = spec == "main" and (long and "Main spec" or "MS") or (long and "Off spec" or "OS")
  return "|c" .. UI.SPEC_HEX[spec] .. word .. "|r"
end

local CHOICE_WORD = { pass = "Pass", tmog = "Transmog", greed = "Greed", need = "Need" }
function UI.ChoiceWord(choice, spec, full)
  local word = CHOICE_WORD[choice] or "Deciding"
  if choice == "need" and (spec == "main" or spec == "off") then
    word = word .. " " .. (full and (spec == "main" and "(main spec)" or "(off spec)") or (spec == "main" and "MS" or "OS"))
  end
  return word
end

------------------------------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------------------------------

function UI.Button(parent, label, width, onClick)
  local b = UI.Make("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, 22)
  b:SetText(label)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Glyph(parent, size, file, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size)
  b:SetHeight(size)
  b.art = b:CreateTexture(nil, "ARTWORK")
  b.art:SetPoint("TOPLEFT")
  b.art:SetPoint("BOTTOMRIGHT")
  if file then b.art:SetTexture(file) end
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

------------------------------------------------------------------------------------------------
-- Motion (can be turned off in settings)
------------------------------------------------------------------------------------------------

function UI.Motion() return RW.Opt("motion") ~= false end

-- A short slide-and-fade used when something appears.
function UI.Entrance(frame, distance)
  if type(frame.rwEntrance) == "table" then return frame.rwEntrance end
  local ok, group = pcall(frame.CreateAnimationGroup, frame)
  if not ok or not group then return nil end
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(0)
  fade:SetToAlpha(1)
  fade:SetDuration(0.22)
  local slide = group:CreateAnimation("Translation")
  slide:SetOffset(0, distance or -10)
  slide:SetDuration(0)
  slide:SetOrder(1)
  local settle = group:CreateAnimation("Translation")
  settle:SetOffset(0, -(distance or -10))
  settle:SetDuration(0.22)
  if settle.SetSmoothing then settle:SetSmoothing("OUT") end
  settle:SetOrder(1)
  frame.rwEntrance = group
  return group
end

-- Shift-click a link into the chat box.
function UI.LinkToChat(link)
  if type(link) ~= "string" then return end
  local put = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  if put then pcall(put, link) end
end

function UI.WantsLink() return IsModifiedClick ~= nil and IsModifiedClick("CHATLINK") end
