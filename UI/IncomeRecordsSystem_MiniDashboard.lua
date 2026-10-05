--[[
IRS — Floating Mini Dashboard
Creates and refreshes the movable summary panel for earnings, Projects, and Reserves.
]]

local IRS = IRS

-- Mini-dashboard-only visual palette.
local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.86},
    border = {0.36, 0.28, 0.18, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {110 / 255, 153 / 255, 92 / 255, 1},
    red = {0.63, 0.29, 0.25, 1},
    mutedRed = {0.63, 0.29, 0.25, 1},
    softFill = {0.190, 0.145, 0.098, 0.14},
}

local MINI_MAX_PROJECTS = 5

local function SetColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function MakeText(parent, size, color, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local renderedSize = IRS.GetFontSize and IRS:GetFontSize("mini", size) or size
    local fontFlags = flags or ""

    fs:SetFont(STANDARD_TEXT_FONT, renderedSize, fontFlags)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then SetColor(fs, color) end

    if size and size ~= 1 and IRS.RegisterFontString then
        IRS:RegisterFontString("mini", size, fs, STANDARD_TEXT_FONT, fontFlags)
    end

    return fs
end

local function MakePanel(parent, bgColor)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    local c = bgColor or COLORS.panel
    panel:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    panel:SetBackdropBorderColor(unpack(COLORS.border))
    return panel
end

local function AddDivider(parent, anchorPoint, relPoint, x, y, alpha)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetTexture("Interface/Buttons/WHITE8X8")
    line:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], alpha or 0.85)
    line:SetHeight(1)
    line:SetPoint(anchorPoint, parent, relPoint, x or 0, y or 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -(x or 0), y or 0)
    return line
end

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

local function SetNetColor(fontString, amount, zeroColor)
    amount = tonumber(amount) or 0
    if amount < 0 then
        SetColor(fontString, COLORS.red)
    elseif amount > 0 then
        SetColor(fontString, COLORS.gold)
    else
        SetColor(fontString, zeroColor or COLORS.gold)
    end
end


-- Individual project rows use separate FontStrings so "Daily Needed:" can be
-- visually bold while the amount remains normal default-colored text.
local function GetProjectDailyParts(daily, available)
    if not available then
        return "Source unavailable", "", COLORS.muted
    end

    if daily.achieved then
        return "0g", "(Complete)", COLORS.green
    end

    local goal = FormatGold(daily.dailyGoal or 0, true)

    if daily.met then
        local over = math.max(
            0,
            (tonumber(daily.todayChange) or 0) - (tonumber(daily.dailyGoal) or 0)
        )

        if over > 0 then
            return goal, "(Over +" .. FormatGold(over) .. ")", COLORS.green
        end

        return goal, "(Met)", COLORS.green
    end

    return goal, "(Short " .. FormatGold(daily.shortfall or 0) .. ")", COLORS.red
end

-- Inline color markup is still convenient for the single centered aggregate
-- target line at the bottom.
local INLINE_GREEN = "|cff6e995c"
local INLINE_RED = "|cffa14a40"
local INLINE_MUTED = "|cff9e968a"
local INLINE_GOLD = "|cffdfd6bf"
local INLINE_RESET = "|r"

local function FormatAggregateTargetLine(summary)
    if not summary or (summary.availableCount or 0) <= 0 then
        return INLINE_MUTED .. "Unavailable" .. INLINE_RESET
    end

    local target = FormatGold(summary.dailyNeeded or 0, true)
    local difference = tonumber(summary.difference) or 0

    if difference > 0 then
        return INLINE_GOLD .. target .. INLINE_RESET
            .. "  " .. INLINE_GREEN .. "(Over +" .. FormatGold(difference) .. ")" .. INLINE_RESET
    elseif difference < 0 then
        return INLINE_GOLD .. target .. INLINE_RESET
            .. "  " .. INLINE_RED .. "(Short " .. FormatGold(math.abs(difference)) .. ")" .. INLINE_RESET
    end

    return INLINE_GOLD .. target .. INLINE_RESET
        .. "  " .. INLINE_GREEN .. "(On Target)" .. INLINE_RESET
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local miniDashboard = CreateFrame("Frame", "IncomeRecordsSystemMiniDashboard", UIParent, "BackdropTemplate")
miniDashboard:SetSize(350, 260)
miniDashboard:SetFrameStrata("HIGH")
miniDashboard:SetClampedToScreen(true)
miniDashboard:EnableMouse(true)
miniDashboard:SetMovable(true)
miniDashboard:RegisterForDrag("LeftButton")
miniDashboard:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
miniDashboard:SetBackdropColor(0.165, 0.125, 0.085, 0.90)
miniDashboard:SetBackdropBorderColor(0.52, 0.39, 0.22, 1)
miniDashboard:Hide()
IRS.miniDashboardFrame = miniDashboard

