--[[
IRS — Income Records System
Main window, dashboard, projects, characters, reports, help, and minimap UI.
Supporting interfaces are split into their own modules.
]]

local IRS = IRS
local _irsStartupModuleTiming = IRS:BeginStartupTiming("Main UI initialization / module load")

-- Central visual palette. Change colors here instead of hunting through the UI.
-- Values are RGBA (red, green, blue, alpha), each from 0.0 to 1.0.
local COLORS = {
    -- Warm report palette based on the original IRS scanner aesthetic.
    bg = {0.165, 0.125, 0.085, 0.92},
    panel = {0.190, 0.145, 0.098, 0.88},
    panelAlt = {0.225, 0.170, 0.112, 0.88},
    border = {0.52, 0.39, 0.22, 1},
    borderSoft = {0.36, 0.28, 0.18, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {0.43, 0.60, 0.36, 1},
    amber = {0.72, 0.54, 0.26, 1},
    red = {0.63, 0.29, 0.25, 1},
    cyan = {0.40, 0.63, 0.65, 1},
}

-- Base folder for custom IRS artwork. Helper functions append filenames to this.
local MEDIA = [[Interface\AddOns\IncomeRecordsSystem\Media\]]

-- Applies one COLORS entry to a FontString. Keeping this tiny helper avoids
-- repeating RGBA indexing everywhere.
local function SetColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- Creates a consistently styled FontString. Most visible text in IRS starts here.
local function MakeText(parent, size, color, justify, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontPath = font or STANDARD_TEXT_FONT
    local renderedSize = IRS.GetFontSize and IRS:GetFontSize("main", size) or size

    fs:SetFont(fontPath, renderedSize, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then SetColor(fs, color) end

    -- Size 1 is used only for a few hidden compatibility FontStrings and should
    -- never become a user-facing editable style.
    if size and size ~= 1 and IRS.RegisterFontString then
        IRS:RegisterFontString("main", size, fs, fontPath, "")
    end

    return fs
end

-- Creates the dark bordered panel used throughout IRS cards and content boxes.
local function MakePanel(parent, bgColor)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    local c = bgColor or COLORS.panel
    panel:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    panel:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    return panel
end

-- Creates a custom IRS texture from the Media folder. "path" is the filename
-- without the file extension.
local function MakeTexture(parent, path, size, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture(MEDIA .. path)
    tex:SetSize(size, size)
    return tex
end

-- UI-friendly money formatter. Unlike the Core formatter, this intentionally
-- favors compact dashboard text such as 12.4k or -250g.
local function FormatGold(copper, includeChange)
    copper = math.floor(tonumber(copper) or 0)
    local negative = copper < 0
    local absolute = math.abs(copper)
    local gold = math.floor(absolute / 10000)
    local silver = math.floor((absolute % 10000) / 100)
    local copperOnly = absolute % 100
    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    local sign = negative and "-" or ""

    if gold > 0 then
        if includeChange and (silver > 0 or copperOnly > 0) and gold < 1000 then
            return string.format("%s%sg %02ds %02dc", sign, goldText, silver, copperOnly)
        end
        return sign .. goldText .. "g"
    end
    if silver > 0 then return string.format("%s%ds %02dc", sign, silver, copperOnly) end
    if copperOnly > 0 then return sign .. tostring(copperOnly) .. "c" end
    return "0g"
end

-- Extra-short number formatter used only for graph axis labels.
local function FormatChartGold(copper)
    local value = tonumber(copper) or 0
    local sign = value < 0 and "-" or ""
    local gold = math.floor(math.abs(value) / 10000)
    if gold >= 1000000 then return string.format("%s%.1fm", sign, gold / 1000000) end
    if gold >= 1000 then return string.format("%s%.0fk", sign, gold / 1000) end
    return sign .. tostring(gold)
end

-- Color convention for NET values: losses red, gains gold, zero uses the supplied
-- neutral color.
local function SetNetColor(fontString, amount, zeroColor, positiveColor)
    amount = tonumber(amount) or 0
    if amount < 0 then
        SetColor(fontString, COLORS.red)
    elseif amount > 0 then
        SetColor(fontString, positiveColor or COLORS.gold)
    else
        SetColor(fontString, zeroColor or COLORS.gold)
    end
end



local frame = CreateFrame("Frame", "IncomeRecordsSystemFrame", UIParent, "BackdropTemplate")
frame:SetSize(1020, 760)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(unpack(COLORS.bg))
frame:SetBackdropBorderColor(unpack(COLORS.border))
frame:Hide()
IRS.mainFrame = frame

if UISpecialFrames then
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "IncomeRecordsSystemFrame" then found = true break end
    end
    if not found then table.insert(UISpecialFrames, "IncomeRecordsSystemFrame") end
end

-- ============================================================================
-- SECTION 1 — MAIN WINDOW HEADER
-- IRS title, logo, Last Updated text, and close button.
-- ============================================================================
local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
header:SetPoint("TOPLEFT", 12, -12)
header:SetPoint("TOPRIGHT", -12, -12)
header:SetHeight(64)
header:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
header:SetBackdropColor(unpack(COLORS.bg))

local headerLine = header:CreateTexture(nil, "BORDER")
headerLine:SetTexture("Interface/Buttons/WHITE8X8")
headerLine:SetVertexColor(unpack(COLORS.border))
headerLine:SetHeight(1)
headerLine:SetPoint("BOTTOMLEFT", 0, 0)
headerLine:SetPoint("BOTTOMRIGHT", 0, 0)

local titleIcon = MakeTexture(header, "IRSTitleIcon", 54)
titleIcon:SetPoint("LEFT", 8, 0)

local irsText = MakeText(header, 32, COLORS.gold, "LEFT")
irsText:SetPoint("LEFT", titleIcon, "RIGHT", 8, 7)
irsText:SetText("IRS")

local title = MakeText(header, 18, COLORS.text, "LEFT")
title:SetPoint("LEFT", irsText, "RIGHT", 15, 9)
title:SetText("INCOME RECORDS SYSTEM")

local titleSub = MakeText(header, 11, COLORS.goldSoft, "LEFT")
titleSub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
titleSub:SetText("ACCOUNT GOLD TRACKER")

local lastUpdated = MakeText(header, 10, COLORS.muted, "RIGHT")
lastUpdated:SetPoint("RIGHT", -118, 3)
lastUpdated:SetWidth(210)
lastUpdated:SetText("Last Updated\n—")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -8, -8)

-- ============================================================================
-- SECTION 2 — SIDEBAR NAVIGATION
-- Dashboard / Projects / Characters / Reports / Settings / Help.
-- ============================================================================
local rail = MakePanel(frame, COLORS.bg)
rail:SetPoint("TOPLEFT", 14, -84)
rail:SetPoint("BOTTOMLEFT", 14, 14)
rail:SetWidth(104)
rail:SetBackdropBorderColor(0, 0, 0, 0)
rail.divider = rail:CreateTexture(nil, "BORDER")
rail.divider:SetTexture("Interface/Buttons/WHITE8X8")
rail.divider:SetVertexColor(unpack(COLORS.borderSoft))
rail.divider:SetWidth(1)
rail.divider:SetPoint("TOPRIGHT", -1, 0)
rail.divider:SetPoint("BOTTOMRIGHT", -1, 0)

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", 130, -84)
content:SetPoint("BOTTOMRIGHT", -16, 16)

local pages, tabs = {}, {}
local activeTab = "dashboard"

-- Page frames are exposed so UI\IncomeRecordsSystem_PageScroll.lua can wrap each
-- tab in a vertical viewport without bloating this already-large UI file.
IRS.pageFrames = IRS.pageFrames or {}

-- Builds one left-sidebar navigation button and wires its hover/click behavior.
local function MakeTab(key, label, y)
    local button = CreateFrame("Button", nil, rail, "BackdropTemplate")
    button:SetPoint("TOPLEFT", 4, y)
    button:SetSize(96, 34)
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)

    button.activeBar = button:CreateTexture(nil, "ARTWORK")
    button.activeBar:SetTexture("Interface/Buttons/WHITE8X8")
    button.activeBar:SetVertexColor(unpack(COLORS.gold))
    button.activeBar:SetWidth(2)
    button.activeBar:SetPoint("TOPLEFT", 0, -5)
    button.activeBar:SetPoint("BOTTOMLEFT", 0, 5)
    button.activeBar:Hide()

    button.label = MakeText(button, 11, COLORS.text, "LEFT")
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.label:SetText(label)

    button:SetScript("OnEnter", function(self)
        if activeTab ~= key then
            SetColor(self.label, COLORS.goldSoft)
        end
    end)

    button:SetScript("OnLeave", function(self)
        if activeTab ~= key then
            SetColor(self.label, COLORS.text)
        end
    end)

    button:SetScript("OnClick", function()
        IRS:SelectTab(key)
    end)

    tabs[key] = button
end

MakeTab("dashboard", "Dashboard", -8)
MakeTab("projects", "Projects", -46)
MakeTab("reserves", "Reserves", -84)
MakeTab("tools", "Tools", -122)
MakeTab("characters", "Characters", -160)
MakeTab("reports", "Reports", -198)
MakeTab("settings", "Settings", -236)
MakeTab("help", "Help", -274)

-- ============================================================================
-- SECTION 3 — DASHBOARD
-- Surveillance state, period totals, daily chart, and Account Overview.
-- ============================================================================
local dashboard = CreateFrame("Frame", nil, content)
dashboard:SetAllPoints()
pages.dashboard = dashboard
IRS.pageFrames.dashboard = dashboard

local currentLine = MakeText(dashboard, 12, COLORS.text, "LEFT")
currentLine:SetPoint("TOPLEFT", 4, -2)
currentLine:SetPoint("TOPRIGHT", -184, -2)
currentLine:SetText("CURRENT CHARACTER")

local rescanButton = CreateFrame("Button", nil, dashboard, "UIPanelButtonTemplate")
rescanButton:SetSize(88, 22)
rescanButton:SetPoint("TOPRIGHT", -2, 2)
rescanButton:SetText("Rescan")
rescanButton:SetScript("OnClick", function() IRS:ScanCurrentCharacter() end)

-- Opens the floating at-a-glance panel without leaving the main Dashboard.
local miniButton = CreateFrame("Button", nil, dashboard, "UIPanelButtonTemplate")
miniButton:SetSize(76, 22)
miniButton:SetPoint("RIGHT", rescanButton, "LEFT", -6, 0)
miniButton:SetText("Mini")
miniButton:SetScript("OnClick", function()
    if IRS.ToggleMiniDashboard then IRS:ToggleMiniDashboard() end
end)

local status = MakePanel(dashboard, COLORS.panelAlt)
status:SetPoint("TOPLEFT", 0, -29)
status:SetPoint("TOPRIGHT", 0, -29)
status:SetHeight(58)
status:SetBackdropColor(COLORS.green[1], COLORS.green[2], COLORS.green[3], 0.12)
status:SetBackdropBorderColor(COLORS.green[1], COLORS.green[2], COLORS.green[3], 0.58)

status.marker = status:CreateTexture(nil, "ARTWORK")
status.marker:SetTexture("Interface/Buttons/WHITE8X8")
status.marker:SetSize(7, 7)
status.marker:SetPoint("TOPLEFT", 12, -16)
status.marker:SetVertexColor(unpack(COLORS.green))

status.title = MakeText(status, 13, COLORS.green, "LEFT")
status.title:SetPoint("TOPLEFT", 28, -10)
status.title:SetText("SURVEILLANCE ACTIVE")

status.detail = MakeText(status, 10, COLORS.text, "LEFT")
status.detail:SetPoint("TOPLEFT", status.title, "BOTTOMLEFT", 0, -4)
status.detail:SetPoint("RIGHT", -12, 0)

local periodContainer = CreateFrame("Frame", nil, dashboard)
periodContainer:SetPoint("TOPLEFT", 0, -104)
periodContainer:SetPoint("TOPRIGHT", 0, -104)
periodContainer:SetHeight(84)

-- Builds one headline card: Today, This Week, This Month, or Total Recorded.
-- The large value is account-wide; the small person-marked value is current toon.
local function MakePeriodCard(parent, x, width, heading)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", x, 0)
    card:SetSize(width, 84)

    if x > 0 then
        card.separator = card:CreateTexture(nil, "BORDER")
        card.separator:SetTexture("Interface/Buttons/WHITE8X8")
        card.separator:SetVertexColor(unpack(COLORS.borderSoft))
        card.separator:SetWidth(1)
        card.separator:SetPoint("TOPLEFT", 0, -7)
        card.separator:SetPoint("BOTTOMLEFT", 0, 7)
    end

    card.heading = MakeText(card, 10, COLORS.goldSoft, "CENTER")
    card.heading:SetPoint("TOPLEFT", 5, -6)
    card.heading:SetPoint("TOPRIGHT", -5, -6)
    card.heading:SetText(heading)

    card.value = MakeText(card, 20, COLORS.gold, "CENTER")
    card.value:SetPoint("TOPLEFT", 5, -27)
    card.value:SetPoint("TOPRIGHT", -5, -27)
    card.value:SetText("0g")

    card.characterValue = MakeText(card, 8, COLORS.muted, "CENTER")
    card.characterValue:SetPoint("BOTTOMLEFT", 5, 7)
    card.characterValue:SetPoint("BOTTOMRIGHT", -5, 7)
    card.characterValue:SetText("0g")

    return card
end

local cardGap = 8
local cardWidth = 209
local todayCard = MakePeriodCard(periodContainer, 0, cardWidth, "TODAY")
local weekCard = MakePeriodCard(periodContainer, cardWidth + cardGap, cardWidth, "THIS WEEK")
local monthCard = MakePeriodCard(periodContainer, (cardWidth + cardGap) * 2, cardWidth, "THIS MONTH")
local totalCard = MakePeriodCard(periodContainer, (cardWidth + cardGap) * 3, cardWidth, "TOTAL RECORDED")

local chartTitle = MakeText(dashboard, 15, COLORS.text, "LEFT")
chartTitle:SetPoint("TOPLEFT", 0, -230)
chartTitle:SetText("DAILY EARNINGS (LAST 7 DAYS)")

local titleUnderline = chartTitle:GetParent():CreateTexture(nil, "BORDER")
titleUnderline:SetTexture("Interface/Buttons/WHITE8X8")
titleUnderline:SetVertexColor(unpack(COLORS.border))
titleUnderline:SetHeight(1)
titleUnderline:SetPoint("TOPLEFT", dashboard, "TOPLEFT", 0, -250)
titleUnderline:SetPoint("TOPRIGHT", dashboard, "TOPRIGHT", -2, -250)

local chart = CreateFrame("Frame", nil, dashboard)
chart:SetPoint("TOPLEFT", 0, -255)
chart:SetPoint("TOPRIGHT", 0, -255)
chart:SetHeight(178)
chart.bars = {}
chart.grid = {}

for i = 1, 4 do
    local line = chart:CreateTexture(nil, "BORDER")
    line:SetTexture("Interface/Buttons/WHITE8X8")
    line:SetVertexColor(0.27, 0.23, 0.17, 0.75)
    line:SetHeight(1)
    line:SetPoint("LEFT", 52, 0)
    line:SetPoint("RIGHT", -12, 0)
    line:SetPoint("BOTTOM", 0, 28 + ((i - 1) * 35))
    chart.grid[i] = line
end

chart.yLabels = {}
for i = 1, 4 do
    local label = MakeText(chart, 8, COLORS.muted, "RIGHT")
    label:SetPoint("RIGHT", chart.grid[i], "LEFT", -6, 0)
    label:SetWidth(42)
    chart.yLabels[i] = label
end

for i = 1, 7 do
    local slot = CreateFrame("Frame", nil, chart)
    slot:SetSize(106, 154)
    slot:SetPoint("BOTTOMLEFT", 63 + ((i - 1) * 112), 8)

    local amount = MakeText(slot, 9, COLORS.goldSoft, "CENTER")
    amount:SetPoint("TOP", 0, -2)
    amount:SetWidth(104)

    local bar = slot:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface/Buttons/WHITE8X8")
    bar:SetWidth(52)
    bar:SetPoint("BOTTOM", 0, 25)
    bar:SetVertexColor(unpack(COLORS.cyan))

    local day = MakeText(slot, 9, COLORS.text, "CENTER")
    day:SetPoint("BOTTOM", 0, 3)
    day:SetWidth(104)

    chart.bars[i] = { slot = slot, bar = bar, amount = amount, day = day }
end

local overviewTitle = MakeText(dashboard, 15, COLORS.text, "LEFT")
overviewTitle:SetPoint("TOPLEFT", 0, -445)
overviewTitle:SetText("ACCOUNT OVERVIEW")

local overviewLine = dashboard:CreateTexture(nil, "BORDER")
overviewLine:SetTexture("Interface/Buttons/WHITE8X8")
overviewLine:SetVertexColor(unpack(COLORS.border))
overviewLine:SetHeight(1)
overviewLine:SetPoint("TOPLEFT", dashboard, "TOPLEFT", 0, -465)
overviewLine:SetPoint("TOPRIGHT", dashboard, "TOPRIGHT", -2, -465)

local left = CreateFrame("Frame", nil, dashboard)
left:SetPoint("TOPLEFT", 0, -470)
left:SetSize(278, 181)
local middle = CreateFrame("Frame", nil, dashboard)
middle:SetPoint("TOPLEFT", 288, -470)
middle:SetSize(278, 181)
local right = CreateFrame("Frame", nil, dashboard)
right:SetPoint("TOPLEFT", 576, -470)
right:SetSize(278, 181)

-- Reusable builder for the three Account Overview panels on the dashboard.
local function BuildList(panel, heading, rows)
    panel.heading = MakeText(panel, 11, COLORS.goldSoft, "LEFT")
    panel.heading:SetPoint("TOPLEFT", 2, -4)
    panel.heading:SetText(heading)

    panel.headerLine = panel:CreateTexture(nil, "BORDER")
    panel.headerLine:SetTexture("Interface/Buttons/WHITE8X8")
    panel.headerLine:SetVertexColor(unpack(COLORS.borderSoft))
    panel.headerLine:SetHeight(1)
    panel.headerLine:SetPoint("TOPLEFT", 0, -27)
    panel.headerLine:SetPoint("TOPRIGHT", 0, -27)

    panel.rows = {}
    panel.labels = {}

    for i, labelText in ipairs(rows) do
        local y = -39 - ((i - 1) * 22)
        local label = MakeText(panel, 9, COLORS.text, "LEFT")
        label:SetPoint("TOPLEFT", 2, y)
        label:SetText(labelText)
        table.insert(panel.labels, label)

        local value = MakeText(panel, 10, COLORS.goldSoft, "RIGHT")
        value:SetPoint("TOPRIGHT", -2, y)
        value:SetWidth(116)
        table.insert(panel.rows, value)
    end
end

BuildList(left, "INCOME SOURCES", {
    "Total gold acquired",
    "Gold looted",
    "Quest rewards",
    "Vendor sales",
    "Auction earnings",
    "Other income",
})

BuildList(middle, "AUCTION ACTIVITY", {
    "Auctions posted",
    "Auction purchases",
    "Largest sale",
    "Largest bid",
})

BuildList(right, "SPENDING / COVERAGE", {
    "Travel",
    "Postage",
    "Transmog",
    "Tracking coverage",
    "Warband Bank",
})

if IRS.AttachTokenDashboardCard then
    IRS:AttachTokenDashboardCard(dashboard, left, right)
end

-- ============================================================================
-- SECTION 4 — SAVINGS PROJECTS PAGE
-- Project selection, editor, funding source, tracker, progress, and trajectory graph.
-- ============================================================================
local projectsPage = CreateFrame("Frame", nil, content)
projectsPage:SetAllPoints()
pages.projects = projectsPage
IRS.pageFrames.projects = projectsPage
IRS.projectsPage = projectsPage

local selectedProjectId = nil

function IRS:GetSelectedProjectId()
    return selectedProjectId
end
local projectSourceType = "account"
local projectSourceKey = nil
local deleteArmedId = nil

local projectsTitle = MakeText(projectsPage, 19, COLORS.goldSoft, "LEFT")
projectsTitle:SetPoint("TOPLEFT", 4, -4)
projectsTitle:SetText("SAVINGS PROJECTS")

local projectsDesc = MakeText(projectsPage, 10, COLORS.text, "LEFT")
projectsDesc:SetPoint("TOPLEFT", projectsTitle, "BOTTOMLEFT", 0, -7)
projectsDesc:SetPoint("RIGHT", -4, 0)
projectsDesc:SetText("Create long-term savings goals and track a percentage of account, Warband, guild, or character-held gold against a deadline.")

-- Consistent button factory used inside the Projects page.
local function MakeProjectButton(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 28)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0.045, 0.045, 0.042, 1)
    b:SetBackdropBorderColor(unpack(COLORS.border))
    b.label = MakeText(b, 9, COLORS.text, "CENTER")
    b.label:SetAllPoints()
    b.label:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Creates a labeled edit box used by the project name/target/deadline form.
local function MakeProjectEdit(parent, labelText, x, y, w)
    local label = MakeText(parent, 9, COLORS.muted, "LEFT")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", x + 2, y - 16)
    box:SetSize(w, 25)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    return box, label
end

-- Converts a player's project-target entry (gold text) into copper for Core.lua.
local function ParseGoldInput(text)
    text = strtrim(tostring(text or "")):lower():gsub(",", ""):gsub("%s+", "")
    if text == "" then return nil end
    local mult = 1
    if text:sub(-1) == "m" then mult = 1000000; text = text:sub(1, -2)
    elseif text:sub(-1) == "k" then mult = 1000; text = text:sub(1, -2)
    elseif text:sub(-1) == "g" then text = text:sub(1, -2) end
    local gold = tonumber(text)
    if not gold or gold <= 0 then return nil end
    return math.floor((gold * mult * 10000) + 0.5)
end

-- Converts project copper back into simple editable gold text.
local function GoldInputText(copper)
    local gold = math.floor((tonumber(copper) or 0) / 10000)
    return tostring(gold)
end

local projectSelectLabel = MakeText(projectsPage, 9, COLORS.muted, "LEFT")
projectSelectLabel:SetPoint("TOPLEFT", 4, -58)
projectSelectLabel:SetText("PROJECT")

local projectSelect = MakeProjectButton(projectsPage, "Select project", 4, -75, 280)
projectSelect.label:SetJustifyH("LEFT")
projectSelect.label:ClearAllPoints(); projectSelect.label:SetPoint("LEFT", 10, 0); projectSelect.label:SetPoint("RIGHT", -24, 0)
local projectSelectArrow = MakeText(projectSelect, 10, COLORS.gold, "RIGHT")
projectSelectArrow:SetPoint("RIGHT", -8, 0); projectSelectArrow:SetText("v")

local newProjectButton = MakeProjectButton(projectsPage, "NEW PROJECT", 294, -75, 112)
local deleteProjectButton = MakeProjectButton(projectsPage, "DELETE", 416, -75, 100)

IRS.projectCheckpointsButton = MakeProjectButton(projectsPage, "CHECKPOINTS", 528, -75, 122)
IRS.projectCheckpointsButton:SetScript("OnClick", function()
    if IRS.ShowProjectCheckpointsManager then
        IRS:ShowProjectCheckpointsManager()
    end
end)

local projectStatus = MakeText(projectsPage, 9, COLORS.muted, "LEFT")
projectStatus:SetPoint("TOPLEFT", 662, -81)
projectStatus:SetPoint("RIGHT", -4, 0)
projectStatus:SetText("")

-- Project selection popup
local projectPopup = MakePanel(frame, COLORS.panelAlt)
projectPopup:SetSize(290, 270)
projectPopup:SetFrameStrata("TOOLTIP")
projectPopup:SetPoint("TOPLEFT", projectSelect, "BOTTOMLEFT", 0, -2)
projectPopup:Hide()
local projectPopupScroll = CreateFrame("ScrollFrame", nil, projectPopup, "UIPanelScrollFrameTemplate")
projectPopupScroll:SetPoint("TOPLEFT", 5, -5); projectPopupScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local projectPopupChild = CreateFrame("Frame", nil, projectPopupScroll)
projectPopupChild:SetSize(255, 1); projectPopupScroll:SetScrollChild(projectPopupChild)
projectPopup.rows = {}

-- Lazily creates rows in the project-selection popup as they are needed.
local function EnsureProjectPopupRow(index)
    if projectPopup.rows[index] then return projectPopup.rows[index] end
    local b = CreateFrame("Button", nil, projectPopupChild, "BackdropTemplate")
    b:SetHeight(26)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    b:SetBackdropColor(0.035, 0.038, 0.038, 0.96)
    b.text = MakeText(b, 9, COLORS.text, "LEFT")
    b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.10, 0.08, 0.05, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.035, 0.038, 0.038, 0.96) end)
    projectPopup.rows[index] = b
    return b
