--[[
IRS — Reserve Funds
Persistent reserve goals backed by IRS source-history observations.
]]

local IRS = IRS
local _irsStartupModuleTiming = IRS:BeginStartupTiming("Module load: Reserves")

local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.88},
    panelAlt = {0.225, 0.170, 0.112, 0.88},
    border = {0.52, 0.39, 0.22, 1},
    borderSoft = {0.46, 0.36, 0.22, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {0.43, 0.60, 0.36, 1},
    amber = {0.72, 0.54, 0.26, 1},
    red = {0.63, 0.29, 0.25, 1},
    cyan = {0.40, 0.63, 0.65, 1},
}

local function Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function TodayKey()
    return date("%Y-%m-%d", Now())
end

local function SetColor(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function MakeText(parent, style, color, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontFlags = flags or ""
    fs:SetFont(STANDARD_TEXT_FONT, IRS:GetFontSize("main", style), fontFlags)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then SetColor(fs, color) end
    IRS:RegisterFontString("main", style, fs, STANDARD_TEXT_FONT, fontFlags)
    return fs
end

local function MakePanel(parent, color)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    local c = color or COLORS.panelAlt
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    return frame
end

local function MakeButton(parent, text, x, y, width, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 28)
    button:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    button:SetBackdropColor(unpack(COLORS.panelAlt))
    button:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    button.label = MakeText(button, "helper", COLORS.text, "CENTER")
    button.label:SetAllPoints()
    button.label:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

local function MakeEdit(parent, labelText, x, y, width)
    local label = MakeText(parent, "helper", COLORS.muted, "LEFT")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", x + 2, y - 16)
    box:SetSize(width, 25)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    return box, label
end

local function ParseGoldInput(text)
    text = strtrim(tostring(text or "")):lower():gsub(",", ""):gsub("%s+", "")
    if text == "" then return nil end
    local multiplier = 1
    if text:sub(-1) == "m" then
        multiplier = 1000000
        text = text:sub(1, -2)
    elseif text:sub(-1) == "k" then
        multiplier = 1000
        text = text:sub(1, -2)
    elseif text:sub(-1) == "g" then
        text = text:sub(1, -2)
    end
    local gold = tonumber(text)
    if not gold or gold < 0 then return nil end
    return math.floor((gold * multiplier * 10000) + 0.5)
end

local function GoldInputText(copper)
    return tostring(math.floor((tonumber(copper) or 0) / 10000))
end

local function FormatGold(copper)
    -- Reserve Funds intentionally display whole gold only. At reserve-scale
    -- balances, silver/copper add visual noise without changing the decision.
    -- Always round DOWN to the nearest whole gold.
    local value = tonumber(copper) or 0
    local negative = value < 0
    local gold = math.floor(math.abs(value) / 10000)
    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return (negative and "-" or "") .. goldText .. "g"
end

local function ParseDateKey(key)
    local y, m, d = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d then return nil end
    return y, m, d
end

local function DateKeyToTime(key)
    local y, m, d = ParseDateKey(key)
    if not y then return nil end
    return time({year = y, month = m, day = d, hour = 12})
end

local function TimeToDateKey(stamp)
    return date("%Y-%m-%d", stamp)
end

local function AddDays(key, days)
    local stamp = DateKeyToTime(key)
    if not stamp then return key end
    return TimeToDateKey(stamp + ((tonumber(days) or 0) * 86400))
end

local function MonthKeyOffset(key, offset)
    local y, m = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)")
    y, m = tonumber(y), tonumber(m)
    if not y or not m then return nil end
    local absolute = (y * 12) + (m - 1) + (tonumber(offset) or 0)
    local newYear = math.floor(absolute / 12)
    local newMonth = (absolute % 12) + 1
    return string.format("%04d-%02d", newYear, newMonth)
end

local MONTH_NAMES = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}

local function DateLabel(key)
    local _, m, d = ParseDateKey(key)
    if not m then return tostring(key or "") end
    return string.format("%d/%d", m, d)
end

local function MonthLabel(key)
    local y, m = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)$")
    y, m = tonumber(y), tonumber(m)
    if not y or not m then return tostring(key or "") end
    return MONTH_NAMES[m] .. (m == 1 and (" '" .. tostring(y):sub(-2)) or "")
end

-- ---------------------------------------------------------------------------
-- DATA MODEL
-- ---------------------------------------------------------------------------

function IRS:EnsureReserveDB()
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.reserves = IRS.db.reserves or {}
    local db = IRS.db.reserves
    db.nextId = tonumber(db.nextId) or 1
    db.items = db.items or {}
    db.graphInterval = db.graphInterval or {}
    return db
end

local function SourceHistoryId(sourceType, sourceKey)
    sourceType = tostring(sourceType or "account")
    if sourceType == "account" or sourceType == "warband" then
        return sourceType
    end
    return sourceType .. ":" .. tostring(sourceKey or "")
end

local function EnsureReserveConfigHistory(reserve)
    if not reserve then return {} end
    reserve.startDate = reserve.startDate or TodayKey()
    reserve.configHistory = reserve.configHistory or {}

    if #reserve.configHistory == 0 then
        table.insert(reserve.configHistory, {
            effectiveDay = reserve.startDate,
            changedAt = tonumber(reserve.createdAt) or Now(),
            sourceType = reserve.sourceType or "account",
            sourceKey = reserve.sourceKey,
            allocationPercent = tonumber(reserve.allocationPercent) or 100,
        })
    end

    table.sort(reserve.configHistory, function(a, b)
        local ad = tostring(a.effectiveDay or "")
        local bd = tostring(b.effectiveDay or "")
        if ad == bd then
            return (tonumber(a.changedAt) or 0) < (tonumber(b.changedAt) or 0)
        end
        return ad < bd
    end)
    return reserve.configHistory
end

function IRS:GetReserveConfigForDate(reserveId, dateKey)
    local reserve = type(reserveId) == "table" and reserveId or IRS:GetReserve(reserveId)
    if not reserve then return nil end
    local history = EnsureReserveConfigHistory(reserve)
    local wanted = tostring(dateKey or TodayKey())
    local selected
    for _, config in ipairs(history) do
        if tostring(config.effectiveDay or "") <= wanted then
            selected = config
        else
            break
        end
    end
    selected = selected or history[1]
    if not selected then return nil end
    return {
        sourceType = selected.sourceType or reserve.sourceType or "account",
        sourceKey = selected.sourceKey,
        allocationPercent = math.max(0, math.min(100, tonumber(selected.allocationPercent) or 100)),
        effectiveDay = selected.effectiveDay,
        changedAt = selected.changedAt,
    }