-- Converts the panel to the player's selected corner anchor while preserving
-- its exact current on-screen position.
--
-- This is what makes resizing predictable:
--   TOPLEFT     -> top + left edges stay fixed
--   TOPRIGHT    -> top + right edges stay fixed
--   BOTTOMLEFT  -> bottom + left edges stay fixed
--   BOTTOMRIGHT -> bottom + right edges stay fixed
local function NormalizeMiniDashboardAnchor(anchor)
    anchor = anchor or IRS:GetMiniDashboardAnchor()

    local left = miniDashboard:GetLeft()
    local right = miniDashboard:GetRight()
    local top = miniDashboard:GetTop()
    local bottom = miniDashboard:GetBottom()

    local parentLeft = UIParent:GetLeft() or 0
    local parentRight = UIParent:GetRight() or UIParent:GetWidth()
    local parentTop = UIParent:GetTop() or UIParent:GetHeight()
    local parentBottom = UIParent:GetBottom() or 0

    if not left or not right or not top or not bottom then return false end

    local x, y

    if anchor == "TOPRIGHT" then
        x = right - parentRight
        y = top - parentTop

    elseif anchor == "BOTTOMLEFT" then
        x = left - parentLeft
        y = bottom - parentBottom

    elseif anchor == "BOTTOMRIGHT" then
        x = right - parentRight
        y = bottom - parentBottom

    else
        anchor = "TOPLEFT"
        x = left - parentLeft
        y = top - parentTop
    end

    miniDashboard:ClearAllPoints()
    miniDashboard:SetPoint(anchor, UIParent, anchor, x, y)
    return true
end

-- Saves the panel in the same corner-based coordinate system selected in
-- Settings. This lets dragging and resize anchoring use one consistent model.
local function SaveMiniDashboardAnchor()
    if not IRS.db then return end

    IRS.db.ui = IRS.db.ui or {}
    IRS.db.ui.miniDashboard = IRS.db.ui.miniDashboard or {}

    local anchor = IRS:GetMiniDashboardAnchor()
    NormalizeMiniDashboardAnchor(anchor)

    local _, _, _, x, y = miniDashboard:GetPoint(1)
    local saved = IRS.db.ui.miniDashboard

    saved.point = anchor
    saved.relativePoint = anchor
    saved.x = math.floor((x or 0) + 0.5)
    saved.y = math.floor((y or 0) + 0.5)
end

IRS.SaveMiniDashboardAnchor = SaveMiniDashboardAnchor

-- Public hook used by the Settings page when the player chooses a different
-- corner. It preserves the panel's visible position and simply changes which
-- corner controls future resizing.
function IRS:ApplyMiniDashboardAnchor(anchor)
    if not IRS.db then return end

    anchor = anchor or IRS:GetMiniDashboardAnchor()

    if NormalizeMiniDashboardAnchor(anchor) then
        SaveMiniDashboardAnchor()
    end
end

local function RestoreMiniDashboardPosition()
    if not IRS.db then return end

    local saved = IRS.db.ui and IRS.db.ui.miniDashboard
    local anchor = IRS:GetMiniDashboardAnchor()

    miniDashboard:ClearAllPoints()

    -- Restore a saved position, then normalize it to the selected anchor.
    if saved and saved.point then
        miniDashboard:SetPoint(
            saved.point,
            UIParent,
            saved.relativePoint or saved.point,
            saved.x or 0,
            saved.y or 0
        )
    else
        -- Default location follows the selected corner.
        if anchor == "TOPRIGHT" then
            miniDashboard:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -55, -180)
        elseif anchor == "BOTTOMLEFT" then
            miniDashboard:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 55, 180)
        elseif anchor == "BOTTOMRIGHT" then
            miniDashboard:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -55, 180)
        else
            miniDashboard:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 55, -180)
        end
    end

    SaveMiniDashboardAnchor()
end

miniDashboard:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

miniDashboard:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveMiniDashboardAnchor()
end)

-- ============================================================================
-- HEADER
-- ============================================================================

local miniHeader = CreateFrame("Frame", nil, miniDashboard, "BackdropTemplate")
miniHeader:SetPoint("TOPLEFT", 7, -7)
miniHeader:SetPoint("TOPRIGHT", -7, -7)
miniHeader:SetHeight(34)
miniHeader:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
miniHeader:SetBackdropColor(0.190, 0.145, 0.098, 0.86)

local miniHeaderTitle = MakeText(miniHeader, 13, COLORS.gold, "LEFT")
miniHeaderTitle:SetPoint("LEFT", 8, 2)
miniHeaderTitle:SetText("IRS MINI DASHBOARD")