end

-- Editable project fields
local projectNameBox = MakeProjectEdit(projectsPage, "PROJECT NAME", 4, -118, 205)
local projectTargetBox = MakeProjectEdit(projectsPage, "TARGET GOLD", 219, -118, 130)
local projectStartBox = MakeProjectEdit(projectsPage, "START DATE (YYYY-MM-DD)", 359, -118, 145)
local projectDeadlineBox = MakeProjectEdit(projectsPage, "DEADLINE (YYYY-MM-DD)", 514, -118, 145)
local projectAllocationBox = MakeProjectEdit(projectsPage, "ALLOCATION %", 669, -118, 88)

local sourceLabel = MakeText(projectsPage, 9, COLORS.muted, "LEFT")
sourceLabel:SetPoint("TOPLEFT", 4, -174); sourceLabel:SetText("SOURCE")
local sourceButton = MakeProjectButton(projectsPage, "Account Liquid Gold", 4, -191, 180)
sourceButton.label:SetJustifyH("LEFT"); sourceButton.label:ClearAllPoints(); sourceButton.label:SetPoint("LEFT", 8, 0); sourceButton.label:SetPoint("RIGHT", -20, 0)
local sourceArrow = MakeText(sourceButton, 9, COLORS.gold, "RIGHT"); sourceArrow:SetPoint("RIGHT", -7, 0); sourceArrow:SetText("v")

local sourceDetailLabel = MakeText(projectsPage, 9, COLORS.muted, "LEFT")
sourceDetailLabel:SetPoint("TOPLEFT", 194, -174); sourceDetailLabel:SetText("SOURCE DETAIL")
local sourceDetailButton = MakeProjectButton(projectsPage, "Not required", 194, -191, 270)
sourceDetailButton.label:SetJustifyH("LEFT"); sourceDetailButton.label:ClearAllPoints(); sourceDetailButton.label:SetPoint("LEFT", 8, 0); sourceDetailButton.label:SetPoint("RIGHT", -20, 0)
local sourceDetailArrow = MakeText(sourceDetailButton, 9, COLORS.gold, "RIGHT"); sourceDetailArrow:SetPoint("RIGHT", -7, 0); sourceDetailArrow:SetText("v")

local saveProjectButton = MakeProjectButton(projectsPage, "SAVE PROJECT", 479, -191, 120)
local syncGuildButton = MakeProjectButton(projectsPage, "SYNC GUILD BANK", 609, -191, 145)
local formNote = MakeText(projectsPage, 8, COLORS.muted, "LEFT")
formNote:SetPoint("TOPLEFT", 764, -191); formNote:SetPoint("RIGHT", -4, 0)
formNote:SetText("History is stored by IRS and survives project edits.")

-- Source popup
local sourcePopup = MakePanel(frame, COLORS.panelAlt)
sourcePopup:SetSize(190, 120); sourcePopup:SetFrameStrata("TOOLTIP")
sourcePopup:SetPoint("TOPLEFT", sourceButton, "BOTTOMLEFT", 0, -2); sourcePopup:Hide()
local sourceChoices = {
    { key = "account", label = "Account Liquid Gold" },
    { key = "warband", label = "Warband Bank" },
    { key = "guild", label = "Guild Bank" },
    { key = "character", label = "Specific Character" },
}
for i, item in ipairs(sourceChoices) do
    local b = CreateFrame("Button", nil, sourcePopup, "BackdropTemplate")
    b:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 28)); b:SetSize(182, 26)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" }); b:SetBackdropColor(0.035,0.038,0.038,0.98)
    b.text = MakeText(b, 9, COLORS.text, "LEFT"); b.text:SetPoint("LEFT", 8, 0); b.text:SetText(item.label)
    b:SetScript("OnClick", function()
        projectSourceType = item.key
        projectSourceKey = nil
        sourceButton.label:SetText(item.label)
        if item.key == "character" then sourceDetailButton.label:SetText("Choose a scanned character")
        elseif item.key == "guild" then sourceDetailButton.label:SetText("Choose / sync a Guild Bank")
        else sourceDetailButton.label:SetText("Not required") end
        sourcePopup:Hide()
        if IRS.RefreshProjectsPage then IRS:RefreshProjectsPage(true) end
    end)
end
sourceButton:SetScript("OnClick", function() sourcePopup:SetShown(not sourcePopup:IsShown()) end)

-- Source detail popup (character or guild)
local sourceDetailPopup = MakePanel(frame, COLORS.panelAlt)
sourceDetailPopup:SetSize(310, 285); sourceDetailPopup:SetFrameStrata("TOOLTIP")
sourceDetailPopup:SetPoint("TOPLEFT", sourceDetailButton, "BOTTOMLEFT", 0, -2); sourceDetailPopup:Hide()
local detailScroll = CreateFrame("ScrollFrame", nil, sourceDetailPopup, "UIPanelScrollFrameTemplate")
detailScroll:SetPoint("TOPLEFT", 5, -5); detailScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local detailChild = CreateFrame("Frame", nil, detailScroll); detailChild:SetSize(275, 1); detailScroll:SetScrollChild(detailChild)
sourceDetailPopup.rows = {}
-- Lazily creates source-detail rows (characters or guilds) for the project picker.
local function EnsureDetailRow(index)
    if sourceDetailPopup.rows[index] then return sourceDetailPopup.rows[index] end
    local b = CreateFrame("Button", nil, detailChild, "BackdropTemplate")
    b:SetHeight(25); b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" }); b:SetBackdropColor(0.035,0.038,0.038,0.98)
    b.text = MakeText(b, 9, COLORS.text, "LEFT"); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.10,0.08,0.05,1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.035,0.038,0.038,0.98) end)
    sourceDetailPopup.rows[index] = b
    return b
end