end

function IRS:GetReserve(reserveId)
    local db = IRS:EnsureReserveDB()
    return db.items[reserveId] or db.items[tostring(reserveId)]
end

function IRS:GetSortedReserves()
    local db = IRS:EnsureReserveDB()
    local rows = {}
    for id, reserve in pairs(db.items) do
        table.insert(rows, {id = tonumber(id) or id, reserve = reserve})
    end
    table.sort(rows, function(a, b)
        local ac = tonumber(a.reserve.createdAt) or 0
        local bc = tonumber(b.reserve.createdAt) or 0
        if ac == bc then return tostring(a.reserve.name or "") < tostring(b.reserve.name or "") end
        return ac < bc
    end)
    return rows
end

function IRS:GetMiniReserves()
    local rows = {}
    for _, entry in ipairs(IRS:GetSortedReserves()) do
        if entry.reserve.showMini == true then table.insert(rows, entry) end
    end
    return rows
end

function IRS:GetReserveAllocatedBalance(reserve)
    if not reserve then return 0, false, "Unknown Source", 0 end
    return IRS:GetProjectAllocatedBalance(reserve)
end

local function ReserveStatus(current, target, warning, available)
    if not available then return "UNAVAILABLE" end
    if current >= target then return "FUNDED" end
    if current < warning then return "LOW RESERVE" end
    return "BELOW TARGET"
end

function IRS:GetReserveStats(reserveId)
    local reserve = type(reserveId) == "table" and reserveId or IRS:GetReserve(reserveId)
    if not reserve then return nil end
    local current, available, sourceLabel, sourceBalance = IRS:GetReserveAllocatedBalance(reserve)
    local target = math.max(0, tonumber(reserve.targetCopper) or 0)
    local warning = math.max(0, math.min(target, tonumber(reserve.warningFloorCopper) or math.floor(target * 0.8)))
    local refill = math.max(0, target - current)
    local status = ReserveStatus(current, target, warning, available)
    return {
        current = current,
        target = target,
        warning = warning,
        refill = refill,
        status = status,
        available = available,
        sourceLabel = sourceLabel,
        sourceBalance = sourceBalance,
        allocationPercent = tonumber(reserve.allocationPercent) or 100,
        percent = target > 0 and math.max(0, math.min(1, current / target)) or 0,
    }
end

local function ValidateReserveData(data)
    data = data or {}
    local target = math.floor(tonumber(data.targetCopper) or 0)
    local warning = math.floor(tonumber(data.warningFloorCopper) or math.floor(target * 0.8))
    local allocation = tonumber(data.allocationPercent) or 100
    local startDate = tostring(data.startDate or TodayKey())

    if target <= 0 then return nil, "Target must be greater than 0 gold." end
    if warning < 0 or warning > target then return nil, "Warning Floor must be between 0 and the Target." end
    if allocation <= 0 or allocation > 100 then return nil, "Allocation must be between 1 and 100%." end
    if not IRS:ValidateProjectDeadline(startDate) then return nil, "Start Date must use YYYY-MM-DD." end

    return {
        name = strtrim(tostring(data.name or "Reserve Fund")) ~= "" and strtrim(tostring(data.name)) or "Reserve Fund",
        targetCopper = target,
        warningFloorCopper = warning,
        startDate = startDate,
        allocationPercent = allocation,
        sourceType = data.sourceType or "account",
        sourceKey = data.sourceKey,
        alertsEnabled = data.alertsEnabled ~= false,
        showMini = data.showMini == true,
    }
end

function IRS:CreateReserve(data)
    local normalized, err = ValidateReserveData(data)
    if not normalized then return nil, err end
    local db = IRS:EnsureReserveDB()
    local id = db.nextId
    db.nextId = id + 1
    local reserve = {
        id = id,
        name = normalized.name,
        targetCopper = normalized.targetCopper,
        warningFloorCopper = normalized.warningFloorCopper,
        startDate = normalized.startDate,
        allocationPercent = normalized.allocationPercent,
        sourceType = normalized.sourceType,
        sourceKey = normalized.sourceKey,
        alertsEnabled = normalized.alertsEnabled,
        showMini = normalized.showMini,
        createdAt = Now(),
        historyInterval = "daily",
    }
    db.items[id] = reserve
    EnsureReserveConfigHistory(reserve)
    if IRS.CaptureDailySourceHistory then IRS:CaptureDailySourceHistory() end
    local stats = IRS:GetReserveStats(reserve)
    reserve.lastStatus = stats and stats.status or nil
    return id, reserve
end

function IRS:UpdateReserve(reserveId, data)
    local reserve = IRS:GetReserve(reserveId)
    if not reserve then return false, "Reserve not found." end
    local normalized, err = ValidateReserveData(data)
    if not normalized then return false, err end

    local oldSourceType = reserve.sourceType or "account"
    local oldSourceKey = reserve.sourceKey
    local oldAllocation = tonumber(reserve.allocationPercent) or 100

    reserve.name = normalized.name
    reserve.targetCopper = normalized.targetCopper
    reserve.warningFloorCopper = normalized.warningFloorCopper
    reserve.startDate = normalized.startDate
    reserve.allocationPercent = normalized.allocationPercent
    reserve.sourceType = normalized.sourceType
    reserve.sourceKey = normalized.sourceKey
    reserve.alertsEnabled = normalized.alertsEnabled
    reserve.showMini = normalized.showMini

    EnsureReserveConfigHistory(reserve)
    if oldSourceType ~= reserve.sourceType
        or tostring(oldSourceKey or "") ~= tostring(reserve.sourceKey or "")
        or oldAllocation ~= reserve.allocationPercent then
        table.insert(reserve.configHistory, {
            effectiveDay = TodayKey(),
            changedAt = Now(),
            sourceType = reserve.sourceType,
            sourceKey = reserve.sourceKey,
            allocationPercent = reserve.allocationPercent,
        })
    end

    if IRS.CaptureDailySourceHistory then IRS:CaptureDailySourceHistory() end
    return true, reserve
end