local miniHeaderSub = MakeText(miniHeader, 8, COLORS.muted, "LEFT")
miniHeaderSub:SetPoint("TOPLEFT", miniHeaderTitle, "BOTTOMLEFT", 0, -1)
miniHeaderSub:SetText("ACCOUNT NET")

local miniClose = CreateFrame("Button", nil, miniDashboard, "UIPanelCloseButton")
miniClose:SetPoint("TOPRIGHT", -3, -3)

-- ============================================================================
-- ACCOUNT NET PERIODS
-- ============================================================================

local miniPeriods = MakePanel(miniDashboard, COLORS.softFill)
miniPeriods:SetPoint("TOPLEFT", 9, -47)
miniPeriods:SetPoint("TOPRIGHT", -9, -47)
miniPeriods:SetHeight(104)
miniPeriods:SetBackdropBorderColor(0, 0, 0, 0)
miniPeriods.topLine = AddDivider(miniPeriods, "TOPLEFT", "TOPLEFT", 0, 0, 0.9)
miniPeriods.bottomLine = AddDivider(miniPeriods, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, 0.9)

local miniPeriodRows = {}
local miniPeriodLabels = {
    {"Today", "today"},
    {"This Week", "week"},
    {"This Month", "month"},
    {"Total Recorded", "total"},
}

for i, info in ipairs(miniPeriodLabels) do
    local row = CreateFrame("Frame", nil, miniPeriods)
    row:SetPoint("TOPLEFT", 8, -5 - ((i - 1) * 23))
    row:SetPoint("TOPRIGHT", -8, -5 - ((i - 1) * 23))
    row:SetHeight(21)

    row.label = MakeText(row, 10, COLORS.text, "LEFT")
    row.label:SetPoint("LEFT", 2, 0)
    row.label:SetText(info[1])

    row.value = MakeText(row, 11, COLORS.gold, "RIGHT")
    row.value:SetPoint("RIGHT", -2, 0)
    row.value:SetWidth(180)
    row.value:SetText("0g")

    row.key = info[2]
    if i < #miniPeriodLabels then
        row.divider = row:CreateTexture(nil, "BORDER")
        row.divider:SetTexture("Interface/Buttons/WHITE8X8")
        row.divider:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.45)
        row.divider:SetHeight(1)
        row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -2)
        row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
    end
    miniPeriodRows[i] = row
end

-- ============================================================================
-- PROJECTS
-- ============================================================================

local miniProjectsHeader = CreateFrame("Frame", nil, miniDashboard)
miniProjectsHeader:SetPoint("TOPLEFT", 12, -158)
miniProjectsHeader:SetPoint("TOPRIGHT", -12, -158)
miniProjectsHeader:SetHeight(24)

local miniProjectsTitle = MakeText(miniProjectsHeader, "heading2", COLORS.goldSoft, "LEFT")
miniProjectsTitle:SetPoint("LEFT", 0, 0)
miniProjectsTitle:SetText("SAVINGS PROJECTS")
miniProjectsHeader.topLine = AddDivider(miniProjectsHeader, "TOPLEFT", "TOPLEFT", 0, 0, 0.9)

-- The Settings page decides whether the Savings Projects section exists at all.
-- This arrow ONLY expands/collapses the visible section; it never changes the
-- Settings checkbox.
local miniProjectsCollapse = CreateFrame("Button", nil, miniProjectsHeader)
miniProjectsCollapse:SetSize(22, 22)
miniProjectsCollapse:SetPoint("RIGHT", -2, 0)

miniProjectsCollapse.icon = miniProjectsCollapse:CreateTexture(nil, "ARTWORK")
miniProjectsCollapse.icon:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
miniProjectsCollapse.icon:SetSize(22, 22)
miniProjectsCollapse.icon:SetPoint("CENTER", 0, 0)

miniProjectsCollapse:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")

local function UpdateProjectCollapseArrow(collapsed)
    -- Down arrow = expanded. Rotated sideways = collapsed.
    miniProjectsCollapse.icon:SetRotation(collapsed and (-math.pi / 2) or 0)
end

miniProjectsCollapse:SetScript("OnClick", function()
    if not IRS.db then return end

    IRS.db.ui = IRS.db.ui or {}
    IRS.db.ui.miniDashboard = IRS.db.ui.miniDashboard or {}

    local saved = IRS.db.ui.miniDashboard
    saved.projectsCollapsed = not (saved.projectsCollapsed == true)

    IRS:RefreshMiniDashboard()
end)

miniProjectsCollapse:SetScript("OnEnter", function(self)
    if not IRS.db then return end
    local collapsed = IRS.db.ui
        and IRS.db.ui.miniDashboard
        and IRS.db.ui.miniDashboard.projectsCollapsed == true

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(collapsed and "Expand Savings Projects" or "Collapse Savings Projects")
    GameTooltip:Show()
end)

