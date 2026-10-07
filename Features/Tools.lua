--[[
IRS — Tools
In-addon manual plus Savings Projects Allocation / Profit Distribution.
]]

local IRS = IRS
local _irsStartupModuleTiming = IRS:BeginStartupTiming("Module load: Tools")

local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.88},
    panelAlt = {0.225, 0.170, 0.112, 0.88},
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
    if IRS.GetPeriodKeys then return select(1, IRS:GetPeriodKeys()) end
    return date("%Y-%m-%d", Now())
end

local function RoundPercent(value)
    value = math.max(0, math.min(100, tonumber(value) or 0))
    return math.floor((value * 10) + 0.5) / 10
end

local function RoundDistribution(value)
    value = math.max(0, math.min(100, tonumber(value) or 0))
    return math.floor(value + 0.5)
end

local function GetAllocationProjects()
    local rows = {}
    if not IRS.GetSortedProjects then return rows end
    for _, entry in ipairs(IRS:GetSortedProjects()) do
        local project = entry.project
        if project and not project.convertedToReserveId then
            rows[#rows + 1] = {id=tostring(entry.id), objectId=entry.id, project=project}
        end
    end
    return rows
end

local function NormalizeValues(rawValues, entries, targetTotal)
    local result = {}
    targetTotal = RoundPercent(targetTotal)
    if #entries == 0 then return result end

    local rawTotal = 0
    for _, entry in ipairs(entries) do
        rawTotal = rawTotal + math.max(0, tonumber(rawValues[entry.id]) or 0)
    end
    if rawTotal <= 0 then
        for _, entry in ipairs(entries) do rawValues[entry.id] = 1 end
        rawTotal = #entries
    end

    local used = 0
    for _, entry in ipairs(entries) do
        local exact = targetTotal * (math.max(0, tonumber(rawValues[entry.id]) or 0) / rawTotal)
        local floored = math.floor((exact * 10) + 0.000001) / 10
        result[entry.id] = floored
        used = used + floored
    end

    local remainingTenths = math.floor((((targetTotal - used) * 10) + 0.5))
    local index = 1
    while remainingTenths > 0 and #entries > 0 do
        local entry = entries[index]
        result[entry.id] = RoundPercent((result[entry.id] or 0) + 0.1)
        remainingTenths = remainingTenths - 1
        index = index + 1
        if index > #entries then index = 1 end
    end
    return result
end

local function NormalizeProjectWeights(state, changedProjectId, changedValue)
    local entries = GetAllocationProjects()
    state.projectWeights = state.projectWeights or {}

    local valid = {}
    for _, entry in ipairs(entries) do valid[entry.id] = true end
    for id in pairs(state.projectWeights) do
        if not valid[tostring(id)] then state.projectWeights[id] = nil end
    end

    if #entries == 0 then return entries end
    if #entries == 1 then
        state.projectWeights[entries[1].id] = 100
        return entries
    end

    local changedId = changedProjectId and tostring(changedProjectId) or nil
    local function NormalizeWholeDistribution(rawValues, distributionEntries, targetTotal)
        local result = {}
        targetTotal = math.max(0, math.floor((tonumber(targetTotal) or 0) + 0.5))
        if #distributionEntries == 0 then return result end

        local rawTotal = 0
        for _, entry in ipairs(distributionEntries) do
            rawTotal = rawTotal + math.max(0, tonumber(rawValues[entry.id]) or 0)
        end
        if rawTotal <= 0 then
            for _, entry in ipairs(distributionEntries) do rawValues[entry.id] = 1 end
            rawTotal = #distributionEntries
        end

        local remainders = {}
        local used = 0
        for _, entry in ipairs(distributionEntries) do
            local exact = targetTotal * (math.max(0, tonumber(rawValues[entry.id]) or 0) / rawTotal)
            local whole = math.floor(exact)
            result[entry.id] = whole
            used = used + whole
            remainders[#remainders + 1] = {
                id = entry.id,
                remainder = exact - whole,
            }
        end

        table.sort(remainders, function(a, b)
            if a.remainder == b.remainder then return tostring(a.id) < tostring(b.id) end
            return a.remainder > b.remainder
        end)

        local remaining = targetTotal - used
        local index = 1
        while remaining > 0 and #remainders > 0 do
            local item = remainders[index]
            result[item.id] = (result[item.id] or 0) + 1
            remaining = remaining - 1
            index = index + 1
            if index > #remainders then index = 1 end
        end

        return result
    end

    if changedId and valid[changedId] then
        local newValue = RoundDistribution(changedValue)
        state.projectWeights[changedId] = newValue

        local others, raw = {}, {}
        for _, entry in ipairs(entries) do
            if entry.id ~= changedId then
                others[#others + 1] = entry
                raw[entry.id] = math.max(0, tonumber(state.projectWeights[entry.id]) or 0)
            end
        end
        local redistributed = NormalizeWholeDistribution(raw, others, 100 - newValue)
        for id, value in pairs(redistributed) do state.projectWeights[id] = value end
        return entries
    end

    local raw = {}
    for _, entry in ipairs(entries) do
        raw[entry.id] = math.max(0, tonumber(state.projectWeights[entry.id]) or 0)
    end
    local normalized = NormalizeWholeDistribution(raw, entries, 100)
    for id, value in pairs(normalized) do state.projectWeights[id] = value end
    return entries
end

local function BuildEffectiveSplits(state, entries)
    local projectPool = RoundPercent(100 - RoundPercent(state.reservePercent or 0))
    local raw = {}
    for _, entry in ipairs(entries) do
        raw[entry.id] = math.max(0, tonumber(state.projectWeights[entry.id]) or 0)
    end
    return NormalizeValues(raw, entries, projectPool), projectPool
end

local function ApplyEffectiveProjectAllocations(state)
    if not IRS.SetProjectAllocationPercent then return end
    local entries = NormalizeProjectWeights(state)
    local splits = BuildEffectiveSplits(state, entries)
    for _, entry in ipairs(entries) do
        IRS:SetProjectAllocationPercent(entry.objectId, splits[entry.id] or 0)
    end
end

local function EnsureToolsDB()
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.tools = IRS.db.tools or {}
    IRS.db.tools.distribution = IRS.db.tools.distribution or {}
    IRS.db.tools.distribution.history = IRS.db.tools.distribution.history or {}

    local state = IRS.db.tools.distribution
    IRS.db.migrations = IRS.db.migrations or {}
    state.projectWeights = state.projectWeights or {}
    state.reservePercent = RoundPercent(state.reservePercent or 0)

    if not IRS.db.migrations.projectAllocationPlan120 then
        local legacyWeights = state.weights or {}
        for _, entry in ipairs(GetAllocationProjects()) do
            local legacyId = "project:" .. entry.id
            local seed = legacyWeights[legacyId]
            if seed == nil then seed = tonumber(entry.project.allocationPercent) or 0 end
            state.projectWeights[entry.id] = math.max(0, tonumber(seed) or 0)
        end
        NormalizeProjectWeights(state)
        state.weights = nil
        IRS.db.migrations.projectAllocationPlan120 = Now()
    end

    NormalizeProjectWeights(state)
    ApplyEffectiveProjectAllocations(state)

    if state.baselineTotal == nil then
        local earnings = IRS:GetCurrentEarnings()
        local total = math.floor(tonumber(earnings.total) or 0)
        local today = math.floor(tonumber(earnings.today) or 0)
        state.baselineTotal = total - math.max(0, today)
        state.initializedDay = TodayKey()
        state.initializedFromToday = true
    end
    return state
end

function IRS:SyncProjectDistributionPlan()
    local state = EnsureToolsDB()
    NormalizeProjectWeights(state)
    ApplyEffectiveProjectAllocations(state)
    if IRS.RefreshProjectAllocationPage then IRS:RefreshProjectAllocationPage() end
    return true
end

function IRS:SetProjectDistributionPercent(projectId, value)
    local state = EnsureToolsDB()
    local entries = NormalizeProjectWeights(state, projectId, value)
    local found = false
    for _, entry in ipairs(entries) do
        if entry.id == tostring(projectId) then found = true; break end
    end
    if not found then return false end

    ApplyEffectiveProjectAllocations(state)
    if IRS.RefreshProjectsPage then IRS:RefreshProjectsPage(true) end
    if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    return true
end

function IRS:SetProfitDistributionWeight(goalId, value)
    local projectId = tostring(goalId or ""):match("^project:(.+)$")
    if not projectId then return false end
    return IRS:SetProjectDistributionPercent(tonumber(projectId) or projectId, value)
end

function IRS:SetProfitDistributionReservePercent(value)
    local state = EnsureToolsDB()
    value = tonumber(value)
    if not value then return false end
    state.reservePercent = RoundPercent(value)
    ApplyEffectiveProjectAllocations(state)
    if IRS.RefreshProjectsPage then IRS:RefreshProjectsPage(true) end
    if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    return true
end

function IRS:GetProfitDistributionGoals()
    local state = EnsureToolsDB()
    local entries = NormalizeProjectWeights(state)
    local splits, projectPool = BuildEffectiveSplits(state, entries)
    local rows, completed, unavailable = {}, 0, 0

    for _, entry in ipairs(entries) do
        local project = entry.project
        local stats = IRS:GetProjectStats(project)
        local available = stats and stats.available == true
        local need = stats and math.max(0, math.floor(tonumber(stats.remaining) or 0))
            or math.max(0, math.floor(tonumber(project.targetCopper) or 0))
        local isCompleted = available and need <= 0
        if isCompleted then completed = completed + 1 end
        if not available then unavailable = unavailable + 1 end

        rows[#rows + 1] = {
            id = "project:" .. entry.id,
            objectId = entry.objectId,
            kind = "PROJECT",
            name = project.name or "Savings Project",
            weight = RoundDistribution(state.projectWeights[entry.id] or 0),
            splitPercent = RoundPercent(splits[entry.id] or 0),
            need = need,
            available = available,
            completed = isCompleted,
            sourceLabel = stats and stats.sourceLabel or "Source unavailable",
        }
    end
    return rows, completed, unavailable, projectPool
end

function IRS:GetProfitDistribution()
    local state = EnsureToolsDB()
    local earnings = IRS:GetCurrentEarnings()
    local currentTotal = math.floor(tonumber(earnings.total) or 0)
    local baselineTotal = math.floor(tonumber(state.baselineTotal) or currentTotal)
    local netSince = currentTotal - baselineTotal
    local profit = math.max(0, netSince)
    local goals, completed, unavailable, projectPool = IRS:GetProfitDistributionGoals()

    local reservePercent = RoundPercent(state.reservePercent or 0)
    local reserveSuggested = math.floor(profit * (reservePercent / 100))
    local rows, distributed = {}, reserveSuggested

    for _, goal in ipairs(goals) do
        local amount = 0
        if goal.available and not goal.completed then
            amount = math.floor(profit * ((tonumber(goal.splitPercent) or 0) / 100))
            amount = math.min(goal.need, math.max(0, amount))
        end
        distributed = distributed + amount
        rows[#rows + 1] = {
            id=goal.id, objectId=goal.objectId, kind=goal.kind, name=goal.name,
            weight=goal.weight, normalizedPercent=goal.splitPercent, splitPercent=goal.splitPercent,
            need=goal.need, suggested=amount, needAfter=math.max(0, goal.need-amount),
            sourceLabel=goal.sourceLabel, available=goal.available, completed=goal.completed,
        }
    end

    return {
        baselineTotal=baselineTotal, currentTotal=currentTotal, netSince=netSince,
        availableProfit=profit, distributed=math.max(0, distributed),
        remainder=math.max(0, profit-distributed),
        totalWeight=#rows > 0 and 100 or 0,
        reservePercent=reservePercent, reserveSuggested=reserveSuggested,
        projectPoolPercent=projectPool, rows=rows,
        completedExcluded=completed, unavailableExcluded=unavailable,
        lastAllocationAt=tonumber(state.lastAllocationAt),
        initializedDay=state.initializedDay,
        initializedFromToday=state.initializedFromToday == true,
    }
end

function IRS:MarkProfitsAllocated()
    local state = EnsureToolsDB()
    local distribution = IRS:GetProfitDistribution()
    local now = Now()
    local allocationSnapshot = {}

    for _, row in ipairs(distribution.rows or {}) do
        allocationSnapshot[#allocationSnapshot + 1] = {
            id=row.id, name=row.name, kind=row.kind,
            distributionPercent=row.weight, splitPercent=row.splitPercent,
            suggestedCopper=row.suggested,
        }
    end

    table.insert(state.history, 1, {
        allocatedAt=now,
        amountCopper=math.max(0, tonumber(distribution.availableProfit) or 0),
        netSinceCopper=tonumber(distribution.netSince) or 0,
        totalRecordedCopper=tonumber(distribution.currentTotal) or 0,
        reservePercent=distribution.reservePercent,
        reserveSuggestedCopper=distribution.reserveSuggested,
        allocations=allocationSnapshot,
    })
    while #state.history > 20 do table.remove(state.history) end

    state.baselineTotal = distribution.currentTotal
    state.lastAllocationAt = now
    state.initializedFromToday = false
    return true
end

function IRS:SetToolsSection()
    if IRS.RefreshToolsPage then IRS:RefreshToolsPage() end
end


local function BuildToolsUI()
    local page = IRS.toolsPage
    local distributionView = IRS.projectAllocationView
    if not page or not distributionView then return false end
    if page._irsToolsUIBuilt then return true end

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
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=2})
    local c = color or COLORS.panelAlt
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    return frame
end