function IRS:DeleteReserve(reserveId)
    local db = IRS:EnsureReserveDB()
    if not db.items[reserveId] and not db.items[tostring(reserveId)] then return false end
    db.items[reserveId] = nil
    db.items[tostring(reserveId)] = nil
    return true
end

function IRS:ConvertProjectToReserve(projectId)
    local project = IRS:GetProject(projectId)
    if not project then return nil, "Project not found." end
    local stats = IRS:GetProjectStats(project)
    if not stats or not stats.available then return nil, "Project source is unavailable." end
    if stats.current < (tonumber(project.targetCopper) or 0) then
        return nil, "Only funded projects can be converted to a Reserve."
    end

    local config = IRS:GetProjectConfigForDate(project, TodayKey()) or project
    local target = tonumber(project.targetCopper) or 0
    local id, reserveOrErr = IRS:CreateReserve({
        name = project.name or "Reserve Fund",
        targetCopper = target,
        warningFloorCopper = math.floor(target * 0.8),
        startDate = TodayKey(),
        sourceType = config.sourceType or project.sourceType or "account",
        sourceKey = config.sourceKey,
        allocationPercent = config.allocationPercent or project.allocationPercent or 100,
        alertsEnabled = true,
        showMini = false,
    })
    if not id then return nil, reserveOrErr end
    project.convertedToReserveId = id
    return id, reserveOrErr
end

-- ---------------------------------------------------------------------------
-- HISTORY
-- ---------------------------------------------------------------------------

local function DailyAllocatedMap(reserve)
    local map = {}
    if IRS.EnsureProjectSourceHistoryMigration then IRS:EnsureProjectSourceHistoryMigration() end
    if IRS.CaptureDailySourceHistory then IRS:CaptureDailySourceHistory() end
    local days = IRS.db and IRS.db.sourceHistory and IRS.db.sourceHistory.days or {}
    local startDate = reserve.startDate or TodayKey()
    local today = TodayKey()

    for dayKey, day in pairs(days) do
        if dayKey >= startDate and dayKey <= today then
            local config = IRS:GetReserveConfigForDate(reserve, dayKey)
            if config then
                local source = day.sources and day.sources[SourceHistoryId(config.sourceType, config.sourceKey)]
                if source then
                    local raw = tonumber(source.ending) or tonumber(source.start)
                    if raw ~= nil then
                        map[dayKey] = math.floor(raw * ((tonumber(config.allocationPercent) or 100) / 100))
                    end
                end
            end
        end
    end
    return map
end

function IRS:GetReserveHistory(reserveId, interval)
    local reserve = type(reserveId) == "table" and reserveId or IRS:GetReserve(reserveId)
    if not reserve then return {} end
    interval = interval or reserve.historyInterval or "daily"
    if interval ~= "daily" and interval ~= "weekly" and interval ~= "monthly" then interval = "daily" end
    local map = DailyAllocatedMap(reserve)
    local rows = {}
    local today = TodayKey()

    if interval == "daily" then
        local first = AddDays(today, -29)
        if reserve.startDate and reserve.startDate > first then first = reserve.startDate end
        local key = first
        while key <= today do
            table.insert(rows, {key = key, label = DateLabel(key), amount = map[key]})
            local nextKey = AddDays(key, 1)
            if nextKey == key then break end
            key = nextKey
        end

    elseif interval == "weekly" then
        local windowStart = AddDays(today, -181)
        if reserve.startDate and reserve.startDate > windowStart then windowStart = reserve.startDate end
        local bucketStart = windowStart
        while bucketStart <= today do
            local bucketEnd = AddDays(bucketStart, 6)
            if bucketEnd > today then bucketEnd = today end
            local lastKey, lastAmount
            for dayKey, amount in pairs(map) do
                if dayKey >= bucketStart and dayKey <= bucketEnd then
                    if not lastKey or dayKey > lastKey then
                        lastKey, lastAmount = dayKey, amount
                    end
                end
            end
            table.insert(rows, {
                key = bucketStart,
                label = DateLabel(bucketStart),
                amount = lastAmount,
                detail = bucketStart .. " to " .. bucketEnd,
            })
            local nextKey = AddDays(bucketStart, 7)
            if nextKey == bucketStart then break end
            bucketStart = nextKey
        end

    else
        local currentMonth = today:sub(1, 7)
        local firstMonth = MonthKeyOffset(currentMonth, -11)
        local reserveMonth = tostring(reserve.startDate or today):sub(1, 7)
        if reserveMonth > firstMonth then firstMonth = reserveMonth end
        local monthKey = firstMonth
        while monthKey and monthKey <= currentMonth do
            local lastKey, lastAmount
            for dayKey, amount in pairs(map) do
                if dayKey:sub(1,7) == monthKey then
                    if not lastKey or dayKey > lastKey then lastKey, lastAmount = dayKey, amount end
                end
            end
            table.insert(rows, {
                key = monthKey,
                label = MonthLabel(monthKey),
                amount = lastAmount,
                detail = monthKey,
            })
            local nextMonth = MonthKeyOffset(monthKey, 1)
            if nextMonth == monthKey then break end
            monthKey = nextMonth
        end
    end

    return rows
end

function IRS:SetReserveHistoryInterval(reserveId, interval)
    local reserve = IRS:GetReserve(reserveId)
    if not reserve then return false end
    if interval ~= "daily" and interval ~= "weekly" and interval ~= "monthly" then return false end
    reserve.historyInterval = interval
    return true
end

-- ---------------------------------------------------------------------------
-- ALERTS
-- ---------------------------------------------------------------------------

local function StatusColor(status)
    if status == "FUNDED" then return COLORS.green end
    if status == "LOW RESERVE" then return COLORS.red end
    if status == "BELOW TARGET" then return COLORS.amber end
    return COLORS.muted
end

