--[[
IRS — Settings
Settings navigation, toggles, Mini Dashboard options, transfer settings, Token settings, and fonts.
]]

local IRS = IRS
local page = IRS.settingsPage
if not page then return end

local _irsStartupModuleTiming = IRS:BeginStartupTiming("Settings UI initialization / module load")

local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.980},
    panelAlt = {0.225, 0.170, 0.112, 0.985},
    borderSoft = {0.46, 0.36, 0.22, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {0.43, 0.60, 0.36, 1},
}

local function SetColor(fontString, color)
    IRS:SetLayoutColor(fontString, "SetTextColor", color[1], color[2], color[3], color[4] or 1)
end

local function MakeText(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local renderedSize = IRS:GetFontSize("main", size)

    fs:SetFont(STANDARD_TEXT_FONT, renderedSize, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then SetColor(fs, color) end

    if size and size ~= 1 then
        IRS:RegisterFontString("main", size, fs, STANDARD_TEXT_FONT, "")
    end

    return fs
end

local function MakePanel(parent, bgColor)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    local c = bgColor or COLORS.panel
    IRS:SetLayoutColor(panel, "SetBackdropColor", c[1], c[2], c[3], c[4] or 1)
    IRS:SetLayoutColor(panel, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
    return panel
end

-- ============================================================================
-- PAGE HEADER + INTERNAL SETTINGS SIDEBAR
-- ============================================================================

local title = MakeText(page, 19, COLORS.goldSoft, "LEFT")
title:SetPoint("TOPLEFT", 4, -4)
title:SetText("SETTINGS")

local desc = MakeText(page, 8, COLORS.text, "LEFT")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetPoint("RIGHT", -4, 0)
desc:SetText("Choose a category. IRS settings are saved account-wide.")

local rail = MakePanel(page, COLORS.panel)
rail:SetPoint("TOPLEFT", 4, -72)
rail:SetPoint("BOTTOMLEFT", 4, 4)
rail:SetWidth(154)
IRS:SetLayoutColor(rail, "SetBackdropBorderColor", 0, 0, 0, 0)
rail.divider = rail:CreateTexture(nil, "BORDER")
rail.divider:SetTexture("Interface/Buttons/WHITE8X8")
IRS:SetLayoutColor(rail.divider, "SetVertexColor", unpack(COLORS.borderSoft))
rail.divider:SetWidth(1)
rail.divider:SetPoint("TOPRIGHT", -1, 0)
rail.divider:SetPoint("BOTTOMRIGHT", -1, 0)

local body = MakePanel(page, COLORS.panel)
body:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, 0)
body:SetPoint("BOTTOMRIGHT", -4, 4)
IRS:SetLayoutColor(body, "SetBackdropBorderColor", 0, 0, 0, 0)

local sections = {}
local sectionButtons = {}
local activeSection = "toggles"

local SECTION_INFO = {
    { key = "toggles", label = "Toggles" },
    { key = "mini", label = "Mini Dashboard" },
    { key = "transfers", label = "Transfers" },
    { key = "token", label = "WoW Token" },
    { key = "fonts", label = "Fonts" },
}

local function ApplySectionVisuals()
    for key, button in pairs(sectionButtons) do
        if key == activeSection then
            IRS:SetLayoutColor(button, "SetBackdropColor", 0.15, 0.115, 0.070, 0.42)
            IRS:SetLayoutColor(button, "SetBackdropBorderColor", 0, 0, 0, 0)
            SetColor(button.label, COLORS.gold)
            button.activeBar:Show()
        else
            IRS:SetLayoutColor(button, "SetBackdropColor", unpack(COLORS.panelAlt))
            IRS:SetLayoutColor(button, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
            SetColor(button.label, COLORS.text)
            button.activeBar:Hide()
        end
    end

    for key, section in pairs(sections) do
        section:SetShown(key == activeSection)
    end
end

function IRS:SelectSettingsSection(key)
    if not sections[key] then key = "toggles" end

    activeSection = key

    if IRS.db then
        IRS.db.ui = IRS.db.ui or {}
        IRS.db.ui.settingsSection = key
    end

    ApplySectionVisuals()
end

for i, info in ipairs(SECTION_INFO) do
    local button = CreateFrame("Button", nil, rail, "BackdropTemplate")
    IRS:StyleButtonFeedback(button)
    button:SetPoint("TOPLEFT", 7, -8 - ((i - 1) * 38))
    button:SetSize(140, 32)
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    IRS:SetLayoutColor(button, "SetBackdropColor", 0, 0, 0, 0)
    IRS:SetLayoutColor(button, "SetBackdropBorderColor", 0, 0, 0, 0)

    button.activeBar = button:CreateTexture(nil, "ARTWORK")
    button.activeBar:SetTexture("Interface/Buttons/WHITE8X8")
    IRS:SetLayoutColor(button.activeBar, "SetVertexColor", unpack(COLORS.gold))
    button.activeBar:SetWidth(2)
    button.activeBar:SetPoint("TOPLEFT", 0, -4)
    button.activeBar:SetPoint("BOTTOMLEFT", 0, 4)
    button.activeBar:Hide()

    button.label = MakeText(button, 11, COLORS.text, "LEFT")
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.label:SetText(info.label)

    button:SetScript("OnClick", function()
        IRS:SelectSettingsSection(info.key)
    end)

    button:SetScript("OnEnter", function(self)
        if activeSection ~= info.key then
            SetColor(self.label, COLORS.goldSoft)
        end
    end)

    button:SetScript("OnLeave", function()
        ApplySectionVisuals()
    end)

    sectionButtons[info.key] = button
end

-- ============================================================================
-- TOGGLES SECTION
-- ============================================================================

local toggles = CreateFrame("Frame", nil, body)
toggles:SetAllPoints()
sections.toggles = toggles

local togglesTitle = MakeText(toggles, 16, COLORS.goldSoft, "LEFT")
togglesTitle:SetPoint("TOPLEFT", 16, -14)
togglesTitle:SetText("GENERAL TOGGLES")

local togglesDesc = MakeText(toggles, 8, COLORS.muted, "LEFT")
togglesDesc:SetPoint("TOPLEFT", togglesTitle, "BOTTOMLEFT", 0, -6)
togglesDesc:SetPoint("RIGHT", -16, 0)
togglesDesc:SetText("General IRS interface switches live here.")

local togglePanel = MakePanel(toggles, COLORS.panelAlt)
togglePanel:SetPoint("TOPLEFT", 14, -72)
togglePanel:SetPoint("TOPRIGHT", -14, -72)
togglePanel:SetHeight(144)

local minimapCheck = CreateFrame("CheckButton", nil, togglePanel, "UICheckButtonTemplate")
minimapCheck:SetSize(30, 30)
minimapCheck:SetPoint("TOPLEFT", 14, -18)

local minimapLabel = MakeText(togglePanel, 12, COLORS.text, "LEFT")
minimapLabel:SetPoint("TOPLEFT", minimapCheck, "TOPRIGHT", 8, -1)
minimapLabel:SetText("Show minimap button")

local minimapDesc = MakeText(togglePanel, 8, COLORS.muted, "LEFT")
minimapDesc:SetPoint("TOPLEFT", minimapCheck, "TOPRIGHT", 8, -22)
minimapDesc:SetPoint("RIGHT", -12, 0)
minimapDesc:SetText("Display the IRS button on the minimap.")

minimapCheck:SetScript("OnClick", function(self)
    IRS:SetSetting("showMinimapButton", self:GetChecked())
end)

local miniAutoOpenCheck = CreateFrame("CheckButton", nil, togglePanel, "UICheckButtonTemplate")
miniAutoOpenCheck:SetSize(30, 30)
miniAutoOpenCheck:SetPoint("TOPLEFT", 14, -76)

local miniAutoOpenLabel = MakeText(togglePanel, 12, COLORS.text, "LEFT")
miniAutoOpenLabel:SetPoint("TOPLEFT", miniAutoOpenCheck, "TOPRIGHT", 8, -1)
miniAutoOpenLabel:SetText("Auto-open Mini Dashboard")

local miniAutoOpenDesc = MakeText(togglePanel, 8, COLORS.muted, "LEFT")
miniAutoOpenDesc:SetPoint("TOPLEFT", miniAutoOpenCheck, "TOPRIGHT", 8, -22)
miniAutoOpenDesc:SetPoint("RIGHT", -12, 0)
miniAutoOpenDesc:SetText("Open the Mini Dashboard automatically on every character when logging in.")

miniAutoOpenCheck:SetScript("OnClick", function(self)
    IRS:SetSetting("autoOpenMiniDashboard", self:GetChecked())
end)

local microPanel = MakePanel(toggles, COLORS.panelAlt)
microPanel:SetPoint("TOPLEFT", togglePanel, "BOTTOMLEFT", 0, -12)
microPanel:SetPoint("TOPRIGHT", togglePanel, "BOTTOMRIGHT", 0, -12)
microPanel:SetHeight(170)

local microTitle = MakeText(microPanel, 13, COLORS.goldSoft, "LEFT")
microTitle:SetPoint("TOPLEFT", 12, -12)
microTitle:SetText("MICRO REPORT")

local microCheck = CreateFrame("CheckButton", nil, microPanel, "UICheckButtonTemplate")
microCheck:SetSize(30, 30)
microCheck:SetPoint("TOPLEFT", microTitle, "BOTTOMLEFT", 0, -10)
local microLabel = MakeText(microPanel, 12, COLORS.text, "LEFT")
microLabel:SetPoint("LEFT", microCheck, "RIGHT", 8, 0)
microLabel:SetText("Show Micro Report")
microCheck:SetScript("OnClick", function(self)
    IRS:SetMicroReportOption("shown", self:GetChecked())
end)

local microDesc = MakeText(microPanel, 8, COLORS.muted, "LEFT")
microDesc:SetPoint("TOPLEFT", microCheck, "BOTTOMLEFT", 0, -6)
microDesc:SetPoint("RIGHT", -12, 0)
microDesc:SetText("One small, movable gold amount. Drag to position it anywhere on screen; right-click to change its display. Earnings are account-wide net totals; session and hourly totals reset on reload.")

local microDisplay = CreateFrame("DropdownButton", nil, microPanel, "WowStyle1DropdownTemplate")
microDisplay:SetWidth(250)
microDisplay:SetPoint("TOPLEFT", microDesc, "BOTTOMLEFT", 0, -12)
microDisplay:SetupMenu(function(_, root)
    IRS:BuildMicroReportMenu(root)
end)

-- ============================================================================
-- MINI DASHBOARD SECTION
-- ============================================================================

local mini = CreateFrame("Frame", nil, body)
mini:SetAllPoints()
sections.mini = mini

local miniTitle = MakeText(mini, 16, COLORS.goldSoft, "LEFT")
miniTitle:SetPoint("TOPLEFT", 16, -14)
miniTitle:SetText("MINI DASHBOARD")

local miniDesc = MakeText(mini, 8, COLORS.muted, "LEFT")
miniDesc:SetPoint("TOPLEFT", miniTitle, "BOTTOMLEFT", 0, -6)
miniDesc:SetPoint("RIGHT", -16, 0)
miniDesc:SetText("Control the floating dashboard, its anchor, and which savings projects appear.")

local miniTogglePanel = MakePanel(mini, COLORS.panelAlt)
miniTogglePanel:SetPoint("TOPLEFT", 14, -68)
miniTogglePanel:SetPoint("TOPRIGHT", -14, -68)
miniTogglePanel:SetHeight(76)

local miniProjectsCheck = CreateFrame("CheckButton", nil, miniTogglePanel, "UICheckButtonTemplate")
miniProjectsCheck:SetSize(30, 30)
miniProjectsCheck:SetPoint("TOPLEFT", 14, -16)

local miniProjectsLabel = MakeText(miniTogglePanel, 12, COLORS.text, "LEFT")
miniProjectsLabel:SetPoint("TOPLEFT", miniProjectsCheck, "TOPRIGHT", 8, -1)
miniProjectsLabel:SetText("Show savings projects")

local miniProjectsDesc = MakeText(miniTogglePanel, 8, COLORS.muted, "LEFT")
miniProjectsDesc:SetPoint("TOPLEFT", miniProjectsCheck, "TOPRIGHT", 8, -22)
miniProjectsDesc:SetPoint("RIGHT", -12, 0)
miniProjectsDesc:SetText("When off, the Savings Projects section is completely hidden from the mini dashboard.")

miniProjectsCheck:SetScript("OnClick", function(self)
    IRS:SetSetting("showMiniProjects", self:GetChecked())
end)

local anchorPanel = MakePanel(mini, COLORS.panelAlt)
anchorPanel:SetPoint("TOPLEFT", 14, -156)
anchorPanel:SetPoint("TOPRIGHT", -14, -156)
anchorPanel:SetHeight(112)

local anchorTitle = MakeText(anchorPanel, 13, COLORS.goldSoft, "LEFT")
anchorTitle:SetPoint("TOPLEFT", 12, -11)
anchorTitle:SetText("ANCHOR CORNER")

local anchorDesc = MakeText(anchorPanel, 8, COLORS.muted, "LEFT")
anchorDesc:SetPoint("TOPLEFT", 12, -34)
anchorDesc:SetPoint("RIGHT", -12, 0)
anchorDesc:SetText("This corner stays fixed when Savings Projects expands or collapses.")

local anchorButtons = {}
local anchorChoices = {
    { key = "TOPLEFT", label = "Top Left" },
    { key = "TOPRIGHT", label = "Top Right" },
    { key = "BOTTOMLEFT", label = "Bottom Left" },
    { key = "BOTTOMRIGHT", label = "Bottom Right" },
}

for i, choice in ipairs(anchorChoices) do
    local button = CreateFrame("Button", nil, anchorPanel, "BackdropTemplate")
    IRS:StyleButtonFeedback(button)
    button:SetSize(135, 30)
    button:SetPoint("TOPLEFT", 12 + ((i - 1) * 145), -64)
    button:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })

    button.label = MakeText(button, 10, COLORS.text, "CENTER")
    button.label:SetAllPoints()
    button.label:SetText(choice.label)
    button.anchorKey = choice.key

    button:SetScript("OnClick", function(self)
        IRS:SetMiniDashboardAnchor(self.anchorKey)
    end)

    button:SetScript("OnEnter", function(self)
        if IRS:GetMiniDashboardAnchor() ~= self.anchorKey then
            IRS:SetLayoutColor(self, "SetBackdropColor", unpack(COLORS.panel))
            IRS:SetLayoutColor(self, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
        end
    end)

    button:SetScript("OnLeave", function()
        IRS:RefreshSettingsPage()
    end)

    anchorButtons[choice.key] = button
end

local statsPanel = MakePanel(mini, COLORS.panelAlt)
statsPanel:SetPoint("TOPLEFT", anchorPanel, "BOTTOMLEFT", 0, -12)
statsPanel:SetPoint("TOPRIGHT", anchorPanel, "BOTTOMRIGHT", 0, -12)
statsPanel:SetHeight(92)

local statsTitle = MakeText(statsPanel, 13, COLORS.goldSoft, "LEFT")
statsTitle:SetPoint("TOPLEFT", 12, -11)
statsTitle:SetText("STATS SHOWN")

local statsDesc = MakeText(statsPanel, 8, COLORS.muted, "LEFT")
statsDesc:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", 0, -6)
statsDesc:SetPoint("RIGHT", -12, 0)
statsDesc:SetText("Choose which net-gold rows appear at the top of the Mini Dashboard.")

local miniStatChecks = {}
local miniStatChoices = {
    { key = "character", label = "Character" },
    { key = "today", label = "Today" },
    { key = "week", label = "Week" },
    { key = "month", label = "Month" },
    { key = "total", label = "Total" },
}

for i, choice in ipairs(miniStatChoices) do
    local check = CreateFrame(
        "CheckButton",
        nil,
        statsPanel,
        "UICheckButtonTemplate"
    )

    check:SetSize(28, 28)
    check:SetPoint("BOTTOMLEFT", 12 + ((i - 1) * 115), 10)
    check.statKey = choice.key

    local label = MakeText(statsPanel, 10, COLORS.text, "LEFT")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(choice.label)

    check:SetScript("OnClick", function(self)
        IRS:SetMiniStatVisibility(
            self.statKey,
            self:GetChecked()
        )
    end)

    miniStatChecks[choice.key] = check
end

local projectsPanel = MakePanel(mini, COLORS.panelAlt)
projectsPanel:SetPoint("TOPLEFT", statsPanel, "BOTTOMLEFT", 0, -12)
projectsPanel:SetPoint("BOTTOMRIGHT", -14, 14)

local projectsTitle = MakeText(projectsPanel, 13, COLORS.goldSoft, "LEFT")
projectsTitle:SetPoint("TOPLEFT", 12, -11)
projectsTitle:SetText("PROJECTS SHOWN")

local projectsDesc = MakeText(projectsPanel, 8, COLORS.muted, "LEFT")
projectsDesc:SetPoint("TOPLEFT", 12, -34)
projectsDesc:SetPoint("RIGHT", -12, 0)
projectsDesc:SetText("Choose which savings projects are included in the mini dashboard and its Daily Gold Target.")

local projectScroll = CreateFrame("ScrollFrame", "IncomeRecordsSystemMiniProjectSettingsScroll", projectsPanel, "UIPanelScrollFrameTemplate")
projectScroll:SetPoint("TOPLEFT", 10, -66)
projectScroll:SetPoint("BOTTOMRIGHT", -28, 10)

local projectChild = CreateFrame("Frame", nil, projectScroll)
projectChild:SetSize(570, 1)
projectScroll:SetScrollChild(projectChild)

local projectEmpty = MakeText(projectChild, 10, COLORS.muted, "CENTER")
projectEmpty:SetPoint("TOPLEFT", 8, -14)
projectEmpty:SetWidth(550)
projectEmpty:SetText("No savings projects have been created yet.")

local projectRows = {}

local function EnsureProjectRow(index)
    if projectRows[index] then return projectRows[index] end

    local row = MakePanel(projectChild, COLORS.panel)
    row:SetHeight(48)
    IRS:SetLayoutColor(row, "SetBackdropBorderColor", unpack(COLORS.borderSoft))

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", 8, 0)

    row.name = MakeText(row, 11, COLORS.text, "LEFT")
    row.name:SetPoint("TOPLEFT", 45, -8)
    row.name:SetPoint("RIGHT", -12, 0)

    row.meta = MakeText(row, 8, COLORS.muted, "LEFT")
    row.meta:SetPoint("TOPLEFT", 45, -28)
    row.meta:SetPoint("RIGHT", -12, 0)

    row.check:SetScript("OnClick", function(self)
        if row.projectId ~= nil then
            IRS:SetProjectMiniVisibility(row.projectId, self:GetChecked())
        end
    end)

    projectRows[index] = row
    return row
end

-- ============================================================================
-- INTERNAL TRANSFERS SECTION
-- Implemented in its own module so matching/accounting logic stays isolated.
-- ============================================================================

if IRS.BuildInternalTransferSettingsSection then
    sections.transfers = IRS:BuildInternalTransferSettingsSection(body)
else
    local fallback = CreateFrame("Frame", nil, body)
    fallback:SetAllPoints()
    sections.transfers = fallback
end

-- ============================================================================
-- WOW TOKEN SECTION
-- Implemented in its own module to keep this Settings file manageable.
-- ============================================================================

if IRS.BuildTokenSettingsSection then
    sections.token = IRS:BuildTokenSettingsSection(body)
else
    local fallback = CreateFrame("Frame", nil, body)
    fallback:SetAllPoints()
    sections.token = fallback
end

-- ============================================================================
-- FONTS SECTION
-- ============================================================================

local fonts = CreateFrame("Frame", nil, body)
fonts:SetAllPoints()
sections.fonts = fonts

local fontsTitle = MakeText(fonts, 16, COLORS.goldSoft, "LEFT")
fontsTitle:SetPoint("TOPLEFT", 16, -14)
fontsTitle:SetText("FONTS & LAYOUT STYLE")

local fontsDesc = MakeText(fonts, 8, COLORS.muted, "LEFT")
fontsDesc:SetPoint("TOPLEFT", fontsTitle, "BOTTOMLEFT", 0, -6)
fontsDesc:SetPoint("RIGHT", -16, 0)
fontsDesc:SetText("Each option controls a purpose-based text style across the addon. Main IRS and Mini Dashboard styles are independent.")

local fontsNote = MakeText(fonts, 8, COLORS.muted, "LEFT")
fontsNote:SetPoint("TOPLEFT", 16, -56)
fontsNote:SetPoint("RIGHT", -16, 0)
fontsNote:SetText("Enter a size from 6–40, or use − / +. Reset buttons restore the IRS defaults.")

local fontFaceLabel = MakeText(fonts, "body", COLORS.text, "LEFT")
fontFaceLabel:SetText("Font for all IRS interfaces")
local fontFaceSelect = CreateFrame("Button", nil, fonts, "BackdropTemplate")
IRS:StyleButtonFeedback(fontFaceSelect)
fontFaceSelect:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
IRS:SetLayoutColor(fontFaceSelect, "SetBackdropColor", unpack(COLORS.panelAlt))
IRS:SetLayoutColor(fontFaceSelect, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
fontFaceSelect:SetWidth(280)
fontFaceSelect.label = MakeText(fontFaceSelect, "body", COLORS.text, "LEFT")
fontFaceSelect.label:SetPoint("LEFT", 10, 0)
fontFaceSelect.label:SetPoint("RIGHT", -28, 0)
local fontFaceArrow = MakeText(fontFaceSelect, "helper", COLORS.gold, "RIGHT")
fontFaceArrow:SetPoint("RIGHT", -10, 0)
fontFaceArrow:SetText("v")
local fontFaceMenu = MakePanel(UIParent, COLORS.panel)
IRS:RegisterFormattingRoot(fontFaceMenu, "main")
fontFaceMenu:SetFrameStrata("FULLSCREEN_DIALOG")
fontFaceMenu:SetClampedToScreen(true)
fontFaceMenu:SetPoint("TOPLEFT", fontFaceSelect, "BOTTOMLEFT", 0, -2)
fontFaceMenu:Hide()
local fontFaceRows = {}
for i, option in ipairs(IRS.FONT_FACE_OPTIONS) do
    local key = option.key
    local row = CreateFrame("Button", nil, fontFaceMenu)
    row.label = MakeText(row, "body", COLORS.text, "LEFT")
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetText(option.label)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    IRS:SetLayoutColor(highlight, "SetColorTexture", COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.16)
    row:SetScript("OnClick", function()
        fontFaceMenu:Hide()
        IRS:SetFontFace(key)
    end)
    fontFaceRows[i] = row
end
fontFaceSelect:SetScript("OnClick", function()
    local rowHeight = math.max(28, IRS:GetFontSize("main", "body") + 14)
    local menuWidth = fontFaceSelect:GetWidth()
    local _, _, selected = IRS:GetFontFace()
    for i, row in ipairs(fontFaceRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * rowHeight)
        row:SetHeight(rowHeight)
        SetColor(row.label, IRS.FONT_FACE_OPTIONS[i].key == selected and COLORS.gold or COLORS.text)
        menuWidth = math.max(menuWidth, row.label:GetStringWidth() + 28)
    end
    fontFaceMenu:SetSize(menuWidth, #fontFaceRows * rowHeight + 8)
    fontFaceMenu:SetShown(not fontFaceMenu:IsShown())
end)
fonts:HookScript("OnHide", function() fontFaceMenu:Hide() end)
fontFaceMenu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
fontFaceMenu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
fontFaceMenu:SetScript("OnEvent", function(self)
    for _, focus in ipairs(GetMouseFoci()) do
        while focus do
            if focus == self or focus == fontFaceSelect then return end
            if focus.IsForbidden and focus:IsForbidden() then break end
            focus = focus.GetParent and focus:GetParent() or nil
        end
    end
    self:Hide()
end)

local layoutStyleLabel = MakeText(fonts, "body", COLORS.text, "LEFT")
layoutStyleLabel:SetText("Layout style")
local layoutStyleSelect = CreateFrame("Button", nil, fonts, "BackdropTemplate")
IRS:StyleButtonFeedback(layoutStyleSelect)
layoutStyleSelect:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
IRS:SetLayoutColor(layoutStyleSelect, "SetBackdropColor", unpack(COLORS.panelAlt))
IRS:SetLayoutColor(layoutStyleSelect, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
layoutStyleSelect:SetWidth(260)
layoutStyleSelect.label = MakeText(layoutStyleSelect, "body", COLORS.text, "LEFT")
layoutStyleSelect.label:SetPoint("LEFT", 10, 0)
layoutStyleSelect.label:SetPoint("RIGHT", -28, 0)
local layoutStyleArrow = MakeText(layoutStyleSelect, "helper", COLORS.gold, "RIGHT")
layoutStyleArrow:SetPoint("RIGHT", -10, 0)
layoutStyleArrow:SetText("v")
local layoutStyleMenu = MakePanel(UIParent, COLORS.panel)
IRS:RegisterFormattingRoot(layoutStyleMenu, "main")
layoutStyleMenu:SetFrameStrata("FULLSCREEN_DIALOG")
layoutStyleMenu:SetClampedToScreen(true)
layoutStyleMenu:SetPoint("TOPLEFT", layoutStyleSelect, "BOTTOMLEFT", 0, -2)
layoutStyleMenu:Hide()
local layoutStyleRows = {}
for i, option in ipairs(IRS.LAYOUT_STYLE_OPTIONS) do
    local key = option.key
    local row = CreateFrame("Button", nil, layoutStyleMenu)
    row.label = MakeText(row, "body", COLORS.text, "LEFT")
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetText(option.label)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    IRS:SetLayoutColor(highlight, "SetColorTexture", COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.16)
    row:SetScript("OnClick", function()
        layoutStyleMenu:Hide()
        IRS:SetLayoutStyle(key)
    end)
    layoutStyleRows[i] = row
end
layoutStyleSelect:SetScript("OnClick", function()
    local rowHeight = math.max(28, IRS:GetFontSize("main", "body") + 14)
    local menuWidth = layoutStyleSelect:GetWidth()
    local selected = IRS:GetLayoutStyle()
    for i, row in ipairs(layoutStyleRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * rowHeight)
        row:SetHeight(rowHeight)
        SetColor(row.label, IRS.LAYOUT_STYLE_OPTIONS[i].key == selected and COLORS.gold or COLORS.text)
        menuWidth = math.max(menuWidth, row.label:GetStringWidth() + 28)
    end
    layoutStyleMenu:SetSize(menuWidth, #layoutStyleRows * rowHeight + 8)
    layoutStyleMenu:SetShown(not layoutStyleMenu:IsShown())
end)
fonts:HookScript("OnHide", function() layoutStyleMenu:Hide() end)
layoutStyleMenu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
layoutStyleMenu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
layoutStyleMenu:SetScript("OnEvent", function(self)
    for _, focus in ipairs(GetMouseFoci()) do
        while focus do
            if focus == self or focus == layoutStyleSelect then return end
            if focus.IsForbidden and focus:IsForbidden() then break end
            focus = focus.GetParent and focus:GetParent() or nil
        end
    end
    self:Hide()
end)

local fontControls = {
    main = {},
    mini = {},
}

local function CommitFontField(field)
    local value = tonumber(field:GetText())
    if value then
        IRS:SetFontSize(field.scope, field.styleKey, value)
    end
    field:ClearFocus()
end

local function MakeFontControl(parent, scope, styleKey, x, y, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 30)
    row:SetPoint("TOPLEFT", x, y)

    row.label = MakeText(row, 10, COLORS.text, "LEFT")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(150)
    row.label:SetText(
        IRS.FONT_STYLE_LABELS[scope]
        and IRS.FONT_STYLE_LABELS[scope][tostring(styleKey)]
        or tostring(styleKey)
    )

    row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    IRS:StyleButtonFeedback(row.minus)
    row.minus:SetSize(28, 24)
    row.minus:SetPoint("LEFT", 158, 0)
    row.minus:SetText("−")

    row.field = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.field:SetSize(46, 24)
    row.field:SetPoint("LEFT", row.minus, "RIGHT", 5, 0)
    row.field:SetAutoFocus(false)
    row.field:SetNumeric(true)
    row.field:SetMaxLetters(2)
    row.field:SetJustifyH("CENTER")
    IRS:RegisterFontString("main", "body", row.field, STANDARD_TEXT_FONT, "")
    row.field.scope = scope
    row.field.styleKey = styleKey

    row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    IRS:StyleButtonFeedback(row.plus)
    row.plus:SetSize(28, 24)
    row.plus:SetPoint("LEFT", row.field, "RIGHT", 5, 0)
    row.plus:SetText("+")

    row.minus:SetScript("OnClick", function()
        IRS:SetFontSize(scope, styleKey, IRS:GetFontSize(scope, styleKey) - 1)
    end)

    row.plus:SetScript("OnClick", function()
        IRS:SetFontSize(scope, styleKey, IRS:GetFontSize(scope, styleKey) + 1)
    end)

    row.field:SetScript("OnEnterPressed", CommitFontField)
    row.field:SetScript("OnEditFocusLost", function(self)
        if tonumber(self:GetText()) then
            IRS:SetFontSize(self.scope, self.styleKey, tonumber(self:GetText()))
        else
            self:SetText(tostring(IRS:GetFontSize(self.scope, self.styleKey)))
        end
    end)
    row.field:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(IRS:GetFontSize(self.scope, self.styleKey)))
        self:ClearFocus()
    end)

    fontControls[scope][tostring(styleKey)] = row
    return row
end

local mainFontPanel = MakePanel(fonts, COLORS.panelAlt)
mainFontPanel:SetPoint("TOPLEFT", 14, -88)
mainFontPanel:SetPoint("TOPRIGHT", -14, -88)
mainFontPanel:SetHeight(210)

local mainFontTitle = MakeText(mainFontPanel, 13, COLORS.goldSoft, "LEFT")
mainFontTitle:SetPoint("TOPLEFT", 12, -10)
mainFontTitle:SetText("MAIN IRS INTERFACE")

local mainFontDesc = MakeText(mainFontPanel, 8, COLORS.muted, "LEFT")
mainFontDesc:SetPoint("TOPLEFT", 12, -32)
mainFontDesc:SetPoint("RIGHT", -140, 0)
mainFontDesc:SetText("Seven shared styles cover Dashboard, Projects, Characters, Reports, Settings, and Help.")

local resetMain = CreateFrame("Button", nil, mainFontPanel, "UIPanelButtonTemplate")
IRS:StyleButtonFeedback(resetMain)
resetMain:SetSize(118, 24)
resetMain:SetPoint("TOPRIGHT", -12, -4)
resetMain:SetText("Reset Main")
resetMain:SetScript("OnClick", function()
    IRS:ResetFontSizes("main")
end)

local mainKeys = IRS.FONT_STYLE_ORDER.main
local mainRowsPerColumn = 4

for i, styleKey in ipairs(mainKeys) do
    local column = i > mainRowsPerColumn and 2 or 1
    local rowIndex = column == 1 and i or (i - mainRowsPerColumn)
    local x = column == 1 and 14 or 315
    local y = -62 - ((rowIndex - 1) * 30)
    MakeFontControl(mainFontPanel, "main", styleKey, x, y, 280)
end

local miniFontPanel = MakePanel(fonts, COLORS.panelAlt)
miniFontPanel:SetPoint("TOPLEFT", 14, -310)
miniFontPanel:SetPoint("BOTTOMRIGHT", -14, 14)

local miniFontTitle = MakeText(miniFontPanel, 13, COLORS.goldSoft, "LEFT")
miniFontTitle:SetPoint("TOPLEFT", 12, -10)
miniFontTitle:SetText("MINI DASHBOARD")

local miniFontDesc = MakeText(miniFontPanel, 8, COLORS.muted, "LEFT")
miniFontDesc:SetPoint("TOPLEFT", 12, -32)
miniFontDesc:SetPoint("RIGHT", -140, 0)
miniFontDesc:SetText("Five independent styles control the floating mini dashboard only.")

local resetMini = CreateFrame("Button", nil, miniFontPanel, "UIPanelButtonTemplate")
IRS:StyleButtonFeedback(resetMini)
resetMini:SetSize(118, 24)
resetMini:SetPoint("TOPRIGHT", -12, -4)
resetMini:SetText("Reset Mini")
resetMini:SetScript("OnClick", function()
    IRS:ResetFontSizes("mini")
end)

local miniKeys = IRS.FONT_STYLE_ORDER.mini
local miniRowsPerColumn = 3
for i, styleKey in ipairs(miniKeys) do
    local column = i > miniRowsPerColumn and 2 or 1
    local rowIndex = column == 1 and i or (i - miniRowsPerColumn)
    local x = column == 1 and 14 or 315
    local y = -62 - ((rowIndex - 1) * 32)
    MakeFontControl(miniFontPanel, "mini", styleKey, x, y, 280)
end

-- ============================================================================
-- REFRESH
-- ============================================================================

-- Reflows Settings when editable font styles grow or shrink. This keeps the
-- sidebar, toggle descriptions, project rows, and font controls from colliding.
local function LayoutSettingsForFonts()
    local helper = IRS:GetFontSize("main", "helper")
    local bodySize = IRS:GetFontSize("main", "body")
    local labelSize = IRS:GetFontSize("main", "label")
    local sectionSize = IRS:GetFontSize("main", "section")

    -- Main Settings header and internal category rail.
    rail:ClearAllPoints()
    rail:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    rail:SetPoint("BOTTOMLEFT", 4, 4)

    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, 0)
    body:SetPoint("BOTTOMRIGHT", -4, 4)

    local sidebarButtonHeight = math.max(42, bodySize + 22)
    for i, info in ipairs(SECTION_INFO) do
        local button = sectionButtons[info.key]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 7, -8 - ((i - 1) * (sidebarButtonHeight + 8)))
        button:SetSize(140, sidebarButtonHeight)
    end

    -- General toggle panel.
    local toggleRowHeight = math.max(58, labelSize + helper + 38)

    togglePanel:ClearAllPoints()
    togglePanel:SetPoint("TOPLEFT", togglesDesc, "BOTTOMLEFT", -2, -16)
    togglePanel:SetPoint("TOPRIGHT", toggles, "TOPRIGHT", -14, 0)
    togglePanel:SetHeight(math.max(144, (toggleRowHeight * 2) + 28))

    minimapLabel:ClearAllPoints()
    minimapLabel:SetPoint("TOPLEFT", minimapCheck, "TOPRIGHT", 8, -1)
    minimapDesc:ClearAllPoints()
    minimapDesc:SetPoint("TOPLEFT", minimapLabel, "BOTTOMLEFT", 0, -6)
    minimapDesc:SetPoint("RIGHT", -12, 0)

    miniAutoOpenCheck:ClearAllPoints()
    miniAutoOpenCheck:SetPoint("TOPLEFT", 14, -(18 + toggleRowHeight))

    miniAutoOpenLabel:ClearAllPoints()
    miniAutoOpenLabel:SetPoint("TOPLEFT", miniAutoOpenCheck, "TOPRIGHT", 8, -1)

    miniAutoOpenDesc:ClearAllPoints()
    miniAutoOpenDesc:SetPoint("TOPLEFT", miniAutoOpenLabel, "BOTTOMLEFT", 0, -6)
    miniAutoOpenDesc:SetPoint("RIGHT", -12, 0)

    microPanel:SetHeight(
        microTitle:GetStringHeight() + 10 + 30 + 6
        + microDesc:GetStringHeight() + 12 + microDisplay:GetHeight() + 26
    )

    -- Mini Dashboard section.
    miniTogglePanel:ClearAllPoints()
    miniTogglePanel:SetPoint("TOPLEFT", miniDesc, "BOTTOMLEFT", -2, -14)
    miniTogglePanel:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -14, 0)
    miniTogglePanel:SetHeight(math.max(76, labelSize + helper + 38))

    miniProjectsLabel:ClearAllPoints()
    miniProjectsLabel:SetPoint("TOPLEFT", miniProjectsCheck, "TOPRIGHT", 8, -1)
    miniProjectsDesc:ClearAllPoints()
    miniProjectsDesc:SetPoint("TOPLEFT", miniProjectsLabel, "BOTTOMLEFT", 0, -6)
    miniProjectsDesc:SetPoint("RIGHT", -12, 0)

    anchorPanel:ClearAllPoints()
    anchorPanel:SetPoint("TOPLEFT", miniTogglePanel, "BOTTOMLEFT", 0, -12)
    anchorPanel:SetPoint("TOPRIGHT", miniTogglePanel, "BOTTOMRIGHT", 0, -12)
    anchorPanel:SetHeight(math.max(112, sectionSize + helper + bodySize + 48))

    anchorDesc:ClearAllPoints()
    anchorDesc:SetPoint("TOPLEFT", anchorTitle, "BOTTOMLEFT", 0, -6)
    anchorDesc:SetPoint("RIGHT", -12, 0)

    local anchorButtonHeight = math.max(30, bodySize + 12)
    for i, choice in ipairs(anchorChoices) do
        local button = anchorButtons[choice.key]
        button:SetHeight(anchorButtonHeight)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", 12 + ((i - 1) * 145), 12)
    end

    statsPanel:ClearAllPoints()
    statsPanel:SetPoint("TOPLEFT", anchorPanel, "BOTTOMLEFT", 0, -12)
    statsPanel:SetPoint("TOPRIGHT", anchorPanel, "BOTTOMRIGHT", 0, -12)
    statsPanel:SetHeight(
        math.max(92, sectionSize + helper + bodySize + 46)
    )

    statsDesc:ClearAllPoints()
    statsDesc:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", 0, -6)
    statsDesc:SetPoint("RIGHT", -12, 0)

    for i, choice in ipairs(miniStatChoices) do
        local check = miniStatChecks[choice.key]
        check:ClearAllPoints()
        check:SetPoint("BOTTOMLEFT", 12 + ((i - 1) * 115), 10)
    end

    projectsPanel:ClearAllPoints()
    projectsPanel:SetPoint("TOPLEFT", statsPanel, "BOTTOMLEFT", 0, -12)
    projectsPanel:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -14, 14)

    projectsDesc:ClearAllPoints()
    projectsDesc:SetPoint("TOPLEFT", projectsTitle, "BOTTOMLEFT", 0, -6)
    projectsDesc:SetPoint("RIGHT", -12, 0)

    projectScroll:ClearAllPoints()
    projectScroll:SetPoint("TOPLEFT", projectsDesc, "BOTTOMLEFT", -2, -10)
    projectScroll:SetPoint("BOTTOMRIGHT", -28, 10)

    -- Font editor itself.
    fontsNote:ClearAllPoints()
    fontsNote:SetPoint("TOPLEFT", fontsDesc, "BOTTOMLEFT", 0, -8)
    fontsNote:SetPoint("RIGHT", -16, 0)
    fontFaceLabel:ClearAllPoints()
    fontFaceLabel:SetPoint("TOPLEFT", fontsNote, "BOTTOMLEFT", 0, -12)
    fontFaceSelect:ClearAllPoints()
    fontFaceSelect:SetPoint("TOPLEFT", fontFaceLabel, "BOTTOMLEFT", 0, -8)
    fontFaceSelect:SetHeight(math.max(28, bodySize + 14))
    local selectorWidth = math.max(180, ((body:GetWidth() or 620) - 48) / 2)
    fontFaceLabel:SetWidth(selectorWidth)
    fontFaceSelect:SetWidth(selectorWidth)
    layoutStyleLabel:ClearAllPoints()
    layoutStyleLabel:SetPoint("TOPLEFT", fontFaceLabel, "TOPLEFT", selectorWidth + 16, 0)
    layoutStyleLabel:SetWidth(selectorWidth)
    layoutStyleSelect:ClearAllPoints()
    layoutStyleSelect:SetPoint("TOPLEFT", layoutStyleLabel, "BOTTOMLEFT", 0, -8)
    layoutStyleSelect:SetSize(selectorWidth, math.max(28, bodySize + 14))

    for _, info in ipairs({
        {mainFontTitle, mainFontDesc, resetMain},
        {miniFontTitle, miniFontDesc, resetMini},
    }) do
        local title, description, reset = unpack(info)
        reset:SetHeight(math.max(24, labelSize + 12))
        reset:ClearAllPoints()
        reset:SetPoint("TOPRIGHT", -12, -4)
        title:SetWidth(math.max(1, (body:GetWidth() or 620) - math.max(170, reset:GetWidth() + 36)))
        description:ClearAllPoints()
        local headerBottom = math.max(10 + title:GetStringHeight(), 4 + reset:GetHeight())
        description:SetPoint("TOPLEFT", title:GetParent(), "TOPLEFT", 12, -(headerBottom + 6))
        description:SetPoint("RIGHT", -12, 0)
    end
    mainFontPanel:ClearAllPoints()
    mainFontPanel:SetPoint("TOPLEFT", fontFaceSelect, "BOTTOMLEFT", -2, -16)
    mainFontPanel:SetPoint("TOPRIGHT", fonts, "TOPRIGHT", -14, 0)

    local fontControlRowHeight = math.max(30, math.max(bodySize, labelSize) + 14)
    for _, controls in pairs(fontControls) do
        for _, control in pairs(controls) do
            fontControlRowHeight = math.max(fontControlRowHeight, control.label:GetStringHeight() + 12)
            control.minus:SetHeight(math.max(24, labelSize + 12))
            control.plus:SetHeight(math.max(24, labelSize + 12))
            control.field:SetHeight(math.max(24, bodySize + 12))
        end
    end
    local mainRowsPerColumn = 4
    local mainControlsTop = math.max(10 + mainFontTitle:GetStringHeight(), 4 + resetMain:GetHeight()) + 6 + mainFontDesc:GetStringHeight() + 12
    local miniControlsTop = math.max(10 + miniFontTitle:GetStringHeight(), 4 + resetMini:GetHeight()) + 6 + miniFontDesc:GetStringHeight() + 12
    local mainPanelHeight = mainControlsTop + (mainRowsPerColumn * fontControlRowHeight) + 14
    mainFontPanel:SetHeight(mainPanelHeight)

    for i, styleKey in ipairs(mainKeys) do
        local control = fontControls.main[tostring(styleKey)]
        local column = i > mainRowsPerColumn and 2 or 1
        local rowIndex = column == 1 and i or (i - mainRowsPerColumn)

        control:SetHeight(fontControlRowHeight)
        control:ClearAllPoints()
        control:SetPoint(
            "TOPLEFT",
            column == 1 and 14 or 315,
            -mainControlsTop - ((rowIndex - 1) * fontControlRowHeight)
        )
    end

    miniFontPanel:ClearAllPoints()
    miniFontPanel:SetPoint("TOPLEFT", mainFontPanel, "BOTTOMLEFT", 0, -12)
    miniFontPanel:SetPoint("RIGHT", fonts, "RIGHT", -14, 0)
    miniFontPanel:SetHeight(miniControlsTop + (3 * fontControlRowHeight) + 14)

    local miniRowsPerColumn = 3
    for i, styleKey in ipairs(miniKeys) do
        local control = fontControls.mini[tostring(styleKey)]
        local column = i > miniRowsPerColumn and 2 or 1
        local rowIndex = column == 1 and i or (i - miniRowsPerColumn)

        control:SetHeight(fontControlRowHeight)
        control:ClearAllPoints()
        control:SetPoint(
            "TOPLEFT",
            column == 1 and 14 or 315,
            -miniControlsTop - ((rowIndex - 1) * fontControlRowHeight)
        )
    end