local function MakeButton(parent, text, x, y, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 30)
    button:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=2})
    button:SetBackdropColor(unpack(COLORS.panelAlt))
    button:SetBackdropBorderColor(unpack(COLORS.borderSoft))
    button.label = MakeText(button, "helper", COLORS.text, "CENTER")
    button.label:SetAllPoints()
    button.label:SetText(text)
    return button
end

local function WholeGold(copper, signed)
    copper = math.floor(tonumber(copper) or 0)
    local negative = copper < 0
    local gold = math.floor(math.abs(copper) / 10000)
    local text = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    if signed and copper > 0 then return "+" .. text .. "g" end
    if negative then return "-" .. text .. "g" end
    return text .. "g"
end

local function PercentText(value)
    return string.format("%.1f", tonumber(value) or 0):gsub("%.0$", "") .. "%"
end

local title = MakeText(page, "page", COLORS.goldSoft, "LEFT")
title:SetPoint("TOPLEFT", 4, -4)
title:SetText("TOOLS")

local subtitle = MakeText(page, "body", COLORS.muted, "LEFT")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
subtitle:SetText("Reference IRS systems and addon behavior. Savings allocation now lives under Projects > Allocation.")

local manualView = CreateFrame("Frame", nil, page)
manualView:SetPoint("TOPLEFT", 4, -55)
manualView:SetPoint("BOTTOMRIGHT", -4, 4)