local function NotifyReserve(reserve, stats)
    local message = string.format(
        "%s is %s: %s / %s • refill %s",
        tostring(reserve.name or "Reserve Fund"),
        tostring(stats.status),
        FormatGold(stats.current),
        FormatGold(stats.target),
        FormatGold(stats.refill)
    )
    print("|cffc9a64dIRS Reserve:|r " .. message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local c = StatusColor(stats.status)
        UIErrorsFrame:AddMessage("IRS Reserve — " .. message, c[1], c[2], c[3], 1)
    end
end

function IRS:RefreshReserveStatuses(suppressAlerts)
    for _, entry in ipairs(IRS:GetSortedReserves()) do
        local reserve = entry.reserve
        local stats = IRS:GetReserveStats(reserve)
        local old = reserve.lastStatus
        local newStatus = stats and stats.status or "UNAVAILABLE"

        if not suppressAlerts
            and reserve.alertsEnabled ~= false
            and old
            and old ~= newStatus
            and (newStatus == "BELOW TARGET" or newStatus == "LOW RESERVE") then
            NotifyReserve(reserve, stats)
        end
        reserve.lastStatus = newStatus
    end
end

-- ---------------------------------------------------------------------------
-- MAIN RESERVES PAGE UI
-- ---------------------------------------------------------------------------
-- Build the visual tree after the addon's shared page containers and scrolling
-- wrappers have finished loading. This keeps the feature independent of TOC
-- timing details introduced by the folder/module layout.
local function BuildReservesUI()
    local page = IRS.reservesPage
    if not page then return false end
    if page._irsReservesUIBuilt then return true end
    IRS:EnsureReserveDB()

local selectedReserveId
local reserveSourceType = "account"
local reserveSourceKey
local deleteArmedId

local title = MakeText(page, "page", COLORS.goldSoft, "LEFT")
title:SetPoint("TOPLEFT", 4, -4)
title:SetText("RESERVE FUNDS")

local desc = MakeText(page, "body", COLORS.text, "LEFT")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
desc:SetPoint("RIGHT", -4, 0)
desc:SetText("Maintain indefinite gold buffers. IRS watches the selected source and alerts when a Reserve falls below its target or warning floor.")

local selectLabel = MakeText(page, "helper", COLORS.muted, "LEFT")
selectLabel:SetPoint("TOPLEFT", 4, -58)
selectLabel:SetText("RESERVE")

local selectButton = MakeButton(page, "Select reserve", 4, -75, 260)
selectButton.label:SetJustifyH("LEFT")
selectButton.label:ClearAllPoints(); selectButton.label:SetPoint("LEFT", 10, 0); selectButton.label:SetPoint("RIGHT", -24, 0)
local selectArrow = MakeText(selectButton, "helper", COLORS.gold, "RIGHT")
selectArrow:SetPoint("RIGHT", -8, 0); selectArrow:SetText("v")

local newButton = MakeButton(page, "NEW RESERVE", 274, -75, 112)
local deleteButton = MakeButton(page, "DELETE", 396, -75, 90)
local convertButton = MakeButton(page, "CONVERT PROJECT", 496, -75, 145)
local convertHint = MakeText(page, "helper", COLORS.muted, "CENTER")
convertHint:SetPoint("TOPLEFT", 496, -106)
convertHint:SetWidth(145)
convertHint:SetText("Completed Projects only")
local statusText = MakeText(page, "helper", COLORS.muted, "LEFT")
statusText:SetPoint("TOPLEFT", 654, -81); statusText:SetPoint("RIGHT", -4, 0)

local nameBox = MakeEdit(page, "RESERVE NAME", 4, -118, 205)
local targetBox = MakeEdit(page, "TARGET GOLD", 219, -118, 125)
local warningBox = MakeEdit(page, "WARNING FLOOR", 354, -118, 125)
local startBox = MakeEdit(page, "START DATE (YYYY-MM-DD)", 489, -118, 145)
local allocationBox = MakeEdit(page, "ALLOCATION %", 644, -118, 86)

local alertsCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
alertsCheck:SetSize(28, 28); alertsCheck:SetPoint("TOPLEFT", 744, -130)
local alertsLabel = MakeText(page, "helper", COLORS.text, "LEFT")
alertsLabel:SetPoint("LEFT", alertsCheck, "RIGHT", 2, 0); alertsLabel:SetText("Alerts")

local miniCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
miniCheck:SetSize(28, 28); miniCheck:SetPoint("TOPLEFT", 804, -130)
local miniLabel = MakeText(page, "helper", COLORS.text, "LEFT")
miniLabel:SetPoint("LEFT", miniCheck, "RIGHT", 2, 0); miniLabel:SetText("Mini")

local sourceTitle = MakeText(page, "helper", COLORS.muted, "LEFT")
sourceTitle:SetPoint("TOPLEFT", 4, -174); sourceTitle:SetText("SOURCE")
local sourceButton = MakeButton(page, "Account Liquid Gold", 4, -191, 180)
sourceButton.label:SetJustifyH("LEFT"); sourceButton.label:ClearAllPoints(); sourceButton.label:SetPoint("LEFT", 8, 0); sourceButton.label:SetPoint("RIGHT", -20, 0)
local sourceArrow = MakeText(sourceButton, "helper", COLORS.gold, "RIGHT"); sourceArrow:SetPoint("RIGHT", -7, 0); sourceArrow:SetText("v")

local detailTitle = MakeText(page, "helper", COLORS.muted, "LEFT")
detailTitle:SetPoint("TOPLEFT", 194, -174); detailTitle:SetText("GUILD BANK / CHARACTER")
local detailButton = MakeButton(page, "Not required", 194, -191, 270)
detailButton.label:SetJustifyH("LEFT"); detailButton.label:ClearAllPoints(); detailButton.label:SetPoint("LEFT", 8, 0); detailButton.label:SetPoint("RIGHT", -20, 0)
local detailArrow = MakeText(detailButton, "helper", COLORS.gold, "RIGHT"); detailArrow:SetPoint("RIGHT", -7, 0); detailArrow:SetText("v")

local saveButton = MakeButton(page, "SAVE RESERVE", 479, -191, 120)
local syncButton = MakeButton(page, "SYNC GUILD BANK", 609, -191, 145)

local summary = CreateFrame("Frame", nil, page)
summary:SetPoint("TOPLEFT", 4, -235); summary:SetPoint("TOPRIGHT", -4, -235); summary:SetHeight(100)
summary.cards = {}
local summaryLabels = {"CURRENT RESERVE", "TARGET", "REFILL NEEDED", "STATUS"}
for i, label in ipairs(summaryLabels) do
    local card = CreateFrame("Frame", nil, summary)
    card:SetPoint("TOPLEFT", (i - 1) * 212, 0); card:SetSize(202, 88)
    if i > 1 then
        local divider = card:CreateTexture(nil, "BORDER")
        divider:SetTexture("Interface/Buttons/WHITE8X8")
        divider:SetVertexColor(unpack(COLORS.borderSoft))
        divider:SetWidth(1); divider:SetPoint("TOPLEFT", 0, -4); divider:SetPoint("BOTTOMLEFT", 0, 4)
    end
    card.label = MakeText(card, "helper", COLORS.goldSoft, "CENTER")
    card.label:SetPoint("TOPLEFT", 6, -7); card.label:SetPoint("TOPRIGHT", -6, -7); card.label:SetText(label)
    card.value = MakeText(card, "value", COLORS.gold, "CENTER")
    card.value:SetPoint("CENTER", 0, -3); card.value:SetWidth(190)
    card.detail = MakeText(card, "helper", COLORS.muted, "CENTER")
    card.detail:SetPoint("BOTTOMLEFT", 6, 5); card.detail:SetPoint("BOTTOMRIGHT", -6, 5)
    summary.cards[i] = card
end

local historyTitle = MakeText(page, "section", COLORS.goldSoft, "LEFT")
-- Keep the Reserve History header visually attached to its chart instead of
-- floating directly beneath the summary cards.
historyTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -365)
historyTitle:SetText("RESERVE HISTORY")
local historyNote = MakeText(page, "helper", COLORS.muted, "LEFT")
historyNote:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", 0, -5)
historyNote:SetWidth(510)
historyNote:SetWordWrap(true)
historyNote:SetText("Bars show the last recorded allocated source balance for each period.\nTarget and warning floor remain fixed reference lines.")