-- Repopulates the project source-detail popup based on the currently chosen
-- source type (specific character or guild bank).
local function RefreshSourceDetailPopup()
    local choices = {}
    if projectSourceType == "character" then
        for _, entry in ipairs(IRS:GetSortedCharacters()) do
            table.insert(choices, { key = entry.key, label = entry.record.label or entry.record.name or "Unknown" })
        end
    elseif projectSourceType == "guild" then
        local seen = {}
        for _, entry in ipairs(IRS:GetSortedGuildBanks()) do
            local label = (entry.record.name or "Guild") .. " — " .. FormatGold(entry.record.money or 0, true)
            table.insert(choices, { key = entry.key, label = label })
            seen[entry.key] = true
        end
        local currentKey, currentName = IRS:GetCurrentGuildKey()
        if currentKey and not seen[currentKey] then
            table.insert(choices, { key = currentKey, label = (currentName or "Current Guild") .. " — not synced yet" })
        end
    end

    if #choices == 0 then
        table.insert(choices, { key = nil, label = projectSourceType == "guild" and "Visit a Guild Bank to sync it" or "No scanned characters" })
    end

    for i, item in ipairs(choices) do
        local row = EnsureDetailRow(i)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((i - 1) * 26)); row:SetWidth(275)
        row.text:SetText(item.label)
        row:SetScript("OnClick", function()
            projectSourceKey = item.key
            sourceDetailButton.label:SetText(item.label)
            sourceDetailPopup:Hide()
        end)
        row:SetEnabled(item.key ~= nil)
        row:Show()
    end
    for i = #choices + 1, #sourceDetailPopup.rows do sourceDetailPopup.rows[i]:Hide() end
    detailChild:SetHeight(math.max(1, #choices * 26))
end
sourceDetailButton:SetScript("OnClick", function()
    if projectSourceType ~= "character" and projectSourceType ~= "guild" then return end
    if sourceDetailPopup:IsShown() then sourceDetailPopup:Hide() else RefreshSourceDetailPopup(); sourceDetailPopup:Show() end
end)

-- Project summary
local projectSummary = MakePanel(projectsPage, COLORS.bg)
projectSummary:SetBackdropBorderColor(0, 0, 0, 0)
projectSummary:SetPoint("TOPLEFT", 4, -232); projectSummary:SetPoint("TOPRIGHT", -4, -232); projectSummary:SetHeight(126)
projectSummary.cards = {}
local summaryLabels = {"CURRENT ALLOCATED", "STILL NEEDED", "DAILY NEEDED", "TIME REMAINING"}
for i, label in ipairs(summaryLabels) do
    local card = CreateFrame("Frame", nil, projectSummary)
    card:SetSize(205, 67); card:SetPoint("TOPLEFT", 10 + ((i - 1) * 210), -8)
    card.label = MakeText(card, 9, COLORS.muted, "CENTER"); card.label:SetPoint("TOPLEFT", 2, 0); card.label:SetPoint("TOPRIGHT", -2, 0); card.label:SetText(label)
    card.value = MakeText(card, "value", COLORS.gold, "CENTER"); card.value:SetPoint("TOPLEFT", 2, -20); card.value:SetPoint("TOPRIGHT", -2, -20)
    card.detail = MakeText(card, 8, COLORS.muted, "CENTER"); card.detail:SetPoint("TOPLEFT", 2, -43); card.detail:SetPoint("TOPRIGHT", -2, -43)
    projectSummary.cards[i] = card
end
local progressBG = projectSummary:CreateTexture(nil, "BACKGROUND")
progressBG:SetTexture("Interface/Buttons/WHITE8X8"); progressBG:SetVertexColor(0.08,0.09,0.09,1)
progressBG:SetPoint("BOTTOMLEFT", 14, 13); progressBG:SetPoint("BOTTOMRIGHT", -14, 13); progressBG:SetHeight(18)
local progressBar = projectSummary:CreateTexture(nil, "ARTWORK")
progressBar:SetTexture("Interface/Buttons/WHITE8X8"); progressBar:SetVertexColor(unpack(COLORS.cyan)); progressBar:SetPoint("BOTTOMLEFT", progressBG, "BOTTOMLEFT", 0, 0); progressBar:SetHeight(18)
local progressText = MakeText(projectSummary, 8, COLORS.text, "CENTER"); progressText:SetPoint("CENTER", progressBG, "CENTER", 0, 0)

-- Daily tracker and graph
local dailyPanel = MakePanel(projectsPage, COLORS.bg)
dailyPanel:SetBackdropBorderColor(0, 0, 0, 0)
local dailyTitle = MakeText(dailyPanel, 13, COLORS.goldSoft, "LEFT"); dailyTitle:SetPoint("TOPLEFT", 12, -10); dailyTitle:SetText("DAILY GOLD TRACKER")
local dailySub = MakeText(dailyPanel, 8, COLORS.muted, "LEFT"); dailySub:SetPoint("TOPLEFT", dailyTitle, "BOTTOMLEFT", 0, -3); dailySub:SetText("Shared IRS source history within this project window")
local dailyHeader = CreateFrame("Frame", nil, dailyPanel)
dailyHeader:SetPoint("TOPLEFT", 10, -48); dailyHeader:SetPoint("TOPRIGHT", -24, -48); dailyHeader:SetHeight(22)
local dh1=MakeText(dailyHeader,8,COLORS.muted,"LEFT"); dh1:SetPoint("LEFT",2,0); dh1:SetText("DATE")
local dh2=MakeText(dailyHeader,8,COLORS.muted,"RIGHT"); dh2:SetPoint("LEFT",92,0); dh2:SetWidth(84); dh2:SetText("START")
local dh3=MakeText(dailyHeader,8,COLORS.muted,"RIGHT"); dh3:SetPoint("LEFT",183,0); dh3:SetWidth(84); dh3:SetText("END")
local dh4=MakeText(dailyHeader,8,COLORS.muted,"RIGHT"); dh4:SetPoint("LEFT",274,0); dh4:SetWidth(96); dh4:SetText("CHANGE")
local dailyScroll = CreateFrame("ScrollFrame", nil, dailyPanel, "UIPanelScrollFrameTemplate")
dailyScroll:SetPoint("TOPLEFT", 10, -73); dailyScroll:SetPoint("BOTTOMRIGHT", -25, 10)
local dailyChild = CreateFrame("Frame", nil, dailyScroll); dailyChild:SetSize(370,1); dailyScroll:SetScrollChild(dailyChild)
dailyPanel.rows = {}
-- Lazily creates one row in the project's daily Start / End / Change table.
local function EnsureDailyRow(index)
    if dailyPanel.rows[index] then return dailyPanel.rows[index] end
    local row = CreateFrame("Frame", nil, dailyChild); row:SetHeight(26)
    row.date=MakeText(row,9,COLORS.text,"LEFT"); row.date:SetPoint("LEFT",2,0); row.date:SetWidth(88)
    row.start=MakeText(row,9,COLORS.text,"RIGHT"); row.start:SetPoint("LEFT",92,0); row.start:SetWidth(84)
    row.ending=MakeText(row,9,COLORS.text,"RIGHT"); row.ending:SetPoint("LEFT",183,0); row.ending:SetWidth(84)
    row.change=MakeText(row,9,COLORS.gold,"RIGHT"); row.change:SetPoint("LEFT",274,0); row.change:SetWidth(96)
    local line=row:CreateTexture(nil,"BORDER"); line:SetTexture("Interface/Buttons/WHITE8X8"); line:SetVertexColor(0.11,0.12,0.12,1); line:SetHeight(1); line:SetPoint("BOTTOMLEFT",0,0); line:SetPoint("BOTTOMRIGHT",0,0)
    dailyPanel.rows[index]=row; return row
end
local function LayoutDailyTrackerColumns()
    local contentWidth = math.max(370, dailyHeader:GetWidth() or 370)
    local dateWidth = math.max(105, math.floor(contentWidth * 0.22))
    local valueWidth = math.max(
        85,
        math.floor((contentWidth - dateWidth) / 3)
    )

    dh1:ClearAllPoints()
    dh1:SetPoint("LEFT", 2, 0)
    dh1:SetWidth(dateWidth - 4)

    dh2:ClearAllPoints()
    dh2:SetPoint("LEFT", dateWidth, 0)
    dh2:SetWidth(valueWidth - 8)

    dh3:ClearAllPoints()
    dh3:SetPoint("LEFT", dateWidth + valueWidth, 0)
    dh3:SetWidth(valueWidth - 8)

    dh4:ClearAllPoints()
    dh4:SetPoint("LEFT", dateWidth + (valueWidth * 2), 0)
    dh4:SetWidth(valueWidth - 8)

    for _, row in ipairs(dailyPanel.rows) do
        row.date:ClearAllPoints()
        row.date:SetPoint("LEFT", 2, 0)
        row.date:SetWidth(dateWidth - 4)

        row.start:ClearAllPoints()
        row.start:SetPoint("LEFT", dateWidth, 0)
        row.start:SetWidth(valueWidth - 8)

        row.ending:ClearAllPoints()
        row.ending:SetPoint("LEFT", dateWidth + valueWidth, 0)
        row.ending:SetWidth(valueWidth - 8)

        row.change:ClearAllPoints()
        row.change:SetPoint(
            "LEFT",
            dateWidth + (valueWidth * 2),
            0
        )
        row.change:SetWidth(valueWidth - 8)
    end
end

local graphPanel = MakePanel(projectsPage, COLORS.bg)
graphPanel:SetBackdropBorderColor(0, 0, 0, 0)
graphPanel:SetPoint("TOPLEFT", 4, -370)
graphPanel:SetPoint("TOPRIGHT", -4, -370)
graphPanel:SetHeight(450)
dailyPanel:SetPoint("TOPLEFT", graphPanel, "BOTTOMLEFT", 0, -12)
dailyPanel:SetPoint("TOPRIGHT", graphPanel, "BOTTOMRIGHT", 0, -12)
dailyPanel:SetHeight(450)
local graphTitle = MakeText(graphPanel, 13, COLORS.goldSoft, "LEFT"); graphTitle:SetPoint("TOPLEFT", 12, -10); graphTitle:SetText("PROJECT TRAJECTORY")
local graphLegend = MakeText(graphPanel, 8, COLORS.muted, "RIGHT"); graphLegend:SetPoint("TOPRIGHT", -12, -13); graphLegend:SetText("|cffc9a64dRequired|r   |cff669fa6Actual|r")

graphPanel.intervalButtons = {}
local graphIntervalChoices = {
    { key = "daily", label = "Daily" },
    { key = "weekly", label = "Weekly" },
    { key = "monthly", label = "Monthly" },
    { key = "checkpoints", label = "Checkpoints" },
}
for i, info in ipairs(graphIntervalChoices) do
    local intervalKey = info.key
    local button = CreateFrame("Button", nil, graphPanel, "BackdropTemplate")
    button:SetSize(78, 22)
    button:SetPoint("TOPRIGHT", -12 - ((#graphIntervalChoices - i) * 82), -32)
    button:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    button.label = MakeText(button, 8, COLORS.text, "CENTER")
    button.label:SetAllPoints()
    button.label:SetText(info.label)
    button.intervalKey = intervalKey
    button:SetScript("OnClick", function()
        if selectedProjectId and IRS:SetProjectGraphInterval(selectedProjectId, intervalKey) then
            IRS:RefreshProjectsPage(true)
        end
    end)
    graphPanel.intervalButtons[intervalKey] = button
end

local graph = CreateFrame("Frame", nil, graphPanel)
graph:SetPoint("TOPLEFT", 50, -62)
graph:SetPoint("BOTTOMRIGHT", -16, 108)
local graphAxis = graphPanel:CreateTexture(nil,"BORDER"); graphAxis:SetTexture("Interface/Buttons/WHITE8X8"); graphAxis:SetVertexColor(0.25,0.28,0.28,1); graphAxis:SetHeight(1); graphAxis:SetPoint("BOTTOMLEFT",graph,"BOTTOMLEFT",0,0); graphAxis:SetPoint("BOTTOMRIGHT",graph,"BOTTOMRIGHT",0,0)
local graphLeftAxis = graphPanel:CreateTexture(nil,"BORDER"); graphLeftAxis:SetTexture("Interface/Buttons/WHITE8X8"); graphLeftAxis:SetVertexColor(0.25,0.28,0.28,1); graphLeftAxis:SetWidth(1); graphLeftAxis:SetPoint("TOPLEFT",graph,"TOPLEFT",0,0); graphLeftAxis:SetPoint("BOTTOMLEFT",graph,"BOTTOMLEFT",0,0)
local graphTopLabel = MakeText(graphPanel,8,COLORS.muted,"RIGHT"); graphTopLabel:SetPoint("TOPRIGHT",graph,"TOPLEFT",-6,2); graphTopLabel:SetWidth(46)
local graphBottomLabel = MakeText(graphPanel,8,COLORS.muted,"RIGHT"); graphBottomLabel:SetPoint("BOTTOMRIGHT",graph,"BOTTOMLEFT",-6,-2); graphBottomLabel:SetWidth(46); graphBottomLabel:SetText("0g")

-- Dense interval-aware X axis.
-- Vertical labels reduce horizontal footprint so IRS can show more markers.
graphPanel.xLabels = {}
graphPanel.xTicks = {}
for i = 1, 10 do
    local label = MakeText(graphPanel, 8, COLORS.muted, "LEFT")
    label:SetWidth(92)
    label:SetHeight(16)

    if label.SetWordWrap then label:SetWordWrap(false) end
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end

    if label.SetRotation then
        -- Clockwise rotation makes normal left-to-right text read from the
        -- x-axis DOWNWARD. The first character sits nearest the tick and longer
        -- labels extend into the reserved area below the graph.
        label:SetRotation(-math.pi / 2)
        label._irsVerticalRotation = true
    else
        label._irsVerticalRotation = false
    end

    label:Hide()
    graphPanel.xLabels[i] = label

    local tick = graphPanel:CreateTexture(nil, "BORDER")
    tick:SetTexture("Interface/Buttons/WHITE8X8")
    tick:SetVertexColor(0.25, 0.28, 0.28, 1)
    tick:SetSize(1, 6)
    tick:Hide()
    graphPanel.xTicks[i] = tick
end

-- Checkpoint-mode Y axis milestone labels and horizontal guide lines.
graphPanel.yLabels = {}
graphPanel.yGuides = {}
for i = 1, 10 do
    local label = MakeText(graphPanel, 8, COLORS.muted, "RIGHT")
    label:SetWidth(112)
    label:SetHeight(18)
    label:Hide()
    graphPanel.yLabels[i] = label

    local guide = graphPanel:CreateTexture(nil, "BACKGROUND")
    guide:SetTexture("Interface/Buttons/WHITE8X8")
    guide:SetVertexColor(0.18, 0.20, 0.20, 0.55)
    guide:SetHeight(1)
    guide:Hide()
    graphPanel.yGuides[i] = guide
end

graphPanel.requiredLine = graph:CreateLine(nil,"ARTWORK")
graphPanel.requiredLine:SetThickness(2); graphPanel.requiredLine:SetColorTexture(COLORS.gold[1],COLORS.gold[2],COLORS.gold[3],1)
graphPanel.actualLines = {}
for i=1,64 do
    local line=graph:CreateLine(nil,"ARTWORK"); line:SetThickness(2); line:SetColorTexture(COLORS.cyan[1],COLORS.cyan[2],COLORS.cyan[3],1); line:Hide(); graphPanel.actualLines[i]=line
end

-- Human-readable name for a project's internal sourceType key.
local function SourceTypeLabel(sourceType)
    if sourceType == "warband" then return "Warband Bank"
    elseif sourceType == "guild" then return "Guild Bank"
    elseif sourceType == "character" then return "Specific Character"
    end
    return "Account Liquid Gold"
end

-- Copies a saved project's values into the editable form controls.
local function LoadProjectIntoForm(project)
    deleteArmedId = nil; deleteProjectButton.label:SetText("DELETE")
    if not project then
        selectedProjectId = nil
        projectNameBox:SetText("")
        projectTargetBox:SetText("")
        projectStartBox:SetText(date("%Y-%m-%d"))
        projectDeadlineBox:SetText(date("%Y-%m-%d", time() + (30 * 86400)))
        projectAllocationBox:SetText("100")
        projectSourceType, projectSourceKey = "account", nil
        sourceButton.label:SetText("Account Liquid Gold")
        sourceDetailButton.label:SetText("Not required")
        projectSelect.label:SetText("New project")
        if IRS.RefreshProjectCheckpointsButton then
            IRS:RefreshProjectCheckpointsButton(nil)
        end
        return
    end
    selectedProjectId = project.id
    projectNameBox:SetText(project.name or "")
    projectTargetBox:SetText(GoldInputText(project.targetCopper or 0))
    projectStartBox:SetText(project.startDate or project.createdDay or date("%Y-%m-%d"))
    projectDeadlineBox:SetText(project.deadline or "")
    projectAllocationBox:SetText(tostring(project.allocationPercent or 100))
    projectSourceType, projectSourceKey = project.sourceType or "account", project.sourceKey
    sourceButton.label:SetText(SourceTypeLabel(projectSourceType))
    local _, _, detailLabel = IRS:GetProjectSourceBalance(project)
    sourceDetailButton.label:SetText((projectSourceType == "character" or projectSourceType == "guild") and detailLabel or "Not required")
    projectSelect.label:SetText(project.name or "Savings Project")

    if IRS.RefreshProjectCheckpointsButton then
        IRS:RefreshProjectCheckpointsButton(project)
    end
end

-- Rebuilds the selectable project list without recreating the entire page.
local function RefreshProjectPopup()
    local projects = IRS:GetSortedProjects()
    if #projects == 0 then
        local row=EnsureProjectPopupRow(1); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,0); row:SetWidth(255); row.text:SetText("No projects yet — click NEW PROJECT"); row:SetEnabled(false); row:Show()
        for i=2,#projectPopup.rows do projectPopup.rows[i]:Hide() end
        projectPopupChild:SetHeight(26); return
    end
    for i, entry in ipairs(projects) do
        local row=EnsureProjectPopupRow(i); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-((i-1)*27)); row:SetWidth(255); row:SetEnabled(true)
        local stats=IRS:GetProjectStats(entry.project)
        row.text:SetText(string.format("%s — %.0f%%", entry.project.name or "Project", (stats.percent or 0)*100))
        row:SetScript("OnClick", function() LoadProjectIntoForm(entry.project); projectPopup:Hide(); IRS:RefreshProjectsPage() end)
        row:Show()
    end
    for i=#projects+1,#projectPopup.rows do projectPopup.rows[i]:Hide() end
    projectPopupChild:SetHeight(math.max(1,#projects*27))
end
projectSelect:SetScript("OnClick", function() if projectPopup:IsShown() then projectPopup:Hide() else RefreshProjectPopup(); projectPopup:Show() end end)

newProjectButton:SetScript("OnClick", function() LoadProjectIntoForm(nil); projectStatus:SetText("Enter the project details, then save."); IRS:RefreshProjectsPage(true) end)

deleteProjectButton:SetScript("OnClick", function()
    if not selectedProjectId then projectStatus:SetText("Select a saved project first."); return end
    if deleteArmedId ~= selectedProjectId then
        deleteArmedId = selectedProjectId; deleteProjectButton.label:SetText("CONFIRM")
        projectStatus:SetText("Click CONFIRM to permanently delete this project.")
        return
    end
    IRS:DeleteProject(selectedProjectId)
    selectedProjectId=nil; deleteArmedId=nil; deleteProjectButton.label:SetText("DELETE")
    local first=IRS:GetSortedProjects()[1]
    LoadProjectIntoForm(first and first.project or nil)
    projectStatus:SetText("Project deleted.")
    IRS:RefreshProjectsPage()
end)

saveProjectButton:SetScript("OnClick", function()
    local target=ParseGoldInput(projectTargetBox:GetText())
    local allocation=tonumber(projectAllocationBox:GetText())
    local data={
        name=projectNameBox:GetText(),
        targetCopper=target,
        startDate=strtrim(projectStartBox:GetText() or ""),
        deadline=strtrim(projectDeadlineBox:GetText() or ""),
        sourceType=projectSourceType,
        sourceKey=projectSourceKey,
        allocationPercent=allocation,
    }
    if (projectSourceType=="character" or projectSourceType=="guild") and not projectSourceKey then
        projectStatus:SetText("Choose a character or guild bank for this source."); return
    end
    if selectedProjectId then
        local ok, result=IRS:UpdateProject(selectedProjectId,data)
        if not ok then projectStatus:SetText(result or "Could not save project."); return end
        projectStatus:SetText("Project saved."); LoadProjectIntoForm(result)
    else
        local id, result=IRS:CreateProject(data)
        if not id then projectStatus:SetText(result or "Could not create project."); return end
        selectedProjectId=id; projectStatus:SetText("Project created."); LoadProjectIntoForm(result)
    end
    IRS:RefreshProjectsPage()
end)

syncGuildButton:SetScript("OnClick", function()
    local amount, key, syncState, readSource =
        IRS:ScanGuildBankGold(false)

    local cache = IRS:GetGuildBankCacheStatus(key)

    if amount ~= nil then
        projectStatus:SetText(
            "Guild Bank synced: "
                .. FormatGold(amount, true)
                .. (readSource and (" via " .. readSource) or "")
        )

        if projectSourceType=="guild" and not projectSourceKey then
            projectSourceKey=key
        end

        IRS:UpdateProjectSnapshots()
        IRS:RefreshProjectsPage(true)
        return
    end

    if cache.money ~= nil and cache.money > 0 then
        projectStatus:SetText(
            "Using cached Guild Bank "
                .. FormatGold(cache.money, true)
                .. " — live read not ready."
        )
    elseif syncState == "zero-preserved" then
        projectStatus:SetText(
            "Guild Bank returned 0g, so IRS preserved the last valid cache."
        )
    elseif syncState == "zero-unconfirmed" then
        projectStatus:SetText(
            string.format(
                "Guild Bank read not ready (legacy %s / bank API %s). Keep the bank open.",
                cache.legacyAmount ~= nil and FormatGold(cache.legacyAmount, true) or "n/a",
                cache.modernAmount ~= nil and FormatGold(cache.modernAmount, true) or "n/a"
            )
        )
    else
        projectStatus:SetText(
            "Guild Bank unavailable. Open the Guild Bank and click Sync again."
        )
    end
end)

-- Main Projects-page refresh. Updates project list, form, summary numbers,
-- progress bar, daily tracker, and the required-vs-actual trajectory graph.
function IRS:RefreshProjectsPage(preserveForm)
    if not IRS.db then return end
    IRS:UpdateProjectSnapshots()
    local project = selectedProjectId and IRS:GetProject(selectedProjectId) or nil
    if not project and not preserveForm then
        local first=IRS:GetSortedProjects()[1]
        if first then project=first.project; LoadProjectIntoForm(project) end
    end

    if IRS.RefreshProjectCheckpointsButton then
        IRS:RefreshProjectCheckpointsButton(project)
    end

    local needsDetail = projectSourceType=="character" or projectSourceType=="guild"
    sourceDetailLabel:SetShown(needsDetail); sourceDetailButton:SetShown(needsDetail); sourceDetailArrow:SetShown(needsDetail)
    syncGuildButton:SetShown(projectSourceType=="guild")

    if not project then
        for _,card in ipairs(projectSummary.cards) do card.value:SetText("—"); card.detail:SetText("") end
        progressBar:SetWidth(1); progressText:SetText("No saved project selected")
        for _,row in ipairs(dailyPanel.rows) do row:Hide() end
        for _,line in ipairs(graphPanel.actualLines) do line:Hide() end
        graphPanel.requiredLine:Hide(); graphTopLabel:SetText("—")

        for i = 1, #graphPanel.xLabels do
            graphPanel.xLabels[i]:Hide()
            graphPanel.xTicks[i]:Hide()
        end

        for i = 1, #graphPanel.yLabels do
            graphPanel.yLabels[i]:Hide()
            graphPanel.yGuides[i]:Hide()
        end

        for _, button in pairs(graphPanel.intervalButtons) do
            button:SetBackdropColor(0.045, 0.045, 0.042, 1)
            button:SetBackdropBorderColor(0.25, 0.22, 0.17, 1)
            SetColor(button.label, COLORS.text)
        end
        return
    end

    local stats=IRS:GetProjectStats(project)
    projectSelect.label:SetText(project.name or "Savings Project")
    projectSummary.cards[1].value:SetText(FormatGold(stats.current,true)); projectSummary.cards[1].detail:SetText(string.format("of %s target",FormatGold(stats.target,true)))
    projectSummary.cards[2].value:SetText(FormatGold(stats.remaining,true)); projectSummary.cards[2].detail:SetText(stats.achieved and "Goal reached" or "Still required")
    projectSummary.cards[3].value:SetText(FormatGold(stats.dailyNeeded,true)); projectSummary.cards[3].detail:SetText(stats.daysLeft>0 and "per day to deadline" or "deadline reached")
    projectSummary.cards[4].value:SetText(tostring(stats.daysLeft) .. " days"); projectSummary.cards[4].detail:SetText(string.format("%s → %s • %d plan days",stats.startDate or "—",stats.deadline or "—",stats.totalPlanDays or 0))
    if stats.achieved then SetColor(projectSummary.cards[2].value,COLORS.green) else SetColor(projectSummary.cards[2].value,COLORS.gold) end
    if stats.overdue then SetColor(projectSummary.cards[4].value,COLORS.red) else SetColor(projectSummary.cards[4].value,COLORS.gold) end
    local summaryWidth = projectSummary:GetWidth()
    if not summaryWidth or summaryWidth < 100 then summaryWidth = 850 end
    local barWidth=math.max(1, math.floor((summaryWidth-28)*(stats.percent or 0))); progressBar:SetWidth(barWidth)
    progressText:SetText(string.format("%.1f%% funded • %d days left • %d%% of %s",(stats.percent or 0)*100, stats.daysLeft or 0, project.allocationPercent or 100, stats.sourceLabel or "source"))

    local rows=IRS:GetProjectDailyHistory(project,true)
    if #rows > 0 then
        local oldest = rows[#rows]
        if oldest and stats.startDate and oldest.key > stats.startDate then
            dailySub:SetText("IRS source history available from " .. tostring(oldest.key))
        else
            dailySub:SetText("Shared IRS source history within this project window")
        end
    else
        dailySub:SetText("No source history recorded in this project window yet")
    end
    local rowWidth=math.max(370,dailyScroll:GetWidth()-4)
        dailyChild:SetWidth(rowWidth)
    local dailyRowHeight=math.max(27, IRS:GetFontSize("main","body") + 12)
    for i,data in ipairs(rows) do
        local row=EnsureDailyRow(i); row:SetHeight(dailyRowHeight); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-((i-1)*(dailyRowHeight+1))); row:SetWidth(rowWidth)
        row.date:SetText(data.label or data.key); row.start:SetText(FormatGold(data.start,true)); row.ending:SetText(FormatGold(data.ending,true)); row.change:SetText(FormatGold(data.change,true)); SetNetColor(row.change,data.change,COLORS.muted); row:Show()
    end
    for i=#rows+1,#dailyPanel.rows do dailyPanel.rows[i]:Hide() end
    dailyChild:SetHeight(math.max(1,#rows*(dailyRowHeight+1)))
        LayoutDailyTrackerColumns()

    local graphInterval = IRS:GetProjectGraphInterval(project)
    for intervalKey, button in pairs(graphPanel.intervalButtons) do
        if intervalKey == graphInterval then
            button:SetBackdropColor(0.18, 0.13, 0.05, 1)
            button:SetBackdropBorderColor(unpack(COLORS.goldSoft))
            SetColor(button.label, COLORS.gold)
        else
            button:SetBackdropColor(0.045, 0.045, 0.042, 1)
            button:SetBackdropBorderColor(0.25, 0.22, 0.17, 1)
            SetColor(button.label, COLORS.text)
        end
    end

    local gd=IRS:GetProjectGraphData(project, graphInterval)
    if gd then
        local maxY=math.max(1,gd.target or 0,gd.startAmount or 0,gd.current or 0)
        for _,pt in ipairs(gd.actual or {}) do maxY=math.max(maxY,pt.amount or 0) end

        -- Checkpoints uses named milestone levels on the Y axis. Give those
        -- labels a dedicated left gutter; all other modes keep the compact
        -- numerical Y-axis labels.
        graph:ClearAllPoints()
        if graphInterval == "checkpoints" then
            graph:SetPoint(
                "TOPLEFT",
                122,
                -(math.max(
                    IRS:GetFontSize("main","section"),
                    IRS:GetFontSize("main","helper")
                ) + 54)
            )
            graphTopLabel:Hide()
            graphBottomLabel:Hide()
        else
            graph:SetPoint(
                "TOPLEFT",
                50,
                -(math.max(
                    IRS:GetFontSize("main","section"),
                    IRS:GetFontSize("main","helper")
                ) + 54)
            )
            graphTopLabel:SetText(FormatGold(maxY,true))
            graphTopLabel:Show()
            graphBottomLabel:Show()
        end
        graph:SetPoint("BOTTOMRIGHT", -16, 108)

        local w,h=math.max(1,graph:GetWidth()),math.max(1,graph:GetHeight())

        local yTicks = gd.yTicks or {}
        for i = 1, #graphPanel.yLabels do
            local label = graphPanel.yLabels[i]
            local guide = graphPanel.yGuides[i]
            local tickData = yTicks[i]

            label:ClearAllPoints()
            guide:ClearAllPoints()

            if graphInterval == "checkpoints" and tickData then
                local amount = tonumber(tickData.amount) or 0
                local y = math.max(
                    0,
                    math.min(h, (amount / maxY) * h)
                )

                label:SetText(tickData.label or "")

                if tickData.reached then
                    SetColor(label, COLORS.green)
                elseif tickData.endpoint then
                    SetColor(label, COLORS.goldSoft)
                else
                    SetColor(label, COLORS.muted)
                end

                label:SetPoint("RIGHT", graph, "BOTTOMLEFT", -8, y)

                guide:SetPoint("LEFT", graph, "BOTTOMLEFT", 0, y)
                guide:SetPoint("RIGHT", graph, "BOTTOMRIGHT", 0, y)

                if tickData.endpoint then
                    guide:SetVertexColor(
                        COLORS.goldSoft[1],
                        COLORS.goldSoft[2],
                        COLORS.goldSoft[3],
                        0.35
                    )
                elseif tickData.reached then
                    guide:SetVertexColor(
                        COLORS.green[1],
                        COLORS.green[2],
                        COLORS.green[3],
                        0.22
                    )
                else
                    guide:SetVertexColor(0.18, 0.20, 0.20, 0.55)
                end

                label:Show()
                guide:Show()
            else
                label:Hide()
                guide:Hide()
            end
        end

        local xTicks = gd.xTicks or {}
        for i = 1, #graphPanel.xLabels do
            local label = graphPanel.xLabels[i]
            local tickMark = graphPanel.xTicks[i]
            local tickData = xTicks[i]

            label:ClearAllPoints()
            tickMark:ClearAllPoints()

            if tickData then
                local fraction = math.max(0, math.min(1, tickData.fraction or 0))
                local x = fraction * w
                local text = tickData.label or ""

                SetColor(label, COLORS.muted)

                if label._irsVerticalRotation then
                    label:SetText(text)
                    label:SetJustifyH("LEFT")

                    -- Keep the original tick-relative anchor now that the text
                    -- rotates clockwise. The label starts immediately beneath
                    -- its X-axis tick and then reads downward into the reserved
                    -- label area.
                    label:SetPoint("TOPLEFT", graph, "BOTTOMLEFT", x + 5, -7)
                else
                    local compact = tostring(text):gsub("\n", " • ")
                    local vertical = {}
                    for index = 1, #compact do
                        vertical[#vertical + 1] = compact:sub(index, index)
                    end
                    label:SetText(table.concat(vertical, "\n"))
                    label:SetWidth(18)
                    label:SetHeight(92)
                    label:SetJustifyH("CENTER")
                    label:SetPoint("TOP", graph, "BOTTOMLEFT", x, -8)
                end

                tickMark:SetPoint("BOTTOM", graph, "BOTTOMLEFT", x, 0)
                label:Show()
                tickMark:Show()
            else
                label:Hide()
                tickMark:Hide()
            end
        end
        -- REQUIRED is the ideal savings plan and is always independent of the
        -- player's opening balance: 0g at project start -> target at deadline.
        local startY = 0
        local targetY = math.max(
            0,
            math.min(h, ((gd.target or 0) / maxY) * h)
        )

        graphPanel.requiredLine:SetStartPoint(
            "BOTTOMLEFT",
            graph,
            0,
            startY
        )
        graphPanel.requiredLine:SetEndPoint(
            "BOTTOMLEFT",
            graph,
            w,
            targetY
        )
        graphPanel.requiredLine:Show()

        local pts=gd.actual or {}

        local maxSegments=#graphPanel.actualLines
        local step=(#pts>maxSegments+1) and math.ceil((#pts-1)/maxSegments) or 1
        local display={}
        for i=1,#pts,step do table.insert(display,pts[i]) end
        if #pts>0 and display[#display]~=pts[#pts] then table.insert(display,pts[#pts]) end
        local used=0
        for i=2,#display do
            used=used+1; if used>maxSegments then break end
            local a,b=display[i-1],display[i]; local line=graphPanel.actualLines[used]
            local ax=(a.fraction or 0)*w; local ay=math.max(0,math.min(h,((a.amount or 0)/maxY)*h)); local bx=(b.fraction or 0)*w; local by=math.max(0,math.min(h,((b.amount or 0)/maxY)*h))
            line:SetStartPoint("BOTTOMLEFT",graph,ax,ay); line:SetEndPoint("BOTTOMLEFT",graph,bx,by); line:Show()
        end
        for i=used+1,#graphPanel.actualLines do graphPanel.actualLines[i]:Hide() end
    end
end

-- ============================================================================
-- RESERVE FUNDS PAGE SHELL
-- The full interface and reserve accounting model live in
-- Features\IncomeRecordsSystem_Reserves.lua to keep this large UI chunk below WoW's
-- local-variable ceiling.
-- ============================================================================
IRS.reservesPage = CreateFrame("Frame", nil, content)
IRS.reservesPage:SetAllPoints()
pages.reserves = IRS.reservesPage
IRS.pageFrames.reserves = IRS.reservesPage

-- ============================================================================
-- TOOLS PAGE SHELL
-- The User's Manual and Profit Distribution Calculator live in
-- Features\IncomeRecordsSystem_Tools.lua to keep this already-large UI chunk lean.
-- ============================================================================
IRS.toolsPage = CreateFrame("Frame", nil, content)
IRS.toolsPage:SetAllPoints()
pages.tools = IRS.toolsPage
IRS.pageFrames.tools = IRS.toolsPage

-- ============================================================================
-- SECTION 5 — CHARACTERS PAGE
-- Scanned characters and per-character tracking toggle.
-- ============================================================================
local charactersPage = CreateFrame("Frame", nil, content)
charactersPage:SetAllPoints()
pages.characters = charactersPage
IRS.pageFrames.characters = charactersPage

local charsTitle = MakeText(charactersPage, 19, COLORS.goldSoft, "LEFT")
charsTitle:SetPoint("TOPLEFT", 4, -4)
charsTitle:SetText("CHARACTERS")

local charsSummary = MakeText(charactersPage, 10, COLORS.muted, "RIGHT")
charsSummary:SetPoint("TOPRIGHT", -4, -8)
charsSummary:SetText("0 tracked / 0 scanned")

local charsDesc = MakeText(charactersPage, 10, COLORS.text, "LEFT")
charsDesc:SetPoint("TOPLEFT", charsTitle, "BOTTOMLEFT", 0, -8)
charsDesc:SetPoint("RIGHT", -4, 0)
charsDesc:SetText("Choose which scanned characters IRS should track. Ignored characters remain in your records but do not add new earnings until re-enabled.")

local charHeader = MakePanel(charactersPage, COLORS.panelAlt)
charHeader:SetPoint("TOPLEFT", 0, -70)
charHeader:SetPoint("TOPRIGHT", -18, -70)
charHeader:SetHeight(26)

-- Small helper used to build the Characters table column headers.
local function HeaderText(text, x, width, justify)
    local fs = MakeText(charHeader, 9, COLORS.muted, justify or "LEFT")
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(width)
    fs:SetText(text)
end
HeaderText("TRACK", 8, 48)
HeaderText("CHARACTER", 58, 300)
HeaderText("LEVEL", 360, 48, "CENTER")
HeaderText("CURRENT GOLD", 418, 125, "RIGHT")
HeaderText("IRS EARNINGS", 554, 125, "RIGHT")
HeaderText("STATUS", 690, 130, "CENTER")

local charScroll = CreateFrame("ScrollFrame", "IncomeRecordsSystemCharacterScroll", charactersPage, "UIPanelScrollFrameTemplate")
charScroll:SetPoint("TOPLEFT", 0, -100)
charScroll:SetPoint("BOTTOMRIGHT", -28, 32)
local charScrollChild = CreateFrame("Frame", nil, charScroll)
charScrollChild:SetSize(820, 1)
charScroll:SetScrollChild(charScrollChild)
charactersPage.rows = {}

-- Lazily creates a reusable Characters-table row and its tracking checkbox.
local function EnsureCharacterRow(index)
    if charactersPage.rows[index] then return charactersPage.rows[index] end
    local row = MakePanel(charScrollChild, COLORS.bg)
    row:SetHeight(42)
    row:SetBackdropBorderColor(0.12, 0.14, 0.14, 1)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(25, 25)
    row.check:SetPoint("LEFT", 10, 0)

    row.name = MakeText(row, 10, COLORS.text, "LEFT")
    row.name:SetPoint("LEFT", 58, 7)
    row.name:SetWidth(290)

    row.meta = MakeText(row, 8, COLORS.muted, "LEFT")
    row.meta:SetPoint("LEFT", 58, -9)
    row.meta:SetWidth(290)

    row.level = MakeText(row, 10, COLORS.text, "CENTER")
    row.level:SetPoint("LEFT", 360, 0)
    row.level:SetWidth(48)

    row.gold = MakeText(row, 10, COLORS.text, "RIGHT")
    row.gold:SetPoint("LEFT", 418, 0)
    row.gold:SetWidth(125)

    row.earned = MakeText(row, 10, COLORS.goldSoft, "RIGHT")
    row.earned:SetPoint("LEFT", 554, 0)
    row.earned:SetWidth(125)

    row.statusMarker = row:CreateTexture(nil, "ARTWORK")
    row.statusMarker:SetTexture("Interface/Buttons/WHITE8X8")
    row.statusMarker:SetSize(6, 6)
    row.statusMarker:SetPoint("LEFT", 707, 0)
    row.statusMarker:SetVertexColor(unpack(COLORS.green))

    row.status = MakeText(row, 10, COLORS.green, "LEFT")
    row.status:SetPoint("LEFT", 724, 0)
    row.status:SetWidth(96)

    row.check:SetScript("OnClick", function(self)
        if row.characterKey then IRS:SetCharacterTracking(row.characterKey, self:GetChecked()) end
    end)

    charactersPage.rows[index] = row
    return row
end

local charsNote = MakeText(charactersPage, 9, COLORS.muted, "LEFT")
charsNote:SetPoint("BOTTOMLEFT", 2, 5)
charsNote:SetPoint("RIGHT", -4, 0)
charsNote:SetText("Re-enabling a character creates a fresh baseline on its next scan, so earnings made while it was ignored are not retroactively added.")

-- ============================================================================
-- SECTION 6 — REPORTS PAGE
-- Scope selector, history, averages, and lifetime source breakdown.
-- ============================================================================
local reportsPage = CreateFrame("Frame", nil, content)
reportsPage:SetAllPoints()
pages.reports = reportsPage
IRS.pageFrames.reports = reportsPage

local reportScope = "all"
local reportPeriod = "days"
local reportView = "history"

local reportsTitle = MakeText(reportsPage, 19, COLORS.goldSoft, "LEFT")
reportsTitle:SetPoint("TOPLEFT", 4, -4)
reportsTitle:SetText("REPORTS")

local reportsDesc = MakeText(reportsPage, 10, COLORS.text, "LEFT")
reportsDesc:SetPoint("TOPLEFT", reportsTitle, "BOTTOMLEFT", 0, -8)
reportsDesc:SetPoint("RIGHT", -4, 0)
reportsDesc:SetText("Review full IRS earnings history for the account or a specific scanned character.")

local scopeLabel = MakeText(reportsPage, 9, COLORS.muted, "LEFT")
scopeLabel:SetPoint("TOPLEFT", 4, -65)
scopeLabel:SetText("SCOPE")

local scopeButton = CreateFrame("Button", nil, reportsPage, "BackdropTemplate")
scopeButton:SetPoint("TOPLEFT", 4, -82)
scopeButton:SetSize(250, 28)
scopeButton:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 2 })
scopeButton:SetBackdropColor(unpack(COLORS.panelAlt))
scopeButton:SetBackdropBorderColor(unpack(COLORS.borderSoft))
scopeButton.text = MakeText(scopeButton, 10, COLORS.text, "LEFT")
scopeButton.text:SetPoint("LEFT", 10, 0)
scopeButton.text:SetPoint("RIGHT", -24, 0)
scopeButton.text:SetText("All Characters")
scopeButton.arrow = MakeText(scopeButton, 10, COLORS.gold, "RIGHT")
scopeButton.arrow:SetPoint("RIGHT", -8, 0)
scopeButton.arrow:SetText("v")

local periodLabel = MakeText(reportsPage, 9, COLORS.muted, "LEFT")
periodLabel:SetPoint("TOPLEFT", 275, -65)
periodLabel:SetText("HISTORY PERIOD")

local reportPeriodButtons = {}
-- Builds the compact report-view buttons (Day/Week/Month, Best/Avg, Sources).
local function MakeSmallToggle(parent, text, x, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", x, -82)
    b:SetSize(width, 28)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 2 })
    b:SetBackdropColor(unpack(COLORS.panelAlt))
    b:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    b.label = MakeText(b, 9, COLORS.text, "CENTER")
    b.label:SetAllPoints()
    b.label:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

reportPeriodButtons.days = MakeSmallToggle(reportsPage, "DAY", 275, 72, function() reportPeriod = "days"; IRS:RefreshReportsPage() end)
reportPeriodButtons.weeks = MakeSmallToggle(reportsPage, "WEEK", 351, 72, function() reportPeriod = "weeks"; IRS:RefreshReportsPage() end)
reportPeriodButtons.months = MakeSmallToggle(reportsPage, "MONTH", 427, 72, function() reportPeriod = "months"; IRS:RefreshReportsPage() end)

local viewLabel = MakeText(reportsPage, 9, COLORS.muted, "LEFT")
viewLabel:SetPoint("TOPLEFT", 520, -65)
viewLabel:SetText("VIEW")

local reportViewButtons = {}
reportViewButtons.history = MakeSmallToggle(reportsPage, "HISTORY", 520, 92, function() reportView = "history"; IRS:RefreshReportsPage() end)
reportViewButtons.metrics = MakeSmallToggle(reportsPage, "BEST / AVG", 616, 100, function() reportView = "metrics"; IRS:RefreshReportsPage() end)
reportViewButtons.sources = MakeSmallToggle(reportsPage, "SOURCES", 720, 94, function() reportView = "sources"; IRS:RefreshReportsPage() end)

local reportPanel = MakePanel(reportsPage, COLORS.bg)
reportPanel:SetBackdropBorderColor(0, 0, 0, 0)
reportPanel:SetPoint("TOPLEFT", 4, -124)
reportPanel:SetPoint("BOTTOMRIGHT", -4, 4)

-- Scope popup (custom so large alt lists can scroll cleanly)
local scopePopup = MakePanel(frame, COLORS.panelAlt)
scopePopup:SetSize(260, 290)
scopePopup:SetFrameStrata("TOOLTIP")
scopePopup:SetPoint("TOPLEFT", scopeButton, "BOTTOMLEFT", 0, -2)
scopePopup:Hide()
local scopeScroll = CreateFrame("ScrollFrame", nil, scopePopup, "UIPanelScrollFrameTemplate")
scopeScroll:SetPoint("TOPLEFT", 5, -5)
scopeScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local scopeChild = CreateFrame("Frame", nil, scopeScroll)
scopeChild:SetSize(225, 1)
scopeScroll:SetScrollChild(scopeChild)
scopePopup.rows = {}

-- Lazily creates one character row in the Reports scope selector.
local function EnsureScopeRow(index)
    if scopePopup.rows[index] then return scopePopup.rows[index] end
    local b = CreateFrame("Button", nil, scopeChild, "BackdropTemplate")
    b:SetHeight(24)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    b:SetBackdropColor(0.035, 0.038, 0.038, 0.96)
    b.text = MakeText(b, 9, COLORS.text, "LEFT")
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.10, 0.08, 0.05, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.035, 0.038, 0.038, 0.96) end)
    scopePopup.rows[index] = b
    return b
end

-- Populates the Reports scope selector with All Characters + scanned characters.
local function RefreshScopePopup()
    local choices = { { key = "all", label = "All Characters" } }
    for _, entry in ipairs(IRS:GetSortedCharacters()) do
        table.insert(choices, { key = entry.key, label = entry.record.label or entry.record.name or "Unknown" })
    end
    for i, item in ipairs(choices) do
        local row = EnsureScopeRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * 25))
        row:SetWidth(225)
        row.text:SetText(item.label)
        row:SetScript("OnClick", function()
            reportScope = item.key
            scopeButton.text:SetText(item.label)
            scopePopup:Hide()
    projectPopup:Hide()
    sourcePopup:Hide()
    sourceDetailPopup:Hide()
            IRS:RefreshReportsPage()
        end)
        row:Show()
    end
    for i = #choices + 1, #scopePopup.rows do scopePopup.rows[i]:Hide() end
    scopeChild:SetHeight(math.max(1, #choices * 25))
end

scopeButton:SetScript("OnClick", function()
    if scopePopup:IsShown() then scopePopup:Hide() else RefreshScopePopup(); scopePopup:Show() end
end)

local historyView = CreateFrame("Frame", nil, reportPanel)
historyView:SetAllPoints()
local historyTitle = MakeText(historyView, 14, COLORS.goldSoft, "LEFT")
historyTitle:SetPoint("TOPLEFT", 14, -12)
historyTitle:SetText("FULL NET HISTORY")
local historyScopeText = MakeText(historyView, 9, COLORS.muted, "RIGHT")
historyScopeText:SetPoint("TOPRIGHT", -14, -15)

local historyHeader = MakePanel(historyView, COLORS.panelAlt)
historyHeader:SetBackdropBorderColor(unpack(COLORS.borderSoft))
historyHeader:SetPoint("TOPLEFT", 12, -42)
historyHeader:SetPoint("TOPRIGHT", -28, -42)
historyHeader:SetHeight(26)
local hhPeriod = MakeText(historyHeader, 9, COLORS.muted, "LEFT")
hhPeriod:SetPoint("LEFT", 10, 0); hhPeriod:SetText("PERIOD")
local hhAmount = MakeText(historyHeader, 9, COLORS.muted, "RIGHT")
hhAmount:SetPoint("RIGHT", -10, 0); hhAmount:SetText("NET")

local historyScroll = CreateFrame("ScrollFrame", nil, historyView, "UIPanelScrollFrameTemplate")
historyScroll:SetPoint("TOPLEFT", 12, -72)
historyScroll:SetPoint("BOTTOMRIGHT", -28, 12)
local historyChild = CreateFrame("Frame", nil, historyScroll)
historyChild:SetSize(780, 1)
historyScroll:SetScrollChild(historyChild)
historyView.rows = {}
-- Lazily creates one row in the Reports history table.
local function EnsureHistoryRow(index)
    if historyView.rows[index] then return historyView.rows[index] end
    local row = CreateFrame("Frame", nil, historyChild, "BackdropTemplate")
    row:SetHeight(27)
    row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    row:SetBackdropColor(0.21, 0.16, 0.10, 0.30)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row.period = MakeText(row, 10, COLORS.text, "LEFT")
    row.period:SetPoint("LEFT", 10, 0)
    row.amount = MakeText(row, 10, COLORS.goldSoft, "RIGHT")
    row.amount:SetPoint("RIGHT", -10, 0)
    local line = row:CreateTexture(nil, "BORDER")
    line:SetTexture("Interface/Buttons/WHITE8X8"); line:SetVertexColor(unpack(COLORS.borderSoft)); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0)
    historyView.rows[index] = row
    return row
end
local historyEmpty = MakeText(historyView, 11, COLORS.muted, "CENTER")
historyEmpty:SetPoint("CENTER", 0, -10)
historyEmpty:SetText("No IRS net activity has been recorded for this scope yet.")

local metricsView = CreateFrame("Frame", nil, reportPanel)
metricsView:SetAllPoints()
local metricsTitle = MakeText(metricsView, 14, COLORS.goldSoft, "LEFT")
metricsTitle:SetPoint("TOPLEFT", 14, -12)
metricsTitle:SetText("BEST DAY / AVERAGES")
local metricsScopeText = MakeText(metricsView, 9, COLORS.muted, "RIGHT")
metricsScopeText:SetPoint("TOPRIGHT", -14, -15)
metricsView.cards = {}
local metricLabels = {"BEST DAY", "DAILY AVERAGE", "WEEKLY AVERAGE", "MONTHLY AVERAGE", "TOTAL RECORDED"}
for i, label in ipairs(metricLabels) do
    local card = MakePanel(metricsView, COLORS.panelAlt)
    card:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    card:SetPoint("TOPLEFT", 14 + (col * 260), -55 - (row * 135))
    card:SetSize(245, 112)
    card.label = MakeText(card, 10, COLORS.muted, "CENTER")
    card.label:SetPoint("TOPLEFT", 8, -14); card.label:SetPoint("TOPRIGHT", -8, -14); card.label:SetText(label)
    card.value = MakeText(card, 20, COLORS.gold, "CENTER")
    card.value:SetPoint("CENTER", 0, -3); card.value:SetWidth(220)
    card.detail = MakeText(card, 9, COLORS.muted, "CENTER")
    card.detail:SetPoint("BOTTOMLEFT", 8, 10); card.detail:SetPoint("BOTTOMRIGHT", -8, 10)
    metricsView.cards[i] = card
end

local sourcesView = CreateFrame("Frame", nil, reportPanel)
sourcesView:SetAllPoints()
local sourcesTitle = MakeText(sourcesView, 14, COLORS.goldSoft, "LEFT")
sourcesTitle:SetPoint("TOPLEFT", 14, -12)
sourcesTitle:SetText("SOURCE BREAKDOWN")
local sourcesScopeText = MakeText(sourcesView, 9, COLORS.muted, "RIGHT")
sourcesScopeText:SetPoint("TOPRIGHT", -14, -15)
local sourceNote = MakeText(sourcesView, 9, COLORS.muted, "LEFT")
sourceNote:SetPoint("TOPLEFT", 14, -35)
sourceNote:SetText("Blizzard lifetime wealth statistics for the selected scope.")
sourcesView.rows = {}
local sourceLabels = {
    {"Total gold acquired", "totalAcquired"},
    {"Gold looted", "goldLooted"},
    {"Quest rewards", "questGold"},
    {"Vendor sales", "vendorGold"},
    {"Auction earnings", "auctionGold"},
    {"Other income", "otherIncome"},
}
for i, info in ipairs(sourceLabels) do
    local row = CreateFrame("Frame", nil, sourcesView, "BackdropTemplate")
    row:SetSize(780, 54)
    row:SetPoint("TOPLEFT", 14, -65 - ((i - 1) * 58))
    row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 2 })
    row:SetBackdropColor(unpack(COLORS.panelAlt))
    row:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    row.label = MakeText(row, 10, COLORS.text, "LEFT")
    row.label:SetPoint("TOPLEFT", 8, -6); row.label:SetText(info[1])
    row.value = MakeText(row, 11, COLORS.goldSoft, "RIGHT")
    row.value:SetPoint("TOPRIGHT", -8, -6)
    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface/Buttons/WHITE8X8"); row.barBG:SetVertexColor(0.15, 0.115, 0.070, 0.72)
    row.barBG:SetPoint("BOTTOMLEFT", 8, 10); row.barBG:SetSize(764, 10)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface/Buttons/WHITE8X8"); row.bar:SetVertexColor(unpack(COLORS.cyan))
    row.bar:SetPoint("BOTTOMLEFT", 8, 10); row.bar:SetHeight(10)
    row.statKey = info[2]
    sourcesView.rows[i] = row
end

-- ============================================================================
-- SECTION 7 — SETTINGS PAGE SHELL
-- The Settings interface itself lives in UI\IncomeRecordsSystem_Settings.lua.
-- Keeping it separate avoids bloating this already-large UI file and gives the
-- Settings tab room for its own internal sidebar/navigation.
-- ============================================================================
local settingsPage = CreateFrame("Frame", nil, content)
settingsPage:SetAllPoints()
pages.settings = settingsPage
IRS.pageFrames.settings = settingsPage
IRS.settingsPage = settingsPage

-- ============================================================================
-- SECTION 8 — HELP PAGE
-- In-addon command reference and explanations.
-- ============================================================================
local helpPage = CreateFrame("Frame", nil, content)
helpPage:SetAllPoints()
pages.help = helpPage
IRS.pageFrames.help = helpPage

local helpTitle = MakeText(helpPage, 19, COLORS.goldSoft, "LEFT")
helpTitle:SetPoint("TOPLEFT", 4, -4)
helpTitle:SetText("IRS FIELD MANUAL")
local helpIntro = MakeText(helpPage, 10, COLORS.text, "LEFT")
helpIntro:SetPoint("TOPLEFT", helpTitle, "BOTTOMLEFT", 0, -8)
helpIntro:SetPoint("RIGHT", -4, 0)
helpIntro:SetText("Income Records System tracks net gold movement across the characters you choose: income is positive, spending is negative, and losses reduce the period totals. Historical Blizzard wealth statistics remain available in the account overview and reports.")

local helpCommands = MakePanel(helpPage)
helpCommands:SetPoint("TOPLEFT", 4, -82)
helpCommands:SetPoint("TOPRIGHT", -4, -82)
helpCommands:SetHeight(270)
local helpHeading = MakeText(helpCommands, 13, COLORS.goldSoft, "LEFT")
helpHeading:SetPoint("TOPLEFT", 14, -13); helpHeading:SetText("COMMANDS")
local helpText = MakeText(helpCommands, 11, COLORS.text, "LEFT")
helpText:SetPoint("TOPLEFT", 14, -44); helpText:SetPoint("RIGHT", -14, 0)
helpText:SetText("/irs — toggle the IRS window\n\n/irs mini — toggle the floating mini dashboard\n\n/irs projects — open Savings Projects\n\n/irs reserves — open Reserve Funds\n\n/irs chars — open Characters\n\n/irs reports — open Reports\n\n/irs settings — open Settings\n\n/irs help — open this page\n\n/irs scan — rescan the current character\n\n/irs status — print current net periods to chat")

-- ============================================================================
-- SECTION 9 — REFRESH / CONTROLLER FUNCTIONS
-- Copies current Core.lua data into already-created UI widgets.
-- ============================================================================
-- Applies ACTIVE / PARTIAL / PAUSED colors and text to the
-- dashboard surveillance banner. The fill color is a faded version of the
-- current state color so the banner reads as one soft tinted strip.
local function SetSurveillanceState(state, titleText, detailText)
    if state == "paused" then
        status:SetBackdropColor(COLORS.red[1], COLORS.red[2], COLORS.red[3], 0.12)
        status:SetBackdropBorderColor(COLORS.red[1], COLORS.red[2], COLORS.red[3], 0.62)
        status.marker:SetVertexColor(unpack(COLORS.red))
        SetColor(status.title, COLORS.red)
    elseif state == "partial" then
        status:SetBackdropColor(COLORS.amber[1], COLORS.amber[2], COLORS.amber[3], 0.12)
        status:SetBackdropBorderColor(COLORS.amber[1], COLORS.amber[2], COLORS.amber[3], 0.62)
        status.marker:SetVertexColor(unpack(COLORS.amber))
        SetColor(status.title, COLORS.amber)
    else
        status:SetBackdropColor(COLORS.green[1], COLORS.green[2], COLORS.green[3], 0.12)
        status:SetBackdropBorderColor(COLORS.green[1], COLORS.green[2], COLORS.green[3], 0.58)
        status.marker:SetVertexColor(unpack(COLORS.green))
        SetColor(status.title, COLORS.green)
    end

    status.title:SetText(titleText)
    status.detail:SetText(detailText)
end

-- Rebuilds the visible 7-day NET chart. The Y range is asymmetric and follows
-- the actual data: the floor is the lowest negative value (or 0 when there are
-- no losses), while the ceiling is the highest positive value (or 0 when there
-- are no gains). This avoids inventing a mirrored negative range just because a
-- large positive day exists.
local function RefreshChart()
    local days = IRS:GetRecentDailyEarnings(7)
    local minAmount = 0
    local maxAmount = 0

    for _, day in ipairs(days) do
        local amount = tonumber(day.amount) or 0
        minAmount = math.min(minAmount, amount)
        maxAmount = math.max(maxAmount, amount)
    end

    -- Keep a tiny non-zero range when every displayed day is exactly zero so
    -- positioning math remains valid. Labels still render as 0g.
    local displayMin = minAmount
    local displayMax = maxAmount
    if displayMin == 0 and displayMax == 0 then
        displayMax = 1
    end

    local range = math.max(1, displayMax - displayMin)
    local plotBottom = 28
    local plotTop = 133
    local plotHeight = plotTop - plotBottom
    local slotBottom = 8

    local function ValueToChartY(value)
        return plotBottom
            + (((value - displayMin) / range) * plotHeight)
    end

    -- Four useful grid/tick values. Mixed gain/loss weeks always include the
    -- real minimum, zero, a positive midpoint, and the real maximum. Weeks that
    -- are entirely positive or negative use evenly spaced ticks across the real
    -- range with zero as the appropriate edge.
    local ticks
    if minAmount < 0 and maxAmount > 0 then
        ticks = {
            minAmount,
            0,
            maxAmount * 0.5,
            maxAmount,
        }
    elseif maxAmount > 0 then
        ticks = {
            0,
            maxAmount / 3,
            (maxAmount * 2) / 3,
            maxAmount,
        }
    elseif minAmount < 0 then
        ticks = {
            minAmount,
            (minAmount * 2) / 3,
            minAmount / 3,
            0,
        }
    else
        ticks = {0, 0, 0, 0}
    end

    for i = 1, 4 do
        local value = ticks[i] or 0
        local y = ValueToChartY(value)
        local line = chart.grid[i]

        line:ClearAllPoints()
        line:SetPoint("LEFT", chart, "LEFT", 52, 0)
        line:SetPoint("RIGHT", chart, "RIGHT", -12, 0)
        line:SetPoint("BOTTOM", chart, "BOTTOM", 0, y)

        if math.abs(value) < 1 then
            chart.yLabels[i]:SetText("0")
        else
            chart.yLabels[i]:SetText(FormatChartGold(value))
        end
    end

    local zeroY = ValueToChartY(0)
    local zeroInSlot = zeroY - slotBottom

    for i = 1, 7 do
        local data = days[i] or { label = "—", amount = 0 }
        local ui = chart.bars[i]
        local amount = tonumber(data.amount) or 0
        local h

        if amount == 0 then
            h = 2
        else
            h = math.max(
                3,
                math.min(
                    plotHeight,
                    math.floor((math.abs(amount) / range) * plotHeight)
                )
            )
        end

        ui.bar:ClearAllPoints()
        ui.bar:SetHeight(h)

        if amount < 0 then
            ui.bar:SetPoint("TOP", ui.slot, "BOTTOM", 0, zeroInSlot)
            ui.bar:SetVertexColor(unpack(COLORS.red))
        else
            ui.bar:SetPoint("BOTTOM", ui.slot, "BOTTOM", 0, zeroInSlot)
            ui.bar:SetVertexColor(unpack(COLORS.cyan))
        end

        ui.amount:SetText(FormatGold(amount))
        SetNetColor(ui.amount, amount, COLORS.goldSoft)
        ui.day:SetText(data.dateLabel or data.label or "—")
    end
end

-- Updates the Characters tab from the current saved character records.
function IRS:RefreshCharacterPage()
    if not IRS.db then return end
    local entries = IRS:GetSortedCharacters()
    local totals = IRS:GetTotals()
    charsSummary:SetText(string.format("%d tracked / %d scanned", totals.trackedCharacterCount or 0, totals.scannedCharacterCount or 0))
    local rowWidth = math.max(820, charScroll:GetWidth() - 4)

    local characterRowHeight = math.max(
        42,
        IRS:GetFontSize("main","body") + IRS:GetFontSize("main","helper") + 19
    )

    for i, entry in ipairs(entries) do
        local row = EnsureCharacterRow(i)
        local record = entry.record
        local tracked = record.trackingEnabled ~= false
        row.characterKey = entry.key
        row:SetHeight(characterRowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * (characterRowHeight + 2)))
        row:SetWidth(rowWidth)
        row.check:SetChecked(tracked)
        row.name:SetText(record.label or "Unknown")
        row.meta:SetText(record.className or "Unknown")
        row.level:SetText(tostring(record.level or 0))
        row.gold:SetText(FormatGold(record.money or 0, true))
        row.earned:SetText(FormatGold(record.earnedSinceTracking or 0))
        if tracked then
            row.status:SetText("TRACKING")
            SetColor(row.status, COLORS.green)
            row.statusMarker:SetVertexColor(unpack(COLORS.green))
        else
            row.status:SetText("IGNORED")
            SetColor(row.status, COLORS.red)
            row.statusMarker:SetVertexColor(unpack(COLORS.red))
        end
        row:Show()
    end
    for i = #entries + 1, #charactersPage.rows do charactersPage.rows[i]:Hide() end
    charScrollChild:SetHeight(math.max(1, #entries * (characterRowHeight + 2)))
end

-- Updates the currently selected report scope and view (history, averages, source
-- breakdown) from data supplied by Core.lua.
function IRS:RefreshReportsPage()
    if not IRS.db then return end
    local scopeKey = reportScope == "all" and nil or reportScope
    scopeButton.text:SetText(IRS:GetScopeName(reportScope))

    for key, b in pairs(reportPeriodButtons) do
        if key == reportPeriod then
            b:SetBackdropColor(0.18, 0.13, 0.05, 1); b:SetBackdropBorderColor(unpack(COLORS.goldSoft)); SetColor(b.label, COLORS.gold)
        else
            b:SetBackdropColor(0.045, 0.045, 0.042, 1); b:SetBackdropBorderColor(0.25, 0.22, 0.17, 1); SetColor(b.label, COLORS.text)
        end
    end
    for key, b in pairs(reportViewButtons) do
        if key == reportView then
            b:SetBackdropColor(0.18, 0.13, 0.05, 1); b:SetBackdropBorderColor(unpack(COLORS.goldSoft)); SetColor(b.label, COLORS.gold)
        else
            b:SetBackdropColor(0.045, 0.045, 0.042, 1); b:SetBackdropBorderColor(0.25, 0.22, 0.17, 1); SetColor(b.label, COLORS.text)
        end
    end

    historyView:SetShown(reportView == "history")
    metricsView:SetShown(reportView == "metrics")
    sourcesView:SetShown(reportView == "sources")

    local scopeName = IRS:GetScopeName(reportScope)
    historyScopeText:SetText(scopeName)
    metricsScopeText:SetText(scopeName)
    sourcesScopeText:SetText(scopeName)

    if reportView == "history" then
        local rows = IRS:GetReportHistory(reportPeriod, scopeKey)
        historyEmpty:SetShown(#rows == 0)
        local rowWidth = math.max(780, historyScroll:GetWidth() - 4)
        local historyRowHeight = math.max(27, IRS:GetFontSize("main","body") + 12)
        for i, data in ipairs(rows) do
            local row = EnsureHistoryRow(i)
            row:SetHeight(historyRowHeight)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((i - 1) * (historyRowHeight + 1))); row:SetWidth(rowWidth)
            row.period:SetText(data.label or tostring(data.key))
            row.amount:SetText(FormatGold(data.amount or 0, true))
            SetNetColor(row.amount, data.amount or 0, COLORS.goldSoft)
            row:Show()
        end
        for i = #rows + 1, #historyView.rows do historyView.rows[i]:Hide() end
        historyChild:SetHeight(math.max(1, #rows * (historyRowHeight + 1)))
    elseif reportView == "metrics" then
        local m = IRS:GetReportMetrics(scopeKey)
        metricsView.cards[1].value:SetText(FormatGold(m.bestDayAmount or 0)); SetNetColor(metricsView.cards[1].value, m.bestDayAmount or 0)
        metricsView.cards[1].detail:SetText(m.bestDayLabel or "—")
        metricsView.cards[2].value:SetText(FormatGold(m.dailyAverage or 0)); SetNetColor(metricsView.cards[2].value, m.dailyAverage or 0)
        metricsView.cards[2].detail:SetText(string.format("Across %d recorded day%s", m.dayCount or 0, (m.dayCount or 0) == 1 and "" or "s"))
        metricsView.cards[3].value:SetText(FormatGold(m.weeklyAverage or 0)); SetNetColor(metricsView.cards[3].value, m.weeklyAverage or 0)
        metricsView.cards[3].detail:SetText(string.format("Across %d recorded week%s", m.weekCount or 0, (m.weekCount or 0) == 1 and "" or "s"))
        metricsView.cards[4].value:SetText(FormatGold(m.monthlyAverage or 0)); SetNetColor(metricsView.cards[4].value, m.monthlyAverage or 0)
        metricsView.cards[4].detail:SetText(string.format("Across %d recorded month%s", m.monthCount or 0, (m.monthCount or 0) == 1 and "" or "s"))
        metricsView.cards[5].value:SetText(FormatGold(m.total or 0)); SetNetColor(metricsView.cards[5].value, m.total or 0)
        metricsView.cards[5].detail:SetText("IRS recorded net total")
    else
        local s = IRS:GetLifetimeSourceBreakdown(reportScope)
        local maxValue = math.max(1, s.totalAcquired or 0, s.goldLooted or 0, s.questGold or 0, s.vendorGold or 0, s.auctionGold or 0, s.otherIncome or 0)
        for _, row in ipairs(sourcesView.rows) do
            local value = s[row.statKey] or 0
            row.value:SetText(FormatGold(value, true))
            row.bar:SetWidth(math.max(1, math.floor(math.max(1, row.barBG:GetWidth()) * (value / maxValue))))
        end
    end
end

-- Settings refresh is implemented in UI\IncomeRecordsSystem_Settings.lua.

-- Reflows width-sensitive content when the main IRS window is resized.
-- Height overflow is handled by the tab ScrollFrames; width changes are applied
-- to the report strips, charts, summary columns, and report cards so they use
-- the newly available horizontal room instead of stretching artwork.
function IRS:RefreshMainWindowSizeLayout()
    local dashboardWidth = math.max(1, dashboard:GetWidth() or 1)

    -- Dashboard headline strip: four equal columns.
    local periodGap = 8
    local periodWidth = math.max(120, (dashboardWidth - (periodGap * 3)) / 4)
    local periodCards = {todayCard, weekCard, monthCard, totalCard}

    for i, card in ipairs(periodCards) do
        card:ClearAllPoints()
        card:SetPoint(
            "TOPLEFT",
            periodContainer,
            "TOPLEFT",
            (i - 1) * (periodWidth + periodGap),
            0
        )
        card:SetWidth(periodWidth)
    end

    -- Dashboard chart: seven equal time slots across the real plot width.
    local chartWidth = math.max(1, chart:GetWidth() or dashboardWidth)
    local plotLeft = 52
    local plotRight = 12
    local plotWidth = math.max(210, chartWidth - plotLeft - plotRight)
    local slotWidth = plotWidth / 7

    for i, data in ipairs(chart.bars) do
        data.slot:ClearAllPoints()
        data.slot:SetPoint(
            "BOTTOMLEFT",
            chart,
            "BOTTOMLEFT",
            plotLeft + ((i - 1) * slotWidth),
            8
        )
        data.slot:SetWidth(slotWidth)
        data.amount:SetWidth(math.max(40, slotWidth - 4))
        data.day:SetWidth(math.max(40, slotWidth - 4))
        data.bar:SetWidth(math.max(18, math.min(52, slotWidth * 0.46)))
    end

    -- Section rules span the current Dashboard width.
    titleUnderline:ClearAllPoints()
    titleUnderline:SetPoint("TOPLEFT", chartTitle, "BOTTOMLEFT", 0, -6)
    titleUnderline:SetSize(dashboardWidth, 1)

    overviewLine:ClearAllPoints()
    overviewLine:SetPoint("TOPLEFT", overviewTitle, "BOTTOMLEFT", 0, -6)
    overviewLine:SetSize(dashboardWidth, 1)

    -- Account Overview: three equal report columns.
    local overviewGap = 10
    local overviewWidth = math.max(180, (dashboardWidth - (overviewGap * 2)) / 3)

    left:ClearAllPoints()
    middle:ClearAllPoints()
    right:ClearAllPoints()
    left:SetPoint("TOPLEFT", overviewLine, "BOTTOMLEFT", 0, -5)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", overviewGap, 0)
    right:SetPoint("TOPLEFT", middle, "TOPRIGHT", overviewGap, 0)
    left:SetWidth(overviewWidth)
    middle:SetWidth(overviewWidth)
    right:SetWidth(overviewWidth)

    -- Project summary: four equal statistics across the resized page.
    local summaryWidth = math.max(1, projectSummary:GetWidth() or 1)
    local summaryGap = 5
    local summaryInset = 20
    local summaryCardWidth = math.max(120,
        (summaryWidth - summaryInset - (summaryGap * 3)) / 4
    )

    for i, card in ipairs(projectSummary.cards) do
        card:ClearAllPoints()
        card:SetPoint(
            "TOPLEFT",
            projectSummary,
            "TOPLEFT",
            10 + ((i - 1) * (summaryCardWidth + summaryGap)),
            -8
        )
        card:SetWidth(summaryCardWidth)
    end

    -- Project Trajectory and Daily Gold Tracker stack vertically and use the
    -- full available Projects page width.
    dailyPanel:ClearAllPoints()
    dailyPanel:SetPoint("TOPLEFT", projectSummary, "BOTTOMLEFT", 0, -12)
    dailyPanel:SetWidth(410)

    graphPanel:ClearAllPoints()
    graphPanel:SetPoint("TOPLEFT", projectSummary, "BOTTOMLEFT", 0, -12)
    graphPanel:SetPoint("TOPRIGHT", projectSummary, "BOTTOMRIGHT", 0, -12)
    dailyPanel:ClearAllPoints()
    dailyPanel:SetPoint("TOPLEFT", graphPanel, "BOTTOMLEFT", 0, -12)
    dailyPanel:SetPoint("TOPRIGHT", graphPanel, "BOTTOMRIGHT", 0, -12)
    LayoutDailyTrackerColumns()

    -- Reports metric cards fill their three-column grid.
    local reportWidth = math.max(1, reportPanel:GetWidth() or 1)
    local reportInset = 28
    local reportGap = 15
    local reportCardWidth = math.max(180,
        (reportWidth - reportInset - (reportGap * 2)) / 3
    )

    for i, card in ipairs(metricsView.cards) do
        local col = (i - 1) % 3
        local rowIndex = math.floor((i - 1) / 3)
        card:ClearAllPoints()
        card:SetPoint(
            "TOPLEFT",
            metricsView,
            "TOPLEFT",
            14 + (col * (reportCardWidth + reportGap)),
            -55 - (rowIndex * (card:GetHeight() + 23))
        )
        card:SetWidth(reportCardWidth)
        card.value:SetWidth(math.max(120, reportCardWidth - 24))
    end

    -- Source rows and bars expand with Reports.
    -- IMPORTANT: do not ClearAllPoints() here. RefreshMainFontLayout owns each
    -- row's vertical anchor. Clearing the anchors during width-only resize made
    -- the Source Breakdown values update correctly but left the rows with no
    -- position, so the entire view appeared blank.
    for _, row in ipairs(sourcesView.rows) do
        row:SetWidth(math.max(300, reportWidth - 28))
        row.barBG:ClearAllPoints()
        row.barBG:SetPoint("BOTTOMLEFT", 8, 10)
        row.barBG:SetPoint("BOTTOMRIGHT", -8, 10)
        row.barBG:SetHeight(10)
    end

    charScrollChild:SetWidth(math.max(820, (charScroll:GetWidth() or 840) - 18))
    historyChild:SetWidth(math.max(300, (historyScroll:GetWidth() or 800) - 18))

    if IRS.RefreshReservesLayout then
        IRS:RefreshReservesLayout()
    end
    if IRS.RefreshToolsLayout then
        IRS:RefreshToolsLayout()
    end
end

-- Recalculates the most overlap-prone IRS layouts after font-style changes.
-- Most labels already anchor relative to one another; this function handles the
-- remaining fixed-height cards, tables, and stacked panels.
function IRS:RefreshMainFontLayout()
    if not IRS.db then return end

    local helper = IRS:GetFontSize("main", "helper")
    local body = IRS:GetFontSize("main", "body")
    local labelSize = IRS:GetFontSize("main", "label")
    local sectionSize = IRS:GetFontSize("main", "section")
    local valueSize = IRS:GetFontSize("main", "value")

    -- DASHBOARD: surveillance banner and headline period cards.
    local statusHeight = math.max(58, labelSize + body + 25)
    status:SetHeight(statusHeight)

    periodContainer:ClearAllPoints()
    periodContainer:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -9)
    periodContainer:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, -9)

    local periodHeight = math.max(84, helper + valueSize + helper + 31)
    periodContainer:SetHeight(periodHeight)

    for _, card in ipairs({todayCard, weekCard, monthCard, totalCard}) do
        card:SetHeight(periodHeight)
    end

    chartTitle:ClearAllPoints()
    chartTitle:SetPoint("TOPLEFT", periodContainer, "BOTTOMLEFT", 0, -12)

    titleUnderline:ClearAllPoints()
    titleUnderline:SetPoint("TOPLEFT", chartTitle, "BOTTOMLEFT", 0, -6)
    titleUnderline:SetPoint("TOPRIGHT", chartTitle, "BOTTOMRIGHT", 854, -6)

    chart:ClearAllPoints()
    chart:SetPoint("TOPLEFT", titleUnderline, "BOTTOMLEFT", 0, -5)
    chart:SetPoint("TOPRIGHT", dashboard, "TOPRIGHT", 0, 0)

    local chartHeight = math.max(178, helper + body + 158)
    chart:SetHeight(chartHeight)
    for _, data in ipairs(chart.bars) do
        data.slot:SetHeight(math.max(154, chartHeight - 24))
    end

    overviewTitle:ClearAllPoints()
    overviewTitle:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -12)

    overviewLine:ClearAllPoints()
    overviewLine:SetPoint("TOPLEFT", overviewTitle, "BOTTOMLEFT", 0, -6)
    overviewLine:SetPoint("TOPRIGHT", overviewTitle, "BOTTOMRIGHT", 854, -6)

    local overviewRowHeight = math.max(21, math.max(helper, body) + 8)
    local overviewPanels = {left, middle, right}
    local overviewTop = overviewLine

    for _, panel in ipairs(overviewPanels) do
        panel:ClearAllPoints()
    end

    left:SetPoint("TOPLEFT", overviewTop, "BOTTOMLEFT", 0, -5)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("TOPLEFT", middle, "TOPRIGHT", 10, 0)

    for _, panel in ipairs(overviewPanels) do
        local rowCount = #panel.rows
        local panelHeight = math.max(160, 39 + (rowCount * overviewRowHeight) + 8)
        panel:SetHeight(panelHeight)

        for i, value in ipairs(panel.rows) do
            local y = -39 - ((i - 1) * overviewRowHeight)
            local label = panel.labels and panel.labels[i]

            if label then
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", 2, y)
            end

            value:ClearAllPoints()
            value:SetPoint("TOPRIGHT", -2, y)
        end
    end

    -- PROJECTS: summary cards grow vertically with their three text tiers.
    local summaryCardHeight = math.max(
        67,
        helper + valueSize + helper + 30
    )
    local progressHeight = math.max(18, helper + 8)
    local summaryHeight = summaryCardHeight + progressHeight + 32

    projectSummary:SetHeight(summaryHeight)

    for _, card in ipairs(projectSummary.cards) do
        card:SetHeight(summaryCardHeight)

        card.label:ClearAllPoints()
        card.label:SetPoint("TOPLEFT", 2, 0)
        card.label:SetPoint("TOPRIGHT", -2, 0)

        card.value:ClearAllPoints()
        card.value:SetPoint("TOPLEFT", 2, -(helper + 8))
        card.value:SetPoint("TOPRIGHT", -2, -(helper + 8))

        card.detail:ClearAllPoints()
        card.detail:SetPoint("TOPLEFT", 2, -(helper + valueSize + 18))
        card.detail:SetPoint("TOPRIGHT", -2, -(helper + valueSize + 18))
    end

    progressBG:SetHeight(progressHeight)
    progressBar:SetHeight(progressHeight)

    -- Give the lower panels enough room for the graph and vertical X-axis labels.
    local lowerPanelHeight = math.max(
        450,
        340 + (helper * 2)
    )

    graphPanel:ClearAllPoints()
    graphPanel:SetPoint("TOPLEFT", projectSummary, "BOTTOMLEFT", 0, -12)
    graphPanel:SetPoint("TOPRIGHT", projectsPage, "TOPRIGHT", 0, -12)
    graphPanel:SetHeight(lowerPanelHeight)
    dailyPanel:ClearAllPoints()
    dailyPanel:SetPoint("TOPLEFT", graphPanel, "BOTTOMLEFT", 0, -12)
    dailyPanel:SetPoint("TOPRIGHT", graphPanel, "BOTTOMRIGHT", 0, -12)
    dailyPanel:SetHeight(lowerPanelHeight)

    dailyHeader:ClearAllPoints()
    dailyHeader:SetPoint("TOPLEFT", dailySub, "BOTTOMLEFT", -2, -10)
    dailyHeader:SetPoint("TOPRIGHT", dailyPanel, "TOPRIGHT", -24, -(sectionSize + helper + 31))
    dailyHeader:SetHeight(math.max(22, helper + 10))

    dailyScroll:ClearAllPoints()
    dailyScroll:SetPoint("TOPLEFT", dailyHeader, "BOTTOMLEFT", 0, -3)
    dailyScroll:SetPoint("BOTTOMRIGHT", -25, 10)
    LayoutDailyTrackerColumns()

    graph:ClearAllPoints()
    graph:SetPoint("TOPLEFT", 50, -(math.max(sectionSize, helper) + 54))
    graph:SetPoint("BOTTOMRIGHT", -16, 108)

    -- CHARACTERS: header and scroll area follow the description rather than a
    -- fixed pixel Y value; name/meta rows get extra vertical room.
    charHeader:ClearAllPoints()
    charHeader:SetPoint("TOPLEFT", charsDesc, "BOTTOMLEFT", -4, -12)
    charHeader:SetPoint("TOPRIGHT", charactersPage, "TOPRIGHT", -18, 0)
    charHeader:SetHeight(math.max(26, helper + 12))

    charScroll:ClearAllPoints()
    charScroll:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, -4)
    charScroll:SetPoint("BOTTOMRIGHT", -28, 32)

    for _, row in ipairs(charactersPage.rows) do
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", 58, -6)

        row.meta:ClearAllPoints()
        row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    end

    -- REPORTS: the history table header/rows and metric cards breathe with text.
    historyHeader:ClearAllPoints()
    historyHeader:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", -2, -12)
    historyHeader:SetPoint("TOPRIGHT", historyView, "TOPRIGHT", -28, 0)
    historyHeader:SetHeight(math.max(26, helper + 12))

    historyScroll:ClearAllPoints()
    historyScroll:SetPoint("TOPLEFT", historyHeader, "BOTTOMLEFT", 0, -4)
    historyScroll:SetPoint("BOTTOMRIGHT", -28, 12)

    local metricCardHeight = math.max(112, body + valueSize + helper + 40)
    for i, card in ipairs(metricsView.cards) do
        local col = (i - 1) % 3
        local rowIndex = math.floor((i - 1) / 3)
        card:ClearAllPoints()
        card:SetPoint(
            "TOPLEFT",
            14 + (col * 260),
            -55 - (rowIndex * (metricCardHeight + 23))
        )
        card:SetHeight(metricCardHeight)
    end

    local sourceRowHeight = math.max(54, body + 38)
    for i, row in ipairs(sourcesView.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 14, -65 - ((i - 1) * (sourceRowHeight + 4)))
        row:SetHeight(sourceRowHeight)
    end

    IRS:RefreshMainWindowSizeLayout()