local manualHeading = MakeText(manualView, "section", COLORS.goldSoft, "LEFT")
manualHeading:SetPoint("TOPLEFT", 0, 0)
manualHeading:SetText("IRS USER'S MANUAL")

local manualIntro = MakeText(manualView, "helper", COLORS.muted, "LEFT")
manualIntro:SetPoint("TOPLEFT", manualHeading, "BOTTOMLEFT", 0, -4)
manualIntro:SetText("Built-in reference for the current IRS feature set. Scroll to browse every major system.")

local manualScroll = CreateFrame("ScrollFrame", "IncomeRecordsSystemToolsManualScroll", manualView, "UIPanelScrollFrameTemplate")
manualScroll:SetPoint("TOPLEFT", 0, -48)
manualScroll:SetPoint("BOTTOMRIGHT", -24, 0)
local manualChild = CreateFrame("Frame", nil, manualScroll)
manualChild:SetSize(780, 1900)
manualScroll:SetScrollChild(manualChild)

local MANUAL_SECTIONS = {
    {
        "GETTING STARTED",
        "IRS tracks account-wide net gold while you play. Positive wallet changes are income; negative wallet changes are spending/loss. Internal transfers between your own tracked storage locations are filtered so moving gold does not masquerade as profit or loss. Use /irs to open the main window and /irs mini for the floating Mini Dashboard."
    },
    {
        "DASHBOARD",
        "Today, This Week, This Month, and Total Recorded are IRS net values. Green means positive, red means negative. The smaller line under each account total is the current character's contribution. Daily Earnings shows recent day-by-day net results. Account Overview uses Blizzard lifetime statistics where available and IRS-observed values for features Blizzard does not expose, such as tracked transmog spending."
    },
    {
        "MINI DASHBOARD",
        "The Mini Dashboard is a draggable at-a-glance panel. Its net-gold section can show the active character's daily net plus account-wide Today, This Week, This Month, and Total Recorded values; each statistic can be shown or hidden in Settings. It also shows selected Savings Projects, selected Reserve Funds, and the combined Daily Gold Target. The Daily Gold Target compares the selected Projects' combined daily requirement against the sum of those Projects' actual allocated source changes today, so the total uses the same savings progress shown by the individual rows. When WoW Token Screen alerts are enabled, an active Good/Extreme Buy or Sell zone appears as a persistent banner under the Mini Dashboard header; if the Mini Dashboard is closed when the market enters an alert zone, IRS shows a temporary splash notification instead. Savings Projects and Reserve Funds can be collapsed independently. Right-click the minimap button or use /irs mini to toggle it. Its position, size, collapse states, and per-character open state are saved, and Settings can optionally auto-open it on login."
    },
    {
        "SAVINGS PROJECTS",
        "Savings Projects now have two tabs. Project Management stores the goal itself: name, target, Start Date, Deadline, funding source, checkpoints, progress, and history. Allocation is account-wide planning: every Project has a linked whole-number Distribution % slider and the Project sliders always total 100%. Project Management no longer has an editable Allocation % field. The calculated Split % from the Allocation tab is what IRS uses when attributing a shared source balance to each Project."
    },
    {
        "PROJECT HISTORY & CHECKPOINTS",
        "The Daily tracker reads historical source balances inside the Project's Start Date to Deadline window. Trajectory compares actual allocated balance against the required path toward the target. Daily, Weekly, Monthly, and Checkpoint graph modes change how the same underlying history is presented. Custom checkpoints are named gold milestones inside the Project; they do not move gold."
    },
    {
        "RESERVE FUNDS",
        "Reserves answer: 'Can I KEEP at least X gold available indefinitely?' A Reserve has a Target, Warning Floor, Start Date, source, and Allocation %. FUNDED means current allocated gold is at or above Target. BELOW TARGET means it needs replenishment but remains above the Warning Floor. LOW RESERVE means it has fallen below the Warning Floor. Reserve History can show 30 days, 6 months, or 12 months. Completed Savings Projects can be converted to Reserves from the Reserve page."
    },
    {
        "PROFIT DISTRIBUTION CALCULATOR",
        "Profit Distribution now lives in Savings Projects > Allocation. Distribution % is each Project's share of the Project pool; moving one slider automatically redistributes the remaining percentage across the other Projects so the Project Distribution total stays exactly 100%. Reserve % is a separate manual entry taken from total profit first. Split % is the calculated effective share of total profit after that Reserve carve-out. For example, a 10% Reserve leaves a 90% Project pool, so a 75% Project Distribution becomes a 67.5% Split. Suggested gold uses Split %, caps Project suggestions at remaining need, and shows the Reserve suggestion separately. After physically moving the suggested gold, press MARK ALLOCATED to start a new profit checkpoint."
    },
    {
        "CHARACTERS",
        "Characters lists every character IRS has scanned. Tracking can be disabled per character without deleting that character's saved record. Ignored characters stop contributing new IRS earnings while their previously recorded data remains available."
    },
    {
        "REPORTS",
        "Reports can show All Characters or one character and can summarize Day, Week, Month, Best/Average, Total Recorded, lifetime source breakdowns, and a seven-day Transaction Log. The Transaction Log records each observed wallet change plus the final IRS effect and classification, including internal transfers and late transfer corrections, so unexpected profit changes can be audited. IRS history begins when IRS starts tracking; Blizzard lifetime statistics may predate IRS and are shown separately so historical lifetime totals are not confused with the forward-looking IRS ledger."
    },
    {
        "WOW TOKEN MARKET",
        "IRS samples Blizzard's current WoW Token market price while you are logged in and builds a local rolling history. Good Buy alerts mean the Token is unusually cheap relative to its rolling average; Good Sell alerts mean unusually high. You can configure check interval, average window, thresholds, chat/screen alerts, and the alert sound in Settings > WoW Token."
    },
    {
        "INTERNAL TRANSFERS & OWNED STORAGE",
        "Character <-> Warband Bank transfers are treated as internal automatically. Guild Banks can be designated as owned storage under Settings > Transfers. While an owned Guild Bank is open, IRS matches wallet and Guild Bank balance changes in either event order so deposits and withdrawals are not filed as income/loss. Guild Banks used by Savings Projects default to internal storage unless explicitly disabled."
    },
    {
        "SOURCES & GUILD BANKS",
        "Account Liquid Gold uses last-known character wallets plus the Warband Bank and excludes Guild Banks. Warband Bank uses Blizzard's account-bank balance. Character uses the selected character wallet. Guild Bank uses the last valid balance IRS observed for the chosen guild; opening the Guild Bank refreshes its cache. If a source has never been observed, IRS reports it as unavailable rather than inventing a value."
    },
    {
        "SETTINGS & RESIZING",
        "Settings contains Toggles, Mini Dashboard, WoW Token, Transfers, and Fonts. Main and Mini font styles are independently editable. Both IRS windows can be unlocked and resized; their sizes and lock states persist. Main pages scroll when their content is taller than the window."
    },
    {
        "SLASH COMMANDS",
        "/irs — toggle IRS\n/irs mini — toggle Mini Dashboard\n/irs projects — Savings Projects\n/irs reserves — Reserve Funds\n/irs tools — Tools\n/irs chars — Characters\n/irs reports — Reports\n/irs settings — Settings\n/irs help — command help\n/irs scan — rescan current character\n/irs status — print current IRS net totals"
    },
    {
        "IMPORTANT LIMITATIONS",
        "IRS can only observe data Blizzard exposes while your account is logged in. It cannot reconstruct a Guild Bank balance from before IRS observed it, and it cannot physically protect or move gold. Project/Reserve allocations are planning/accounting rules. Profit Distribution is also advisory: you perform the transfers, then press MARK ALLOCATED to save the new profit checkpoint."
    },
}