local intervalButtons = {}
local function MakeInterval(key, label, x)
    -- Align the range controls with the Reserve History heading. The note is
    -- intentionally limited to the left side so it can sit immediately above
    -- the chart without colliding with these controls.
    local b = MakeButton(page, label, x, -365, 92)
    b:SetScript("OnClick", function()
        local reserve = IRS:GetReserve(selectedReserveId)
        if reserve then IRS:SetReserveHistoryInterval(reserve, key); IRS:RefreshReservesPage(true) end
    end)
    intervalButtons[key] = b
end
MakeInterval("daily", "30 DAYS", 548)
MakeInterval("weekly", "6 MONTHS", 646)
MakeInterval("monthly", "12 MONTHS", 744)

local chart = MakePanel(page, COLORS.panel)
chart:SetPoint("TOPLEFT", 4, -425); chart:SetPoint("TOPRIGHT", -4, -425); chart:SetHeight(285)

chart.empty = MakeText(chart, "body", COLORS.muted, "CENTER")
chart.empty:SetPoint("CENTER", 0, 0); chart.empty:SetText("Select a Reserve to view history.")

chart.targetLine = chart:CreateTexture(nil, "ARTWORK")
chart.targetLine:SetTexture("Interface/Buttons/WHITE8X8"); chart.targetLine:SetVertexColor(unpack(COLORS.goldSoft)); chart.targetLine:SetHeight(2)
chart.warningLine = chart:CreateTexture(nil, "ARTWORK")
chart.warningLine:SetTexture("Interface/Buttons/WHITE8X8"); chart.warningLine:SetVertexColor(unpack(COLORS.red)); chart.warningLine:SetHeight(1)
chart.targetLabel = MakeText(chart, "helper", COLORS.goldSoft, "RIGHT")
chart.warningLabel = MakeText(chart, "helper", COLORS.red, "RIGHT")
chart.zeroLabel = MakeText(chart, "helper", COLORS.muted, "RIGHT"); chart.zeroLabel:SetText("0g")

chart.bars = {}
for i = 1, 30 do
    local slot = CreateFrame("Button", nil, chart)
    slot:SetHeight(230)
    slot.bar = slot:CreateTexture(nil, "ARTWORK")
    slot.bar:SetTexture("Interface/Buttons/WHITE8X8")
    slot.bar:SetPoint("BOTTOM", 0, 24); slot.bar:SetWidth(12); slot.bar:SetHeight(1)
    slot.label = MakeText(slot, "helper", COLORS.muted, "CENTER")
    slot.label:SetPoint("BOTTOMLEFT", -20, 1); slot.label:SetPoint("BOTTOMRIGHT", 20, 1)
    slot:SetScript("OnEnter", function(self)
        if not self.row or self.row.amount == nil then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.row.detail or self.row.key or "Reserve history")
        GameTooltip:AddLine(FormatGold(self.row.amount), 0.88, 0.84, 0.75)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chart.bars[i] = slot
end

-- Selection popup.
local selectPopup = MakePanel(IRS.mainFrame, COLORS.panelAlt)
selectPopup:SetSize(270, 285); selectPopup:SetFrameStrata("TOOLTIP")
selectPopup:SetPoint("TOPLEFT", selectButton, "BOTTOMLEFT", 0, -2); selectPopup:Hide()
local selectScroll = CreateFrame("ScrollFrame", nil, selectPopup, "UIPanelScrollFrameTemplate")
selectScroll:SetPoint("TOPLEFT", 5, -5); selectScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local selectChild = CreateFrame("Frame", nil, selectScroll); selectChild:SetSize(235, 1); selectScroll:SetScrollChild(selectChild)
selectPopup.rows = {}

local sourcePopup = MakePanel(IRS.mainFrame, COLORS.panelAlt)
sourcePopup:SetSize(190, 120); sourcePopup:SetFrameStrata("TOOLTIP")
sourcePopup:SetPoint("TOPLEFT", sourceButton, "BOTTOMLEFT", 0, -2); sourcePopup:Hide()

local detailPopup = MakePanel(IRS.mainFrame, COLORS.panelAlt)
detailPopup:SetSize(310, 285); detailPopup:SetFrameStrata("TOOLTIP")
detailPopup:SetPoint("TOPLEFT", detailButton, "BOTTOMLEFT", 0, -2); detailPopup:Hide()
local detailScroll = CreateFrame("ScrollFrame", nil, detailPopup, "UIPanelScrollFrameTemplate")
detailScroll:SetPoint("TOPLEFT", 5, -5); detailScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local detailChild = CreateFrame("Frame", nil, detailScroll); detailChild:SetSize(275, 1); detailScroll:SetScrollChild(detailChild)
detailPopup.rows = {}