miniProjectsCollapse:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local miniProjectsBody = CreateFrame("Frame", nil, miniDashboard)
miniProjectsBody:SetPoint("TOPLEFT", 9, -184)
miniProjectsBody:SetPoint("TOPRIGHT", -9, -184)
miniProjectsBody:SetHeight(1)
miniProjectsBody.rows = {}

local function EnsureMiniProjectRow(index)
    if miniProjectsBody.rows[index] then
        return miniProjectsBody.rows[index]
    end

    local row = MakePanel(miniProjectsBody, COLORS.softFill)
    row:SetHeight(50)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row.divider = row:CreateTexture(nil, "BORDER")
    row.divider:SetTexture("Interface/Buttons/WHITE8X8")
    row.divider:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.65)
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    -- Gold + OUTLINE gives project names the stronger bold treatment requested.
    row.name = MakeText(row, "heading3", COLORS.gold, "CENTER", "OUTLINE")
    row.name:SetPoint("TOPLEFT", 4, -7)
    row.name:SetPoint("TOPRIGHT", -4, -7)
    row.name:SetWordWrap(false)
    row.name:SetNonSpaceWrap(false)

    row.needLine = CreateFrame("Frame", nil, row)
    row.needLine:SetPoint("BOTTOMLEFT", 8, 6)
    row.needLine:SetPoint("BOTTOMRIGHT", -8, 6)
    row.needLine:SetHeight(20)

    -- "Daily Needed:" is visually bold; the amount itself uses normal default
    -- IRS text color. Short/over status remains color-coded in parentheses.
    row.needLabel = MakeText(row.needLine, "body", COLORS.text, "LEFT", "OUTLINE")
    row.needLabel:SetText("Daily Needed:")

    row.needAmount = MakeText(row.needLine, "body", COLORS.text, "LEFT")
    row.needStatus = MakeText(row.needLine, "body", COLORS.green, "LEFT")

    -- Centers the combined label + amount + status as one visual line.
    row.LayoutNeedLine = function()
        local gap = 5
        local labelWidth = math.ceil(row.needLabel:GetStringWidth() or 0)
        local amountWidth = math.ceil(row.needAmount:GetStringWidth() or 0)
        local statusWidth = math.ceil(row.needStatus:GetStringWidth() or 0)
        local statusGap = statusWidth > 0 and 8 or 0
        local totalWidth = labelWidth + gap + amountWidth + statusGap + statusWidth

        row.needLabel:ClearAllPoints()
        row.needAmount:ClearAllPoints()
        row.needStatus:ClearAllPoints()

        row.needLabel:SetPoint("LEFT", row.needLine, "CENTER", -(totalWidth / 2), 0)
        row.needAmount:SetPoint("LEFT", row.needLabel, "RIGHT", gap, 0)
        row.needStatus:SetPoint("LEFT", row.needAmount, "RIGHT", statusGap, 0)
    end

    miniProjectsBody.rows[index] = row
    return row
end

local miniProjectsMore = MakeText(miniDashboard, 8, COLORS.muted, "CENTER")
miniProjectsMore:SetText("")
miniProjectsMore:Hide()

-- Aggregate progress for ALL projects selected for the mini dashboard.
-- This sits below the individual project rows and is not limited by the
-- five-row compact display limit.
local miniProjectsSummary = MakePanel(miniDashboard, COLORS.softFill)
miniProjectsSummary:SetHeight(62)
miniProjectsSummary:SetBackdropBorderColor(0, 0, 0, 0)
miniProjectsSummary.topLine = AddDivider(miniProjectsSummary, "TOPLEFT", "TOPLEFT", 0, 0, 0.9)
miniProjectsSummary:Hide()

miniProjectsSummary.title = MakeText(miniProjectsSummary, "heading2", COLORS.goldSoft, "CENTER")
miniProjectsSummary.title:SetPoint("TOPLEFT", 9, -8)
miniProjectsSummary.title:SetPoint("TOPRIGHT", -9, -8)
miniProjectsSummary.title:SetText("DAILY GOLD TARGET")

miniProjectsSummary.need = MakeText(miniProjectsSummary, 12, COLORS.text, "CENTER")
miniProjectsSummary.need:SetPoint("BOTTOMLEFT", 9, 10)
miniProjectsSummary.need:SetPoint("BOTTOMRIGHT", -9, 10)
miniProjectsSummary.need:SetText("0g")

-- Aggregate status is now inline after the target amount.
miniProjectsSummary.status = MakeText(miniProjectsSummary, 1, COLORS.green, "CENTER")
miniProjectsSummary.status:Hide()