local manualWidgets = {}
for _, section in ipairs(MANUAL_SECTIONS) do
    local heading = MakeText(manualChild, "label", COLORS.goldSoft, "LEFT")
    heading:SetText(section[1])
    local body = MakeText(manualChild, "body", COLORS.text, "LEFT")
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(false)
    body:SetText(section[2])
    manualWidgets[#manualWidgets + 1] = {heading=heading, body=body}
end

local function LayoutManual()
    local width = math.max(420, (manualScroll:GetWidth() or 800) - 18)
    manualChild:SetWidth(width)
    local y = 0
    for _, widget in ipairs(manualWidgets) do
        widget.heading:ClearAllPoints()
        widget.heading:SetPoint("TOPLEFT", manualChild, "TOPLEFT", 4, -y)
        widget.heading:SetWidth(width - 8)
        y = y + math.max(20, IRS:GetFontSize("main", "label") + 7)
        widget.body:ClearAllPoints()
        widget.body:SetPoint("TOPLEFT", manualChild, "TOPLEFT", 4, -y)
        widget.body:SetWidth(width - 8)
        local h = math.max(18, widget.body:GetStringHeight() or 18)
        y = y + h + 19
    end
    manualChild:SetHeight(math.max(1, y + 6))
end

local distHeading = MakeText(distributionView, "section", COLORS.goldSoft, "LEFT")
distHeading:SetPoint("TOPLEFT", 0, 0)
distHeading:SetText("PROJECT ALLOCATION")

local distNote = MakeText(distributionView, "helper", COLORS.muted, "LEFT")
distNote:SetPoint("TOPLEFT", distHeading, "BOTTOMLEFT", 0, -4)
distNote:SetPoint("TOPRIGHT", -4, 0)
distNote:SetWordWrap(true)
distNote:SetText("Each Project has its own linked whole-number Distribution slider. Project Distribution always totals 100%. Reserve % is removed from total profit first; Split % is each Project's effective share after that reserve carve-out.")

local summary = MakePanel(distributionView, COLORS.panel)
summary:SetPoint("TOPLEFT", 0, -58)
summary:SetPoint("TOPRIGHT", 0, -58)
summary:SetHeight(112)

local lastLabel = MakeText(summary, "helper", COLORS.goldSoft, "LEFT")
lastLabel:SetPoint("TOPLEFT", 12, -10); lastLabel:SetText("LAST ALLOCATION")
local lastValue = MakeText(summary, "body", COLORS.text, "LEFT")
lastValue:SetPoint("TOPLEFT", lastLabel, "BOTTOMLEFT", 0, -5)
local netLabel = MakeText(summary, "helper", COLORS.goldSoft, "CENTER")
netLabel:SetPoint("TOP", 0, -10); netLabel:SetText("NET SINCE LAST ALLOCATION")
local netValue = MakeText(summary, "value", COLORS.text, "CENTER")
netValue:SetPoint("TOP", netLabel, "BOTTOM", 0, -3)
local availableLabel = MakeText(summary, "helper", COLORS.goldSoft, "RIGHT")
availableLabel:SetPoint("TOPRIGHT", -12, -10); availableLabel:SetText("AVAILABLE TO DISTRIBUTE")
local availableValue = MakeText(summary, "value", COLORS.green, "RIGHT")
availableValue:SetPoint("TOPRIGHT", availableLabel, "BOTTOMRIGHT", 0, -3)

local checkpoint = MakeButton(summary, "MARK ALLOCATED", 8, -76, 145)
local checkpointHint = MakeText(summary, "helper", COLORS.muted, "LEFT")
checkpointHint:SetPoint("LEFT", checkpoint, "RIGHT", 10, 0)
checkpointHint:SetPoint("RIGHT", summary, "RIGHT", -10, 0)
checkpointHint:SetText("After moving the suggested gold, save this point. Only later net profit accumulates for the next distribution.")

local tableHeader = MakePanel(distributionView, COLORS.panelAlt)
tableHeader:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -12)
tableHeader:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", -22, -12)
tableHeader:SetHeight(30)