local convertPopup = MakePanel(IRS.mainFrame, COLORS.panelAlt)
convertPopup:SetSize(310, 240); convertPopup:SetFrameStrata("TOOLTIP")
convertPopup:SetPoint("TOPLEFT", convertButton, "BOTTOMLEFT", 0, -2); convertPopup:Hide()
local convertScroll = CreateFrame("ScrollFrame", nil, convertPopup, "UIPanelScrollFrameTemplate")
convertScroll:SetPoint("TOPLEFT", 5, -5); convertScroll:SetPoint("BOTTOMRIGHT", -25, 5)
local convertChild = CreateFrame("Frame", nil, convertScroll); convertChild:SetSize(275, 1); convertScroll:SetScrollChild(convertChild)
convertPopup.rows = {}

function IRS:HideReservePopups()
    selectPopup:Hide(); sourcePopup:Hide(); detailPopup:Hide(); convertPopup:Hide()
end

local function EnsurePopupRow(container, child, index, width)
    if container.rows[index] then return container.rows[index] end
    local row = CreateFrame("Button", nil, child, "BackdropTemplate")
    row:SetHeight(26); row:SetWidth(width)
    row:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8"})
    row:SetBackdropColor(0.15, 0.115, 0.070, 0.65)
    row.text = MakeText(row, "helper", COLORS.text, "LEFT")
    row.text:SetPoint("LEFT", 8, 0); row.text:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.19, 0.12, 0.85) end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.115, 0.070, 0.65) end)
    container.rows[index] = row
    return row
end

local function SourceLabel(sourceType)
    if sourceType == "warband" then return "Warband Bank" end
    if sourceType == "guild" then return "Guild Bank" end
    if sourceType == "character" then return "Specific Character" end
    return "Account Liquid Gold"
end

local function ResetForm()
    selectedReserveId = nil
    reserveSourceType = "account"; reserveSourceKey = nil
    nameBox:SetText("")
    targetBox:SetText("")
    warningBox:SetText("")
    startBox:SetText(TodayKey())
    allocationBox:SetText("100")
    alertsCheck:SetChecked(true); miniCheck:SetChecked(false)
    selectButton.label:SetText("New Reserve")
    sourceButton.label:SetText("Account Liquid Gold")
    detailButton.label:SetText("Not required")
    statusText:SetText("New Reserve")
    deleteArmedId = nil
end

local function LoadReserve(reserveId)
    local reserve = IRS:GetReserve(reserveId)
    if not reserve then ResetForm(); return end
    selectedReserveId = reserveId
    reserveSourceType = reserve.sourceType or "account"
    reserveSourceKey = reserve.sourceKey
    nameBox:SetText(reserve.name or "")
    targetBox:SetText(GoldInputText(reserve.targetCopper))
    warningBox:SetText(GoldInputText(reserve.warningFloorCopper))
    startBox:SetText(reserve.startDate or TodayKey())
    allocationBox:SetText(tostring(math.floor(tonumber(reserve.allocationPercent) or 100)))
    alertsCheck:SetChecked(reserve.alertsEnabled ~= false)
    miniCheck:SetChecked(reserve.showMini == true)
    selectButton.label:SetText(reserve.name or "Reserve Fund")
    sourceButton.label:SetText(SourceLabel(reserveSourceType))
    local _, _, sourceLabel = IRS:GetReserveAllocatedBalance(reserve)
    detailButton.label:SetText((reserveSourceType == "guild" or reserveSourceType == "character") and sourceLabel or "Not required")
    deleteArmedId = nil
end

