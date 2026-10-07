--[[
IRS — Tools
In-addon manual and Profit Distribution Calculator.
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

local function EnsureToolsDB()
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.tools = IRS.db.tools or {}
    IRS.db.tools.distribution = IRS.db.tools.distribution or {}
    IRS.db.tools.distribution.history = IRS.db.tools.distribution.history or {}
    IRS.db.tools.distribution.weights = IRS.db.tools.distribution.weights or {}
    IRS.db.ui = IRS.db.ui or {}
    IRS.db.ui.toolsSection = IRS.db.ui.toolsSection or "manual"

    local state = IRS.db.tools.distribution
    if state.baselineTotal == nil then
        local earnings = IRS:GetCurrentEarnings()
        local total = math.floor(tonumber(earnings.total) or 0)
        local today = math.floor(tonumber(earnings.today) or 0)

        -- First use starts with today's positive net profit available. Historical
        -- IRS totals before today are treated as already handled rather than
        -- suddenly becoming a giant distribution obligation after upgrading.
        state.baselineTotal = total - math.max(0, today)
        state.initializedDay = TodayKey()
        state.initializedFromToday = true
    end

    return state
end

function IRS:GetProfitDistributionGoals()
    local state = EnsureToolsDB()
    local rows = {}
    local completed = 0
    local unavailable = 0

    if IRS.GetSortedProjects then
        for _, entry in ipairs(IRS:GetSortedProjects()) do
            local project = entry.project
            if project and not project.convertedToReserveId then
                local stats = IRS:GetProjectStats(project)
                if not stats or not stats.available then
                    unavailable = unavailable + 1
                elseif (tonumber(stats.remaining) or 0) > 0 then
                    local goalId = "project:" .. tostring(entry.id)
                    local defaultWeight = math.max(0, tonumber(project.allocationPercent) or 0)
                    local savedWeight = state.weights[goalId]
                    table.insert(rows, {
                        id = goalId,
                        objectId = entry.id,
                        kind = "PROJECT",
                        name = project.name or "Savings Project",
                        weight = savedWeight ~= nil and math.max(0, tonumber(savedWeight) or 0) or defaultWeight,
                        defaultWeight = defaultWeight,
                        need = math.max(0, math.floor(tonumber(stats.remaining) or 0)),
                        sourceLabel = stats.sourceLabel or "Unknown Source",
                    })
                else
                    completed = completed + 1
                end
            end
        end
    end

    if IRS.GetSortedReserves then
        for _, entry in ipairs(IRS:GetSortedReserves()) do
            local reserve = entry.reserve
            local stats = reserve and IRS:GetReserveStats(reserve) or nil
            if not stats or not stats.available then
                unavailable = unavailable + 1
            elseif (tonumber(stats.refill) or 0) > 0 then
                local goalId = "reserve:" .. tostring(entry.id)
                local defaultWeight = math.max(0, tonumber(reserve.allocationPercent) or 0)
                local savedWeight = state.weights[goalId]
                table.insert(rows, {
                    id = goalId,
                    objectId = entry.id,
                    kind = "RESERVE",
                    name = reserve.name or "Reserve Fund",
                    weight = savedWeight ~= nil and math.max(0, tonumber(savedWeight) or 0) or defaultWeight,
                    defaultWeight = defaultWeight,
                    need = math.max(0, math.floor(tonumber(stats.refill) or 0)),
                    sourceLabel = stats.sourceLabel or "Unknown Source",
                })
            else
                completed = completed + 1
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.kind == b.kind then return tostring(a.name) < tostring(b.name) end
        return a.kind < b.kind
    end)

    return rows, completed, unavailable
end

local function AllocateWithCaps(totalCopper, goals)
    totalCopper = math.max(0, math.floor(tonumber(totalCopper) or 0))
    local result = {}
    local active = {}

    for i, goal in ipairs(goals or {}) do
        result[i] = 0
        if (tonumber(goal.weight) or 0) > 0 and (tonumber(goal.need) or 0) > 0 then
            active[#active + 1] = i
        end
    end

    local remaining = totalCopper
    local guard = 0
    while remaining > 0 and #active > 0 and guard < 100 do
        guard = guard + 1
        local totalWeight = 0
        for _, index in ipairs(active) do
            totalWeight = totalWeight + math.max(0, tonumber(goals[index].weight) or 0)
        end
        if totalWeight <= 0 then break end

        local proposals = {}
        local used = 0
        for _, index in ipairs(active) do
            local goal = goals[index]
            local needLeft = math.max(0, math.floor((tonumber(goal.need) or 0) - (result[index] or 0)))
            local exact = remaining * (math.max(0, tonumber(goal.weight) or 0) / totalWeight)
            local share = math.min(needLeft, math.floor(exact))
            proposals[#proposals + 1] = {
                index = index,
                amount = share,
                fraction = exact - math.floor(exact),
            }
            used = used + share
        end

        -- Integer copper rounding can leave a few copper undistributed. Hand
        -- those to the largest fractional remainders before recalculating.
        local roundLeft = remaining - used
        if roundLeft > 0 then
            table.sort(proposals, function(a, b)
                if a.fraction == b.fraction then return a.index < b.index end
                return a.fraction > b.fraction
            end)
            for _, proposal in ipairs(proposals) do
                if roundLeft <= 0 then break end
                local needLeft = math.max(0, math.floor((tonumber(goals[proposal.index].need) or 0)
                    - (result[proposal.index] or 0) - proposal.amount))
                if needLeft > 0 then
                    proposal.amount = proposal.amount + 1
                    used = used + 1
                    roundLeft = roundLeft - 1
                end
            end
        end

        if used <= 0 then break end

        for _, proposal in ipairs(proposals) do
            result[proposal.index] = (result[proposal.index] or 0) + proposal.amount
        end
        remaining = math.max(0, remaining - used)

        local nextActive = {}
        for _, index in ipairs(active) do
            if (result[index] or 0) < math.max(0, tonumber(goals[index].need) or 0) then
                nextActive[#nextActive + 1] = index
            end
        end
        active = nextActive
    end

    return result, remaining
end

function IRS:SetProfitDistributionWeight(goalId, value)
    local state = EnsureToolsDB()
    goalId = tostring(goalId or "")
    if goalId == "" then return false end

    value = tonumber(value)
    if not value then return false end
    value = math.max(0, math.min(100, value))
    -- Keep one decimal place so users can use values like 12.5% without
    -- accumulating floating-point noise in SavedVariables.
    value = math.floor((value * 10) + 0.5) / 10
    state.weights[goalId] = value
    return true
end

function IRS:GetProfitDistribution()
    local state = EnsureToolsDB()
    local earnings = IRS:GetCurrentEarnings()
    local currentTotal = math.floor(tonumber(earnings.total) or 0)
    local baselineTotal = math.floor(tonumber(state.baselineTotal) or currentTotal)
    local netSince = currentTotal - baselineTotal
    local profit = math.max(0, netSince)
    local goals, completed, unavailable = IRS:GetProfitDistributionGoals()

    local totalWeight = 0
    for _, goal in ipairs(goals) do totalWeight = totalWeight + math.max(0, tonumber(goal.weight) or 0) end

    local allocations, remainder = AllocateWithCaps(profit, goals)
    local rows = {}
    local distributed = 0
    for i, goal in ipairs(goals) do
        local amount = math.max(0, math.floor(tonumber(allocations[i]) or 0))
        distributed = distributed + amount
        rows[#rows + 1] = {
            id = goal.id,
            kind = goal.kind,
            name = goal.name,
            weight = goal.weight,
            defaultWeight = goal.defaultWeight,
            normalizedPercent = totalWeight > 0 and ((goal.weight / totalWeight) * 100) or 0,
            need = goal.need,
            suggested = amount,
            needAfter = math.max(0, goal.need - amount),
            sourceLabel = goal.sourceLabel,
        }
    end

    return {
        baselineTotal = baselineTotal,
        currentTotal = currentTotal,
        netSince = netSince,
        availableProfit = profit,
        distributed = distributed,
        remainder = math.max(0, remainder),
        totalWeight = totalWeight,
        rows = rows,
        completedExcluded = completed,
        unavailableExcluded = unavailable,
        lastAllocationAt = tonumber(state.lastAllocationAt),
        initializedDay = state.initializedDay,
        initializedFromToday = state.initializedFromToday == true,
    }
end

function IRS:MarkProfitsAllocated()
    local state = EnsureToolsDB()
    local distribution = IRS:GetProfitDistribution()
    local now = Now()

    local allocationSnapshot = {}
    for _, row in ipairs(distribution.rows or {}) do
        allocationSnapshot[#allocationSnapshot + 1] = {
            id = row.id,
            name = row.name,
            kind = row.kind,
            weight = row.weight,
            normalizedPercent = row.normalizedPercent,
            suggestedCopper = row.suggested,
        }
    end

    table.insert(state.history, 1, {
        allocatedAt = now,
        amountCopper = math.max(0, tonumber(distribution.availableProfit) or 0),
        netSinceCopper = tonumber(distribution.netSince) or 0,
        totalRecordedCopper = tonumber(distribution.currentTotal) or 0,
        allocations = allocationSnapshot,
    })
    while #state.history > 20 do table.remove(state.history) end

    state.baselineTotal = distribution.currentTotal
    state.lastAllocationAt = now
    state.initializedFromToday = false
    return true
end

function IRS:SetToolsSection(section)
    EnsureToolsDB()
    section = section == "distribution" and "distribution" or "manual"
    IRS.db.ui.toolsSection = section
    if IRS.RefreshToolsPage then IRS:RefreshToolsPage() end
end

-- Logic above can be smoke-tested without loading WoW UI objects. The visual
-- tree is deliberately deferred until the addon's shared page containers and
-- scrolling wrappers are finished loading.
local function BuildToolsUI()
    local page = IRS.toolsPage
    if not page then return false end
    if page._irsToolsUIBuilt then return true end

-- ---------------------------------------------------------------------------
-- UI HELPERS
-- ---------------------------------------------------------------------------

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

local function MakeButton(parent, text, x, y, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 30)
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

local title = MakeText(page, "page", COLORS.goldSoft, "LEFT")
title:SetPoint("TOPLEFT", 4, -4)
title:SetText("TOOLS")

local subtitle = MakeText(page, "body", COLORS.muted, "LEFT")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
subtitle:SetText("Reference IRS systems or calculate how unallocated net profit should be divided among active goals.")

local manualTab = MakeButton(page, "USER'S MANUAL", 4, -55, 150)
local distributionTab = MakeButton(page, "PROFIT DISTRIBUTION", 164, -55, 180)

local manualView = CreateFrame("Frame", nil, page)
manualView:SetPoint("TOPLEFT", 4, -96)
manualView:SetPoint("BOTTOMRIGHT", -4, 4)

local distributionView = CreateFrame("Frame", nil, page)
distributionView:SetPoint("TOPLEFT", 4, -96)
distributionView:SetPoint("BOTTOMRIGHT", -4, 4)

-- ---------------------------------------------------------------------------
-- USER MANUAL
-- ---------------------------------------------------------------------------
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
        "The Mini Dashboard is a draggable at-a-glance panel. Its net-gold section can show the active character's daily net plus account-wide Today, This Week, This Month, and Total Recorded values; each statistic can be shown or hidden in Settings. It also shows selected Savings Projects, selected Reserve Funds, and the combined Daily Gold Target. The Daily Gold Target compares the selected Projects' combined daily requirement against today's account-wide net income, so earnings count regardless of where the gold is currently stored. When WoW Token Screen alerts are enabled, an active Good/Extreme Buy or Sell zone appears as a persistent banner under the Mini Dashboard header; if the Mini Dashboard is closed when the market enters an alert zone, IRS shows a temporary splash notification instead. Savings Projects and Reserve Funds can be collapsed independently. Right-click the minimap button or use /irs mini to toggle it. Its position, size, collapse states, and per-character open state are saved, and Settings can optionally auto-open it on login."
    },
    {
        "SAVINGS PROJECTS",
        "Projects answer: 'Can I reach X gold by Y date?' Set a name, target, Start Date, Deadline, source, and Allocation %. Current Allocated is the selected source balance multiplied by Allocation %. Daily Needed is based on remaining gold and remaining days. Project history is read from IRS's central source history, so editing a Project no longer deletes financial observations. Source/allocation changes are dated configuration changes rather than rewritten history."
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
        "The calculator uses IRS net profit accumulated since the last manual allocation checkpoint. Each eligible goal has an editable Distribution % used only by this calculator; new goals initially inherit their Project or Reserve Allocation %, but changing the calculator value does not rewrite the goal. IRS normalizes those Distribution % values as a whole, then suggests how much of the available profit goes to each. Suggestions are capped at each goal's remaining need; excess stays Unallocated. After physically moving the suggested gold, press MARK ALLOCATED. IRS records the current Total Recorded value as the new checkpoint and immediately begins accumulating only later net profit. Internal transfers do not change the profit pool."
    },
    {
        "CHARACTERS",
        "Characters lists every character IRS has scanned. Tracking can be disabled per character without deleting that character's saved record. Ignored characters stop contributing new IRS earnings while their previously recorded data remains available."
    },
    {
        "REPORTS",
        "Reports can show All Characters or one character and can summarize Day, Week, Month, Best/Average, Total Recorded, and lifetime source breakdowns. IRS history begins when IRS starts tracking; Blizzard lifetime statistics may predate IRS and are shown separately so historical lifetime totals are not confused with the forward-looking IRS ledger."
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
    manualWidgets[#manualWidgets + 1] = {heading = heading, body = body}
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

-- ---------------------------------------------------------------------------
-- PROFIT DISTRIBUTION
-- ---------------------------------------------------------------------------
local distHeading = MakeText(distributionView, "section", COLORS.goldSoft, "LEFT")
distHeading:SetPoint("TOPLEFT", 0, 0)
distHeading:SetText("PROFIT DISTRIBUTION CALCULATOR")

local distNote = MakeText(distributionView, "helper", COLORS.muted, "LEFT")
distNote:SetPoint("TOPLEFT", distHeading, "BOTTOMLEFT", 0, -4)
distNote:SetPoint("TOPRIGHT", -4, 0)
distNote:SetWordWrap(true)
distNote:SetText("Splits positive IRS NET profit since the last allocation checkpoint. Edit Distribution % here without changing the Project/Reserve itself; eligible values are normalized as a whole.")

local summary = MakePanel(distributionView, COLORS.panel)
summary:SetPoint("TOPLEFT", 0, -64)
summary:SetPoint("TOPRIGHT", 0, -64)
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
checkpointHint:SetText("After moving the suggested gold, save this point. Only later net profit will accumulate for the next distribution.")

local tableHeader = MakePanel(distributionView, COLORS.panelAlt)
tableHeader:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -12)
-- Leave the scrollbar gutter outside the table itself so the header and data
-- rows share exactly the same usable width.
tableHeader:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", -22, -12)
tableHeader:SetHeight(30)

local headerGoal = MakeText(tableHeader, "helper", COLORS.goldSoft, "LEFT")
local headerDestination = MakeText(tableHeader, "helper", COLORS.goldSoft, "LEFT")
local headerWeight = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
local headerShare = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
local headerSuggested = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
local headerNeed = MakeText(tableHeader, "helper", COLORS.goldSoft, "RIGHT")
headerGoal:SetText("GOAL"); headerDestination:SetText("ALLOCATE TO"); headerWeight:SetText("DISTRIBUTION %")
headerShare:SetText("SPLIT %"); headerSuggested:SetText("SUGGESTED"); headerNeed:SetText("NEED AFTER")

local listScroll = CreateFrame("ScrollFrame", "IncomeRecordsSystemDistributionScroll", distributionView, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -2)
listScroll:SetPoint("TOPRIGHT", tableHeader, "BOTTOMRIGHT", -22, -2)
listScroll:SetHeight(250)
local listChild = CreateFrame("Frame", nil, listScroll)
listChild:SetSize(780, 1)
listScroll:SetScrollChild(listChild)

local footerLine = MakeText(distributionView, "body", COLORS.text, "LEFT")
footerLine:SetPoint("TOPLEFT", listScroll, "BOTTOMLEFT", 0, -10)
footerLine:SetPoint("TOPRIGHT", -4, -10)
local footerHint = MakeText(distributionView, "helper", COLORS.muted, "LEFT")
footerHint:SetPoint("TOPLEFT", footerLine, "BOTTOMLEFT", 0, -5)
footerHint:SetPoint("TOPRIGHT", -4, -5)
footerHint:SetWordWrap(true)

local distRows = {}
local function EnsureDistRow(index)
    if distRows[index] then return distRows[index] end
    local row = CreateFrame("Button", nil, listChild, "BackdropTemplate")
    row:SetHeight(38)
    row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    row:SetBackdropColor(COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], 0.50)
    row:SetBackdropBorderColor(COLORS.borderSoft[1], COLORS.borderSoft[2], COLORS.borderSoft[3], 0.55)
    row.goal = MakeText(row, "body", COLORS.text, "LEFT")
    row.destination = MakeText(row, "helper", COLORS.muted, "LEFT")
    row.weight = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.weight:SetAutoFocus(false)
    row.weight:SetJustifyH("RIGHT")
    row.weight:SetFontObject(GameFontHighlightSmall)
    row.weight:SetMaxLetters(5)
    row.weight:SetNumeric(false)
    row.share = MakeText(row, "body", COLORS.text, "RIGHT")
    row.suggested = MakeText(row, "body", COLORS.gold, "RIGHT")
    row.need = MakeText(row, "body", COLORS.muted, "RIGHT")
    row:SetScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.data.name or "Goal")
        GameTooltip:AddLine(
            (self.data.kind == "PROJECT" and "Project" or "Reserve")
                .. "  •  Allocate to: "
                .. (self.data.sourceLabel or "Unknown Source"),
            0.68, 0.62, 0.51
        )
        GameTooltip:AddLine(string.format("Distribution weight: %.1f%%", self.data.weight or 0), 0.88, 0.84, 0.75)
        GameTooltip:AddLine("Suggested: " .. WholeGold(self.data.suggested or 0), 0.86, 0.71, 0.36)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function CommitWeight(self)
        if not row.data then return end
        local raw = tostring(self:GetText() or ""):gsub("%%", "")
        local value = tonumber(raw)
        if value and IRS:SetProfitDistributionWeight(row.data.id, value) then
            self:ClearFocus()
            IRS:RefreshToolsPage()
        else
            self:SetText(string.format("%.1f", tonumber(row.data.weight) or 0):gsub("%.0$", ""))
            self:ClearFocus()
        end
    end
    row.weight:SetScript("OnEnterPressed", CommitWeight)
    row.weight:SetScript("OnEditFocusLost", function(self)
        if row.data and self:GetText() ~= "" then CommitWeight(self) end
    end)

    distRows[index] = row
    return row
end

local emptyText = MakeText(listChild, "body", COLORS.muted, "CENTER")
emptyText:SetPoint("TOPLEFT", 0, -28)
emptyText:SetWidth(760)
emptyText:SetText("No active Projects or underfunded Reserves currently need a distribution.")

local function LayoutDistributionColumns()
    -- The table header and scroll child intentionally share one content width.
    -- Previously the header was wider than the rows by the scrollbar gutter,
    -- which let NEED AFTER extend through the row's right border.
    local width = math.max(680, tableHeader:GetWidth() or 780)
    local childW = math.max(680, (listScroll:GetWidth() or width) - 2)
    width = math.min(width, childW)
    local usable = math.max(650, width - 20)

    local goalW = math.max(155, math.floor(usable * 0.24))
    local destinationW = math.max(130, math.floor(usable * 0.20))
    local weightW = 110
    local shareW = 75
    local suggestW = 105
    local needW = math.max(100, usable - goalW - destinationW - weightW - shareW - suggestW)

    local x = 10
    headerGoal:ClearAllPoints(); headerGoal:SetPoint("LEFT", x, 0); headerGoal:SetWidth(goalW); x=x+goalW
    headerDestination:ClearAllPoints(); headerDestination:SetPoint("LEFT", x, 0); headerDestination:SetWidth(destinationW); x=x+destinationW
    headerWeight:ClearAllPoints(); headerWeight:SetPoint("LEFT", x, 0); headerWeight:SetWidth(weightW); x=x+weightW
    headerShare:ClearAllPoints(); headerShare:SetPoint("LEFT", x, 0); headerShare:SetWidth(shareW); x=x+shareW
    headerSuggested:ClearAllPoints(); headerSuggested:SetPoint("LEFT", x, 0); headerSuggested:SetWidth(suggestW); x=x+suggestW
    headerNeed:ClearAllPoints(); headerNeed:SetPoint("LEFT", x, 0); headerNeed:SetWidth(needW)

    listChild:SetWidth(width)
    emptyText:SetWidth(width)
    for _, row in ipairs(distRows) do
        row:SetWidth(width)
        local rx=10
        row.goal:ClearAllPoints(); row.goal:SetPoint("LEFT", rx, 0); row.goal:SetWidth(goalW); rx=rx+goalW
        row.destination:ClearAllPoints(); row.destination:SetPoint("LEFT", rx, 0); row.destination:SetWidth(destinationW); rx=rx+destinationW
        row.weight:ClearAllPoints(); row.weight:SetPoint("LEFT", rx + 8, 0); row.weight:SetSize(math.max(54, weightW - 16), 24); rx=rx+weightW
        row.share:ClearAllPoints(); row.share:SetPoint("LEFT", rx, 0); row.share:SetWidth(shareW); rx=rx+shareW
        row.suggested:ClearAllPoints(); row.suggested:SetPoint("LEFT", rx, 0); row.suggested:SetWidth(suggestW); rx=rx+suggestW
        row.need:ClearAllPoints(); row.need:SetPoint("LEFT", rx, 0); row.need:SetWidth(needW)
    end
end

local checkpointHover = false
local checkpointAppearanceRefreshing = false

local function RefreshCheckpointAppearance()
    -- Enabling or disabling a hovered button can fire OnEnter/OnLeave while this
    -- function is still running. Ignore that nested appearance refresh and only
    -- change the enabled state when it actually needs to change.
    if checkpointAppearanceRefreshing then return end
    checkpointAppearanceRefreshing = true

    local data = IRS:GetProfitDistribution()
    local enabled = (tonumber(data.availableProfit) or 0) > 0

    if enabled then
        if not checkpoint:IsEnabled() then
            checkpoint:Enable()
        end
        if checkpointHover then
            checkpoint:SetBackdropColor(0.285, 0.215, 0.135, 0.98)
            checkpoint:SetBackdropBorderColor(unpack(COLORS.gold))
            SetColor(checkpoint.label, COLORS.gold)
        else
            checkpoint:SetBackdropColor(unpack(COLORS.panelAlt))
            checkpoint:SetBackdropBorderColor(unpack(COLORS.borderSoft))
            SetColor(checkpoint.label, COLORS.text)
        end
    else
        if checkpoint:IsEnabled() then
            checkpoint:Disable()
        end
        checkpoint:SetBackdropColor(COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], 0.55)
        checkpoint:SetBackdropBorderColor(COLORS.borderSoft[1], COLORS.borderSoft[2], COLORS.borderSoft[3], 0.55)
        SetColor(checkpoint.label, COLORS.muted)
    end

    checkpointAppearanceRefreshing = false