end

function IRS:RefreshSettingsPage()
    if not IRS.db then return end

    LayoutSettingsForFonts()
    local _, fontFaceName = IRS:GetFontFace()
    fontFaceSelect.label:SetText(fontFaceName)
    layoutStyleSelect.label:SetText(IRS:GetLayoutStyleLabel())

    minimapCheck:SetChecked(IRS.db.settings.showMinimapButton ~= false)
    miniAutoOpenCheck:SetChecked(IRS.db.settings.autoOpenMiniDashboard == true)
    microCheck:SetChecked(IRS:GetMicroReportSettings().shown == true)
    microDisplay:GenerateMenu()
    miniProjectsCheck:SetChecked(IRS.db.settings.showMiniProjects ~= false)
    for _, choice in ipairs(miniStatChoices) do
        miniStatChecks[choice.key]:SetChecked(
            IRS:IsMiniStatShown(choice.key)
        )
    end

    if IRS.RefreshInternalTransferSettingsSection then
        IRS:RefreshInternalTransferSettingsSection()
    end

    if IRS.RefreshTokenSettingsSection then
        IRS:RefreshTokenSettingsSection()
    end

    local selectedAnchor = IRS:GetMiniDashboardAnchor()
    for anchorKey, button in pairs(anchorButtons) do
        if anchorKey == selectedAnchor then
            IRS:SetLayoutColor(button, "SetBackdropColor", unpack(COLORS.panel))
            IRS:SetLayoutColor(button, "SetBackdropBorderColor", unpack(COLORS.gold))
            SetColor(button.label, COLORS.gold)
        else
            IRS:SetLayoutColor(button, "SetBackdropColor", unpack(COLORS.panelAlt))
            IRS:SetLayoutColor(button, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
            SetColor(button.label, COLORS.text)
        end
    end

    local entries = IRS:GetSortedProjects()
    projectEmpty:SetShown(#entries == 0)

    local rowWidth = math.max(520, (projectScroll:GetWidth() or 560) - 5)
    local projectRowHeight = math.max(
        48,
        IRS:GetFontSize("main","body") + IRS:GetFontSize("main","helper") + 21
    )

    for i, entry in ipairs(entries) do
        local row = EnsureProjectRow(i)
        local project = entry.project
        local _, _, sourceLabel = IRS:GetProjectAllocatedBalance(project)

        row.projectId = entry.id
        row:SetHeight(projectRowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * (projectRowHeight + 4)))
        row:SetWidth(rowWidth)

        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", 45, -7)
        row.name:SetPoint("RIGHT", -12, 0)

        row.meta:ClearAllPoints()
        row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
        row.meta:SetPoint("RIGHT", -12, 0)

        row.check:SetChecked(IRS:IsProjectShownInMini(entry.id))
        row.name:SetText(project.name or "Savings Project")
        row.meta:SetText(string.format(
            "%d%% of %s",
            math.floor(tonumber(project.allocationPercent) or 100),
            sourceLabel or "Unknown source"
        ))
        row:Show()
    end

    for i = #entries + 1, #projectRows do
        projectRows[i]:Hide()
    end

    projectChild:SetHeight(math.max(1, #entries * (projectRowHeight + 4)))

    for scope, controls in pairs(fontControls) do
        for styleKey, row in pairs(controls) do
            if not row.field:HasFocus() then
                row.field:SetText(tostring(IRS:GetFontSize(scope, styleKey)))
            end
        end
    end

    activeSection = IRS.db.ui and IRS.db.ui.settingsSection or activeSection
    if not sections[activeSection] then activeSection = "toggles" end
    ApplySectionVisuals()
end

-- Restore the last Settings subject instead of forcing the sidebar back to
-- Toggles every time the addon loads.
IRS:SelectSettingsSection(
    IRS.db
    and IRS.db.ui
    and IRS.db.ui.settingsSection
    or "toggles"
)

IRS:EndStartupTiming(_irsStartupModuleTiming)