end

-- MASTER UI REFRESH.
-- Pulls the newest totals/character/project data from Core.lua and updates the
-- dashboard plus whichever supporting pages need to stay synchronized.
function IRS:RefreshUI()
    if not IRS.db then return end

    local refreshTiming = IRS:BeginStartupTiming("Master UI refresh")

    local stageTiming = IRS:BeginStartupTiming("UI: Page scroll preparation")
    if IRS.PreparePageScroll then
        IRS:PreparePageScroll()
    end
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("UI: Main layout refresh")
    IRS:RefreshMainFontLayout()
    IRS:EndStartupTiming(stageTiming)

    local dashboardTiming = IRS:BeginStartupTiming("Dashboard refresh")
    local totals = IRS:GetTotals()
    local earnings = IRS:GetCurrentEarnings()
    local current = IRS.db.characters[IRS:CharacterKey()]
    local currentEarnings = IRS:GetCharacterEarnings(IRS:CharacterKey())
    local currentTracked = current and current.trackingEnabled ~= false

    if current then
        local stateText = currentTracked and "|cff39ff59TRACKING|r" or "|cffff3833IGNORED|r"
        currentLine:SetText(string.format("%s  •  Level %d %s  •  %s", current.label or "Unknown", current.level or 0, current.className or "", stateText))
    else
        currentLine:SetText(IRS:CharacterLabel())
    end

    local tracked = totals.trackedCharacterCount or 0
    local scanned = totals.scannedCharacterCount or 0
    local ignored = math.max(0, scanned - tracked)
    if not currentTracked or tracked == 0 then
        local detail = current and not currentTracked
            and string.format("%s is ignored. Account coverage: %d of %d scanned characters tracked.", current.name or "Current character", tracked, scanned)
            or "No scanned characters are currently enabled for earnings tracking."
        SetSurveillanceState("paused", "SURVEILLANCE PAUSED", detail)
    elseif ignored > 0 then
        SetSurveillanceState("partial", "SURVEILLANCE PARTIAL", string.format("Tracking %d of %d scanned characters. %d character%s ignored.", tracked, scanned, ignored, ignored == 1 and "" or "s"))
    else
        SetSurveillanceState("active", "SURVEILLANCE ACTIVE", string.format("Tracking all %d scanned character%s. New gold earnings are being filed automatically.", scanned, scanned == 1 and "" or "s"))
    end

    todayCard.value:SetText(FormatGold(earnings.today))
    weekCard.value:SetText(FormatGold(earnings.week))
    monthCard.value:SetText(FormatGold(earnings.month))
    totalCard.value:SetText(FormatGold(earnings.total))
    SetNetColor(todayCard.value, earnings.today, COLORS.muted, COLORS.green)
    SetNetColor(weekCard.value, earnings.week, COLORS.muted, COLORS.green)
    SetNetColor(monthCard.value, earnings.month, COLORS.muted, COLORS.green)
    SetNetColor(totalCard.value, earnings.total, COLORS.muted, COLORS.green)

    local shortName = current and current.name or "Current"
    todayCard.characterValue:SetText(string.format("%s (%s)", FormatGold(currentEarnings.today), shortName))
    weekCard.characterValue:SetText(string.format("%s (%s)", FormatGold(currentEarnings.week), shortName))
    monthCard.characterValue:SetText(string.format("%s (%s)", FormatGold(currentEarnings.month), shortName))
    totalCard.characterValue:SetText(string.format("%s (%s)", FormatGold(currentEarnings.total), shortName))

    -- Character-specific helper values are informational, not account status.
    -- Keep them in the default muted white regardless of gain/loss direction.
    SetColor(todayCard.characterValue, COLORS.muted)
    SetColor(weekCard.characterValue, COLORS.muted)
    SetColor(monthCard.characterValue, COLORS.muted)
    SetColor(totalCard.characterValue, COLORS.muted)

    local otherIncome = math.max(0, (totals.totalAcquired or 0) - ((totals.goldLooted or 0) + (totals.questGold or 0) + (totals.vendorGold or 0) + (totals.auctionGold or 0)))
    left.rows[1]:SetText(FormatGold(totals.totalAcquired or 0, true))
    left.rows[2]:SetText(FormatGold(totals.goldLooted or 0, true))
    left.rows[3]:SetText(FormatGold(totals.questGold or 0, true))
    left.rows[4]:SetText(FormatGold(totals.vendorGold or 0, true))
    left.rows[5]:SetText(FormatGold(totals.auctionGold or 0, true))
    left.rows[6]:SetText(FormatGold(otherIncome, true))

    middle.rows[1]:SetText(IRS:FormatCount(totals.auctionsPosted or 0))
    middle.rows[2]:SetText(IRS:FormatCount(totals.auctionPurchases or 0))
    middle.rows[3]:SetText(FormatGold(totals.largestSale or 0, true))
    middle.rows[4]:SetText(FormatGold(totals.largestBid or 0, true))

    right.rows[1]:SetText(FormatGold(totals.travelSpent or 0, true))
    right.rows[2]:SetText(FormatGold(totals.postageSpent or 0, true))
    right.rows[3]:SetText(FormatGold(totals.transmogSpent or 0, true))
    right.rows[4]:SetText(string.format("%d / %d", tracked, scanned))
    right.rows[5]:SetText(totals.warbandGoldSeen and FormatGold(totals.warbandGold or 0, true) or "Unavailable")

    if IRS.RefreshTokenDashboardCard then
        local tokenTiming = IRS:BeginStartupTiming("Token dashboard refresh")
        IRS:RefreshTokenDashboardCard()
        IRS:EndStartupTiming(tokenTiming)
    end

    local updated = IRS.db.account.lastScan
    lastUpdated:SetText("Last Updated\n" .. (updated and date("%b %d, %Y  %I:%M %p", updated) or "—"))

    RefreshChart()
    IRS:EndStartupTiming(dashboardTiming)

    stageTiming = IRS:BeginStartupTiming("Projects refresh")
    IRS:RefreshProjectsPage(true)
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Reserves refresh")
    if IRS.RefreshReservesPage then IRS:RefreshReservesPage(true) end
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Tools refresh")
    if IRS.RefreshToolsPage then IRS:RefreshToolsPage() end
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Characters refresh")
    IRS:RefreshCharacterPage()
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Reports refresh")
    IRS:RefreshReportsPage()
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Settings refresh")
    IRS:RefreshSettingsPage()
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("Mini Dashboard refresh")
    if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    IRS:EndStartupTiming(stageTiming)

    stageTiming = IRS:BeginStartupTiming("UI: Page scroll refresh")
    if IRS.RefreshPageScroll then
        IRS:RefreshPageScroll(activeTab)
    end
    IRS:EndStartupTiming(stageTiming)

    IRS:EndStartupTiming(refreshTiming)