end

checkpoint:SetScript("OnEnter", function()
    checkpointHover = true
    RefreshCheckpointAppearance()
end)
checkpoint:SetScript("OnLeave", function()
    checkpointHover = false
    RefreshCheckpointAppearance()
end)
checkpoint:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() then
        self:SetBackdropColor(0.32, 0.24, 0.145, 1)
    end
end)
checkpoint:SetScript("OnMouseUp", function()
    RefreshCheckpointAppearance()
end)
checkpoint:SetScript("OnClick", function()
    local data = IRS:GetProfitDistribution()
    if (tonumber(data.availableProfit) or 0) <= 0 then return end
    IRS:MarkProfitsAllocated()
    IRS:RefreshToolsPage()
end)

manualTab:SetScript("OnClick", function() IRS:SetToolsSection("manual") end)
distributionTab:SetScript("OnClick", function() IRS:SetToolsSection("distribution") end)

function IRS:RefreshToolsLayout()
    if not page then return end
    LayoutManual()
    LayoutDistributionColumns()
end

function IRS:RefreshToolsPage()
    EnsureToolsDB()
    local section = IRS.db.ui.toolsSection == "distribution" and "distribution" or "manual"
    manualView:SetShown(section == "manual")
    distributionView:SetShown(section == "distribution")

    for key, button in pairs({manual=manualTab, distribution=distributionTab}) do
        local active = key == section
        button:SetBackdropColor(unpack(active and COLORS.panelAlt or COLORS.panel))
        button:SetBackdropBorderColor(unpack(active and COLORS.goldSoft or COLORS.borderSoft))
        SetColor(button.label, active and COLORS.gold or COLORS.text)
    end

    if section == "manual" then
        LayoutManual()
        return
    end

    local data = IRS:GetProfitDistribution()
    if data.lastAllocationAt then
        lastValue:SetText(date("%b %d, %Y  %I:%M %p", data.lastAllocationAt))
    elseif data.initializedFromToday then
        lastValue:SetText("Start of today (first use)")
    else
        lastValue:SetText("No checkpoint recorded")
    end

    netValue:SetText(WholeGold(data.netSince, true))
    if data.netSince > 0 then SetColor(netValue, COLORS.green)
    elseif data.netSince < 0 then SetColor(netValue, COLORS.red)
    else SetColor(netValue, COLORS.muted) end

    availableValue:SetText(WholeGold(data.availableProfit))
    SetColor(availableValue, data.availableProfit > 0 and COLORS.green or COLORS.muted)
    RefreshCheckpointAppearance()

    for i, item in ipairs(data.rows) do
        local row = EnsureDistRow(i)
        row.data = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 40))
        row.goal:SetText(item.name)
        row.destination:SetText(item.sourceLabel or "Unknown source")
        local weightText = string.format("%.1f", item.weight or 0):gsub("%.0$", "")
        if not row.weight:HasFocus() then row.weight:SetText(weightText) end
        row.share:SetText(string.format("%.1f%%", item.normalizedPercent or 0))
        row.suggested:SetText(WholeGold(item.suggested or 0))
        row.need:SetText(WholeGold(item.needAfter or 0))
        row:Show()
    end
    for i=#data.rows+1,#distRows do distRows[i]:Hide(); distRows[i].data=nil end
    emptyText:SetShown(#data.rows == 0)
    listChild:SetHeight(math.max(250, (#data.rows * 40) + 4))

    footerLine:SetText(string.format(
        "Suggested total: %s    •    Unallocated remainder: %s",
        WholeGold(data.distributed), WholeGold(data.remainder)
    ))
    footerHint:SetText(string.format(
        "Distribution weights total %.1f%% and are normalized across eligible goals. %d funded/completed goal%s excluded; %d unavailable source%s excluded. A negative net since the checkpoint produces 0g available until the loss is recovered or a new allocation checkpoint is recorded.",
        data.totalWeight or 0,
        data.completedExcluded or 0, (data.completedExcluded or 0) == 1 and "" or "s",
        data.unavailableExcluded or 0, (data.unavailableExcluded or 0) == 1 and "" or "s"
    ))

    LayoutDistributionColumns()
end

IRS:RefreshToolsLayout()
IRS:RefreshToolsPage()
    page._irsToolsUIBuilt = true
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
