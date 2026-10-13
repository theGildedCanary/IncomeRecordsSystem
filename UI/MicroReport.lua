-- A single movable amount, independent of the main window and Mini Dashboard.
local IRS = IRS
local GOLD = {0.86, 0.71, 0.36}
local WHITE = {0.88, 0.84, 0.75}
local BACKGROUND = {0.165, 0.125, 0.085, 0.86}
local BORDER = {0.52, 0.39, 0.22, 1}

-- Keep the report's theme local; never recolor the shared game tooltip.
local tooltip = IRS:CreateMicroTooltip()
local function StyleTooltip()
    if tooltip.NineSlice then tooltip.NineSlice:Hide() end
    tooltip:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    tooltip:SetBackdropColor(unpack(BACKGROUND))
    tooltip:SetBackdropBorderColor(unpack(BORDER))
end
tooltip:HookScript("OnShow", StyleTooltip)

local function StyleMenuText(description, color)
    description:AddInitializer(function(button)
        if button.fontString then
            button.fontString:SetFontObject(IRS:GetControlFont("main"))
            button.fontString:SetTextColor(unpack(color))
            button:SetHeight(math.max(button:GetHeight(), button.fontString:GetStringHeight() + 12))
        end
        if button.leftTexture2 then button.leftTexture2:SetVertexColor(unpack(GOLD)) end
    end)
    return description
end

