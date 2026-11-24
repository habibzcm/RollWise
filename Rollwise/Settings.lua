-- Rollwise / Settings: the settings page is described by a list below and built from it. The
-- same page appears in the Rollwise window and under Options > AddOns.

local _, RW = ...
local UI = RW.UI

local Settings = { syncers = {} }
RW.Settings = Settings

function Settings.Sync()
  for _, fn in ipairs(Settings.syncers) do pcall(fn) end
end
RW.OnOption(function() Settings.Sync() end)

local function synced(fn)
  Settings.syncers[#Settings.syncers + 1] = fn
  fn()
end

local function explain(frame, title, body)
  if not body then return end
  frame:EnableMouse(true)
  UI.Tip(frame, function(tip)
    tip:SetText(title)
    tip:AddLine(body, 1, 1, 1, true)
  end)
end

------------------------------------------------------------------------------------------------
-- Controls (each returns a frame with a height)
------------------------------------------------------------------------------------------------

local control = {}

function control.check(parent, key, label, help)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(320, 22)
  local box = UI.Make("CheckButton", row, "UICheckButtonTemplate")
  box:SetSize(22, 22)
  box:SetPoint("LEFT", -2, 0)
  for _, field in ipairs({ "Text", "text" }) do
    if type(box[field]) == "table" and box[field].SetText then box[field]:SetText("") end
  end
  local text = UI.Text(row, "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 2, 0)
  text:SetText(label)
  box:SetScript("OnClick", function(self) RW.SetOpt(key, self:GetChecked() == true) end)
  synced(function() box:SetChecked(RW.Opt(key) == true) end)
  explain(row, label, help)
  return row
end

function control.radio(parent, key, label, choices, help)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(320, 22)
  local title = UI.Text(row, "GameFontNormal")
  title:SetPoint("LEFT", 0, 0)
  title:SetWidth(84)
  title:SetText(label)
  local buttons, after = {}, title
  for _, choice in ipairs(choices) do
    local b = UI.Make("CheckButton", row, "UIRadioButtonTemplate", "UICheckButtonTemplate")
    b:SetSize(17, 17)
    b:SetPoint("LEFT", after, "RIGHT", after == title and 0 or 8, 0)
    for _, field in ipairs({ "Text", "text" }) do
      if type(b[field]) == "table" and b[field].SetText then b[field]:SetText("") end
    end
    local word = UI.Text(row, "GameFontHighlightSmall")
    word:SetPoint("LEFT", b, "RIGHT", 1, 0)
    word:SetText(choice[2])
    b.value = choice[1]
    b:SetScript("OnClick", function()
      if type(key) == "function" then key(choice[1]) else RW.SetOpt(key, choice[1]) end
      Settings.Sync()
    end)
    buttons[#buttons + 1] = b
    after = word
  end
  synced(function()
    local current = type(key) == "function" and key() or RW.Opt(key)
    for _, b in ipairs(buttons) do b:SetChecked(b.value == current) end
  end)
  explain(row, label, help)
  return row
end

-- A slider with - and + steppers.
function control.slider(parent, key, label, low, high, step, shown, help)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(320, 36)
  local title = UI.Text(row, "GameFontNormal")
  title:SetPoint("TOPLEFT", 0, 0)
  title:SetText(label)
  local value = UI.Text(row, "GameFontHighlight", "RIGHT")
  value:SetPoint("TOPRIGHT", -6, 0)

  local s = CreateFrame("Slider", nil, row)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(16)
  s:SetPoint("BOTTOMLEFT", 20, 0)
  s:SetPoint("BOTTOMRIGHT", -26, 0)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetHeight(5)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetColorTexture(0.05, 0.08, 0.14, 0.9)
  local edge = s:CreateTexture(nil, "BORDER")
  edge:SetHeight(7)
  edge:SetPoint("LEFT", -1, 0)
  edge:SetPoint("RIGHT", 1, 0)
  edge:SetColorTexture(0.31, 0.54, 0.85, 0.5)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(low, high)
  s:SetValueStep(step)
  if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end

  local quiet = false
  local function snap(v) return math.max(low, math.min(high, math.floor((v - low) / step + 0.5) * step + low)) end
  local function show(v) value:SetText(shown and shown(v) or tostring(v)) end
  s:SetScript("OnValueChanged", function(_, v)
    v = snap(v)
    show(v)
    if not quiet then RW.SetOpt(key, v) end
  end)
  local minus = UI.Glyph(row, 16, "Interface\\Buttons\\UI-MinusButton-Up", function() s:SetValue(snap(s:GetValue() - step)) end)
  minus:SetPoint("RIGHT", s, "LEFT", -3, 0)
  local plus = UI.Glyph(row, 16, "Interface\\Buttons\\UI-PlusButton-Up", function() s:SetValue(snap(s:GetValue() + step)) end)
  plus:SetPoint("LEFT", s, "RIGHT", 3, 0)
  synced(function()
    quiet = true
    local v = RW.Opt(key) or low
    s:SetValue(v)
    show(v)
    quiet = false
  end)
  explain(row, label, help)
  return row
end

function control.buttons(parent, list)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(320, 24)
  local after
  for _, spec in ipairs(list) do
    local b = UI.Button(row, spec[1], spec[3] or 120, spec[2])
    if after then b:SetPoint("LEFT", after, "RIGHT", 6, 0) else b:SetPoint("LEFT", 0, 0) end
    after = b
  end
  return row
end

function control.header(parent, text)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(320, 26)
  local title = UI.Text(row, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 0, -2)
  title:SetText(text)
  local rule = row:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 0, 2)
  rule:SetPoint("BOTTOMRIGHT", 0, 2)
  rule:SetColorTexture(0.31, 0.54, 0.85, 0.45)
  return row
end

------------------------------------------------------------------------------------------------
-- The page
------------------------------------------------------------------------------------------------

local function percent(v) return ("%d%%"):format(v * 100 + 0.5) end
local function seconds(v) return v .. " s" end

local function chatPreset(value)
  if value then RW.Chatter.ApplyPreset(value) end
  return RW.Chatter.CurrentPreset()
end

local LAYOUT = {
  { 1, "header", "Board" },
  { 1, "check", "board", "Show the roll board", "A card for every item being rolled on: each pick grouped by strength, rolls, the leader and the winner." },
  { 1, "radio", "look", "Look", { { "signature", "Rollwise" }, { "modern", "Tooltip" }, { "classic", "Classic" } } },
  { 1, "check", "motion", "Animations", "Cards slide in, roll bars fill, the winner's row shines." },
  { 1, "check", "dock", "Dock the game's roll windows on their cards", "Each Need / Greed window sits on top of its card and moves and scales with the board. Turn off if another addon moves the roll windows." },
  { 1, "check", "fitWidth", "Same width as the game's roll window" },
  { 1, "slider", "width", "Width", 220, 460, 10, nil, "Used when the width isn't matched to the game's roll window." },
  { 1, "slider", "size", "Size", 0.6, 1.6, 0.05, percent },
  { 1, "radio", "flow", "Stack", { { "up", "Upward" }, { "down", "Downward" } } },
  { 1, "buttons", { { "Move board", function() RW.SetOpt("pinned", not RW.Opt("pinned")) end, 110 },
                    { "Default spot", function() RollwiseDB.anchor = nil RW.Emit("ANCHOR") end, 110 } } },
  { 1, "buttons", { { "Preview", function() RW.Preview:Play() end, 110 },
                    { "Raid preview", function() RW.Preview:Play("raid") end, 110 } } },
  { 1, "header", "Chat" },
  { 1, "radio", chatPreset, "Roll lines", { { "all", "All" }, { "results", "Results only" }, { "none", "None" } },
    "Quick choices for the four boxes below." },
  { 1, "check", "hideMine", "Hide your own choices" },
  { 1, "check", "hideOthers", "Hide other players' choices" },
  { 1, "check", "hideNumbers", "Hide roll numbers (\"Need Roll - 54 ...\")" },
  { 1, "check", "hideResults", "Hide who won", "Turn the Rollwise result line on if you hide these." },
  { 1, "radio", "chatWhere", "Where", { { "everywhere", "Everywhere" }, { "instances", "Dungeons and raids" } } },
  { 1, "check", "recap", "Rollwise result line per item (only you see it)" },

  { 2, "header", "Lists" },
  { 2, "slider", "rows", "Lines before scrolling", 4, 20, 1 },
  { 2, "slider", "holdTime", "Keep decided items", 3, 30, 1, seconds, "Hovering the board keeps them longer." },
  { 2, "radio", "passView", "Passes", { { "chips", "One line" }, { "rows", "Own group" }, { "off", "Hidden" } } },
  { 2, "radio", "specWords", "Spec", { { "short", "MS / OS" }, { "long", "Main spec / Off spec" } },
    "The game decides whether a Need counts for main spec or off spec; Rollwise shows its answer." },
  { 2, "check", "showDeciding", "Show who is still deciding" },
  { 2, "check", "lootCount", "Items each player already won this run" },
  { 2, "check", "odds", "Your chance to win", "Worked out from the picks so far: a stronger pick means 0%, otherwise your share of your group." },
  { 2, "check", "gear", "Compare with what you wear", "Item level against the item you'd replace." },
  { 2, "check", "countdown", "Countdown bar" },
  { 2, "check", "tray", "Recent items tray", "The last items to leave the board, as icons. Click one to see its card again." },
  { 2, "check", "winSound", "Sound when you win something" },
  { 2, "header", "Wishlist" },
  { 2, "check", "wishSound", "Sound when a wishlist item drops" },
  { 2, "check", "wishBanner", "Banner on screen when it drops" },
  { 2, "check", "wishTooltip", "Wishlist line on item tooltips" },
  { 2, "check", "wishRemoveOnWin", "Remove items from the list once you win them", "Off: they stay, marked \"Got it\"." },
}

-- The page scrolls, so every option stays reachable at any window size or UI scale.
function Settings.Build(host)
  local view = UI.Make("ScrollFrame", host, "UIPanelScrollFrameTemplate")
  view:SetPoint("TOPLEFT", 0, 0)
  view:SetPoint("BOTTOMRIGHT", -26, 4)
  local sheet = CreateFrame("Frame", nil, view)
  sheet:SetSize(720, 100)
  view:SetScrollChild(sheet)

  local cursor = { -10, -10 }
  local X = { 16, 372 }
  for _, line in ipairs(LAYOUT) do
    local col, kind = line[1], line[2]
    local frame = control[kind](sheet, select(3, unpack(line)))
    frame:SetPoint("TOPLEFT", sheet, "TOPLEFT", X[col], cursor[col])
    cursor[col] = cursor[col] - frame:GetHeight() - (kind == "header" and 4 or 3)
  end
  local bottom = math.min(cursor[1], cursor[2]) - 10
  local foot = UI.Text(sheet, "GameFontDisableSmall")
  foot:SetPoint("TOPLEFT", sheet, "TOPLEFT", X[1], bottom)
  foot:SetText("Rollwise is read-only: it shows rolls, it never makes them.")
  sheet:SetHeight(-bottom + 24)

  -- Wheel scrolling (the template has its own; this covers clients without it).
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", function(self, step)
    local most = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(most, (self:GetVerticalScroll() or 0) - step * 40)))
  end)
  local function fit() sheet:SetWidth(math.max(700, (view:GetWidth() or 700))) end
  view:HookScript("OnSizeChanged", fit)
  fit()
  Settings.view = view
end

------------------------------------------------------------------------------------------------
-- Options > AddOns
------------------------------------------------------------------------------------------------

RW.Watch("READY", function()
  local S = _G.Settings
  if not (S and S.RegisterCanvasLayoutCategory) then return end
  local canvas = CreateFrame("Frame")
  local logo = UI.Icon(canvas, 32)
  logo:SetPoint("TOPLEFT", 14, -10)
  logo:SetTexture(UI.ICON)
  local name = UI.Text(canvas, "GameFontNormalHuge")
  name:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  name:SetText(RW.BRAND .. "  |cff808080" .. tostring(RW.version) .. "|r")
  local body = CreateFrame("Frame", nil, canvas)
  body:SetPoint("TOPLEFT", 0, -48)
  body:SetPoint("BOTTOMRIGHT")
  Settings.Build(body)
  canvas:SetScript("OnShow", Settings.Sync)
  local ok, category = pcall(S.RegisterCanvasLayoutCategory, canvas, "Rollwise")
  if ok and category then
    pcall(S.RegisterAddOnCategory, category)
    Settings.category = category
  end
end)