end

-- Shows one page, hides the others, updates sidebar active-state artwork, and
-- refreshes page-specific content when needed.
function IRS:SelectTab(key)
    key = pages[key] and key or "dashboard"
    activeTab = key
    IRS.activeTab = key

    scopePopup:Hide()
    projectPopup:Hide()
    sourcePopup:Hide()
    sourceDetailPopup:Hide()
    if IRS.HideReservePopups then IRS:HideReservePopups() end
    for pageKey, page in pairs(pages) do page:SetShown(pageKey == key) end

    if IRS.UpdatePageScrollVisibility then
        IRS:UpdatePageScrollVisibility(key)
    end

    for tabKey, button in pairs(tabs) do
        if tabKey == key then
            button:SetBackdropColor(0.15, 0.115, 0.070, 0.42)
            SetColor(button.label, COLORS.gold)
            button.activeBar:Show()
        else
            button:SetBackdropColor(0, 0, 0, 0)
            SetColor(button.label, COLORS.text)
            button.activeBar:Hide()
        end
    end
    if key == "projects" then IRS:RefreshProjectsPage()
    elseif key == "reserves" and IRS.RefreshReservesPage then IRS:RefreshReservesPage()
    elseif key == "tools" and IRS.RefreshToolsPage then IRS:RefreshToolsPage()
    elseif key == "characters" then IRS:RefreshCharacterPage()
    elseif key == "reports" then IRS:RefreshReportsPage()
    elseif key == "settings" then IRS:RefreshSettingsPage() end

    if IRS.RefreshPageScroll then
        IRS:RefreshPageScroll(key)
    end