-- Optional availability note remains separate so the title can stay exactly
-- "Daily Gold Target" as requested.
miniProjectsSummary.note = MakeText(miniProjectsSummary, 8, COLORS.muted, "CENTER")
miniProjectsSummary.note:SetPoint("TOPLEFT", 9, -25)
miniProjectsSummary.note:SetPoint("TOPRIGHT", -9, -25)
miniProjectsSummary.note:SetText("")
miniProjectsSummary.note:Hide()

-- ============================================================================
-- RESERVE FUNDS
-- Only Reserve Funds explicitly marked "Mini" are shown here.
-- ============================================================================
local miniReservesHeader = CreateFrame("Frame", nil, miniDashboard)
miniReservesHeader:SetHeight(24)
miniReservesHeader:Hide()
miniReservesHeader.line = AddDivider(miniReservesHeader, "TOPLEFT", "TOPLEFT", 0, 0, 0.9)
miniReservesHeader.title = MakeText(miniReservesHeader, "heading2", COLORS.goldSoft, "LEFT")
miniReservesHeader.title:SetPoint("LEFT", 3, 0)
miniReservesHeader.title:SetPoint("RIGHT", -28, 0)
miniReservesHeader.title:SetText("RESERVE FUNDS")

-- Reserve Funds collapse independently from Savings Projects. The state is
-- stored on the Mini Dashboard so it survives reloads and relogs.
local miniReservesCollapse = CreateFrame("Button", nil, miniReservesHeader)
miniReservesCollapse:SetSize(22, 22)
miniReservesCollapse:SetPoint("RIGHT", -2, 0)
miniReservesCollapse.icon = miniReservesCollapse:CreateTexture(nil, "ARTWORK")
miniReservesCollapse.icon:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
miniReservesCollapse.icon:SetSize(22, 22)
miniReservesCollapse.icon:SetPoint("CENTER", 0, 0)
miniReservesCollapse:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")

local function UpdateReserveCollapseArrow(collapsed)
    miniReservesCollapse.icon:SetRotation(collapsed and (-math.pi / 2) or 0)
end

miniReservesCollapse:SetScript("OnClick", function()
    if not IRS.db then return end
    IRS.db.ui = IRS.db.ui or {}
    IRS.db.ui.miniDashboard = IRS.db.ui.miniDashboard or {}
    local saved = IRS.db.ui.miniDashboard
    saved.reservesCollapsed = not (saved.reservesCollapsed == true)
    IRS:RefreshMiniDashboard()
end)

miniReservesCollapse:SetScript("OnEnter", function(self)
    if not IRS.db then return end
    local collapsed = IRS.db.ui
        and IRS.db.ui.miniDashboard
        and IRS.db.ui.miniDashboard.reservesCollapsed == true
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(collapsed and "Expand Reserve Funds" or "Collapse Reserve Funds")
    GameTooltip:Show()
end)
miniReservesCollapse:SetScript("OnLeave", function() GameTooltip:Hide() end)

local miniReservesBody = CreateFrame("Frame", nil, miniDashboard)
miniReservesBody:SetHeight(1)
miniReservesBody.rows = {}
miniReservesBody:Hide()

local MINI_MAX_RESERVES = 3

local function EnsureMiniReserveRow(index)
    if miniReservesBody.rows[index] then return miniReservesBody.rows[index] end
    local row = MakePanel(miniReservesBody, COLORS.softFill)
    row:SetHeight(48); row:SetBackdropBorderColor(0,0,0,0)
    row.divider = row:CreateTexture(nil, "BORDER")
    row.divider:SetTexture("Interface/Buttons/WHITE8X8")
    row.divider:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.65)
    row.divider:SetHeight(1); row.divider:SetPoint("BOTTOMLEFT", 0, 0); row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
    row.name = MakeText(row, "heading3", COLORS.goldSoft, "LEFT")
    row.name:SetPoint("TOPLEFT", 8, -7); row.name:SetPoint("TOPRIGHT", -8, -7)
    row.amount = MakeText(row, "body", COLORS.text, "LEFT")
    row.amount:SetPoint("BOTTOMLEFT", 8, 7); row.amount:SetPoint("RIGHT", -112, 0)
    row.status = MakeText(row, "body", COLORS.muted, "RIGHT", "OUTLINE")
    row.status:SetPoint("BOTTOMRIGHT", -8, 7); row.status:SetWidth(105)
    miniReservesBody.rows[index] = row
    return row
end

-- ============================================================================
-- REFRESH
-- ============================================================================

