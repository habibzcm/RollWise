-- Rollwise / Window: Journal (decided items by boss), Players (who has had what), Export, Settings.

local _, RW = ...
local Safe, UI, Journal = RW.Safe, RW.UI, RW.Journal

local Window = { page = "journal", filter = "all", query = "" }
RW.Window = Window

local WIDTH, HEIGHT = 780, 560
local frame

local function shownRun()
  local runs = Journal.Runs()
  local count = #runs
  local index = Window.runIndex
  if not index or index < 1 or index > count then index = count end
  return runs[index], index, count
end

------------------------------------------------------------------------------------------------
-- Virtual list: only builds as many lines as fit, scrolls with the wheel or the bar.
------------------------------------------------------------------------------------------------

local function scroller(parent, lineHeight, makeLine, drawLine)
  local box = CreateFrame("Frame", nil, parent)
  box.data, box.top, box.lines = {}, 0, {}
  box:EnableMouseWheel(true)

  local rail = CreateFrame("Slider", nil, box)
  rail:SetOrientation("VERTICAL")
  rail:SetWidth(10)
  rail:SetPoint("TOPRIGHT", -2, -2)
  rail:SetPoint("BOTTOMRIGHT", -2, 2)
  UI.Fill(rail, "BACKGROUND", 0, 0, 0, 0.35)
  local knob = rail:CreateTexture(nil, "OVERLAY")
  knob:SetSize(8, 28)
  knob:SetColorTexture(0.31, 0.54, 0.85, 0.85)
  rail:SetThumbTexture(knob)
  rail:SetValueStep(1)
  local syncing = false
  rail:SetScript("OnValueChanged", function(_, v)
    if syncing then return end
    box.top = math.floor(v + 0.5)
    box:Draw()
  end)
  box:SetScript("OnMouseWheel", function(_, step)
    local _, high = rail:GetMinMaxValues()
    rail:SetValue(math.min(high, math.max(0, box.top - step * 3)))
  end)

  function box:Show(data, keepPlace)
    self.data = data or {}
    if not keepPlace then self.top = 0 end
    self:Draw()
  end

  function box:Draw()
    local fit = math.max(1, math.floor((self:GetHeight() or 0) / lineHeight))
    local last = math.max(0, #self.data - fit)
    self.top = math.min(self.top, last)
    syncing = true
    rail:SetMinMaxValues(0, last)
    rail:SetValue(self.top)
    syncing = false
    rail:SetShown(last > 0)
    for i = 1, fit do
      local line = self.lines[i]
      if not line then
        line = makeLine(self)
        self.lines[i] = line
      end
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", 0, -(i - 1) * lineHeight)
      line:SetPoint("RIGHT", -16, 0)
      line:SetHeight(lineHeight)
      local item = self.data[self.top + i]
      line:SetShown(item ~= nil)
      if item then
        local ok, err = pcall(drawLine, line, item, self.top + i)
        if not ok then RW.Note("list", err) end
      end
    end
    for i = fit + 1, #self.lines do self.lines[i]:Hide() end
  end
  box:SetScript("OnSizeChanged", function() box:Draw() end)
  return box
end

local function rowFrame(parent)
  local row = CreateFrame("Button", nil, parent)
  row.tint = UI.Fill(row, "BACKGROUND")
  local glow = row:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(0.31, 0.54, 0.85, 0.12)
  return row
end

local function columnLabels(parent, y, columns)
  for _, c in ipairs(columns) do
    local t = UI.Text(parent, "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", c[2], y)
    t:SetText(c[1])
  end
end

local function pageRollsTooltip(tip, page)
  tip:SetHyperlink(page.link)
  tip:AddLine(" ")
  tip:AddLine((page.boss or "Trash") .. "  ·  " .. date("%H:%M", page.at or 0), 0.6, 0.6, 0.6)
  local picks = {}
  for _, p in ipairs(page.picks or {}) do picks[#picks + 1] = p end
  table.sort(picks, function(a, b)
    if (a.won and 1 or 0) ~= (b.won and 1 or 0) then return a.won and true or false end
    local ta, tb = RW.Ledger.Tier(a) or 9, RW.Ledger.Tier(b) or 9
    if ta ~= tb then return ta < tb end
    return (a.roll or 0) > (b.roll or 0)
  end)
  local passes = {}
  for _, p in ipairs(picks) do
    if p.choice == "pass" then
      passes[#passes + 1] = p.name
    else
      local left = UI.Inline(p.choice) .. " " .. UI.Colored(p.name, p.cls)
      if UI.SpecWord(p.spec) ~= "" then left = left .. "  " .. UI.SpecWord(p.spec) end
      local right = p.roll and tostring(p.roll) or "-"
      if p.won then right = UI.Inline("crown", 12) .. " |cffffd100" .. right .. "|r" end
      tip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
    end
  end
  if #passes > 0 then tip:AddLine(UI.Inline("pass", 11) .. " " .. table.concat(passes, ", "), 0.6, 0.6, 0.6, true) end
  if page.outcome == "nobody" then tip:AddLine("Everyone passed.", 0.6, 0.6, 0.6) end
  if page.source == "chat" then tip:AddLine("Read from chat: main / off spec not known.", 0.5, 0.5, 0.5, true) end
end

------------------------------------------------------------------------------------------------
-- Journal page
------------------------------------------------------------------------------------------------

local FILTERS = { { "all", "Everything" }, { "rolled", "I rolled" }, { "won", "I won" }, { "wish", "Wishlist" }, { "nobody", "No takers" } }

local function keep(page)
  local f = Window.filter
  if f == "won" and not (page.winner and page.winner.you) then return false end
  if f == "nobody" and page.outcome ~= "nobody" then return false end
  if f == "wish" and not (page.wanted or RW.Wishlist.Has(page.itemID)) then return false end
  if f == "rolled" then
    local mine = false
    for _, p in ipairs(page.picks or {}) do if p.you and p.choice ~= "pass" then mine = true end end
    if not mine then return false end
  end
  local q = Window.query
  if q ~= "" then
    local words = { Safe.LinkText(page.link), page.boss or "" }
    for _, p in ipairs(page.picks or {}) do words[#words + 1] = p.name or "" end
    if not table.concat(words, "|"):lower():find(q, 1, true) then return false end
  end
  return true
end

local function buildJournal(page)
  local search = UI.Make("EditBox", page, "SearchBoxTemplate", "InputBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("TOPLEFT", 12, -6)
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function(self)
    Window.query = (self:GetText() or ""):lower()
    page:Refresh()
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local buttons, after = {}, search
  for _, f in ipairs(FILTERS) do
    local b = UI.Button(page, f[2], 82, function() Window.filter = f[1] page:Refresh() end)
    b:SetPoint("LEFT", after, "RIGHT", after == search and 14 or 3, 0)
    b.value = f[1]
    buttons[#buttons + 1] = b
    after = b
  end
  local summary = UI.Text(page, "GameFontDisableSmall", "RIGHT")
  summary:SetPoint("TOPRIGHT", -14, -10)

  local X = { at = 6, item = 50, winner = 300, how = 450, tally = 600 }
  columnLabels(page, -34, { { "Time", X.at }, { "Item", X.item }, { "Went to", X.winner }, { "How", X.how }, { "N / G / P", X.tally } })

  local list = scroller(page, 22, function(box)
    local row = rowFrame(box)
    row.at = UI.Text(row, "GameFontHighlightSmall")
    row.at:SetPoint("LEFT", X.at, 0)
    row.icon = UI.Icon(row, 18)
    row.icon:SetPoint("LEFT", X.item, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.item = UI.Text(row, "GameFontNormal")
    row.item:SetPoint("LEFT", X.item + 24, 0)
    row.item:SetWidth(X.winner - X.item - 30)
    row.cls = UI.Icon(row, 14)
    row.cls:SetPoint("LEFT", X.winner, 0)
    row.winner = UI.Text(row, "GameFontHighlight")
    row.winner:SetPoint("LEFT", X.winner + 18, 0)
    row.winner:SetWidth(X.how - X.winner - 22)
    row.how = UI.Text(row, "GameFontHighlightSmall")
    row.how:SetPoint("LEFT", X.how, 0)
    row.how:SetWidth(X.tally - X.how - 6)
    row.tally = UI.Text(row, "GameFontHighlightSmall")
    row.tally:SetPoint("LEFT", X.tally, 0)
    row.boss = UI.Text(row, "GameFontNormalLarge")
    row.boss:SetPoint("LEFT", 6, -2)
    UI.Tip(row, function(tip, self)
      if self.page then pageRollsTooltip(tip, self.page) else tip:Hide() end
    end, "ANCHOR_CURSOR")
    row:SetScript("OnClick", function(self)
      if self.page and UI.WantsLink() then UI.LinkToChat(self.page.link) end
    end)
    return row
  end, function(row, item, index)
    local isHeader = item.header ~= nil
    row.page = item.page
    for _, part in ipairs({ row.at, row.icon, row.item, row.cls, row.winner, row.how, row.tally }) do part:SetShown(not isHeader) end
    row.boss:SetShown(isHeader)
    if isHeader then
      row.boss:SetText(item.header .. "  |cff808080" .. item.count .. "|r")
      row.tint:SetColorTexture(0.12, 0.26, 0.48, 0.35)
      return
    end
    local p = item.page
    if p.winner and p.winner.you then row.tint:SetColorTexture(1, 0.8, 0.15, 0.10)
    else row.tint:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0) end
    row.at:SetText(date("%H:%M", p.at or 0))
    row.icon:SetTexture(p.icon or RW.Safe.ItemFacts(p.itemID).icon or 134400)
    local _, _, _, hex = UI.QualityRGB(p.quality)
    local star = (p.wanted or RW.Wishlist.Has(p.itemID)) and (UI.Inline("wish", 12) .. " ") or ""
    row.item:SetText(star .. hex .. Safe.LinkText(p.link) .. "|r")
    local w = p.winner
    if p.outcome == "nobody" or not w then
      row.cls:Hide()
      row.winner:SetText("|cff808080nobody|r")
      row.how:SetText("")
    else
      UI.ClassIcon(row.cls, w.cls)
      row.winner:SetText(UI.Colored(w.name, w.cls) .. (w.you and "  |cff4cff4cyou|r" or ""))
      local word = w.choice == "need" and (UI.SpecWord(w.spec) ~= "" and ("Need " .. UI.SpecWord(w.spec)) or "Need") or UI.ChoiceWord(w.choice)
      row.how:SetText(word .. (w.roll and ("  |cffd0d0d0" .. w.roll .. "|r") or ""))
    end
    local n, g, pa = 0, 0, 0
    for _, x in ipairs(p.picks or {}) do
      if x.choice == "need" then n = n + 1 elseif x.choice == "pass" then pa = pa + 1 elseif x.choice then g = g + 1 end
    end
    row.tally:SetText(("%d / %d / %d"):format(n, g, pa))
  end)
  list:SetPoint("TOPLEFT", 6, -50)
  list:SetPoint("BOTTOMRIGHT", -6, 6)

  local empty = UI.Text(page, "GameFontDisable", "CENTER")
  empty:SetPoint("CENTER", list, "CENTER", 0, 30)
  if empty.SetWordWrap then empty:SetWordWrap(true) end
  empty:SetWidth(440)

  function page:Refresh()
    for _, b in ipairs(buttons) do
      if b.value == Window.filter then b:LockHighlight() else b:UnlockHighlight() end
    end
    local run = shownRun()
    local items = run and run.items or {}
    local rows, kept = {}, 0
    local lastBoss, lastHeader = false, nil
    for i = #items, 1, -1 do
      local p = items[i]
      if keep(p) then
        kept = kept + 1
        local boss = p.boss or "Trash and chests"
        if boss ~= lastBoss then
          lastHeader = { header = boss, count = 0 }
          rows[#rows + 1] = lastHeader
          lastBoss = boss
        end
        lastHeader.count = lastHeader.count + 1
        rows[#rows + 1] = { page = p }
      end
    end
    list:Show(rows, true)
    summary:SetText(("%d of %d items"):format(kept, #items))
    if #items == 0 then
      empty:SetText("Nothing decided in this run yet.\n\nTry |cffffd100/rollwise preview|r to see the board.")
    elseif kept == 0 then
      empty:SetText("No items match.")
    end
    empty:SetShown(kept == 0)
  end
end

------------------------------------------------------------------------------------------------
-- Players page
------------------------------------------------------------------------------------------------

local function buildPlayers(page)
  local intro = UI.Text(page, "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", 12, -10)
  intro:SetText("Who has had loot this run. MS / OS: won with a main spec or off spec Need (the game's call).")

  local X = { name = 30, wins = 210, ms = 270, os = 320, other = 370, needs = 440, rolls = 510, recent = 570 }
  columnLabels(page, -34, { { "Player", X.name }, { "Won", X.wins }, { "MS", X.ms },
    { "OS", X.os }, { "Other", X.other }, { "Needs", X.needs }, { "Rolls", X.rolls }, { "Latest", X.recent } })

  local list = scroller(page, 22, function(box)
    local row = rowFrame(box)
    row.cls = UI.Icon(row, 15)
    row.cls:SetPoint("LEFT", 8, 0)
    row.name = UI.Text(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", X.name, 0)
    row.name:SetWidth(X.wins - X.name - 6)
    row.cells = {}
    for _, key in ipairs({ "wins", "mainWins", "offWins", "otherWins", "needs", "rolls" }) do
      local cell = UI.Text(row, key == "wins" and "GameFontNormal" or "GameFontHighlightSmall", "CENTER")
      cell:SetWidth(40)
      row.cells[key] = cell
    end
    row.cells.wins:SetPoint("LEFT", X.wins - 10, 0)
    row.cells.mainWins:SetPoint("LEFT", X.ms - 10, 0)
    row.cells.offWins:SetPoint("LEFT", X.os - 10, 0)
    row.cells.otherWins:SetPoint("LEFT", X.other - 10, 0)
    row.cells.needs:SetPoint("LEFT", X.needs - 10, 0)
    row.cells.rolls:SetPoint("LEFT", X.rolls - 10, 0)
    row.recent = UI.Text(row, "GameFontHighlightSmall")
    row.recent:SetPoint("LEFT", X.recent, 0)
    row.recent:SetPoint("RIGHT", -6, 0)
    UI.Tip(row, function(tip, self)
      local r = self.record
      if not r then return end
      tip:SetText(UI.Colored(r.name, r.cls))
      tip:AddLine(("%d won · %d rolled on · %d Needs"):format(r.wins, r.rolls, r.needs), 0.8, 0.8, 0.8)
      for _, page in ipairs(r.pages) do
        local w = page.winner or {}
        tip:AddDoubleLine(page.link or "?", "|cffb0b0b0" .. UI.ChoiceWord(w.choice, w.spec) .. (w.roll and (" " .. w.roll) or "") .. "|r")
      end
    end, "ANCHOR_CURSOR")
    return row
  end, function(row, r, index)
    row.record = r
    row.tint:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
    UI.ClassIcon(row.cls, r.cls)
    row.name:SetText(UI.Colored(r.name, r.cls))
    for key, cell in pairs(row.cells) do
      local v = r[key] or 0
      cell:SetText(v > 0 and tostring(v) or "|cff4a4a4a-|r")
    end
    local names = {}
    for i = #r.pages, math.max(1, #r.pages - 1), -1 do names[#names + 1] = r.pages[i].link or "?" end
    row.recent:SetText(table.concat(names, " "))
  end)
  list:SetPoint("TOPLEFT", 6, -50)
  list:SetPoint("BOTTOMRIGHT", -6, 34)

  local nothing = UI.Text(page, "GameFontHighlightSmall")
  nothing:SetPoint("BOTTOMLEFT", 12, 12)
  nothing:SetPoint("RIGHT", -12, 0)

  function page:Refresh()
    local run = shownRun()
    list:Show((Journal.Tally(run)), true)
    local empty = Journal.EmptyHanded(run)
    if #empty == 0 then
      nothing:SetText("")
    else
      local names = {}
      for _, m in ipairs(empty) do names[#names + 1] = UI.Colored(m.name, m.cls) end
      nothing:SetText("|cffffd100Nothing yet this run:|r " .. table.concat(names, ", "))
    end
  end
end

------------------------------------------------------------------------------------------------
-- Export page
------------------------------------------------------------------------------------------------

local function buildExport(page)
  local format = "text"
  local tabs, after = {}, nil
  for _, f in ipairs(Journal.FORMATS) do
    local b = UI.Button(page, f.label, 90, function() format = f.key page:Refresh() end)
    if after then b:SetPoint("LEFT", after, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 12, -6) end
    b.value = f.key
    tabs[#tabs + 1] = b
    after = b
  end
  local hint = UI.Text(page, "GameFontDisableSmall")
  hint:SetPoint("LEFT", after, "RIGHT", 12, 0)
  hint:SetText("Select all, then Ctrl+C. Discord format pastes as a tidy list.")

  local well = CreateFrame("Frame", nil, page, "BackdropTemplate")
  well:SetPoint("TOPLEFT", 8, -34)
  well:SetPoint("BOTTOMRIGHT", -8, 8)
  UI.Skin(well, UI.LOOKS.modern)
  local pane = UI.Make("ScrollFrame", well, "UIPanelScrollFrameTemplate")
  pane:SetPoint("TOPLEFT", 8, -8)
  pane:SetPoint("BOTTOMRIGHT", -28, 8)
  local text = CreateFrame("EditBox", nil, pane)
  text:SetMultiLine(true)
  text:SetAutoFocus(false)
  text:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  text:SetWidth(WIDTH - 90)
  text:SetScript("OnEscapePressed", text.ClearFocus)
  pane:SetScrollChild(text)

  local pick = UI.Button(page, "Select all", 100, function() text:SetFocus() text:HighlightText() end)
  pick:SetPoint("TOPRIGHT", -12, -6)

  local content = ""
  text:SetScript("OnTextChanged", function(self, typed) if typed then self:SetText(content) end end)

  function page:Refresh()
    for _, b in ipairs(tabs) do
      if b.value == format then b:LockHighlight() else b:UnlockHighlight() end
    end
    content = Journal.Export((shownRun()), format)
    text:SetText(content)
    text:SetCursorPosition(0)
  end
end

------------------------------------------------------------------------------------------------
-- Wishlist page
------------------------------------------------------------------------------------------------

local function buildWishlist(page)
  local Wishlist = RW.Wishlist

  local slot = CreateFrame("Button", nil, page)
  slot:SetSize(40, 40)
  slot:SetPoint("TOPLEFT", 14, -8)
  slot.art = UI.Icon(slot, 40, "BACKGROUND")
  slot.art:SetAllPoints()
  slot.art:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  slot.plus = UI.Text(slot, "GameFontNormalHuge", "CENTER")
  slot.plus:SetPoint("CENTER", 0, 1)
  slot.plus:SetText("+")
  slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  local function takeFromCursor()
    local kind, id, link = RW.Safe.api.GetCursorInfo()
    if Safe.Plain(kind) ~= "item" then return end
    Wishlist:Add(Safe.Plain(link) or Safe.Plain(id))
    if ClearCursor then ClearCursor() end
  end
  slot:SetScript("OnReceiveDrag", takeFromCursor)
  slot:SetScript("OnClick", takeFromCursor)
  UI.Tip(slot, function(tip)
    tip:SetText("Add to wishlist")
    tip:AddLine("Drop an item here.", 1, 1, 1)
  end)

  local how = UI.Text(page, "GameFontHighlight")
  how:SetPoint("TOPLEFT", slot, "TOPRIGHT", 12, -2)
  local how2 = UI.Text(page, "GameFontHighlightSmall")
  how2:SetPoint("TOPLEFT", how, "BOTTOMLEFT", 0, -4)
  how2:SetText("While this tab is open, |cffffd100Shift-click|r any item link (AtlasLoot, chat, auction house) to add it.")
  local how3 = UI.Text(page, "GameFontDisableSmall")
  how3:SetPoint("TOPLEFT", how2, "BOTTOMLEFT", 0, -3)
  how3:SetText("Also: Alt-click items you have, drag one onto the slot, or paste a link / item ID below. Each character has its own list.")
  local tally = UI.Text(page, "GameFontNormal", "RIGHT")
  tally:SetPoint("TOPRIGHT", -14, -12)

  local paste = UI.Make("EditBox", page, "InputBoxTemplate")
  paste:SetSize(230, 20)
  paste:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 6, -10)
  paste:SetAutoFocus(false)
  paste.hint = UI.Text(paste, "GameFontDisableSmall")
  paste.hint:SetPoint("LEFT", 2, 0)
  paste.hint:SetText("Paste a link or item ID, then Enter")
  paste:HookScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
  paste:SetScript("OnEnterPressed", function(self)
    local text = self:GetText() or ""
    if text ~= "" then Wishlist.Command(text) end
    self:SetText("")
    self:ClearFocus()
  end)
  paste:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local bindButton = UI.Button(page, "Use Ctrl+W", 110, function() Wishlist.QuickBind("CTRL-W") end)
  bindButton:SetPoint("LEFT", paste, "RIGHT", 14, 0)
  local keyNote = UI.Text(page, "GameFontDisableSmall")
  keyNote:SetPoint("LEFT", bindButton, "RIGHT", 8, 0)
  keyNote:SetText("or any key: Options > Keybindings > AddOns > Rollwise")

  page:SetScript("OnShow", function() Wishlist.collecting = true end)
  page:SetScript("OnHide", function() Wishlist.collecting = false end)

  local X = { item = 8, status = 290, seen = 410, last = 470, who = 600 }
  columnLabels(page, -88, { { "Item", X.item }, { "Status", X.status }, { "Seen", X.seen }, { "Last seen", X.last }, { "Last went to", X.who } })

  local list = scroller(page, 26, function(box)
    local row = rowFrame(box)
    row.icon = CreateFrame("Button", nil, row)
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", X.item, 0)
    row.icon.art = UI.Icon(row.icon, 22)
    row.icon.art:SetAllPoints()
    row.icon.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Tip(row.icon, function(tip, self) if self.link then tip:SetHyperlink(self.link) end end)
    row.icon:SetScript("OnClick", function(self) if UI.WantsLink() then UI.LinkToChat(self.link) end end)
    row.item = UI.Text(row, "GameFontNormal")
    row.item:SetPoint("LEFT", X.item + 28, 0)
    row.item:SetWidth(X.status - X.item - 34)
    row.status = UI.Text(row, "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", X.status, 0)
    row.status:SetWidth(X.seen - X.status - 6)
    row.seen = UI.Text(row, "GameFontHighlight", "CENTER")
    row.seen:SetPoint("LEFT", X.seen, 0)
    row.seen:SetWidth(36)
    row.last = UI.Text(row, "GameFontHighlightSmall")
    row.last:SetPoint("LEFT", X.last, 0)
    row.last:SetWidth(X.who - X.last - 6)
    row.who = UI.Text(row, "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", X.who, 0)
    row.who:SetWidth(100)
    row.drop = UI.Glyph(row, 16, "Interface\\Buttons\\UI-StopButton", function(self) Wishlist:Remove(self:GetParent().record.id) end)
    row.drop:SetPoint("RIGHT", -4, 0)
    UI.Tip(row.drop, function(tip) tip:SetText("Remove from wishlist") end)
    row.got = UI.Glyph(row, 16, "Interface\\RaidFrame\\ReadyCheck-Ready", function(self)
      local r = self:GetParent().record
      Wishlist:SetGot(r.id, not r.got)
    end)
    row.got:SetPoint("RIGHT", row.drop, "LEFT", -6, 0)
    UI.Tip(row.got, function(tip) tip:SetText("Mark as got / not got") end)
    return row
  end, function(row, w, index)
    row.record = w
    row.tint:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
    local link = w.link
    row.icon.link = link
    row.icon.art:SetTexture(RW.Safe.ItemFacts(link).icon or 134400)
    local _, _, _, hex = UI.QualityRGB(RW.Safe.ItemFacts(link).quality)
    row.item:SetText(hex .. Safe.LinkText(link) .. "|r")
    row.item:SetAlpha(w.got and 0.55 or 1)
    if w.got then row.status:SetText("|cff4cff4cGot it|r " .. Wishlist.Ago(w.got))
    elseif (w.seen or 0) == 0 then row.status:SetText("|cffb0b0b0Waiting for a drop|r")
    else row.status:SetText("|cffffd100Still hunting|r") end
    row.seen:SetText((w.seen or 0) > 0 and tostring(w.seen) or "|cff4a4a4a-|r")
    row.last:SetText(w.lastSeen and (Wishlist.Ago(w.lastSeen) .. (w.lastWhere and ("  |cff9d9d9d" .. w.lastWhere .. "|r") or "")) or "|cff4a4a4a-|r")
    if w.lastOutcome == "nobody" then row.who:SetText("|cff9d9d9dnobody|r")
    else row.who:SetText(w.lastWinner and UI.Colored(w.lastWinner, w.lastWinnerClass) or "|cff4a4a4a-|r") end
    row.got.art:SetDesaturated(not w.got)
    row.got.art:SetAlpha(w.got and 1 or 0.45)
  end)
  list:SetPoint("TOPLEFT", 6, -104)
  list:SetPoint("BOTTOMRIGHT", -6, 6)

  local empty = UI.Text(page, "GameFontDisable", "CENTER")
  empty:SetPoint("CENTER", list, "CENTER", 0, 20)
  if empty.SetWordWrap then empty:SetWordWrap(true) end
  empty:SetWidth(460)
  empty:SetText("Your wishlist is empty.\n\nAlt-click an item you want. When it drops, Rollwise will make sure you notice.")

  function page:Refresh()
    local key = Wishlist.BoundKey()
    how:SetText(key and ("Point at any item and press |cffffd100%s|r to add or remove it, even items you don't own."):format(key)
      or "Point at any item and press your |cffffd100wishlist key|r to add it, even items you don't own. Set one: |cffffd100Use Ctrl+W|r.")
    bindButton:SetShown(key == nil)
    keyNote:ClearAllPoints()
    if key then keyNote:SetPoint("LEFT", paste, "RIGHT", 14, 0) keyNote:SetText("Change the key in Options > Keybindings > AddOns > Rollwise")
    else keyNote:SetPoint("LEFT", bindButton, "RIGHT", 8, 0) keyNote:SetText("or any key: Options > Keybindings > AddOns > Rollwise") end
    local items = Wishlist.List()
    list:Show(items, true)
    local open, total = Wishlist.Count()
    tally:SetText(("%d wanted  ·  %d got"):format(open, total - open))
    empty:SetShown(#items == 0)
  end
end

------------------------------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------------------------------

local PAGES = { { "journal", "Journal" }, { "wishlist", "Wishlist" }, { "players", "Players" }, { "export", "Export" }, { "settings", "Settings" } }

local function setTitle(f, text)
  if f.SetTitle then pcall(f.SetTitle, f, text) return end
  if type(f.TitleText) == "table" then f.TitleText:SetText(text) return end
  f.ownTitle = f.ownTitle or UI.Text(f, "GameFontNormal", "CENTER")
  f.ownTitle:SetPoint("TOP", 0, -6)
  f.ownTitle:SetText(text)
end

local function build()
  local f
  for _, template in ipairs({ "ButtonFrameTemplate", "BasicFrameTemplateWithInset" }) do
    local ok, made = pcall(CreateFrame, "Frame", "RollwiseWindow", UIParent, template)
    if ok and made then f = made break end
  end
  if not f then
    f = CreateFrame("Frame", "RollwiseWindow", UIParent, "BackdropTemplate")
    UI.Skin(f, UI.LOOKS.classic)
    local x = UI.Make("Button", f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -2, -2)
    x:SetScript("OnClick", function() f:Hide() end)
  end
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetClampedToScreen(true)
  local portrait = (type(f.PortraitContainer) == "table" and f.PortraitContainer.portrait) or (type(f.portrait) == "table" and f.portrait) or nil
  if portrait and portrait.SetTexture then portrait:SetTexture(UI.ICON) end
  if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
  if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end
  f:Hide()

  -- Run picker
  local runBar = CreateFrame("Frame", nil, f)
  runBar:SetPoint("TOPLEFT", 64, -26)
  runBar:SetPoint("TOPRIGHT", -12, -26)
  runBar:SetHeight(34)
  local back = UI.Glyph(runBar, 22, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", function()
    local _, i = shownRun()
    if i > 1 then Window.runIndex = i - 1 Window:Refresh() end
  end)
  back:SetPoint("LEFT", 0, 0)
  local fwd = UI.Glyph(runBar, 22, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", function()
    local _, i, n = shownRun()
    Window.runIndex = (i < n) and (i + 1) or nil
    Window:Refresh()
  end)
  fwd:SetPoint("LEFT", back, "RIGHT", 2, 0)
  local runTitle = UI.Text(runBar, "GameFontNormalLarge")
  runTitle:SetPoint("TOPLEFT", fwd, "TOPRIGHT", 8, 4)
  local runInfo = UI.Text(runBar, "GameFontDisableSmall")
  runInfo:SetPoint("TOPLEFT", runTitle, "BOTTOMLEFT", 0, -2)
  local split = UI.Button(runBar, "New run", 90, function()
    Journal:Begin(nil, true)
    Window.runIndex = nil
    Window:Refresh()
  end)
  split:SetPoint("RIGHT", 0, 0)
  UI.Tip(split, function(tip)
    tip:SetText("New run")
    tip:AddLine("Rollwise starts one on its own when you enter a different dungeon or raid.", 1, 1, 1, true)
  end)
  function runBar:Refresh()
    local run, i, n = shownRun()
    back:SetEnabled(i > 1)
    fwd:SetEnabled(i < n)
    if not run then runTitle:SetText("No runs yet") runInfo:SetText("") return end
    runTitle:SetText(run.title .. (run.mode and ("  |cff9d9d9d" .. run.mode .. "|r") or ""))
    local yours = 0
    for _, p in ipairs(run.items) do if p.winner and p.winner.you then yours = yours + 1 end end
    runInfo:SetText(("%s   ·   %d items   ·   %d for you   ·   run %d of %d"):format(
      date("%a %d %b %H:%M", run.opened or 0), #run.items, yours, i, n))
  end
  f.runBar = runBar

  f.pages = {}
  for _, def in ipairs(PAGES) do
    local page = CreateFrame("Frame", nil, f)
    local own = def[1] == "settings" or def[1] == "wishlist"
    page:SetPoint("TOPLEFT", 8, own and -60 or -64)
    page:SetPoint("BOTTOMRIGHT", -8, 8)
    page:Hide()
    f.pages[def[1]] = page
  end
  buildJournal(f.pages.journal)
  buildPlayers(f.pages.players)
  buildExport(f.pages.export)
  buildWishlist(f.pages.wishlist)
  RW.Settings.Build(f.pages.settings)
  f.pages.settings.Refresh = RW.Settings.Sync

  f.tabs = {}
  for i, def in ipairs(PAGES) do
    local tab = UI.Make("Button", f, "PanelTabButtonTemplate", "UIPanelButtonTemplate", "RollwiseWindowTab" .. i)
    tab:SetText(def[2])
    tab:SetID(i)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    if tab:GetWidth() < 40 then tab:SetSize(96, 24) end
    if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 2, 0) end
    tab:SetScript("OnClick", function() Window:Open(def[1]) end)
    tab.key = def[1]
    f.tabs[i] = tab
  end
  f.Tabs = f.tabs
  if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, f, #PAGES) end
  return f
end

function Window:Refresh()
  if not (frame and frame:IsShown()) then return end
  frame.runBar:SetShown(self.page ~= "settings" and self.page ~= "wishlist")
  frame.runBar:Refresh()
  local page = frame.pages[self.page]
  if page and page.Refresh then page:Refresh() end
end

function Window:Open(key)
  if not RW.ready then return end
  frame = frame or build()
  self.page = key or self.page
  frame:Show()
  for name, page in pairs(frame.pages) do page:SetShown(name == self.page) end
  for i, tab in ipairs(frame.tabs) do
    if tab.key == self.page then
      if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, frame, i) end
      tab:LockHighlight()
    else
      tab:UnlockHighlight()
    end
  end
  local titles = { settings = "Settings", wishlist = "Wishlist", players = "Players", export = "Export" }
  setTitle(frame, "Rollwise  -  " .. (titles[self.page] or "Journal"))
  self:Refresh()
end

function Window:Toggle(key)
  if frame and frame:IsShown() and (key == nil or key == self.page) then frame:Hide() return end
  self:Open(key)
end

RW.Watch("JOURNAL", function() Window:Refresh() end)
RW.Watch("WISHLIST", function() Window:Refresh() end)