end

-- Opens IRS on a requested tab after taking a fresh current-character scan.
function IRS:ShowUI(tabKey)
    IRS:ScanCurrentCharacter()
    IRS:RefreshUI()
    IRS:SelectTab(tabKey or activeTab or "dashboard")
    frame:Show()
end

-- Main open/close behavior used by /irs and the minimap button.
function IRS:ToggleUI()
    if frame:IsShown() then frame:Hide() else IRS:ShowUI(activeTab or "dashboard") end
end


-- ============================================================================
-- SECTION 10 — MINIMAP BUTTON
-- Left-click opens/closes the full IRS dashboard.
-- Right-click opens/closes the floating mini dashboard.
--
-- The floating mini dashboard itself lives in:
--   UI\IncomeRecordsSystem_MiniDashboard.lua
--
-- It was intentionally split into a separate Lua file to keep this already
-- large UI file under WoW Lua's per-chunk local-variable limit.
-- ============================================================================

-- Left-click opens/closes the full IRS dashboard.
-- Right-click opens/closes the floating mini dashboard.
-- ============================================================================
local minimapButton = CreateFrame("Button", "IncomeRecordsSystemMinimapButton", Minimap)
minimapButton:SetSize(34, 34)
minimapButton:SetPoint("CENTER", Minimap, "CENTER", -56, -56)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local miniIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
miniIcon:SetTexture(MEDIA .. "IRSButton")
miniIcon:SetSize(34, 34)
miniIcon:SetPoint("CENTER", 0, 0)

local miniHighlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
miniHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
miniHighlight:SetBlendMode("ADD")
miniHighlight:SetSize(36, 36)
miniHighlight:SetPoint("CENTER", 0, 0)

minimapButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        IRS:ToggleMiniDashboard()
    else
        IRS:ToggleUI()
    end
end)
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("IRS — Income Records System", 1.0, 0.76, 0.28)
    GameTooltip:AddLine("Left-click: open or close IRS.", 0.9, 0.88, 0.81)
    GameTooltip:AddLine("Right-click: toggle mini dashboard.", 0.9, 0.88, 0.81)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Shows or hides the minimap button according to the saved Settings checkbox.
function IRS:RefreshMinimapButton()
    if not IRS.db then IRS:EnsureDB() end
    minimapButton:SetShown(IRS.db.settings.showMinimapButton ~= false)
end

IRS:SelectTab("dashboard")

IRS:EndStartupTiming(_irsStartupModuleTiming)