local headerGoal = MakeText(tableHeader, "helper", COLORS.goldSoft, "LEFT")
local headerDestination = MakeText(tableHeader, "helper", COLORS.goldSoft, "LEFT")
local headerWeight = MakeText(tableHeader, "helper", COLORS.goldSoft, "CENTER")
local headerShare = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
local headerSuggested = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
local headerNeed = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
headerGoal:SetText("PROJECT"); headerDestination:SetText("ALLOCATE TO"); headerWeight:SetText("DISTRIBUTION %")
headerShare:SetText("SPLIT %"); headerSuggested:SetText("SUGGESTED"); headerNeed:SetText("NEED AFTER")

local listScroll = CreateFrame("ScrollFrame", "IncomeRecordsSystemDistributionScroll", distributionView, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -2)
listScroll:SetPoint("TOPRIGHT", tableHeader, "BOTTOMRIGHT", -22, -2)
listScroll:SetHeight(235)
local listChild = CreateFrame("Frame", nil, listScroll)
listChild:SetSize(780, 1)
listScroll:SetScrollChild(listChild)

local distRows = {}
local function EnsureDistRow(index)
    if distRows[index] then return distRows[index] end
    local row = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
    row:SetHeight(42)
    row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
    row:SetBackdropColor(COLORS.panel[1],COLORS.panel[2],COLORS.panel[3],0.50)
    row:SetBackdropBorderColor(COLORS.borderSoft[1],COLORS.borderSoft[2],COLORS.borderSoft[3],0.55)
    row.goal = MakeText(row, "body", COLORS.text, "LEFT")
    row.destination = MakeText(row, "helper", COLORS.muted, "LEFT")

    local sliderName = "IncomeRecordsSystemProjectDistributionSlider" .. tostring(index)
    row.slider = CreateFrame("Slider", sliderName, row, "OptionsSliderTemplate")
    row.slider:SetMinMaxValues(0,100)
    row.slider:SetValueStep(1)
    if row.slider.SetObeyStepOnDrag then row.slider:SetObeyStepOnDrag(true) end
    local low=_G[sliderName.."Low"]; if low then low:SetText("") end
    local high=_G[sliderName.."High"]; if high then high:SetText("") end
    local sliderText=_G[sliderName.."Text"]; if sliderText then sliderText:SetText("") end

    row.sliderValue = MakeText(row, "helper", COLORS.goldSoft, "RIGHT")
    row.share = MakeText(row, "body", COLORS.text, "RIGHT")
    row.suggested = MakeText(row, "body", COLORS.gold, "RIGHT")
    row.need = MakeText(row, "body", COLORS.muted, "RIGHT")

    row.slider:SetScript("OnValueChanged", function(self, value)
        local wholeValue = RoundDistribution(value)
        row.sliderValue:SetText(string.format("%d%%", wholeValue))
        if not row._refreshing then row._pendingWeight=wholeValue end
    end)
    row.slider:SetScript("OnMouseUp", function()
        if not row.data or row._refreshing then return end
        local value=row._pendingWeight or row.slider:GetValue()
        row._pendingWeight=nil
        if IRS:SetProfitDistributionWeight(row.data.id,value) then IRS:RefreshProjectAllocationPage() end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText(self.data.name or "Savings Project")
        GameTooltip:AddLine("Distribution: "..PercentText(self.data.weight),0.88,0.84,0.75)
        GameTooltip:AddLine("Split of total profit: "..PercentText(self.data.splitPercent),0.88,0.84,0.75)
        GameTooltip:AddLine("Suggested: "..WholeGold(self.data.suggested or 0),0.86,0.71,0.36)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    distRows[index]=row
    return row
end

local emptyText=MakeText(listChild,"body",COLORS.muted,"CENTER")
emptyText:SetPoint("TOPLEFT",0,-28)
emptyText:SetWidth(760)
emptyText:SetText("No Savings Projects yet. Create one in Project Management.")

local reservePanel=MakePanel(distributionView,COLORS.panelAlt)
reservePanel:SetPoint("TOPLEFT",listScroll,"BOTTOMLEFT",0,-10)
reservePanel:SetPoint("TOPRIGHT",tableHeader,"BOTTOMRIGHT",0,-10)
reservePanel:SetHeight(68)

local reserveTitle=MakeText(reservePanel,"body",COLORS.goldSoft,"LEFT")
reserveTitle:SetPoint("TOPLEFT",10,-9); reserveTitle:SetText("RESERVES")
local reserveDetail=MakeText(reservePanel,"helper",COLORS.muted,"LEFT")
reserveDetail:SetPoint("TOPLEFT",reserveTitle,"BOTTOMLEFT",0,-4)
reserveDetail:SetText("Manual share of total profit set aside for Reserve Funds before Project Distribution is applied.")
local reservePercentLabel=MakeText(reservePanel,"helper",COLORS.goldSoft,"RIGHT")
reservePercentLabel:SetPoint("RIGHT",-250,10); reservePercentLabel:SetText("RESERVE %")
local reserveInput=CreateFrame("EditBox",nil,reservePanel,"InputBoxTemplate")
reserveInput:SetSize(62,24); reserveInput:SetPoint("LEFT",reservePercentLabel,"RIGHT",8,0)
reserveInput:SetAutoFocus(false); reserveInput:SetJustifyH("RIGHT"); reserveInput:SetFontObject(GameFontHighlightSmall)
reserveInput:SetMaxLetters(5); reserveInput:SetNumeric(false)
local reserveSplit=MakeText(reservePanel,"body",COLORS.text,"RIGHT")
reserveSplit:SetPoint("RIGHT",-105,10); reserveSplit:SetWidth(72)
local reserveSuggested=MakeText(reservePanel,"body",COLORS.gold,"RIGHT")
reserveSuggested:SetPoint("RIGHT",-10,10); reserveSuggested:SetWidth(92)

local footerLine=MakeText(distributionView,"body",COLORS.text,"LEFT")
footerLine:SetPoint("TOPLEFT",reservePanel,"BOTTOMLEFT",0,-10); footerLine:SetPoint("TOPRIGHT",-4,-10)
local footerHint=MakeText(distributionView,"helper",COLORS.muted,"LEFT")
footerHint:SetPoint("TOPLEFT",footerLine,"BOTTOMLEFT",0,-5); footerHint:SetPoint("TOPRIGHT",-4,-5); footerHint:SetWordWrap(true)

local function CommitReservePercent(self)
    local raw=tostring(self:GetText() or ""):gsub("%%","")
    local value=tonumber(raw)
    if value and IRS:SetProfitDistributionReservePercent(value) then
        self:ClearFocus(); IRS:RefreshProjectAllocationPage()
    else
        local data=IRS:GetProfitDistribution()
        self:SetText(string.format("%.1f",data.reservePercent or 0):gsub("%.0$",""))
        self:ClearFocus()
    end
end
reserveInput:SetScript("OnEnterPressed",CommitReservePercent)
reserveInput:SetScript("OnEditFocusLost",function(self) if self:GetText()~="" then CommitReservePercent(self) end end)

local function LayoutDistributionColumns()
    local width=math.max(680,tableHeader:GetWidth() or 780)
    local childW=math.max(680,(listScroll:GetWidth() or width)-2)
    width=math.min(width,childW)
    local usable=math.max(650,width-20)
    local goalW=math.max(135,math.floor(usable*0.19))
    local destinationW=math.max(120,math.floor(usable*0.17))
    local weightW=175
    local shareW=72
    local suggestW=102
    local needW=math.max(95,usable-goalW-destinationW-weightW-shareW-suggestW)

    local x=10
    headerGoal:ClearAllPoints(); headerGoal:SetPoint("LEFT",x,0); headerGoal:SetWidth(goalW); x=x+goalW
    headerDestination:ClearAllPoints(); headerDestination:SetPoint("LEFT",x,0); headerDestination:SetWidth(destinationW); x=x+destinationW
    headerWeight:ClearAllPoints(); headerWeight:SetPoint("LEFT",x,0); headerWeight:SetWidth(weightW); x=x+weightW
    headerShare:ClearAllPoints(); headerShare:SetPoint("LEFT",x,0); headerShare:SetWidth(shareW); x=x+shareW
    headerSuggested:ClearAllPoints(); headerSuggested:SetPoint("LEFT",x,0); headerSuggested:SetWidth(suggestW); x=x+suggestW
    headerNeed:ClearAllPoints(); headerNeed:SetPoint("LEFT",x,0); headerNeed:SetWidth(needW)

    listChild:SetWidth(width); emptyText:SetWidth(width)
    for _,row in ipairs(distRows) do
        row:SetWidth(width)
        local rx=10
        row.goal:ClearAllPoints(); row.goal:SetPoint("LEFT",rx,0); row.goal:SetWidth(goalW); rx=rx+goalW
        row.destination:ClearAllPoints(); row.destination:SetPoint("LEFT",rx,0); row.destination:SetWidth(destinationW); rx=rx+destinationW
        row.slider:ClearAllPoints(); row.slider:SetPoint("LEFT",rx+4,0); row.slider:SetWidth(math.max(88,weightW-54))
        row.sliderValue:ClearAllPoints(); row.sliderValue:SetPoint("LEFT",rx+weightW-48,0); row.sliderValue:SetWidth(44); rx=rx+weightW
        row.share:ClearAllPoints(); row.share:SetPoint("LEFT",rx,0); row.share:SetWidth(shareW); rx=rx+shareW
        row.suggested:ClearAllPoints(); row.suggested:SetPoint("LEFT",rx,0); row.suggested:SetWidth(suggestW); rx=rx+suggestW
        row.need:ClearAllPoints(); row.need:SetPoint("LEFT",rx,0); row.need:SetWidth(needW)
    end
end

local checkpointHover=false
local checkpointAppearanceRefreshing=false
local function RefreshCheckpointAppearance()
    if checkpointAppearanceRefreshing then return end
    checkpointAppearanceRefreshing=true
    local data=IRS:GetProfitDistribution()
    local enabled=(tonumber(data.availableProfit) or 0)>0
    if enabled then
        if not checkpoint:IsEnabled() then checkpoint:Enable() end
        if checkpointHover then
            checkpoint:SetBackdropColor(0.285,0.215,0.135,0.98)
            checkpoint:SetBackdropBorderColor(unpack(COLORS.gold))
            SetColor(checkpoint.label,COLORS.gold)
        else
            checkpoint:SetBackdropColor(unpack(COLORS.panelAlt))
            checkpoint:SetBackdropBorderColor(unpack(COLORS.borderSoft))
            SetColor(checkpoint.label,COLORS.text)
        end
    else
        if checkpoint:IsEnabled() then checkpoint:Disable() end
        checkpoint:SetBackdropColor(COLORS.panel[1],COLORS.panel[2],COLORS.panel[3],0.55)
        checkpoint:SetBackdropBorderColor(COLORS.borderSoft[1],COLORS.borderSoft[2],COLORS.borderSoft[3],0.55)
        SetColor(checkpoint.label,COLORS.muted)
    end
    checkpointAppearanceRefreshing=false
end

checkpoint:SetScript("OnEnter",function() checkpointHover=true; RefreshCheckpointAppearance() end)
checkpoint:SetScript("OnLeave",function() checkpointHover=false; RefreshCheckpointAppearance() end)
checkpoint:SetScript("OnMouseDown",function(self) if self:IsEnabled() then self:SetBackdropColor(0.32,0.24,0.145,1) end end)
checkpoint:SetScript("OnMouseUp",RefreshCheckpointAppearance)
checkpoint:SetScript("OnClick",function()
    local data=IRS:GetProfitDistribution()
    if (tonumber(data.availableProfit) or 0)<=0 then return end
    IRS:MarkProfitsAllocated()
    IRS:RefreshProjectAllocationPage()
end)

function IRS:RefreshToolsLayout()
    LayoutManual()
    LayoutDistributionColumns()
end

function IRS:RefreshToolsPage()
    EnsureToolsDB()
    LayoutManual()
end

function IRS:RefreshProjectAllocationPage()
    EnsureToolsDB()
    local data=IRS:GetProfitDistribution()

    if data.lastAllocationAt then
        lastValue:SetText(date("%b %d, %Y  %I:%M %p",data.lastAllocationAt))
    elseif data.initializedFromToday then
        lastValue:SetText("Start of today (first use)")
    else
        lastValue:SetText("No checkpoint recorded")
    end

    netValue:SetText(WholeGold(data.netSince,true))
    if data.netSince>0 then SetColor(netValue,COLORS.green)
    elseif data.netSince<0 then SetColor(netValue,COLORS.red)
    else SetColor(netValue,COLORS.muted) end

    availableValue:SetText(WholeGold(data.availableProfit))
    SetColor(availableValue,data.availableProfit>0 and COLORS.green or COLORS.muted)
    RefreshCheckpointAppearance()

    for i,item in ipairs(data.rows) do
        local row=EnsureDistRow(i)
        row.data=item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",listChild,"TOPLEFT",0,-((i-1)*44))
        local suffix=""
        if item.completed then suffix="  |cff6e995cCOMPLETE|r"
        elseif not item.available then suffix="  |cff9e4a40UNAVAILABLE|r" end
        row.goal:SetText((item.name or "Savings Project")..suffix)
        row.destination:SetText(item.sourceLabel or "Unknown source")
        row._refreshing=true
        row.slider:SetValue(item.weight or 0)
        row.sliderValue:SetText(string.format("%d%%", RoundDistribution(item.weight or 0)))
        row._refreshing=false
        row._pendingWeight=nil
        row.slider:SetEnabled(#data.rows>1)
        row.share:SetText(PercentText(item.splitPercent or 0))
        row.suggested:SetText(WholeGold(item.suggested or 0))
        row.need:SetText(WholeGold(item.needAfter or 0))
        row:Show()
    end
    for i=#data.rows+1,#distRows do distRows[i]:Hide(); distRows[i].data=nil end
    emptyText:SetShown(#data.rows==0)
    listChild:SetHeight(math.max(235,(#data.rows*44)+4))

    if not reserveInput:HasFocus() then
        reserveInput:SetText(string.format("%.1f",data.reservePercent or 0):gsub("%.0$",""))
    end
    reserveSplit:SetText("Split "..PercentText(data.reservePercent or 0))
    reserveSuggested:SetText(WholeGold(data.reserveSuggested or 0))

    footerLine:SetText(string.format(
        "Suggested total: %s    •    Unallocated remainder: %s",
        WholeGold(data.distributed),WholeGold(data.remainder)
    ))
    footerHint:SetText(string.format(
        "Project Distribution: %.1f%% of the Project pool • Project pool: %.1f%% of total • Reserves: %.1f%% of total. Split %% is the effective total-profit share after Reserves. Completed or unavailable Projects keep their configured Distribution share but receive a 0g suggestion until adjusted.",
        data.totalWeight or 0,data.projectPoolPercent or 0,data.reservePercent or 0
    ))
    LayoutDistributionColumns()
end

IRS:RefreshToolsLayout()
IRS:RefreshToolsPage()
IRS:RefreshProjectAllocationPage()
page._irsToolsUIBuilt=true
return true
end

local function BuildToolsUIForStartup()
    local startupTiming = IRS:BeginStartupTiming("Tools UI initialization")
    local built = BuildToolsUI()
    IRS:EndStartupTiming(startupTiming)
    return built
end

local toolsInitFrame = CreateFrame("Frame")
toolsInitFrame:RegisterEvent("ADDON_LOADED")
toolsInitFrame:RegisterEvent("PLAYER_LOGIN")
toolsInitFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "IncomeRecordsSystem" then return end
    if BuildToolsUIForStartup() then
        self:UnregisterAllEvents()
    end
end)

-- A zero-delay retry also handles reloads where page geometry becomes available
-- on the next UI tick. BuildToolsUI is idempotent.
if C_Timer and C_Timer.After then
    C_Timer.After(0, BuildToolsUIForStartup)
end

IRS:EndStartupTiming(_irsStartupModuleTiming)