function IRS:RefreshMiniDashboard()
    if not IRS.db then return end

    local earnings = IRS:GetCurrentEarnings()

    for _, row in ipairs(miniPeriodRows) do
        local amount = earnings[row.key] or 0
        row.value:SetText(FormatGold(amount, true))
        SetNetColor(row.value, amount, COLORS.goldSoft)
    end

    local showProjects = IRS.db.settings.showMiniProjects ~= false
    local collapsed = IRS.db.ui
        and IRS.db.ui.miniDashboard
        and IRS.db.ui.miniDashboard.projectsCollapsed == true
    local reservesCollapsed = IRS.db.ui
        and IRS.db.ui.miniDashboard
        and IRS.db.ui.miniDashboard.reservesCollapsed == true

    -- Settings OFF means the entire section disappears: no title, no arrow,
    -- no empty-state message, and no project rows.
    miniProjectsHeader:SetShown(showProjects)

    if showProjects then
        UpdateProjectCollapseArrow(collapsed)
    end

    miniProjectsBody:SetShown(showProjects and not collapsed)

    local allProjects = IRS:GetSortedProjects()
    local projects = {}

    for _, entry in ipairs(allProjects) do
        if IRS:IsProjectShownInMini(entry.id) then
            table.insert(projects, entry)
        end
    end

    local aggregate = IRS:GetMiniProjectDailySummary()
    local shown = 0

    if showProjects and not collapsed then
        for _, entry in ipairs(projects) do
            if shown >= MINI_MAX_PROJECTS then break end

            local project = entry.project
            local stats = IRS:GetProjectStats(project)
            local daily = IRS:GetProjectDailyGoalStatus(project)

            if project and stats and daily then
                shown = shown + 1

                local row = EnsureMiniProjectRow(shown)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -((shown - 1) * 54))
                row:SetPoint("TOPRIGHT", 0, -((shown - 1) * 54))

                row.name:SetText(tostring(project.name or "Savings Project"))

                local amountText, statusText, statusColor = GetProjectDailyParts(
                    daily,
                    stats.available
                )

                if not stats.available then
                    row.needLabel:SetText("")
                    row.needAmount:SetText(amountText)
                else
                    row.needLabel:SetText("Daily Needed:")
                    row.needAmount:SetText(amountText)
                end

                row.needStatus:SetText(statusText or "")
                SetColor(row.needStatus, statusColor or COLORS.muted)
                row.LayoutNeedLine()
                row:Show()
            end
        end
    end

    for i = shown + 1, #miniProjectsBody.rows do
        miniProjectsBody.rows[i]:Hide()
    end

    local extra = math.max(0, #projects - shown)

    -- The aggregate uses every selected project, including selected projects
    -- beyond the five rows shown in this compact window.
    local showAggregate = showProjects
        and not collapsed
        and aggregate
        and (aggregate.trackedCount or 0) > 0

    miniProjectsSummary:SetShown(showAggregate)

    if showAggregate then
        miniProjectsSummary.title:SetText("DAILY GOLD TARGET")
        miniProjectsSummary.need:SetText(
            FormatAggregateTargetLine(aggregate)
        )

        if (aggregate.unavailableCount or 0) > 0 then
            miniProjectsSummary.note:SetText(
                string.format(
                    "%d selected project%s unavailable",
                    aggregate.unavailableCount,
                    aggregate.unavailableCount == 1 and "" or "s"
                )
            )
            miniProjectsSummary.note:Show()
        else
            miniProjectsSummary.note:SetText("")
            miniProjectsSummary.note:Hide()
        end
    else
        miniProjectsSummary.note:Hide()
    end

    if showProjects and not collapsed and extra > 0 then
        miniProjectsMore:SetText(
            string.format(
                "+%d more project%s — open Projects for details",
                extra,
                extra == 1 and "" or "s"
            )
        )
        miniProjectsMore:Show()
    else
        miniProjectsMore:Hide()
    end

    -- Reserve Funds use current physical/source balances, not Daily Needed.
    local miniReserveEntries = IRS.GetMiniReserves and IRS:GetMiniReserves() or {}
    local shownReserves = 0
    for _, entry in ipairs(miniReserveEntries) do
        if shownReserves >= MINI_MAX_RESERVES then break end
        local stats = IRS.GetReserveStats and IRS:GetReserveStats(entry.reserve) or nil
        if stats then
            shownReserves = shownReserves + 1
            local row = EnsureMiniReserveRow(shownReserves)
            row.name:SetText(entry.reserve.name or "Reserve Fund")
            row.amount:SetText(FormatGold(stats.current, true) .. " / " .. FormatGold(stats.target, true))
            row.status:SetText(stats.status or "")
            if stats.status == "FUNDED" then SetColor(row.status, COLORS.green)
            elseif stats.status == "LOW RESERVE" then SetColor(row.status, COLORS.red)
            elseif stats.status == "BELOW TARGET" then SetColor(row.status, COLORS.goldSoft)
            else SetColor(row.status, COLORS.muted) end
            row:Show()
        end
    end
    for i = shownReserves + 1, #miniReservesBody.rows do miniReservesBody.rows[i]:Hide() end
    miniReservesHeader:SetShown(shownReserves > 0)
    if shownReserves > 0 then
        UpdateReserveCollapseArrow(reservesCollapsed)
    end
    miniReservesBody:SetShown(shownReserves > 0 and not reservesCollapsed)

    -- ------------------------------------------------------------------------
    -- ADAPTIVE FONT LAYOUT
    -- Font settings are user-editable, so vertical spacing is recalculated from
    -- the current semantic sizes instead of assuming the default 10–13px text.
    -- ------------------------------------------------------------------------
    local helperSize = IRS:GetFontSize("mini", "helper")
    local bodySize = IRS:GetFontSize("mini", "body")
    local headingSize = IRS:GetFontSize("mini", "heading")
    local heading2Size = IRS:GetFontSize("mini", "heading2")
    local heading3Size = IRS:GetFontSize("mini", "heading3")
    local valueSize = IRS:GetFontSize("mini", "value")

    local headerHeight = math.max(38, headingSize + helperSize + 14)
    miniHeader:SetHeight(headerHeight)

    miniHeaderTitle:ClearAllPoints()
    miniHeaderTitle:SetPoint("TOPLEFT", miniHeader, "TOPLEFT", 8, -7)
    miniHeaderSub:ClearAllPoints()
    miniHeaderSub:SetPoint("TOPLEFT", miniHeaderTitle, "BOTTOMLEFT", 0, -3)

    miniPeriods:ClearAllPoints()
    miniPeriods:SetPoint("TOPLEFT", miniHeader, "BOTTOMLEFT", 2, -6)
    miniPeriods:SetPoint("TOPRIGHT", miniHeader, "BOTTOMRIGHT", -2, -6)

    local periodRowHeight = math.max(23, math.max(bodySize, valueSize) + 9)
    miniPeriods:SetHeight((periodRowHeight * #miniPeriodRows) + 10)

    for i, row in ipairs(miniPeriodRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -5 - ((i - 1) * periodRowHeight))
        row:SetPoint("TOPRIGHT", -8, -5 - ((i - 1) * periodRowHeight))
        row:SetHeight(periodRowHeight)
    end

    local projectsHeaderHeight = math.max(24, heading2Size + 11)
    miniProjectsHeader:ClearAllPoints()
    miniProjectsHeader:SetPoint("TOPLEFT", miniPeriods, "BOTTOMLEFT", 3, -7)
    miniProjectsHeader:SetPoint("TOPRIGHT", miniPeriods, "BOTTOMRIGHT", -3, -7)
    miniProjectsHeader:SetHeight(projectsHeaderHeight)

    miniProjectsBody:ClearAllPoints()
    miniProjectsBody:SetPoint("TOPLEFT", miniProjectsHeader, "BOTTOMLEFT", -3, -2)
    miniProjectsBody:SetPoint("TOPRIGHT", miniProjectsHeader, "BOTTOMRIGHT", 3, -2)

    local projectRowHeight = math.max(54, heading3Size + bodySize + 28)
    local shownBodyHeight = 0

    for i = 1, shown do
        local row = miniProjectsBody.rows[i]
        if row then
            row:SetHeight(projectRowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((i - 1) * (projectRowHeight + 4)))
            row:SetPoint("TOPRIGHT", 0, -((i - 1) * (projectRowHeight + 4)))

            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", 8, -8)
            row.name:SetPoint("TOPRIGHT", -8, -8)

            row.needLine:SetHeight(math.max(20, bodySize + 8))
            row.needLine:ClearAllPoints()
            row.needLine:SetPoint("BOTTOMLEFT", 8, 7)
            row.needLine:SetPoint("BOTTOMRIGHT", -8, 7)
            row.LayoutNeedLine()
        end
    end

    if shown > 0 then
        shownBodyHeight = (shown * projectRowHeight) + ((shown - 1) * 4)
    end

    miniProjectsBody:SetHeight(math.max(1, shownBodyHeight))

    local moreHeight = 0
    if miniProjectsMore:IsShown() then
        moreHeight = math.max(18, helperSize + 8)
    end

    miniProjectsMore:ClearAllPoints()
    miniProjectsMore:SetPoint("TOPLEFT", miniProjectsBody, "BOTTOMLEFT", 3, -2)
    miniProjectsMore:SetPoint("TOPRIGHT", miniProjectsBody, "BOTTOMRIGHT", -3, -2)

    local summaryHeight = math.max(62, heading2Size + valueSize + helperSize + 30)
    miniProjectsSummary:SetHeight(summaryHeight)
    miniProjectsSummary:ClearAllPoints()

    if miniProjectsMore:IsShown() then
        miniProjectsSummary:SetPoint("TOPLEFT", miniProjectsMore, "BOTTOMLEFT", -3, -4)
        miniProjectsSummary:SetPoint("TOPRIGHT", miniProjectsMore, "BOTTOMRIGHT", 3, -4)
    else
        miniProjectsSummary:SetPoint("TOPLEFT", miniProjectsBody, "BOTTOMLEFT", 0, -4)
        miniProjectsSummary:SetPoint("TOPRIGHT", miniProjectsBody, "BOTTOMRIGHT", 0, -4)
    end

    -- Reserve section begins after whichever project element is actually last.
    local reserveAnchor = miniPeriods
    if showProjects then
        if showAggregate then reserveAnchor = miniProjectsSummary
        elseif miniProjectsMore:IsShown() then reserveAnchor = miniProjectsMore
        elseif shown > 0 then reserveAnchor = miniProjectsBody
        else reserveAnchor = miniProjectsHeader end
    end

    local reserveHeaderHeight = math.max(24, heading2Size + 11)
    local reserveRowHeight = math.max(48, heading3Size + bodySize + 24)
    local reserveBodyHeight = (shownReserves > 0 and not reservesCollapsed)
        and ((shownReserves * reserveRowHeight) + ((shownReserves - 1) * 3))
        or 0

    miniReservesHeader:ClearAllPoints()
    miniReservesHeader:SetPoint("TOPLEFT", reserveAnchor, "BOTTOMLEFT", 0, -7)
    miniReservesHeader:SetPoint("TOPRIGHT", reserveAnchor, "BOTTOMRIGHT", 0, -7)
    miniReservesHeader:SetHeight(reserveHeaderHeight)

    miniReservesBody:ClearAllPoints()
    miniReservesBody:SetPoint("TOPLEFT", miniReservesHeader, "BOTTOMLEFT", 0, -2)
    miniReservesBody:SetPoint("TOPRIGHT", miniReservesHeader, "BOTTOMRIGHT", 0, -2)
    miniReservesBody:SetHeight(math.max(1, reserveBodyHeight))

    for i = 1, shownReserves do
        local row = miniReservesBody.rows[i]
        row:SetHeight(reserveRowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * (reserveRowHeight + 3)))
        row:SetPoint("TOPRIGHT", 0, -((i - 1) * (reserveRowHeight + 3)))
    end

    local reserveExtraHeight = shownReserves > 0
        and (7 + reserveHeaderHeight + (reservesCollapsed and 10 or (2 + reserveBodyHeight + 10)))
        or 0

    local frameHeight

    if not showProjects then
        frameHeight = 7 + headerHeight + 6 + miniPeriods:GetHeight() + 12 + reserveExtraHeight

    elseif collapsed then
        frameHeight = 7 + headerHeight + 6 + miniPeriods:GetHeight()
            + 7 + projectsHeaderHeight + 10 + reserveExtraHeight

    elseif #projects == 0 then
        frameHeight = 7 + headerHeight + 6 + miniPeriods:GetHeight()
            + 7 + projectsHeaderHeight + 2 + moreHeight + 18 + reserveExtraHeight

    else
        frameHeight = 7 + headerHeight + 6 + miniPeriods:GetHeight()
            + 7 + projectsHeaderHeight + 2 + shownBodyHeight
            + moreHeight
            + (showAggregate and (summaryHeight + 8) or 0)
            + 12
            + reserveExtraHeight
    end

    -- Re-assert the player's chosen corner before resizing. The selected corner
    -- stays fixed while larger fonts make the panel grow away from that corner.
    NormalizeMiniDashboardAnchor(IRS:GetMiniDashboardAnchor())

    local requiredHeight = math.max(164, frameHeight)
    local savedMini = IRS.db.ui
        and IRS.db.ui.miniDashboard
        or nil
    local userHeight = savedMini
        and savedMini.userSized
        and tonumber(savedMini.height)
        or nil

    -- Collapsed sections fit to visible content; expanding restores the saved manual height.
    local hasCollapsedSection = (showProjects and collapsed)
        or (shownReserves > 0 and reservesCollapsed)
    if hasCollapsedSection then
        miniDashboard:SetHeight(requiredHeight)
    else
        miniDashboard:SetHeight(math.max(requiredHeight, userHeight or 0))
    end
end

-- ============================================================================
-- PUBLIC OPEN / CLOSE FUNCTIONS
-- ============================================================================

function IRS:ShowMiniDashboard()
    if not IRS.db then IRS:EnsureDB() end

    RestoreMiniDashboardPosition()
    IRS:UpdateProjectSnapshots()
    IRS:RefreshMiniDashboard()
    miniDashboard:Show()
end

function IRS:ToggleMiniDashboard()
    if miniDashboard:IsShown() then
        miniDashboard:Hide()
    else
        IRS:ShowMiniDashboard()
    end
end