local function StyleMenu(menu)
    -- Acquisition runs after Blizzard generates the background and before it
    -- creates option rows. Include child textures (e.g. the NineSlice border).
    -- The menu compositor restores these pooled regions when it releases them.
    local function HideDefaultBackground(frame)
        for _, region in ipairs({frame:GetRegions()}) do
            if region:IsObjectType("Texture") then region:SetAlpha(0) end
        end
        for _, child in ipairs({frame:GetChildren()}) do
            HideDefaultBackground(child)
        end
    end
    HideDefaultBackground(menu)
    local background = menu:AttachTexture()
    background:SetAlpha(1)
    background:SetDrawLayer("BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(unpack(BACKGROUND))
    for _, edge in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local line = menu:AttachTexture()
        line:SetAlpha(1)
        line:SetDrawLayer("BORDER")
        line:SetColorTexture(unpack(BORDER))
        if edge == "TOP" or edge == "BOTTOM" then
            line:SetHeight(1)
            line:SetPoint(edge .. "LEFT")
            line:SetPoint(edge .. "RIGHT")
        else
            line:SetWidth(1)
            line:SetPoint("TOP" .. edge)
            line:SetPoint("BOTTOM" .. edge)
        end
    end
end
local modes = {
    {key = "character", label = "Character Gold"},
    {key = "totalGold", label = "Total Gold"},
    {key = "warband", label = "Warband Bank"},
    {key = "token", label = "WoW Token"},
    {key = "hour", label = "Profit Per Hour"},
    {key = "session", label = "Session Net"},
    {key = "today", label = "Daily Net"},
    {key = "week", label = "Weekly Net"},
    {key = "month", label = "Monthly Net"},
    {key = "total", label = "Total Recorded Net"},
}
local labels = {}
for _, mode in ipairs(modes) do labels[mode.key] = mode.label end

local sessionNet, rateBaseline, rateStarted = 0, 0, GetTime()
local sessionEarned, sessionSpent = 0, 0
-- Use the central ledger so internal-transfer corrections also reach the report.
hooksecurefunc(IRS, "RecordEarnings", function(self, amount, sourceDeltas, characterKey, reversesTransfer)
    amount = math.floor(tonumber(amount) or 0)
    sessionNet = sessionNet + amount
    if reversesTransfer then
        if amount > 0 then sessionSpent = math.max(0, sessionSpent - amount)
        else sessionEarned = math.max(0, sessionEarned + amount) end
    elseif amount > 0 then sessionEarned = sessionEarned + amount
    else sessionSpent = sessionSpent - amount end
end)

function IRS:GetMicroReportSettings()
    if not self.db then self:EnsureDB() end
    self.db.ui = self.db.ui or {}
    self.db.ui.microReport = self.db.ui.microReport or {}
    local settings = self.db.ui.microReport
    if not labels[settings.mode] then settings.mode = "today" end
    return settings
end

function IRS:GetMicroReportValue()
    local mode = self:GetMicroReportSettings().mode
    if mode == "character" then return GetMoney() end
    if mode == "totalGold" then return self:GetAccountLiquidGoldAllCharacters() end
    if mode == "warband" then
        if not self.db.account.warbandGoldSeen then return nil end
        return self.db.account.warbandGold
    end
    if mode == "token" then
        local value = self:GetTokenMarketSummary().current
        return value and value > 0 and value or nil
    end
    if mode == "session" then return sessionNet end
    if mode == "hour" then
        local elapsed = GetTime() - rateStarted
        return elapsed >= 1 and (sessionNet - rateBaseline) * 3600 / elapsed or 0
    end
    return self:GetCurrentEarnings()[mode] or 0
end

local report = CreateFrame("Frame", "IncomeRecordsSystemMicroReport", UIParent, "BackdropTemplate")
IRS.microReportFrame = report
IRS:RegisterFormattingRoot(report, "main")
report:SetSize(170, 28)
report:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
report:SetFrameStrata("MEDIUM")
report:SetClampedToScreen(true)
report:SetMovable(true)
report:EnableMouse(true)
report:RegisterForDrag("LeftButton")
report:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
report:SetBackdropColor(0.165, 0.125, 0.085, 0.90)
report:SetBackdropBorderColor(0.52, 0.39, 0.22, 1)
report:Hide()
local valueText = report:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
IRS:RegisterFontString("main", "body", valueText, STANDARD_TEXT_FONT, "")
valueText:SetPoint("CENTER")

local function FormatCoins(value, goldOnly)
    if value == nil then return "Unavailable" end
    local copper = math.floor(math.abs(value))
    if goldOnly then
        return (value < 0 and "-" or "") .. IRS:FormatCount(math.floor(copper / 10000))
            .. "|TInterface/MoneyFrame/UI-GoldIcon:0:0:2:0|t"
    end
    return (value < 0 and "-" or "") .. string.format(
        "%s|TInterface/MoneyFrame/UI-GoldIcon:0:0:2:0|t %d|TInterface/MoneyFrame/UI-SilverIcon:0:0:2:0|t %d|TInterface/MoneyFrame/UI-CopperIcon:0:0:2:0|t",
        IRS:FormatCount(math.floor(copper / 10000)), math.floor(copper / 100) % 100, copper % 100
    )
end

function IRS:RefreshMicroReport()
    local settings = self:GetMicroReportSettings()
    -- Keep the amount consistent with the report's Body Text settings, including
    -- reset and reload, before measuring the surrounding frame.
    valueText:SetFont(IRS:GetFontFace(), IRS:GetFontSize("main", "body"), "")
    report:SetShown(settings.shown == true)
    if not report:IsShown() then return end
    local value = self:GetMicroReportValue()
    local text = FormatCoins(value)
    if settings.showLabel then text = labels[settings.mode] .. ": " .. text end
    valueText:SetText(text)
    valueText:SetTextColor(0.88, 0.84, 0.75)
    report:SetWidth(math.max(110, valueText:GetStringWidth() + 24))
    report:SetHeight(math.max(28, valueText:GetStringHeight() + 14))
end

function IRS:SetMicroReportOption(key, value)
    local settings = self:GetMicroReportSettings()
    if key == "mode" then
        if not labels[value] then return end
    elseif key == "shown" or key == "showLabel" then
        value = value == true
    else
        return
    end
    settings[key] = value
    self:RefreshMicroReport()
    if self.RefreshSettingsPage then self:RefreshSettingsPage() end
end

function IRS:BuildMicroReportMenu(root)
    root:AddMenuAcquiredCallback(StyleMenu)
    StyleMenuText(root:CreateTitle("Display Mode"), GOLD)
    for _, mode in ipairs(modes) do
        StyleMenuText(root:CreateRadio(mode.label, function(key)
            return IRS:GetMicroReportSettings().mode == key
        end, function(key)
            IRS:SetMicroReportOption("mode", key)
        end, mode.key), WHITE)
    end
end

-- An IRS-owned popup uses exactly the tooltip's backdrop. There is no
-- Blizzard menu artwork underneath it to make the brown fill look opaque.
local contextMenu = CreateFrame("Frame", "IncomeRecordsSystemMicroMenu", UIParent, "BackdropTemplate")
IRS:RegisterFormattingRoot(contextMenu, "main")
contextMenu:SetSize(240, 38 + (#modes + 2) * 24 + 12)
contextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
contextMenu:SetClampedToScreen(true)
contextMenu:EnableMouse(true)
contextMenu:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
contextMenu:SetBackdropColor(unpack(BACKGROUND))
contextMenu:SetBackdropBorderColor(unpack(BORDER))
contextMenu:Hide()
table.insert(UISpecialFrames, "IncomeRecordsSystemMicroMenu")

local menuTitle = contextMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
IRS:RegisterFontString("main", "section", menuTitle, STANDARD_TEXT_FONT, "")
menuTitle:SetPoint("TOPLEFT", 12, -12)
menuTitle:SetText("IRS - Display Mode")
menuTitle:SetTextColor(unpack(GOLD))
local menuRows = {}
local function AddMenuRow(index, label, selected, action)
    local row = CreateFrame("Button", nil, contextMenu)
    row:SetPoint("TOPLEFT", 8, -34 - (index - 1) * 24)
    row:SetPoint("TOPRIGHT", -8, -34 - (index - 1) * 24)
    row:SetHeight(24)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    IRS:RegisterFontString("main", "body", row.label, STANDARD_TEXT_FONT, "")
    row.label:SetPoint("LEFT", 22, 0)
    row.label:SetText(label)
    row.label:SetTextColor(unpack(WHITE))
    row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    IRS:RegisterFontString("main", "body", row.mark, STANDARD_TEXT_FONT, "")
    row.mark:SetPoint("LEFT", 5, 0)
    row.mark:SetText("•")
    row.mark:SetTextColor(unpack(GOLD))
    row.selected = selected
    row:SetScript("OnClick", function()
        action()
        contextMenu:Hide()
    end)
    menuRows[index] = row
end
for i, mode in ipairs(modes) do
    local key = mode.key
    AddMenuRow(i, mode.label, function()
        return IRS:GetMicroReportSettings().mode == key
    end, function() IRS:SetMicroReportOption("mode", key) end)
end
AddMenuRow(#modes + 1, "Show Label", function()
    return IRS:GetMicroReportSettings().showLabel == true
end, function()
    IRS:SetMicroReportOption("showLabel", not IRS:GetMicroReportSettings().showLabel)
end)
AddMenuRow(#modes + 2, "Reset Profit Per Hour", nil, function()
    rateBaseline, rateStarted = sessionNet, GetTime()
    IRS:RefreshMicroReport()
end)

local function LayoutMicroMenu()
    local rowHeight = math.max(24, IRS:GetFontSize("main", "body") + 12)
    local top = 12 + menuTitle:GetStringHeight() + 10
    local width = math.max(240, menuTitle:GetStringWidth() + 24)
    for i, row in ipairs(menuRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -top - (i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -8, -top - (i - 1) * rowHeight)
        row:SetHeight(rowHeight)
        width = math.max(width, row.label:GetStringWidth() + 46)
    end
    contextMenu:SetSize(width, top + #menuRows * rowHeight + 12)
end

-- Font settings already refresh the main UI. Resize the micro report and its
-- popup in the same pass, including while their text is currently hidden.
hooksecurefunc(IRS, "RefreshUI", function()
    IRS:RefreshMicroReport()
    LayoutMicroMenu()
end)

contextMenu:SetScript("OnShow", function(self)
    LayoutMicroMenu()
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    for _, row in ipairs(menuRows) do
        local selected = row.selected and row.selected()
        row.mark:SetShown(selected == true)
        row.label:SetTextColor(unpack(selected and GOLD or WHITE))
    end
end)
contextMenu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
contextMenu:SetScript("OnEvent", function(self)
    -- Retail exposes mouse focus as a list. Walk parents so clicks on option
    -- buttons stay inside the popup until their OnClick handler can run.
    for _, focus in ipairs(GetMouseFoci()) do
        local frame = focus
        while frame do
            if frame == self or frame == report then return end
            if frame.IsForbidden and frame:IsForbidden() then break end
            frame = frame.GetParent and frame:GetParent() or nil
        end
    end
    self:Hide()
end)
local draggedMicroReport = false
report:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then draggedMicroReport = false end
end)
report:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        if not draggedMicroReport then
            contextMenu:Hide()
            tooltip:Hide()
            IRS:ShowUI("dashboard")
        end
        return
    end
    if button ~= "RightButton" then return end
    tooltip:Hide()
    if contextMenu:IsShown() then contextMenu:Hide(); return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    contextMenu:ClearAllPoints()
    contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    contextMenu:Show()
end)

local function SavePosition()
    report:StopMovingOrSizing()
    local settings = IRS:GetMicroReportSettings()
    local point, _, relativePoint, x, y = report:GetPoint(1)
    settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint, x, y
end
report:SetScript("OnDragStart", function(self)
    draggedMicroReport = true
    contextMenu:Hide()
    tooltip:Hide()
    self:StartMoving()
end)
report:SetScript("OnDragStop", SavePosition)
report:SetScript("OnHide", function()
    contextMenu:Hide()
    SavePosition()
    tooltip:Hide()
end)
local function RefreshTooltip()
    tooltip:SetText("IRS - " .. labels[IRS:GetMicroReportSettings().mode], unpack(GOLD))
    tooltip:AddLine("Left-click to open IRS. Drag to move. Right-click to choose a display.", 0.88, 0.84, 0.75, true, "helper")
    tooltip:AddLine("Periods cover the account. Session resets on logout or UI reload.", 0.68, 0.62, 0.51, true, "helper")
    local function Row(label, value)
        tooltip:AddDoubleLine(label, FormatCoins(value, true), GOLD[1], GOLD[2], GOLD[3], WHITE[1], WHITE[2], WHITE[3])
    end
    tooltip:AddLine(" ")
    Row("Warband Bank:", IRS.db.account.warbandGoldSeen and IRS.db.account.warbandGold or nil)
    Row("Total:", IRS:GetAccountLiquidGoldAllCharacters())
    tooltip:AddLine(" ")
    local token = IRS:GetTokenMarketSummary().current
    Row("WoW Token:", token and token > 0 and token or nil)
    tooltip:AddLine(" ")
    local duration = GetTime() - rateStarted
    Row("Profit Per Hour:", duration >= 1 and (sessionNet - rateBaseline) * 3600 / duration or 0)
    local function Period(label, earned, spent, net)
        tooltip:AddLine(" ")
        Row(label .. " Earned:", earned)
        Row(label .. " Spent:", spent)
        Row(label .. " Net:", net)
    end
    Period("Session", sessionEarned, sessionSpent, sessionNet)
    local day, week, month = IRS:GetPeriodKeys()
    for _, period in ipairs({
        {"Daily", "days", day},
        {"Weekly", "weeks", week},
        {"Monthly", "months", month},
    }) do
        local summary = IRS:GetPeriodFlowSummary(period[2], period[3])
        Period(period[1], summary.income, summary.expense, summary.net)
    end
    tooltip:Show()
    StyleTooltip()
end
hooksecurefunc(IRS, "RefreshUI", function()
    if tooltip:IsOwned(report) then RefreshTooltip() end
end)
report:SetScript("OnEnter", function(self)
    if contextMenu:IsShown() then return end
    tooltip:SetOwner(self, "ANCHOR_TOP")
    RefreshTooltip()
end)
report:SetScript("OnLeave", function() tooltip:Hide() end)
local elapsed = 0
report:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 1 then return end
    elapsed = 0
    IRS:RefreshMicroReport()
    if tooltip:IsOwned(report) then RefreshTooltip() end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        SavePosition()
        sessionNet, sessionEarned, sessionSpent, rateBaseline = 0, 0, 0, 0
        return
    end
    local settings = IRS:GetMicroReportSettings()
    if settings.point then
        report:ClearAllPoints()
        report:SetPoint(settings.point, UIParent, settings.relativePoint or settings.point, settings.x or 0, settings.y or 0)
    end
    rateStarted = GetTime()
    IRS:RefreshMicroReport()
end)