local function RefreshSelectPopup()
    local rows = IRS:GetSortedReserves()
    if #rows == 0 then rows = {{id = nil, reserve = {name = "No Reserve Funds yet"}}} end
    for i, entry in ipairs(rows) do
        local row = EnsurePopupRow(selectPopup, selectChild, i, 235)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((i - 1) * 27)); row:SetWidth(235)
        row.text:SetText(entry.reserve.name or "Reserve Fund")
        row:SetEnabled(entry.id ~= nil)
        row:SetScript("OnClick", function()
            if entry.id then LoadReserve(entry.id); selectPopup:Hide(); IRS:RefreshReservesPage(true) end
        end)
        row:Show()
    end
    for i = #rows + 1, #selectPopup.rows do selectPopup.rows[i]:Hide() end
    selectChild:SetHeight(math.max(1, #rows * 27))
end

selectButton:SetScript("OnClick", function()
    if selectPopup:IsShown() then selectPopup:Hide() else RefreshSelectPopup(); selectPopup:Show() end
end)

local sourceChoices = {
    {key="account", label="Account Liquid Gold"},
    {key="warband", label="Warband Bank"},
    {key="guild", label="Guild Bank"},
    {key="character", label="Specific Character"},
}
for i, choice in ipairs(sourceChoices) do
    local row = CreateFrame("Button", nil, sourcePopup, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 4, -4 - ((i - 1) * 28)); row:SetSize(182, 26)
    row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"}); row:SetBackdropColor(0.15,0.115,0.070,0.65)
    row.text = MakeText(row, "helper", COLORS.text, "LEFT"); row.text:SetPoint("LEFT", 8, 0); row.text:SetText(choice.label)
    row:SetScript("OnClick", function()
        reserveSourceType = choice.key; reserveSourceKey = nil
        sourceButton.label:SetText(choice.label)
        if choice.key == "guild" then detailButton.label:SetText("Choose / sync a Guild Bank")
        elseif choice.key == "character" then detailButton.label:SetText("Choose a scanned character")
        else detailButton.label:SetText("Not required") end
        sourcePopup:Hide()
    end)
end
sourceButton:SetScript("OnClick", function() sourcePopup:SetShown(not sourcePopup:IsShown()) end)

local function RefreshDetailPopup()
    local choices = {}
    if reserveSourceType == "character" then
        for _, entry in ipairs(IRS:GetSortedCharacters()) do
            table.insert(choices, {key=entry.key, label=entry.record.label or entry.record.name or "Unknown"})
        end
    elseif reserveSourceType == "guild" then
        for _, entry in ipairs(IRS:GetSortedGuildBanks()) do
            table.insert(choices, {key=entry.key, label=(entry.record.name or "Guild") .. " — " .. FormatGold(entry.record.money or 0)})
        end
    end
    if #choices == 0 then table.insert(choices, {key=nil, label=reserveSourceType == "guild" and "Visit a Guild Bank to sync it" or "No scanned characters"}) end
    for i, item in ipairs(choices) do
        local row = EnsurePopupRow(detailPopup, detailChild, i, 275)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((i-1)*27)); row:SetWidth(275)
        row.text:SetText(item.label); row:SetEnabled(item.key ~= nil)
        row:SetScript("OnClick", function() reserveSourceKey=item.key; detailButton.label:SetText(item.label); detailPopup:Hide() end)
        row:Show()
    end
    for i=#choices+1,#detailPopup.rows do detailPopup.rows[i]:Hide() end
    detailChild:SetHeight(math.max(1,#choices*27))
end

detailButton:SetScript("OnClick", function()
    if reserveSourceType ~= "guild" and reserveSourceType ~= "character" then return end
    if detailPopup:IsShown() then detailPopup:Hide() else RefreshDetailPopup(); detailPopup:Show() end
end)

local function FormData()
    local target = ParseGoldInput(targetBox:GetText())
    local warning = ParseGoldInput(warningBox:GetText())
    if target and warning == nil then warning = math.floor(target * 0.8) end
    return {
        name=nameBox:GetText(), targetCopper=target, warningFloorCopper=warning,
        startDate=startBox:GetText(), allocationPercent=tonumber(allocationBox:GetText()),
        sourceType=reserveSourceType, sourceKey=reserveSourceKey,
        alertsEnabled=alertsCheck:GetChecked(), showMini=miniCheck:GetChecked(),
    }
end

newButton:SetScript("OnClick", function() ResetForm(); IRS:RefreshReservesPage(true) end)

saveButton:SetScript("OnClick", function()
    local data = FormData()
    local ok, result
    if selectedReserveId then
        ok, result = IRS:UpdateReserve(selectedReserveId, data)
    else
        local id, reserveOrErr = IRS:CreateReserve(data)
        ok = id ~= nil; result = reserveOrErr
        if ok then selectedReserveId = id end
    end
    if ok then
        LoadReserve(selectedReserveId); statusText:SetText("Saved")
        IRS:RefreshReservesPage(true)
        if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    else
        statusText:SetText(tostring(result or "Could not save Reserve")); SetColor(statusText, COLORS.red)
    end
end)

deleteButton:SetScript("OnClick", function()
    if not selectedReserveId then statusText:SetText("Select a Reserve first."); return end
    if deleteArmedId ~= selectedReserveId then
        deleteArmedId = selectedReserveId; statusText:SetText("Click DELETE again to confirm."); SetColor(statusText, COLORS.red); return
    end
    IRS:DeleteReserve(selectedReserveId); ResetForm(); statusText:SetText("Reserve deleted. Source history remains in IRS.")
    IRS:RefreshReservesPage(true); if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
end)

syncButton:SetScript("OnClick", function()
    local amount = IRS:ScanGuildBankGold(true)
    if amount ~= nil then statusText:SetText("Guild Bank synced: " .. FormatGold(amount))
    else statusText:SetText("Guild Bank unavailable — open the Guild Bank to refresh it.") end
    IRS:RefreshReservesPage(true)
end)

local function RefreshConvertPopup()
    local choices = {}
    for _, entry in ipairs(IRS:GetSortedProjects()) do
        local stats = IRS:GetProjectStats(entry.project)
        if stats and stats.available and stats.current >= (tonumber(entry.project.targetCopper) or 0) then
            table.insert(choices, entry)
        end
    end
    if #choices == 0 then choices={{id=nil, project={name="No funded Projects available"}}} end
    for i, entry in ipairs(choices) do
        local row = EnsurePopupRow(convertPopup, convertChild, i, 275)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((i-1)*27)); row:SetWidth(275)
        row.text:SetText(entry.project.name or "Savings Project"); row:SetEnabled(entry.id ~= nil)
        row:SetScript("OnClick", function()
            if not entry.id then return end
            local id, reserveOrErr = IRS:ConvertProjectToReserve(entry.id)
            convertPopup:Hide()
            if id then
                LoadReserve(id); statusText:SetText("Reserve created; completed Project retained as history.")
            else
                statusText:SetText(tostring(reserveOrErr or "Conversion failed")); SetColor(statusText, COLORS.red)
            end
            IRS:RefreshReservesPage(true)
        end)
        row:Show()
    end
    for i=#choices+1,#convertPopup.rows do convertPopup.rows[i]:Hide() end
    convertChild:SetHeight(math.max(1,#choices*27))
end
convertButton:SetScript("OnClick", function()
    if convertPopup:IsShown() then convertPopup:Hide() else RefreshConvertPopup(); convertPopup:Show() end
end)

local function RefreshChart(reserve, stats)
    local interval = reserve and reserve.historyInterval or "daily"
    local rows = reserve and IRS:GetReserveHistory(reserve, interval) or {}
    chart.empty:SetShown(not reserve or #rows == 0)
    if not reserve then
        chart.targetLine:Hide(); chart.warningLine:Hide(); chart.targetLabel:Hide(); chart.warningLabel:Hide(); chart.zeroLabel:Hide()
        for _, slot in ipairs(chart.bars) do slot:Hide() end
        return
    end

    local maxValue = math.max(stats.target or 0, stats.current or 0, 1)
    for _, row in ipairs(rows) do if row.amount and row.amount > maxValue then maxValue = row.amount end end
    maxValue = math.max(1, math.ceil(maxValue * 1.08))

    chart.targetLabel:SetText("Target\n" .. FormatGold(stats.target))
    chart.warningLabel:SetText("Floor\n" .. FormatGold(stats.warning))

    local chartWidth = math.max(300, chart:GetWidth() or 820)
    local labelWidth = math.max(
        chart.targetLabel:GetStringWidth() or 0,
        chart.warningLabel:GetStringWidth() or 0
    )
    local leftInset = math.max(50, math.ceil(labelWidth) + 12)
    local rightInset, bottomInset, topInset = 15, 28, 20
    local plotWidth = math.max(200, chartWidth - leftInset - rightInset)
    local plotHeight = math.max(120, (chart:GetHeight() or 285) - bottomInset - topInset)
    local count = math.max(1, #rows)
    local slotWidth = plotWidth / count

    local targetY = bottomInset + (plotHeight * ((stats.target or 0) / maxValue))
    local warningY = bottomInset + (plotHeight * ((stats.warning or 0) / maxValue))
    chart.targetLine:ClearAllPoints(); chart.targetLine:SetPoint("BOTTOMLEFT", leftInset, targetY); chart.targetLine:SetPoint("BOTTOMRIGHT", -rightInset, targetY); chart.targetLine:Show()
    chart.warningLine:ClearAllPoints(); chart.warningLine:SetPoint("BOTTOMLEFT", leftInset, warningY); chart.warningLine:SetPoint("BOTTOMRIGHT", -rightInset, warningY); chart.warningLine:Show()
    chart.targetLabel:ClearAllPoints(); chart.targetLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", leftInset - 4, targetY - 6); chart.targetLabel:Show()
    chart.warningLabel:ClearAllPoints(); chart.warningLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", leftInset - 4, warningY - 6); chart.warningLabel:Show()
    chart.zeroLabel:ClearAllPoints(); chart.zeroLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", leftInset - 4, bottomInset - 5); chart.zeroLabel:Show()

    local labelEvery = interval == "monthly" and 1 or math.max(1, math.ceil(count / 6))
    for i=1,30 do
        local slot = chart.bars[i]
        local row = rows[i]
        if row then
            slot.row = row; slot:ClearAllPoints(); slot:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", leftInset + ((i-1)*slotWidth), 0); slot:SetWidth(slotWidth); slot:SetHeight(plotHeight + bottomInset)
            slot.bar:ClearAllPoints(); slot.bar:SetPoint("BOTTOM", slot, "BOTTOM", 0, bottomInset)
            local amount = row.amount
            if amount ~= nil then
                local height = math.max(1, plotHeight * (amount / maxValue)); slot.bar:SetHeight(height); slot.bar:SetWidth(math.max(4, math.min(24, slotWidth * 0.60)))
                local c = amount >= stats.target and COLORS.green or (amount < stats.warning and COLORS.red or COLORS.amber)
                slot.bar:SetVertexColor(unpack(c)); slot.bar:Show()
            else slot.bar:Hide() end
            slot.label:SetText(((i-1) % labelEvery == 0 or i == count) and row.label or "")
            slot:Show()
        else
            slot.row=nil; slot:Hide()
        end
    end
end

function IRS:RefreshReservesLayout()
    if not page then return end
    local width = math.max(1, page:GetWidth() or 854)
    summary:SetWidth(width - 8)
    local gap = 8
    local cardWidth = math.max(120, ((width - 8) - (gap * 3)) / 4)
    for i, card in ipairs(summary.cards) do
        card:ClearAllPoints(); card:SetPoint("TOPLEFT", summary, "TOPLEFT", (i-1)*(cardWidth+gap), 0); card:SetWidth(cardWidth); card.value:SetWidth(math.max(100,cardWidth-12))
    end
    chart:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -425)
end

function IRS:RefreshReservesPage(preserveForm)
    IRS:EnsureReserveDB()
    if IRS.CaptureDailySourceHistory then IRS:CaptureDailySourceHistory() end
    IRS:RefreshReserveStatuses(false)

    if not preserveForm and selectedReserveId then LoadReserve(selectedReserveId) end
    if not selectedReserveId then
        local rows = IRS:GetSortedReserves()
        if #rows > 0 and not preserveForm then LoadReserve(rows[1].id) end
    end

    local reserve = IRS:GetReserve(selectedReserveId)
    local stats = reserve and IRS:GetReserveStats(reserve) or nil

    SetColor(statusText, COLORS.muted)
    if reserve and stats then
        summary.cards[1].value:SetText(stats.available and FormatGold(stats.current) or "Unavailable")
        summary.cards[1].detail:SetText(stats.sourceLabel or "")
        summary.cards[2].value:SetText(FormatGold(stats.target)); summary.cards[2].detail:SetText("Maintain indefinitely")
        summary.cards[3].value:SetText(FormatGold(stats.refill)); summary.cards[3].detail:SetText("Warning floor:\n" .. FormatGold(stats.warning))
        summary.cards[4].value:SetText(stats.status); summary.cards[4].detail:SetText(stats.available and "Source observed" or "Source unavailable")
        SetColor(summary.cards[1].value, stats.available and (stats.status == "LOW RESERVE" and COLORS.red or (stats.status == "BELOW TARGET" and COLORS.amber or COLORS.green)) or COLORS.muted)
        SetColor(summary.cards[3].value, stats.refill > 0 and (stats.status == "LOW RESERVE" and COLORS.red or COLORS.amber) or COLORS.green)
        SetColor(summary.cards[4].value, StatusColor(stats.status))

        for key, button in pairs(intervalButtons) do
            local active = key == (reserve.historyInterval or "daily")
            button:SetBackdropColor(unpack(active and COLORS.panelAlt or COLORS.panel))
            button:SetBackdropBorderColor(unpack(active and COLORS.goldSoft or COLORS.borderSoft))
            SetColor(button.label, active and COLORS.gold or COLORS.text)
        end
        RefreshChart(reserve, stats)
    else
        for _, card in ipairs(summary.cards) do card.value:SetText("—"); card.detail:SetText(""); SetColor(card.value, COLORS.muted) end
        chart.empty:SetText("Create or select a Reserve Fund to view its history.")
        RefreshChart(nil, nil)
    end

    IRS:RefreshReservesLayout()
    if IRS.RefreshPageScroll and IRS.activeTab == "reserves" then IRS:RefreshPageScroll("reserves") end
end

ResetForm()
IRS:RefreshReservesLayout()
IRS:RefreshReservesPage(false)

    page._irsReservesUIBuilt = true
    return true
end

local function BuildReservesUIForStartup()
    local startupTiming = IRS:BeginStartupTiming("Reserves UI initialization")
    local built = BuildReservesUI()
    IRS:EndStartupTiming(startupTiming)
    return built
end

local reservesInitFrame = CreateFrame("Frame")
reservesInitFrame:RegisterEvent("ADDON_LOADED")
reservesInitFrame:RegisterEvent("PLAYER_LOGIN")
reservesInitFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "IncomeRecordsSystem" then return end
    if BuildReservesUIForStartup() then
        self:UnregisterAllEvents()
    end
end)

-- A zero-delay retry also handles reloads where page geometry becomes available
-- on the next UI tick. BuildReservesUI is idempotent.
if C_Timer and C_Timer.After then
    C_Timer.After(0, BuildReservesUIForStartup)
end

IRS:EndStartupTiming(_irsStartupModuleTiming)
