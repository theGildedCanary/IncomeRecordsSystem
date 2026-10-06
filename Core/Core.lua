--[[
IRS — Income Records System
Core data, tracking, reporting, project logic, WoW events, and slash commands.
Money values are stored internally in copper.
]]

local ADDON_NAME = ...

IRS = IRS or {}
local IRS = IRS

IRS.version = "0.17.3"

-- ============================================================================
-- TEMPORARY STARTUP TIMING DIAGNOSTICS
-- Runtime-only instrumentation for the intermittent login execution timeout.
-- Nothing in this block is written to IncomeRecordsSystemDB.
-- Remove this block and the Begin/End calls once the culprit is identified.
-- ============================================================================
local function StartupTimingNowMS()
    if debugprofilestop then
        return debugprofilestop()
    end

    local seconds = 0
    if GetTimePreciseSec then
        seconds = GetTimePreciseSec()
    elseif GetTime then
        seconds = GetTime()
    end
    return seconds * 1000
end

IRS._startupTiming = {
    active = true,
    startedAt = StartupTimingNowMS(),
    stages = {},
    order = {},
    tokens = {},
    nextTokenId = 0,
}

function IRS:BeginStartupTiming(label)
    local timing = IRS._startupTiming
    if not timing or not timing.active then return nil end

    timing.nextTokenId = timing.nextTokenId + 1
    local token = {
        id = timing.nextTokenId,
        label = tostring(label or "Unnamed startup stage"),
        startedAt = StartupTimingNowMS(),
        active = true,
    }
    timing.tokens[token.id] = token

    if C_Timer and C_Timer.After then
        C_Timer.After(0.75, function()
            local current = IRS._startupTiming
            local pending = current
                and current.tokens
                and current.tokens[token.id]

            if pending and pending.active then
                print(string.format(
                    "|cffff9f43IRS startup diagnostic:|r '%s' did not complete before the watchdog. Run |cffffffff/irs timing|r after the error.",
                    pending.label
                ))
            end
        end)
    end

    return token
end

function IRS:EndStartupTiming(token)
    if not token or not token.active then return nil end

    token.active = false
    local elapsed = math.max(0, StartupTimingNowMS() - token.startedAt)
    local timing = IRS._startupTiming
    if not timing then return elapsed end

    if timing.tokens then
        timing.tokens[token.id] = nil
    end

    local stage = timing.stages[token.label]
    if not stage then
        stage = {
            count = 0,
            total = 0,
            max = 0,
        }
        timing.stages[token.label] = stage
        table.insert(timing.order, token.label)
    end

    stage.count = stage.count + 1
    stage.total = stage.total + elapsed
    stage.max = math.max(stage.max, elapsed)

    return elapsed
end

function IRS:FinishStartupTiming()
    local timing = IRS._startupTiming
    if not timing or not timing.active then return end

    timing.active = false
    timing.finishedAt = StartupTimingNowMS()
end

function IRS:ScheduleStartupTimingFinish(delay)
    local timing = IRS._startupTiming
    if not timing or timing.finishScheduled then return end

    timing.finishScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 4.0, function()
            IRS:FinishStartupTiming()
        end)
    end
end

function IRS:PrintStartupTiming()
    local timing = IRS._startupTiming
    if not timing then
        print("|cff46d9ffIRS startup timing:|r no timing data is available.")
        return
    end

    print("|cff46d9ffIRS startup timing|r — runtime only; SavedVariables are untouched.")

    if #timing.order == 0 then
        print("  No completed startup stages have been recorded yet.")
    else
        for _, label in ipairs(timing.order) do
            local stage = timing.stages[label]
            if stage.count > 1 then
                print(string.format(
                    "  %s — %.2f ms total (%d calls, %.2f ms max)",
                    label,
                    stage.total,
                    stage.count,
                    stage.max
                ))
            else
                print(string.format(
                    "  %s — %.2f ms",
                    label,
                    stage.total
                ))
            end
        end
    end

    local incomplete = 0
    for _, token in pairs(timing.tokens or {}) do
        if token.active then
            incomplete = incomplete + 1
            print(string.format(
                "  |cffff5555INCOMPLETE|r — %s (%.2f ms since start)",
                token.label,
                math.max(0, StartupTimingNowMS() - token.startedAt)
            ))
        end
    end

    if incomplete == 0 then
        print(timing.active
            and "  Startup timing window is still active."
            or "  Startup timing window is complete.")
    end
end

local _irsCoreModuleTiming = IRS:BeginStartupTiming("Module load: Core")


-- ============================================================================
-- FONT STYLES
-- ============================================================================
-- Semantic font groups shared by the Settings editor.
-- MAIN IRS:
--   helper  = metadata, notes, table headings, graph labels
--   body    = normal copy, row text, ordinary buttons
--   label   = stronger labels and card headings
--   section = subsection / panel headings
--   page    = page-level headings and major status headings
--   value   = prominent gold totals / large numeric values
--   brand   = the large "IRS" masthead only
--
-- MINI DASHBOARD:
--   helper  = small supporting text
--   body    = normal mini-dashboard text
--   heading = mini-dashboard headings
--   value   = emphasized mini-dashboard amounts
IRS.FONT_STYLE_DEFAULTS = {
    main = {
        helper = 10,
        body = 11,
        label = 12,
        section = 15,
        page = 19,
        value = 18,
        brand = 32,
    },
    mini = {
        helper = 10,
        body = 11,
        heading = 13,
        heading2 = 12,
        heading3 = 11,
        value = 12,
    },
}

IRS.FONT_STYLE_ORDER = {
    main = {"helper", "body", "label", "section", "page", "value", "brand"},
    mini = {"helper", "body", "heading", "heading2", "heading3", "value"},
}

IRS.FONT_STYLE_LABELS = {
    main = {
        helper = "Helper Text",
        body = "Body Text",
        label = "Labels & Controls",
        section = "Section Headings",
        page = "Page Headings",
        value = "Large Values",
        brand = "IRS Brand",
    },
    mini = {
        helper = "Helper Text",
        body = "Body Text",
        heading = "Headings",
        heading2 = "Headings 2",
        heading3 = "Headings 3",
        value = "Key Values",
    },
}

-- Compatibility mapping for SavedVariables and callers that still use numerical tiers.
IRS.FONT_STYLE_LEGACY_MAP = {
    main = {
        ["8"] = "helper",
        ["9"] = "helper",
        ["10"] = "body",
        ["11"] = "body",
        ["12"] = "label",
        ["13"] = "section",
        ["14"] = "section",
        ["15"] = "section",
        ["16"] = "section",
        ["17"] = "section",
        ["18"] = "page",
        ["19"] = "page",
        ["20"] = "value",
        ["32"] = "brand",
    },
    mini = {
        ["8"] = "helper",
        ["10"] = "body",
        ["11"] = "body",
        ["12"] = "value",
        ["13"] = "heading",
    },
}

-- Runtime references to FontStrings. This is not SavedVariables data.
IRS._fontRegistry = IRS._fontRegistry or {
    main = {},
    mini = {},
}
-- Blizzard Statistics IDs used by IRS. These numbers correspond to rows in
-- WoW's built-in Statistics > Character > Wealth section.
--
-- If a Blizzard statistic changes or a new statistic is added, this is the
-- first table to inspect.
IRS.STAT_IDS = {
    totalAcquired    = 328,
    avgGoldPerDay    = 753,
    goldLooted       = 333,
    questGold        = 326,
    auctionGold      = 919,
    auctionsPosted   = 329,
    auctionPurchases = 330,
    largestBid       = 331,
    largestSale      = 332,
    vendorGold       = 921,
    travelSpent      = 1146,
    postageSpent     = 1148,
    mostGold         = 334,
}

-- Tells ReadStatistic() which Blizzard statistics represent MONEY rather than
-- simple counts. Money statistics need special gold/silver/copper parsing.
local MONEY_STATS = {
    totalAcquired = true,
    avgGoldPerDay = true,
    goldLooted = true,
    questGold = true,
    auctionGold = true,
    largestBid = true,
    largestSale = true,
    vendorGold = true,
    travelSpent = true,
    postageSpent = true,
    mostGold = true,
}

-- Income categories IRS tracks separately for source-breakdown reports.
-- These DO NOT control the headline net total; wallet changes do that.
local TRACKED_SOURCE_STATS = {
    "goldLooted",
    "questGold",
    "vendorGold",
    "auctionGold",
}

-- Transmog spending is NOT exposed as a lifetime Wealth statistic like Travel
-- or Postage. IRS therefore tracks it prospectively while the addon is running.
-- This table is runtime-only state used to remember the pending transmog cost
-- until WoW confirms that the appearance change succeeded.
IRS.transmogRuntime = IRS.transmogRuntime or {
    isOpen = false,
    pendingCost = 0,
    armedCost = 0,
    transactionRecorded = false,
}

-- ============================================================================
-- SECTION 1 — BASIC PARSING / TIME HELPERS
-- Small helpers used throughout the data layer.
-- ============================================================================
-- Returns the server timestamp when possible so characters on the account use
-- one consistent clock. Falls back to Lua's time() if the API is unavailable.
local function ServerNow()
    if GetServerTime then
        local value = GetServerTime()
        if type(value) == "number" and value > 0 then return value end
    end
    return time()
end

-- Converts formatted text such as "1,234" into 1234 by stripping non-digits.
-- Used only when Blizzard returns a display string instead of a raw number.
local function DigitsToNumber(text)
    if text == nil then return nil end
    local digits = tostring(text):gsub("[^0-9]", "")
    if digits == "" then return nil end
    return tonumber(digits)
end

local UINT32_MAX_PLUS_ONE = 4294967296
-- Blizzard has historically exposed some very large statistics as signed
-- 32-bit values. A negative result can therefore really be a wrapped positive
-- value. This converts that wrapped value back to its intended unsigned number.
local function NormalizeUnsigned32(value)
    if value == nil then return nil end
    value = tonumber(value)
    if not value then return nil end
    if value < 0 then
        value = UINT32_MAX_PLUS_ONE + value
    end
    if value < 0 then return nil end
    return value
end

-- Parses an integer-looking string, including wrapped negative values, and
-- normalizes it through NormalizeUnsigned32().
local function ParseSignedIntegerText(text)
    if text == nil then return nil end
    local compact = tostring(text):gsub(",", ""):gsub("%s+", "")
    if compact == "" then return nil end
    if compact:match("^[+-]?%d+$") then
        return NormalizeUnsigned32(tonumber(compact))
    end
    return nil
end

-- Money-valued statistics can be returned as display strings containing
-- gold/silver/copper texture markup. Parse the denominations separately so
-- numbers used by texture markup are never accidentally treated as currency.
-- Reads a Blizzard MONEY statistic safely. It supports raw numbers, Blizzard
-- coin-icon strings, and plain text such as "1,234g 56s 78c". Returns COPPER.
local function ParseMoneyStatistic(value)
    if value == nil then return nil end
    if type(value) == "number" then
        return NormalizeUnsigned32(value)
    end

    local text = tostring(value)
    if text == "" or text == "--" then return nil end

    local signedDirect = ParseSignedIntegerText(text)
    if signedDirect ~= nil then
        return signedDirect
    end

    local function FindCoin(iconName)
        local captured = text:match("([%d%.,]+)%s*|T[^|]-" .. iconName .. "[^|]-|t")
        if not captured then
            captured = text:match("([%d%.,]+)%s*|A:[^:]-" .. iconName .. "[^|]-|a")
        end
        return DigitsToNumber(captured) or 0
    end

    local gold = FindCoin("GoldIcon")
    local silver = FindCoin("SilverIcon")
    local copper = FindCoin("CopperIcon")

    if gold > 0 or silver > 0 or copper > 0 or text:find("GoldIcon", 1, true)
        or text:find("SilverIcon", 1, true) or text:find("CopperIcon", 1, true) then
        return (gold * 10000) + (silver * 100) + copper
    end

    -- Fallback for plain strings such as "1,234g 56s 78c".
    local g = DigitsToNumber(text:match("([%d%.,]+)%s*[gG]")) or 0
    local s = DigitsToNumber(text:match("([%d%.,]+)%s*[sS]")) or 0
    local c = DigitsToNumber(text:match("([%d%.,]+)%s*[cC]")) or 0
    if g > 0 or s > 0 or c > 0 then
        return (g * 10000) + (s * 100) + c
    end

    return nil
end

-- Reads a non-money Blizzard statistic such as "Auctions Posted" and returns
-- a plain number.
local function ParseCountStatistic(value)
    if value == nil then return nil end
    if type(value) == "number" then
        return NormalizeUnsigned32(value)
    end

    local text = tostring(value)
    if text == "" or text == "--" then return nil end

    local signedDirect = ParseSignedIntegerText(text)
    if signedDirect ~= nil then return signedDirect end
    return DigitsToNumber(text)
end

-- One doorway for GetStatistic(). Decides whether the requested statistic is
-- money or a count and sends it to the correct parser.
local function ReadStatistic(statName, id)
    if not id or not GetStatistic then return nil end
    local raw = GetStatistic(id)
    if MONEY_STATS[statName] then
        return ParseMoneyStatistic(raw)
    end
    return ParseCountStatistic(raw)
end

-- ============================================================================
-- SECTION 2 — CHARACTER IDENTITY
-- How IRS uniquely identifies and labels characters.
-- ============================================================================
-- Returns the persistent key IRS uses for the current character. GUID is
-- preferred because character names alone are not guaranteed to be unique.
function IRS:CharacterKey()
    local guid = UnitGUID("player")
    if guid and guid ~= "" then return guid end
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

-- Returns the human-readable "Name-Realm" label shown in the UI.
function IRS:CharacterLabel()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

-- ============================================================================
-- SECTION 3 — LEDGER BUCKETS / MIGRATION HELPERS
-- Structures used to store day, week, month, and source totals.
-- ============================================================================
-- Creates one empty ledger bucket. A bucket stores the NET amount plus the
-- separate income-source deltas observed during the same period.
local function NewBucket()
    return {
        earned = 0,
        sources = {
            goldLooted = 0,
            questGold = 0,
            vendorGold = 0,
            auctionGold = 0,
        },
    }
end

-- Returns an existing day/week/month bucket or creates it if this is the first
-- activity IRS has seen for that period.
local function EnsureBucket(tableRef, key)
    if not tableRef[key] then tableRef[key] = NewBucket() end
    tableRef[key].sources = tableRef[key].sources or NewBucket().sources
    tableRef[key].earned = tableRef[key].earned or 0
    return tableRef[key]
end

-- Adds the four source categories IRS knows how to classify individually.
local function SumTrackedSources(sourceTable)
    local total = 0
    sourceTable = sourceTable or {}
    for _, statName in ipairs(TRACKED_SOURCE_STATS) do
        total = total + math.max(0, math.floor(tonumber(sourceTable[statName]) or 0))
    end
    return total
end

-- Migration for older source-only records that were missing the matching earning.
local function RepairSourceOnlyEarnings(db)
    local tracking = db.tracking
    if tracking then
        for _, periodName in ipairs({"days", "weeks", "months"}) do
            for _, bucket in pairs(tracking[periodName] or {}) do
                if type(bucket) == "table" then
                    bucket.earned = math.max(tonumber(bucket.earned) or 0, SumTrackedSources(bucket.sources))
                end
            end
        end
        tracking.totalEarned = math.max(tonumber(tracking.totalEarned) or 0, SumTrackedSources(tracking.sources))
    end

    for _, record in pairs(db.characters or {}) do
        local sourceTotal = SumTrackedSources(record.sourceEarningsSinceTracking)
        record.earnedSinceTracking = math.max(tonumber(record.earnedSinceTracking) or 0, sourceTotal)

        record.periodEarnings = record.periodEarnings or { days = {}, weeks = {}, months = {} }
        record.periodEarnings.days = record.periodEarnings.days or {}
        record.periodEarnings.weeks = record.periodEarnings.weeks or {}
        record.periodEarnings.months = record.periodEarnings.months or {}

        local sourcePeriods = record.periodSourceEarnings or {}
        for _, periodName in ipairs({"days", "weeks", "months"}) do
            for key, sources in pairs(sourcePeriods[periodName] or {}) do
                local existing = tonumber(record.periodEarnings[periodName][key]) or 0
                record.periodEarnings[periodName][key] = math.max(existing, SumTrackedSources(sources))
            end
        end
    end
end

-- ============================================================================
-- SECTION 4 — SAVEDVARIABLES DATABASE
-- Creates missing database fields and performs safe migrations.
-- ============================================================================
-- Initializes the database and applies compatible SavedVariables migrations.
function IRS:EnsureDB()
    local startupTiming = IRS:BeginStartupTiming("Database initialization / migration")

    IncomeRecordsSystemDB = IncomeRecordsSystemDB or {}
    local db = IncomeRecordsSystemDB
    local now = ServerNow()

    local previousSchema = tonumber(db.schema) or 0
    db.createdAt = db.createdAt or now
    db.characters = db.characters or {}
    db.account = db.account or {}
    db.account.peakKnownWealth = db.account.peakKnownWealth or 0
    db.account.warbandGold = db.account.warbandGold or 0
    db.account.warbandGoldSeen = db.account.warbandGoldSeen or false
    db.settings = db.settings or {}
    if db.settings.showMinimapButton == nil then db.settings.showMinimapButton = true end
    if db.settings.showMiniProjects == nil then db.settings.showMiniProjects = true end
    if db.settings.autoOpenMiniDashboard == nil then db.settings.autoOpenMiniDashboard = false end

    -- Preserve custom sizes from the previous numerical font settings.
    db.settings.fontSizes = db.settings.fontSizes or {}
    db.settings.fontSizes.main = db.settings.fontSizes.main or {}
    db.settings.fontSizes.mini = db.settings.fontSizes.mini or {}

    local legacyMainFonts = db.settings.fontSizes.main
    local legacyMiniFonts = db.settings.fontSizes.mini

    local migratedMainFonts = {
        helper = legacyMainFonts["8"] or legacyMainFonts["9"],
        body = legacyMainFonts["10"] or legacyMainFonts["11"],
        label = legacyMainFonts["12"],
        section = legacyMainFonts["15"] or legacyMainFonts["14"] or legacyMainFonts["13"],
        page = legacyMainFonts["19"] or legacyMainFonts["18"],
        value = legacyMainFonts["20"] or legacyMainFonts["16"],
        brand = legacyMainFonts["32"],
    }

    local migratedMiniFonts = {
        helper = legacyMiniFonts["8"],
        body = legacyMiniFonts["11"] or legacyMiniFonts["10"],
        heading = legacyMiniFonts["13"],
        heading2 = nil,
        heading3 = nil,
        value = legacyMiniFonts["12"],
    }

    for scope, defaults in pairs(IRS.FONT_STYLE_DEFAULTS) do
        local target = db.settings.fontSizes[scope]
        local migration = scope == "mini" and migratedMiniFonts or migratedMainFonts

        for styleKey, defaultSize in pairs(defaults) do
            if tonumber(target[styleKey]) == nil then
                target[styleKey] = tonumber(migration[styleKey]) or defaultSize
            end
        end
    end

    -- Which mini-dashboard corner remains fixed when the panel changes height.
    -- Valid values: TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT.
    if db.settings.miniDashboardAnchor == nil then
        db.settings.miniDashboardAnchor = "TOPLEFT"
    end

    -- Per-project visibility for the floating mini dashboard.
    -- Missing entries intentionally mean "shown" so old and newly-created
    -- projects appear by default until the player opts them out.
    db.settings.miniProjectVisibility = db.settings.miniProjectVisibility or {}

    -- UI-only persistent state. This keeps the floating mini dashboard in the
    -- position where the player dragged it without mixing layout data into the
    -- financial ledgers.
    db.ui = db.ui or {}
    db.ui.miniDashboard = db.ui.miniDashboard or {}
    db.ui.miniDashboard.characterOpenState = db.ui.miniDashboard.characterOpenState or {}

    -- Last Settings sub-page selected in the Settings sidebar.
    db.ui.settingsSection = db.ui.settingsSection or "toggles"

    -- This is a UI preference, not the Settings-page "show projects" toggle.
    -- false = the projects section is expanded when visible.
    -- true  = the projects section is collapsed to its header row.
    if db.ui.miniDashboard.projectsCollapsed == nil then
        db.ui.miniDashboard.projectsCollapsed = false
    end

    -- IRS-tracked spending categories that Blizzard does not provide as lifetime
    -- Wealth statistics. These totals begin when the feature is introduced; IRS
    -- cannot reconstruct older transmog spending retroactively.
    db.spending = db.spending or {}
    db.spending.transmog = tonumber(db.spending.transmog) or 0

    -- Savings projects are persistent, account-wide planning records. Project
    -- source balances are snapshots of known WoW balances; IRS never moves or
    -- reserves gold automatically.
    db.projects = db.projects or { nextId = 1, items = {} }
    db.projects.nextId = tonumber(db.projects.nextId) or 1
    db.projects.items = db.projects.items or {}
    db.guildBanks = db.guildBanks or {}

    -- Central daily source history belongs to IRS, not to individual projects.
    -- Projects now query this shared history across their Start Date -> Deadline
    -- window, so editing a project can never delete the underlying observations.
    db.sourceHistory = db.sourceHistory or {}
    db.sourceHistory.days = db.sourceHistory.days or {}

    for _, project in pairs(db.projects.items) do
        if type(project) == "table" then
            project.startDate = project.startDate
                or project.createdDay
                or date("%Y-%m-%d", now)
        end
    end

    -- Discard deprecated SavedVariables fields from older builds.
    db.savings = nil

    for _, project in pairs(db.projects.items) do
        if type(project) == "table" then
            project.reservedCopper = nil
            project.legacyReservedCopper = nil
            project.vaultAssignments = nil
            project.savingsRule = nil
            project.savingsPreferredVaultId = nil
            project.lastReservedAt = nil
        end
    end

    if db.ui and db.ui.settingsSection == "savings" then
        db.ui.settingsSection = "toggles"
    end

    -- Every character already known to IRS is tracked by default. A user can
    -- opt any character out from the Characters tab without deleting its file.
    for _, record in pairs(db.characters) do
        if record.trackingEnabled == nil then record.trackingEnabled = true end
    end

    -- IRS net history is forward-looking; Blizzard lifetime stats are not backfilled.
    db.tracking = db.tracking or {
        startedAt = now,
        totalEarned = 0,
        days = {},
        weeks = {},
        months = {},
        sources = {
            goldLooted = 0,
            questGold = 0,
            vendorGold = 0,
            auctionGold = 0,
        },
    }
    db.tracking.startedAt = db.tracking.startedAt or now
    db.tracking.totalEarned = db.tracking.totalEarned or 0
    db.tracking.days = db.tracking.days or {}
    db.tracking.weeks = db.tracking.weeks or {}
    db.tracking.months = db.tracking.months or {}
    db.tracking.sources = db.tracking.sources or {}
    for _, statName in ipairs(TRACKED_SOURCE_STATS) do
        db.tracking.sources[statName] = db.tracking.sources[statName] or 0
    end

    db.migrations = db.migrations or {}

    if not db.migrations.localDailyBoundary132 then
        local localDayKey = date("%Y-%m-%d", now)
        local legacyDayKey

        if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
            local ok, cal = pcall(C_DateAndTime.GetCurrentCalendarTime)
            if ok and cal and cal.year and cal.month and cal.monthDay then
                legacyDayKey = string.format(
                    "%04d-%02d-%02d",
                    tonumber(cal.year) or 0,
                    tonumber(cal.month) or 0,
                    tonumber(cal.monthDay) or 0
                )
            end
        end

        local lastAt = tonumber(db.tracking.lastEarnedAt)
        local lastAmount = math.floor(
            tonumber(db.tracking.lastEarningAmount) or 0
        )

        local lastEventIsLocalToday =
            lastAt
            and date("%Y-%m-%d", lastAt) == localDayKey

        local oldBucket = legacyDayKey
            and db.tracking.days[legacyDayKey]
            or nil
        local newBucket = db.tracking.days[localDayKey]

        if legacyDayKey
            and legacyDayKey ~= localDayKey
            and lastEventIsLocalToday
            and lastAmount ~= 0
            and oldBucket
            and newBucket == nil then

            -- Move ONLY the latest already-counted wallet event between day
            -- buckets. Week/month/total stay untouched so nothing is duplicated.
            oldBucket.earned =
                (tonumber(oldBucket.earned) or 0) - lastAmount

            local repairedToday = EnsureBucket(
                db.tracking.days,
                localDayKey
            )
            repairedToday.earned =
                (tonumber(repairedToday.earned) or 0) + lastAmount

            -- The wallet event belongs to the currently logged-in character.
            -- Move that character's DAILY contribution too; week/month/total do
            -- not change because those already contain the transaction once.
            local characterKey = IRS:CharacterKey()
            local record = characterKey and db.characters[characterKey]

            if record then
                record.periodEarnings = record.periodEarnings
                    or {days = {}, weeks = {}, months = {}}
                record.periodEarnings.days =
                    record.periodEarnings.days or {}

                record.periodEarnings.days[legacyDayKey] =
                    (tonumber(
                        record.periodEarnings.days[legacyDayKey]
                    ) or 0) - lastAmount

                record.periodEarnings.days[localDayKey] =
                    (tonumber(
                        record.periodEarnings.days[localDayKey]
                    ) or 0) + lastAmount
            end

            db.migrations.localDailyBoundary132Repair = {
                repairedAt = now,
                fromDay = legacyDayKey,
                toDay = localDayKey,
                amount = lastAmount,
            }
        end

        db.migrations.localDailyBoundary132 = now
    end

    if previousSchema < 5 then
        RepairSourceOnlyEarnings(db)
    end
    db.schema = 15

    IRS.db = db

    -- Re-baseline legacy Project snapshots once against their configured source.
    db.migrations = db.migrations or {}

    if not db.migrations.projectSourceModelRestored111 then
        local todayKey

        if IRS.GetPeriodKeys then
            todayKey = select(1, IRS:GetPeriodKeys())
        end

        if not todayKey then
            todayKey = date("%Y-%m-%d", now)
        end

        for _, project in pairs(db.projects.items or {}) do
            local amount, available = IRS:GetProjectAllocatedBalance(project)

            if available then
                project.daily = project.daily or {}
                project.daily[todayKey] = {
                    start = amount,
                    ending = amount,
                    firstSeen = now,
                    lastSeen = now,
                }
            end
        end

        db.migrations.projectSourceModelRestored111 = now
    end

    IRS:EndStartupTiming(startupTiming)
end

-- ============================================================================
-- SECTION 5 — NET GOLD LEDGER
-- Period keys, wallet deltas, and source attribution.
-- ============================================================================
-- Builds the keys IRS uses for TODAY, THIS WEEK, and THIS MONTH.
-- Weekly keys follow WoW's weekly reset rather than an arbitrary calendar week.
-- Returns: dayKey, weekKey, monthKey.
function IRS:GetPeriodKeys()
    local now = ServerNow()

    -- Use one local-calendar basis for day and month ledgers.
    local year = tonumber(date("%Y", now))
    local month = tonumber(date("%m", now))
    local day = tonumber(date("%d", now))

    local dayKey = string.format("%04d-%02d-%02d", year, month, day)
    local monthKey = string.format("%04d-%02d", year, month)

    local weekStart
    if C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime then
        local ok, value = pcall(C_DateAndTime.GetWeeklyResetStartTime)
        if ok and type(value) == "number" and value > 0 then weekStart = value end
    end
    if not weekStart and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, untilReset = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(untilReset) == "number" and untilReset >= 0 then
            weekStart = math.floor(now + untilReset - (7 * 86400))
        end
    end
    weekStart = weekStart or math.floor(now / (7 * 86400)) * (7 * 86400)
    local weekKey = tostring(math.floor(weekStart))

    return dayKey, weekKey, monthKey
end

-- CENTRAL LEDGER WRITER.
-- amount may be positive (income) or negative (spending/loss).
-- sourceDeltas contains any Blizzard income categories that changed.
-- Writes the change to account totals AND the selected character's history.
function IRS:RecordEarnings(amount, sourceDeltas, characterKey)
    if not IRS.db then IRS:EnsureDB() end
    -- "Earnings" is a net ledger: positive wallet changes are income and
    -- negative wallet changes are spending/losses.
    amount = math.floor(tonumber(amount) or 0)
    sourceDeltas = sourceDeltas or {}

    local hasSourceDelta = false
    for _, statName in ipairs(TRACKED_SOURCE_STATS) do
        if (tonumber(sourceDeltas[statName]) or 0) > 0 then
            hasSourceDelta = true
            break
        end
    end
    if amount == 0 and not hasSourceDelta then return end

    local tracking = IRS.db.tracking
    local record = characterKey and IRS.db.characters[characterKey]
    local dayKey, weekKey, monthKey = IRS:GetPeriodKeys()
    local dayBucket = EnsureBucket(tracking.days, dayKey)
    local weekBucket = EnsureBucket(tracking.weeks, weekKey)
    local monthBucket = EnsureBucket(tracking.months, monthKey)

    if amount ~= 0 then
        tracking.totalEarned = (tracking.totalEarned or 0) + amount
        dayBucket.earned = (dayBucket.earned or 0) + amount
        weekBucket.earned = (weekBucket.earned or 0) + amount
        monthBucket.earned = (monthBucket.earned or 0) + amount
        tracking.lastEarnedAt = ServerNow()
        tracking.lastEarningAmount = amount

        if record then
            record.earnedSinceTracking = (record.earnedSinceTracking or 0) + amount
            record.periodEarnings = record.periodEarnings or { days = {}, weeks = {}, months = {} }
            record.periodEarnings.days = record.periodEarnings.days or {}
            record.periodEarnings.weeks = record.periodEarnings.weeks or {}
            record.periodEarnings.months = record.periodEarnings.months or {}
            record.periodEarnings.days[dayKey] = (record.periodEarnings.days[dayKey] or 0) + amount
            record.periodEarnings.weeks[weekKey] = (record.periodEarnings.weeks[weekKey] or 0) + amount
            record.periodEarnings.months[monthKey] = (record.periodEarnings.months[monthKey] or 0) + amount
        end
    end

    if record then
        record.sourceEarningsSinceTracking = record.sourceEarningsSinceTracking or {}
        record.periodSourceEarnings = record.periodSourceEarnings or { days = {}, weeks = {}, months = {} }
        record.periodSourceEarnings.days = record.periodSourceEarnings.days or {}
        record.periodSourceEarnings.weeks = record.periodSourceEarnings.weeks or {}
        record.periodSourceEarnings.months = record.periodSourceEarnings.months or {}
        record.periodSourceEarnings.days[dayKey] = record.periodSourceEarnings.days[dayKey] or {}
        record.periodSourceEarnings.weeks[weekKey] = record.periodSourceEarnings.weeks[weekKey] or {}
        record.periodSourceEarnings.months[monthKey] = record.periodSourceEarnings.months[monthKey] or {}
    end

    for _, statName in ipairs(TRACKED_SOURCE_STATS) do
        local delta = math.max(0, math.floor(tonumber(sourceDeltas[statName]) or 0))
        if delta > 0 then
            tracking.sources[statName] = (tracking.sources[statName] or 0) + delta
            dayBucket.sources[statName] = (dayBucket.sources[statName] or 0) + delta
            weekBucket.sources[statName] = (weekBucket.sources[statName] or 0) + delta
            monthBucket.sources[statName] = (monthBucket.sources[statName] or 0) + delta

            if record then
                record.sourceEarningsSinceTracking[statName] = (record.sourceEarningsSinceTracking[statName] or 0) + delta
                local daySources = record.periodSourceEarnings.days[dayKey]
                local weekSources = record.periodSourceEarnings.weeks[weekKey]
                local monthSources = record.periodSourceEarnings.months[monthKey]
                daySources[statName] = (daySources[statName] or 0) + delta
                weekSources[statName] = (weekSources[statName] or 0) + delta
                monthSources[statName] = (monthSources[statName] or 0) + delta
            end
        end
    end
end

-- Saves the latest Blizzard source-stat values so the next scan can calculate
-- only the amount that changed since this scan.
local function SaveTrackerBaseline(tracker, currentStats)
    tracker.lastStats = tracker.lastStats or {}
    for statName in pairs(IRS.STAT_IDS) do
        if currentStats[statName] ~= nil then
            tracker.lastStats[statName] = currentStats[statName]
        end
    end
end

-- Compares Blizzard source statistics against their previous baselines.
-- Important: this function CLASSIFIES income sources; it does not decide the
-- headline net gain/loss. Net money comes from HandleMoneyChange().
function IRS:UpdateEarningsLedger(record, currentStats)
    local now = ServerNow()
    record.earningsTracker = record.earningsTracker or {}
    local tracker = record.earningsTracker
    tracker.lastStats = tracker.lastStats or {}

    -- Ignored characters keep their statistic baselines fresh, but source
    -- changes are not filed while tracking is disabled.
    if record.trackingEnabled == false then
        tracker.initialized = true
        tracker.startedAt = tracker.startedAt or now
        SaveTrackerBaseline(tracker, currentStats)
        tracker.needsRebaseline = false
        tracker.lastScan = now
        return
    end

    if not tracker.initialized or tracker.needsRebaseline then
        tracker.initialized = true
        tracker.startedAt = tracker.startedAt or now
        SaveTrackerBaseline(tracker, currentStats)
        tracker.needsRebaseline = false
        tracker.lastScan = now
        return
    end

    -- Blizzard's wealth counters are useful for categorizing income, but they
    -- do not always update at the same moment as the player's wallet. Gross
    -- earnings are therefore recorded from PLAYER_MONEY / GetMoney deltas;
    -- these deltas only classify the already-recorded earnings by source.
    local sourceDeltas = {}
    for _, statName in ipairs(TRACKED_SOURCE_STATS) do
        local current = currentStats[statName]
        local previous = tracker.lastStats[statName]
        if type(current) == "number" and type(previous) == "number" and current >= previous then
            sourceDeltas[statName] = current - previous
        else
            sourceDeltas[statName] = 0
        end
    end

    IRS:RecordEarnings(0, sourceDeltas, IRS:CharacterKey())
    SaveTrackerBaseline(tracker, currentStats)
    tracker.lastScan = now
end

-- ============================================================================
-- SECTION 6 — CHARACTER TRACKING / LIVE SCANNING
-- Enabling, disabling, scanning, wallet events, and account totals.
-- ============================================================================
-- Turns IRS tracking on/off for one saved character. Re-enabling forces fresh
-- baselines so gold moved while ignored is not retroactively imported.
function IRS:SetCharacterTracking(characterKey, enabled)
    if not IRS.db then IRS:EnsureDB() end
    local record = IRS.db.characters[characterKey]
    if not record then return end

    enabled = enabled and true or false
    if record.trackingEnabled == enabled then return end

    record.trackingEnabled = enabled
    record.earningsTracker = record.earningsTracker or {}
    record.earningsTracker.needsRebaseline = true
    record.earningsTracker.walletInitialized = false

    if IRS.RefreshUI then IRS:RefreshUI() end
end

-- Returns all scanned character records alphabetically for dropdowns/lists.
function IRS:GetSortedCharacters()
    if not IRS.db then IRS:EnsureDB() end
    local rows = {}
    for key, record in pairs(IRS.db.characters or {}) do
        table.insert(rows, { key = key, record = record })
    end
    table.sort(rows, function(a, b)
        return (a.record.label or "") < (b.record.label or "")
    end)
    return rows
end

-- Reads the live Warband Bank balance when Blizzard makes that bank available.
-- Returns nil when the balance cannot currently be read.
local function FetchWarbandGold()
    if not C_Bank or not C_Bank.FetchDepositedMoney or not Enum or not Enum.BankType then
        return nil
    end
    local ok, amount = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(amount) == "number" and amount >= 0 then
        return amount
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- TRANSMOG SPENDING TRACKER
-- ---------------------------------------------------------------------------
-- Blizzard does not include "Gold spent on transmogrification" in the built-in
-- Wealth statistics list. Midnight does expose the pending transmog cost and a
-- success event, so IRS can build its own account-wide transmog-spend counter
-- from this version forward.

-- Reads the currently pending transmog cost (in copper) and remembers the last
-- positive value. We intentionally keep armedCost when the API later returns 0,
-- because WoW may clear the pending cost immediately before firing SUCCESS.
function IRS:RefreshPendingTransmogCost()
    local state = IRS.transmogRuntime
    if not state then return end

    if C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetPendingTransmogCost then
        local ok, cost = pcall(C_TransmogOutfitInfo.GetPendingTransmogCost)
        if ok and type(cost) == "number" and cost >= 0 then
            state.pendingCost = math.floor(cost)
            if cost > 0 then
                state.armedCost = math.floor(cost)
                state.transactionRecorded = false
            end
        end
    end
end

-- Files one completed transmog purchase into IRS's own tracked-spending data.
-- This is separate from the headline net ledger; PLAYER_MONEY already records
-- the corresponding negative gold movement there.
function IRS:RecordTransmogSpend(amount, characterKey)
    if not IRS.db then IRS:EnsureDB() end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return end

    local record = characterKey and IRS.db.characters[characterKey]
    if record and record.trackingEnabled == false then return end

    IRS.db.spending = IRS.db.spending or {}
    IRS.db.spending.transmog = (tonumber(IRS.db.spending.transmog) or 0) + amount

    if record then
        record.spendingSinceTracking = record.spendingSinceTracking or {}
        record.spendingSinceTracking.transmog = (tonumber(record.spendingSinceTracking.transmog) or 0) + amount
    end
end

-- Called when WoW confirms at least one slot was successfully transmogrified.
-- TRANSMOGRIFY_SUCCESS can fire once per slot, so transactionRecorded prevents
-- a multi-slot outfit from being counted multiple times.
function IRS:HandleTransmogSuccess()
    local state = IRS.transmogRuntime
    if not state or state.transactionRecorded then return end

    local amount = math.max(0, math.floor(tonumber(state.armedCost) or 0))
    if amount > 0 then
        IRS:RecordTransmogSpend(amount, IRS:CharacterKey())
        state.transactionRecorded = true
        state.pendingCost = 0
        state.armedCost = 0
        if IRS.RefreshUI then IRS:RefreshUI() end
    end
end

-- MAIN NET-PROFIT / LOSS TRACKER.
-- Called from PLAYER_MONEY. Compares the previous wallet balance with GetMoney().
-- Positive delta = income; negative delta = spending/loss.
-- Matching Warband Bank transfers are removed so moving your own gold does not
-- look like profit or loss.
function IRS:HandleMoneyChange()
    if not IRS.db then IRS:EnsureDB() end

    local key = IRS:CharacterKey()
    local record = IRS.db.characters[key] or {}
    IRS.db.characters[key] = record
    if record.trackingEnabled == nil then record.trackingEnabled = true end

    local currentMoney = GetMoney and GetMoney() or 0
    record.earningsTracker = record.earningsTracker or {}
    local tracker = record.earningsTracker

    -- On upgrades / first sight, use the last saved wallet value when possible.
    -- Otherwise establish a baseline rather than treating the entire wallet as income.
    if not tracker.walletInitialized then
        tracker.walletLastMoney = tonumber(record.money) or currentMoney
        tracker.walletInitialized = true
    end

    local previousMoney = tonumber(tracker.walletLastMoney) or currentMoney
    local currentDayKey = select(1, IRS:GetPeriodKeys())

    -- Freeze a wallet opening balance for each LOCAL calendar day. If the day
    -- changed while this character was online (or between logins), yesterday's
    -- last known wallet is today's opening wallet. Historical day buckets are
    -- never rewritten here; subsequent deltas can only be filed into today.
    if tracker.walletDayKey ~= currentDayKey then
        tracker.walletDayKey = currentDayKey
        tracker.walletDayStartMoney = previousMoney
        tracker.walletDayStartedAt = ServerNow()
    elseif tracker.walletDayStartMoney == nil then
        tracker.walletDayStartMoney = previousMoney
    end

    local delta = currentMoney - previousMoney
    tracker.walletLastMoney = currentMoney
    record.money = currentMoney

    local currentWarband = FetchWarbandGold()
    local previousWarband = IRS.db.account.warbandGoldSeen and tonumber(IRS.db.account.warbandGold) or nil
    if currentWarband ~= nil then
        IRS.db.account.warbandGold = currentWarband
        IRS.db.account.warbandGoldSeen = true
    end

    if record.trackingEnabled == false then
        return
    end

    if delta ~= 0 then
        -- Internal storage movements are NOT profit/loss. The transfer module
        -- matches wallet changes against Warband Bank and user-owned Guild Bank
        -- balance changes, including either event order. A short defer is used
        -- while an owned Guild Bank is open so GUILDBANK_UPDATE_MONEY has time
        -- to arrive before a wallet decrease is filed as spending.
        local netChange = delta
        local deferred = false

        if IRS.FilterInternalWalletChange then
            netChange, deferred = IRS:FilterInternalWalletChange(
                delta,
                key,
                previousWarband,
                currentWarband
            )
        elseif previousWarband and currentWarband then
            -- Compatibility fallback if the transfer module is unavailable.
            if delta > 0 and currentWarband < previousWarband then
                local transfer = math.min(delta, previousWarband - currentWarband)
                netChange = delta - transfer
            elseif delta < 0 and currentWarband > previousWarband then
                local transfer = math.min(-delta, currentWarband - previousWarband)
                netChange = delta + transfer
            end
        end

        if netChange ~= 0 and not deferred then
            IRS:RecordEarnings(netChange, {}, key)
        end
    end

    IRS:UpdateProjectSnapshots()
    if IRS.RefreshUI then IRS:RefreshUI() end
end

-- Refreshes the cached Warband Bank balance and then updates savings projects
-- that depend on that balance.
function IRS:ScanWarbandGold()
    local startupTiming = IRS:BeginStartupTiming("Warband Bank scan")

    if not IRS.db then IRS:EnsureDB() end
    local amount = FetchWarbandGold()
    if amount ~= nil then
        local previous = IRS.db.account.warbandGoldSeen
            and tonumber(IRS.db.account.warbandGold)
            or nil

        if previous ~= nil
            and amount ~= previous
            and IRS.ObserveInternalStorageDelta then
            IRS:ObserveInternalStorageDelta(
                "warband",
                nil,
                amount - previous
            )
        end

        IRS.db.account.warbandGold = amount
        IRS.db.account.warbandGoldSeen = true
        IRS:UpdateProjectSnapshots()
    end

    IRS:EndStartupTiming(startupTiming)
end

-- FULL CHARACTER REFRESH.
-- Updates identity, wallet, Blizzard Wealth statistics, Warband Bank cache,
-- project snapshots, and finally the UI. /irs scan calls this directly.
function IRS:ScanCurrentCharacter()
    local scanTiming = IRS:BeginStartupTiming("Character scan")

    if not IRS.db then IRS:EnsureDB() end

    local identityTiming = IRS:BeginStartupTiming("Character scan: identity / wallet")
    local key = IRS:CharacterKey()
    local record = IRS.db.characters[key] or {}
    IRS.db.characters[key] = record
    if record.trackingEnabled == nil then record.trackingEnabled = true end

    record.name = UnitName("player") or record.name or "Unknown"
    record.realm = GetRealmName() or record.realm or "Unknown"
    record.label = IRS:CharacterLabel()
    record.level = UnitLevel("player") or record.level or 0
    record.className = select(1, UnitClass("player")) or record.className or "Unknown"
    record.lastSeen = ServerNow()

    local currentMoney = GetMoney and GetMoney() or record.money or 0

    record.earningsTracker = record.earningsTracker or {}
    local tracker = record.earningsTracker
    local currentDayKey = select(1, IRS:GetPeriodKeys())

    if not tracker.walletInitialized then
        tracker.walletLastMoney = tonumber(record.money) or currentMoney
        tracker.walletInitialized = true
        tracker.walletDayKey = currentDayKey
        tracker.walletDayStartMoney = tonumber(record.money) or currentMoney
        tracker.walletDayStartedAt = ServerNow()
        record.money = currentMoney
    elseif tracker.walletDayKey ~= currentDayKey then
        -- Preserve the PREVIOUS known wallet as the new day's opening balance
        -- before HandleMoneyChange files any missed delta into the new day.
        tracker.walletDayKey = currentDayKey
        tracker.walletDayStartMoney =
            tonumber(tracker.walletLastMoney) or currentMoney
        tracker.walletDayStartedAt = ServerNow()
    end

    if currentMoney ~= (tonumber(tracker.walletLastMoney) or currentMoney) then
        -- PLAYER_MONEY is the normal path. This fallback catches a missed wallet
        -- event and uses the same transfer-aware logic rather than blindly filing
        -- a positive balance difference as earnings.
        IRS:HandleMoneyChange()
        currentMoney = GetMoney and GetMoney() or currentMoney
    else
        record.money = currentMoney
    end
    IRS:EndStartupTiming(identityTiming)

    local statisticsTiming = IRS:BeginStartupTiming("Character scan: Blizzard statistics")
    local currentStats = {}
    for statName, id in pairs(IRS.STAT_IDS) do
        local value = ReadStatistic(statName, id)
        if value ~= nil then currentStats[statName] = value end
    end

    IRS:UpdateEarningsLedger(record, currentStats)
    record.stats = record.stats or {}
    for statName, value in pairs(currentStats) do
        record.stats[statName] = value
    end
    IRS:EndStartupTiming(statisticsTiming)

    IRS:ScanWarbandGold()

    local totalsTiming = IRS:BeginStartupTiming("Character scan: account totals")
    local totals = IRS:GetTotals()
    if totals.knownWealth > (IRS.db.account.peakKnownWealth or 0) then
        IRS.db.account.peakKnownWealth = totals.knownWealth
    end
    IRS:EndStartupTiming(totalsTiming)

    IRS.db.account.lastScan = ServerNow()
    IRS:UpdateProjectSnapshots()

    if IRS.RefreshUI then IRS:RefreshUI() end

    IRS:EndStartupTiming(scanTiming)
end

-- Aggregates the latest Blizzard lifetime statistics across TRACKED characters.
-- These values power Account Overview. They are separate from the IRS net ledger.
function IRS:GetTotals()
    if not IRS.db then IRS:EnsureDB() end

    local totals = {
        scannedCharacterCount = 0,
        trackedCharacterCount = 0,
        characterCount = 0,
        characterGold = 0,
        warbandGold = IRS.db.account.warbandGoldSeen and (IRS.db.account.warbandGold or 0) or 0,
        warbandGoldSeen = IRS.db.account.warbandGoldSeen,
        peakSingleCharacter = 0,
    }

    for statName in pairs(IRS.STAT_IDS) do totals[statName] = 0 end

    for _, record in pairs(IRS.db.characters) do
        totals.scannedCharacterCount = totals.scannedCharacterCount + 1
        if record.trackingEnabled ~= false then
            totals.trackedCharacterCount = totals.trackedCharacterCount + 1
            totals.characterCount = totals.characterCount + 1
            totals.characterGold = totals.characterGold + (record.money or 0)

            local stats = record.stats or {}
            for statName in pairs(IRS.STAT_IDS) do
                local value = stats[statName]
                if type(value) == "number" and value >= 0 then
                    if statName == "mostGold" then
                        totals.peakSingleCharacter = math.max(totals.peakSingleCharacter, value)
                    elseif statName == "largestBid" or statName == "largestSale" then
                        totals[statName] = math.max(totals[statName], value)
                    elseif statName ~= "avgGoldPerDay" then
                        totals[statName] = totals[statName] + value
                    end
                end
            end
        end
    end

    totals.knownWealth = totals.characterGold + totals.warbandGold

    -- Unlike Travel/Postage, this is IRS-observed spending rather than a Blizzard
    -- lifetime statistic. It begins with the version that introduced tracking.
    totals.transmogSpent = (IRS.db.spending and tonumber(IRS.db.spending.transmog)) or 0
    return totals
end

-- ============================================================================
-- SECTION 7 — DASHBOARD / HISTORY DATA
-- Read-only helpers consumed by the dashboard and reports.
-- ============================================================================
-- Returns the account-wide IRS net values for today, this week, this month,
-- and Total Recorded, plus source-classification data.
function IRS:GetCurrentEarnings()
    if not IRS.db then IRS:EnsureDB() end
    local tracking = IRS.db.tracking
    local dayKey, weekKey, monthKey = IRS:GetPeriodKeys()
    local day = tracking.days[dayKey] or NewBucket()
    local week = tracking.weeks[weekKey] or NewBucket()
    local month = tracking.months[monthKey] or NewBucket()

    return {
        today = day.earned or 0,
        week = week.earned or 0,
        month = month.earned or 0,
        total = tracking.totalEarned or 0,
        daySources = day.sources or {},
        weekSources = week.sources or {},
        monthSources = month.sources or {},
        totalSources = tracking.sources or {},
        startedAt = tracking.startedAt,
        lastEarnedAt = tracking.lastEarnedAt,
        lastEarningAmount = tracking.lastEarningAmount or 0,
    }
end


-- Same idea as GetCurrentEarnings(), but for one scanned character.
function IRS:GetCharacterEarnings(characterKey)
    if not IRS.db then IRS:EnsureDB() end
    characterKey = characterKey or IRS:CharacterKey()
    local record = IRS.db.characters[characterKey]
    if not record then
        return { today = 0, week = 0, month = 0, total = 0 }
    end

    local dayKey, weekKey, monthKey = IRS:GetPeriodKeys()
    local periods = record.periodEarnings or {}
    local days = periods.days or {}
    local weeks = periods.weeks or {}
    local months = periods.months or {}

    return {
        today = days[dayKey] or 0,
        week = weeks[weekKey] or 0,
        month = months[monthKey] or 0,
        total = record.earnedSinceTracking or 0,
    }
end

-- Returns the most recent N daily account-ledger entries for the dashboard graph.
-- Missing days are returned as zero so the chart stays continuous.
function IRS:GetRecentDailyEarnings(count)
    if not IRS.db then IRS:EnsureDB() end
    count = math.max(1, math.min(31, math.floor(tonumber(count) or 7)))

    local results = {}
    local trackingDays = IRS.db.tracking.days or {}
    local now = ServerNow()

    for offset = count - 1, 0, -1 do
        local stamp = now - (offset * 86400)
        local key = date("%Y-%m-%d", stamp)
        local bucket = trackingDays[key]
        table.insert(results, {
            key = key,
            label = offset == 0 and "Today" or date("%a", stamp),
            dateLabel = offset == 0 and date("%b %d", stamp) or date("%b %d", stamp),
            amount = bucket and (bucket.earned or 0) or 0,
        })
    end

    return results
end

local MONTH_NAMES = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

-- Converts database period keys into human-readable report labels.
local function FormatHistoryLabel(period, key)
    if period == "days" then
        local y, m, d = tostring(key):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        if y and m and d then
            return string.format("%s %d, %s", MONTH_NAMES[tonumber(m)] or m, tonumber(d), y)
        end
    elseif period == "months" then
        local y, m = tostring(key):match("^(%d%d%d%d)%-(%d%d)$")
        if y and m then
            return string.format("%s %s", MONTH_NAMES[tonumber(m)] or m, y)
        end
    elseif period == "weeks" then
        local stamp = tonumber(key)
        if stamp then
            return "Week of " .. date("%b %d, %Y", stamp)
        end
    end
    return tostring(key)
end

-- ============================================================================
-- SECTION 8 — REPORTING
-- Builds history, averages, and source breakdowns.
-- ============================================================================
-- Builds report rows for Day / Week / Month. If characterKey is nil or "all",
-- returns account history; otherwise returns that character's contribution.
function IRS:GetReportHistory(period, characterKey)
    if not IRS.db then IRS:EnsureDB() end
    period = (period == "weeks" or period == "months") and period or "days"

    local source
    local isCharacter = characterKey ~= nil and characterKey ~= "all"
    if isCharacter then
        local record = IRS.db.characters[characterKey]
        local periods = record and record.periodEarnings or nil
        source = periods and periods[period] or {}
    else
        source = IRS.db.tracking[period] or {}
    end

    local rows = {}
    for key, value in pairs(source or {}) do
        local amount
        if isCharacter then
            amount = tonumber(value) or 0
        else
            amount = type(value) == "table" and (tonumber(value.earned) or 0) or (tonumber(value) or 0)
        end
        table.insert(rows, {
            key = key,
            label = FormatHistoryLabel(period, key),
            amount = amount,
        })
    end

    table.sort(rows, function(a, b)
        if period == "weeks" then
            return (tonumber(a.key) or 0) > (tonumber(b.key) or 0)
        end
        return tostring(a.key) > tostring(b.key)
    end)
    return rows
end

-- Calculates Best Day, daily/weekly/monthly averages, sample counts, and total
-- recorded net gold for the chosen report scope.
function IRS:GetReportMetrics(characterKey)
    if not IRS.db then IRS:EnsureDB() end

    -- Reports uses "all" as the UI sentinel for the account-wide scope.
    -- Do not use `(condition and nil or value)` here: nil is falsey in Lua, so
    -- that expression resolves straight back to "all". That made Total Recorded
    -- look for a character literally keyed "all" and return 0g.
    local scopeKey = characterKey
    if scopeKey == "all" then
        scopeKey = nil
    end

    local days = IRS:GetReportHistory("days", scopeKey)
    local weeks = IRS:GetReportHistory("weeks", scopeKey)
    local months = IRS:GetReportHistory("months", scopeKey)

    local function Average(rows)
        if #rows == 0 then return 0 end
        local total = 0
        for _, row in ipairs(rows) do total = total + (row.amount or 0) end
        return math.floor(total / #rows)
    end

    local bestDayLabel, bestDayAmount = "—", nil
    for _, row in ipairs(days) do
        local amount = row.amount or 0
        if bestDayAmount == nil or amount > bestDayAmount then
            bestDayAmount = amount
            bestDayLabel = row.label or "—"
        end
    end
    bestDayAmount = bestDayAmount or 0

    local total
    if scopeKey then
        local record = IRS.db.characters[scopeKey]
        total = record and (record.earnedSinceTracking or 0) or 0
    else
        total = IRS.db.tracking.totalEarned or 0
    end

    return {
        bestDayLabel = bestDayLabel,
        bestDayAmount = bestDayAmount,
        dailyAverage = Average(days),
        weeklyAverage = Average(weeks),
        monthlyAverage = Average(months),
        total = total,
        dayCount = #days,
        weekCount = #weeks,
        monthCount = #months,
    }
end

-- Aggregates Blizzard LIFETIME wealth statistics for the chosen scope.
-- This report can predate IRS because Blizzard owns the underlying counters.
function IRS:GetLifetimeSourceBreakdown(characterKey)
    if not IRS.db then IRS:EnsureDB() end
    local result = {
        totalAcquired = 0,
        goldLooted = 0,
        questGold = 0,
        vendorGold = 0,
        auctionGold = 0,
        otherIncome = 0,
    }

    local function AddRecord(record)
        local stats = record and record.stats or {}
        result.totalAcquired = result.totalAcquired + (tonumber(stats.totalAcquired) or 0)
        result.goldLooted = result.goldLooted + (tonumber(stats.goldLooted) or 0)
        result.questGold = result.questGold + (tonumber(stats.questGold) or 0)
        result.vendorGold = result.vendorGold + (tonumber(stats.vendorGold) or 0)
        result.auctionGold = result.auctionGold + (tonumber(stats.auctionGold) or 0)
    end

    if characterKey and characterKey ~= "all" then
        AddRecord(IRS.db.characters[characterKey])
    else
        for _, record in pairs(IRS.db.characters or {}) do AddRecord(record) end
    end

    local categorized = result.goldLooted + result.questGold + result.vendorGold + result.auctionGold
    result.otherIncome = math.max(0, result.totalAcquired - categorized)
    return result
end

-- Returns the display name used by Reports for "All Characters" or one toon.
function IRS:GetScopeName(characterKey)
    if not characterKey or characterKey == "all" then return "All Characters" end
    local record = IRS.db and IRS.db.characters and IRS.db.characters[characterKey]
    if not record then return "Unknown Character" end
    return record.name or record.label or "Unknown Character"
end


-- ============================================================================
-- SECTION 9 — SAVINGS PROJECTS
-- Persistent long-term goals, funding sources, daily snapshots, and graph data.
-- ============================================================================
-- SAVINGS PROJECTS ---------------------------------------------------------
-- Returns today's YYYY-MM-DD key using the same date logic as the main ledger.
local function CurrentDateKey()
    return select(1, IRS:GetPeriodKeys())
end

-- Converts YYYY-MM-DD into a stable day number. Using an ordinal avoids DST and
-- timezone surprises when a savings project calculates days remaining.
local function DateKeyToOrdinal(key)
    if type(key) ~= "string" then return nil end
    local y, m, d = key:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d or m < 1 or m > 12 then return nil end
    local monthDays = {31,28,31,30,31,30,31,31,30,31,30,31}
    local leap = (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
    if leap then monthDays[2] = 29 end
    if d < 1 or d > monthDays[m] then return nil end

    -- Gregorian civil date to a stable day ordinal. This avoids local/server
    -- timezone and daylight-saving differences when calculating project days.
    local yy = y
    local mm = m
    if mm <= 2 then yy = yy - 1; mm = mm + 12 end
    return (365 * yy) + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400)
        + math.floor((153 * (mm - 3) + 2) / 5) + d
end

-- Returns the number of calendar days from date A to date B.
local function DaysBetweenDateKeys(a, b)
    local da, db = DateKeyToOrdinal(a), DateKeyToOrdinal(b)
    if not da or not db then return nil end
    return db - da
end


local function ParseProjectDateKey(key)
    if type(key) ~= "string" then return nil end
    local y, m, d = key:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d then return nil end
    return y, m, d
end

local function ProjectDaysInMonth(year, month)
    local monthDays = {31,28,31,30,31,30,31,31,30,31,30,31}
    local leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    if leap then monthDays[2] = 29 end
    return monthDays[month]
end

-- Adds a non-negative number of calendar days to YYYY-MM-DD without relying on
-- local-machine timezone conversion.
local function AddDaysToProjectDateKey(key, days)
    local y, m, d = ParseProjectDateKey(key)
    if not y then return key end

    days = math.max(0, math.floor(tonumber(days) or 0))

    while days > 0 do
        local remaining = ProjectDaysInMonth(y, m) - d

        if days <= remaining then
            d = d + days
            days = 0
        else
            days = days - remaining - 1
            d = 1
            m = m + 1

            if m > 12 then
                m = 1
                y = y + 1
            end
        end
    end

    return string.format("%04d-%02d-%02d", y, m, d)
end

local GRAPH_MONTH_NAMES = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

local function FormatGraphAxisDate(key, interval, elapsedDays)
    local y, m, d = ParseProjectDateKey(key)
    if not y then return tostring(key or "") end

    if interval == "monthly" then
        return string.format("%s '%02d", GRAPH_MONTH_NAMES[m], y % 100)
    elseif interval == "weekly" then
        local weekNumber = math.floor((tonumber(elapsedDays) or 0) / 7) + 1
        return string.format("W%d %d/%d", weekNumber, m, d)
    end

    return string.format("%d/%d", m, d)
end

-- Keeps axis labels readable by reducing a long sequence to at most maxTicks,
-- always preserving the first and last checkpoint.
local function ThinProjectGraphTicks(ticks, maxTicks)
    if #ticks <= maxTicks then return ticks end

    local result = {}
    local used = {}

    for i = 1, maxTicks do
        local raw = 1 + ((i - 1) * (#ticks - 1) / (maxTicks - 1))
        local index = math.floor(raw + 0.5)

        if not used[index] then
            table.insert(result, ticks[index])
            used[index] = true
        end
    end

    return result
end


local function FormatCheckpointAxisGold(copper)
    local gold = math.floor(math.max(0, tonumber(copper) or 0) / 10000)

    if gold >= 1000000 then
        return string.format("%.1fm", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.0fk", gold / 1000)
    end

    return tostring(gold) .. "g"
end

-- Validates the project deadline field (YYYY-MM-DD).
function IRS:ValidateProjectDeadline(deadline)
    local ordinal = DateKeyToOrdinal(deadline)
    return ordinal ~= nil, ordinal
end

-- Guild-bank reads are only trustworthy while the bank is actually available.
-- In particular, GetGuildBankMoney() can report 0 before bank data is ready.
IRS.guildBankRuntime = IRS.guildBankRuntime or {
    isOpen = false,
    hasMoneyUpdate = false,
}

-- Creates a stable "Guild@Realm" identifier for the player's current guild.
function IRS:GetCurrentGuildKey()
    if not IsInGuild or not IsInGuild() then return nil end
    local guildName, guildRealm
    if GetGuildInfo then
        local name, _, _, realm = GetGuildInfo("player")
        guildName, guildRealm = name, realm
    end
    if not guildName or guildName == "" then return nil end
    local realm = guildRealm or (GetRealmName and GetRealmName()) or "Unknown"
    return guildName .. "@" .. realm, guildName, realm
end

-- Reads guild-bank money from BOTH APIs currently available on Retail.
--
-- Why both?
--   C_Bank.FetchDepositedMoney(Enum.BankType.Guild) is the modern Bank API.
--   GetGuildBankMoney() is the older guild-bank-frame API.
--
-- In practice one can briefly report 0 while the other already has the live
-- balance. IRS therefore compares both rather than accepting the first 0 it sees.
local function FetchGuildBankGold()
    local legacyAmount
    local modernAmount

    if GetGuildBankMoney then
        local ok, value = pcall(GetGuildBankMoney)
        if ok and type(value) == "number" and value >= 0 then
            legacyAmount = value
        end
    end

    if C_Bank
        and C_Bank.FetchDepositedMoney
        and Enum
        and Enum.BankType
        and Enum.BankType.Guild ~= nil then

        local ok, value = pcall(
            C_Bank.FetchDepositedMoney,
            Enum.BankType.Guild
        )

        if ok and type(value) == "number" and value >= 0 then
            modernAmount = value
        end
    end

    -- GetGuildBankMoney is tied directly to the guild-bank frame and is the
    -- preferred live value while the bank is open.
    if legacyAmount and legacyAmount > 0 then
        return legacyAmount, "GetGuildBankMoney", legacyAmount, modernAmount
    end

    if modernAmount and modernAmount > 0 then
        return modernAmount, "C_Bank.FetchDepositedMoney", legacyAmount, modernAmount
    end

    -- If neither API has a positive value, preserve the diagnostic 0/nil state
    -- so ScanGuildBankGold can decide whether zero is actually trustworthy.
    if legacyAmount ~= nil then
        return legacyAmount, "GetGuildBankMoney", legacyAmount, modernAmount
    end

    if modernAmount ~= nil then
        return modernAmount, "C_Bank.FetchDepositedMoney", legacyAmount, modernAmount
    end

    return nil, "none", legacyAmount, modernAmount
end

-- Saves the current guild-bank balance so projects can use it later even when
-- the bank window is closed.
--
-- Safety rule:
--   IRS NEVER treats a closed-bank 0g read as a successful refresh. The last
--   valid cached balance remains intact until Blizzard has exposed the bank.
--
-- allowZero should only be true after GUILDBANK_UPDATE_MONEY has fired.
function IRS:ScanGuildBankGold(allowZero)
    if not IRS.db then IRS:EnsureDB() end

    local guildKey, guildName, realm = IRS:GetCurrentGuildKey()
    if not guildKey then return nil, nil, "no-guild" end

    local runtime = IRS.guildBankRuntime or {}
    local canViewModern = false

    if C_Bank
        and C_Bank.CanViewBank
        and Enum
        and Enum.BankType
        and Enum.BankType.Guild ~= nil then

        local ok, value = pcall(
            C_Bank.CanViewBank,
            Enum.BankType.Guild
        )
        canViewModern = ok and value == true
    end

    if canViewModern then
        runtime.isOpen = true
    end

    local amount, sourceName, legacyAmount, modernAmount =
        FetchGuildBankGold()

    runtime.lastLegacyAmount = legacyAmount
    runtime.lastModernAmount = modernAmount
    runtime.lastReadSource = sourceName
    runtime.lastReadAt = ServerNow()

    if amount == nil then
        return nil, guildKey, "unavailable"
    end

    local record = IRS.db.guildBanks[guildKey] or {}
    local previousAmount = record.money ~= nil
        and tonumber(record.money)
        or nil

    -- A positive value is useful even if our OPENED event was missed. This is
    -- important for manual Sync and for clients where bank-frame timing differs.
    if amount > 0 then
        IRS.db.guildBanks[guildKey] = record
        record.key = guildKey
        record.name = guildName
        record.realm = realm
        record.money = amount
        record.lastSeen = ServerNow()
        record.lastReadSource = sourceName

        -- allowZero is only used by GUILDBANK_UPDATE_MONEY in the current event
        -- flow. Do not treat the initial bank-open cache refresh as a transfer:
        -- the balance may have changed while the player was offline.
        if allowZero
            and previousAmount ~= nil
            and previousAmount ~= amount
            and IRS.ObserveInternalStorageDelta then
            IRS:ObserveInternalStorageDelta(
                "guild",
                guildKey,
                amount - previousAmount
            )
        end

        return amount, guildKey, "ok", sourceName
    end

    -- Never overwrite a positive cached balance with a suspicious zero.
    if (tonumber(record.money) or 0) > 0 then
        return nil, guildKey, "zero-preserved", sourceName
    end

    -- A zero is only accepted when Blizzard has explicitly fired the money
    -- update while IRS believes the bank is viewable/open, or when the caller
    -- requested a confirmed-zero scan under those same conditions.
    local zeroConfirmed =
        runtime.isOpen
        and (
            runtime.hasMoneyUpdate
            or (allowZero and canViewModern)
        )

    if not zeroConfirmed then
        return nil, guildKey, "zero-unconfirmed", sourceName
    end

    IRS.db.guildBanks[guildKey] = record
    record.key = guildKey
    record.name = guildName
    record.realm = realm
    record.money = 0
    record.lastSeen = ServerNow()
    record.lastReadSource = sourceName

    if allowZero
        and previousAmount ~= nil
        and previousAmount ~= 0
        and IRS.ObserveInternalStorageDelta then
        IRS:ObserveInternalStorageDelta(
            "guild",
            guildKey,
            -previousAmount
        )
    end

    return 0, guildKey, "ok", sourceName
end

function IRS:GetGuildBankCacheStatus(guildKey)
    if not IRS.db then IRS:EnsureDB() end

    guildKey = guildKey or IRS:GetCurrentGuildKey()
    local record = guildKey and IRS.db.guildBanks[guildKey] or nil

    return {
        open = IRS.guildBankRuntime and IRS.guildBankRuntime.isOpen == true,
        hasMoneyUpdate = IRS.guildBankRuntime
            and IRS.guildBankRuntime.hasMoneyUpdate == true,
        key = guildKey,
        record = record,
        money = record and tonumber(record.money) or nil,
        lastSeen = record and record.lastSeen or nil,
        lastReadSource = IRS.guildBankRuntime
            and IRS.guildBankRuntime.lastReadSource
            or nil,
        legacyAmount = IRS.guildBankRuntime
            and IRS.guildBankRuntime.lastLegacyAmount
            or nil,
        modernAmount = IRS.guildBankRuntime
            and IRS.guildBankRuntime.lastModernAmount
            or nil,
    }
end

-- Returns cached guild banks alphabetically for the project source picker.
function IRS:GetSortedGuildBanks()
    if not IRS.db then IRS:EnsureDB() end
    local rows = {}
    for key, record in pairs(IRS.db.guildBanks or {}) do
        table.insert(rows, { key = key, record = record })
    end
    table.sort(rows, function(a, b)
        return (a.record.name or a.key or "") < (b.record.name or b.key or "")
    end)
    return rows
end

-- Adds last-known wallets for ALL scanned characters plus the Warband Bank.
-- Guild-bank gold is deliberately excluded from "Account Liquid Gold".
function IRS:GetAccountLiquidGoldAllCharacters()
    if not IRS.db then IRS:EnsureDB() end
    local total = 0
    for _, record in pairs(IRS.db.characters or {}) do
        total = total + math.max(0, tonumber(record.money) or 0)
    end
    if IRS.db.account.warbandGoldSeen then
        total = total + math.max(0, tonumber(IRS.db.account.warbandGold) or 0)
    end
    return math.floor(total)
end

-- Resolves a project's selected funding source and returns:
-- balance, available?, human-readable source label.
function IRS:GetProjectSourceBalance(project)
    if not IRS.db then IRS:EnsureDB() end
    project = project or {}
    local sourceType = project.sourceType or "account"

    if sourceType == "account" then
        return IRS:GetAccountLiquidGoldAllCharacters(), true, "Account Liquid Gold"
    elseif sourceType == "warband" then
        if IRS.db.account.warbandGoldSeen then
            return math.max(0, tonumber(IRS.db.account.warbandGold) or 0), true, "Warband Bank"
        end
        return 0, false, "Warband Bank"
    elseif sourceType == "character" then
        local record = project.sourceKey and IRS.db.characters[project.sourceKey]
        if record then
            return math.max(0, tonumber(record.money) or 0), true, record.label or record.name or "Character"
        end
        return 0, false, "Character unavailable"
    elseif sourceType == "guild" then
        local record = project.sourceKey and IRS.db.guildBanks[project.sourceKey]
        if record and record.money ~= nil then
            return math.max(0, tonumber(record.money) or 0), true, (record.name or "Guild") .. " Guild Bank"
        end
        return 0, false, "Guild Bank unavailable"
    end
    return 0, false, "Unknown Source"
end

-- Applies the project's allocation percentage to its selected source balance.
-- Example: 25% of a 4m Warband Bank = 1m allocated to this project view.
function IRS:GetProjectAllocatedBalance(project)
    local sourceBalance, available, label = IRS:GetProjectSourceBalance(project)
    local pct = tonumber(project and project.allocationPercent) or 100
    pct = math.max(0, math.min(100, pct))
    return math.floor(sourceBalance * (pct / 100)), available, label, sourceBalance
end

-- ---------------------------------------------------------------------------
-- CENTRAL SOURCE HISTORY
-- ---------------------------------------------------------------------------
-- Physical/source balances are recorded once at the IRS level. Projects only
-- describe a goal, a date window, and configuration changes; they never own or
-- delete financial history anymore.
local function ProjectSourceHistoryId(sourceType, sourceKey)
    sourceType = tostring(sourceType or "account")
    if sourceType == "account" or sourceType == "warband" then
        return sourceType
    end
    return sourceType .. ":" .. tostring(sourceKey or "")
end

local function EnsureProjectConfigHistory(project)
    if not project then return {} end

    project.startDate = project.startDate
        or project.createdDay
        or CurrentDateKey()
    project.configHistory = project.configHistory or {}

    -- Import the former configuration audit format when needed.
    if #project.configHistory == 0 then
        local legacy = project.configurationHistory or {}
        table.sort(legacy, function(a, b)
            local ad = tostring(a.day or "")
            local bd = tostring(b.day or "")
            if ad == bd then
                return (tonumber(a.changedAt) or 0) < (tonumber(b.changedAt) or 0)
            end
            return ad < bd
        end)

        if #legacy > 0 then
            local first = legacy[1]
            table.insert(project.configHistory, {
                effectiveDay = project.startDate,
                changedAt = tonumber(project.createdAt) or 0,
                sourceType = first.oldSourceType or project.sourceType or "account",
                sourceKey = first.oldSourceKey,
                allocationPercent = tonumber(first.oldAllocationPercent) or 100,
            })

            for _, event in ipairs(legacy) do
                table.insert(project.configHistory, {
                    effectiveDay = tostring(event.day or project.startDate),
                    changedAt = tonumber(event.changedAt) or 0,
                    sourceType = event.newSourceType or project.sourceType or "account",
                    sourceKey = event.newSourceKey,
                    allocationPercent = tonumber(event.newAllocationPercent) or 100,
                })
            end
        else
            table.insert(project.configHistory, {
                effectiveDay = project.startDate,
                changedAt = tonumber(project.createdAt) or 0,
                sourceType = project.sourceType or "account",
                sourceKey = project.sourceKey,
                allocationPercent = tonumber(project.allocationPercent) or 100,
            })
        end
    end

    project.configurationHistory = nil

    table.sort(project.configHistory, function(a, b)
        local ad = tostring(a.effectiveDay or "")
        local bd = tostring(b.effectiveDay or "")
        if ad == bd then
            return (tonumber(a.changedAt) or 0) < (tonumber(b.changedAt) or 0)
        end
        return ad < bd
    end)

    return project.configHistory
end

function IRS:GetProjectConfigForDate(projectId, dateKey)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return nil end

    local history = EnsureProjectConfigHistory(project)
    local wanted = tostring(dateKey or CurrentDateKey())
    local selected

    for _, config in ipairs(history) do
        local effective = tostring(config.effectiveDay or project.startDate or "")
        if effective <= wanted then
            selected = config
        else
            break
        end
    end

    -- If the player moves a Start Date earlier than IRS's first configuration
    -- record, the oldest known configuration is the best available rule for that
    -- earlier window. Gold data itself is never fabricated; missing source days
    -- simply remain unavailable.
    selected = selected or history[1]

    if not selected then return nil end
    return {
        sourceType = selected.sourceType or project.sourceType or "account",
        sourceKey = selected.sourceKey,
        allocationPercent = math.max(
            0,
            math.min(100, tonumber(selected.allocationPercent) or 100)
        ),
        effectiveDay = selected.effectiveDay,
        changedAt = selected.changedAt,
    }
end

local function EnsureSourceDay(dateKey)
    IRS.db.sourceHistory = IRS.db.sourceHistory or {days = {}}
    IRS.db.sourceHistory.days = IRS.db.sourceHistory.days or {}
    local day = IRS.db.sourceHistory.days[dateKey]
    if not day then
        day = {sources = {}}
        IRS.db.sourceHistory.days[dateKey] = day
    end
    day.sources = day.sources or {}
    return day
end

local function RecordSourceSnapshot(sourceType, sourceKey, dateKey, startBalance, endBalance, preserveExisting)
    if not IRS.db then IRS:EnsureDB() end
    dateKey = tostring(dateKey or CurrentDateKey())
    local day = EnsureSourceDay(dateKey)
    local id = ProjectSourceHistoryId(sourceType, sourceKey)
    local row = day.sources[id]

    if not row then
        row = {
            sourceType = sourceType or "account",
            sourceKey = sourceKey,
            start = math.floor(tonumber(startBalance) or tonumber(endBalance) or 0),
            ending = math.floor(tonumber(endBalance) or tonumber(startBalance) or 0),
            firstSeen = ServerNow(),
            lastSeen = ServerNow(),
        }
        day.sources[id] = row
    else
        if row.start == nil then
            row.start = math.floor(tonumber(startBalance) or tonumber(endBalance) or 0)
        elseif not preserveExisting and startBalance ~= nil and row.firstSeen == nil then
            row.start = math.floor(tonumber(startBalance) or row.start or 0)
        end

        if not preserveExisting or row.ending == nil then
            row.ending = math.floor(tonumber(endBalance) or row.ending or row.start or 0)
        end
        row.lastSeen = ServerNow()
    end

    return row
end

function IRS:CaptureDailySourceHistory()
    if not IRS.db then IRS:EnsureDB() end
    local dayKey = CurrentDateKey()

    RecordSourceSnapshot(
        "account",
        nil,
        dayKey,
        nil,
        IRS:GetAccountLiquidGoldAllCharacters()
    )

    if IRS.db.account.warbandGoldSeen then
        RecordSourceSnapshot(
            "warband",
            nil,
            dayKey,
            nil,
            math.max(0, tonumber(IRS.db.account.warbandGold) or 0)
        )
    end

    for key, record in pairs(IRS.db.characters or {}) do
        local money = math.max(0, tonumber(record.money) or 0)
        local startMoney
        local tracker = record.earningsTracker
        if tracker
            and tracker.walletDayKey == dayKey
            and tracker.walletDayStartMoney ~= nil then
            startMoney = math.max(0, tonumber(tracker.walletDayStartMoney) or 0)
        end

        RecordSourceSnapshot("character", key, dayKey, startMoney, money)
    end

    for key, record in pairs(IRS.db.guildBanks or {}) do
        if record.money ~= nil then
            RecordSourceSnapshot(
                "guild",
                key,
                dayKey,
                nil,
                math.max(0, tonumber(record.money) or 0)
            )
        end
    end
end

function IRS:EnsureProjectSourceHistoryMigration()
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.migrations = IRS.db.migrations or {}
    if IRS.db.migrations.projectSourceHistory150 then return end

    -- Import legacy project-owned snapshots into shared source history.
    for _, project in pairs(IRS.db.projects.items or {}) do
        EnsureProjectConfigHistory(project)

        for dayKey, legacyDay in pairs(project.daily or {}) do
            local config = IRS:GetProjectConfigForDate(project, dayKey)
            local pct = config and tonumber(config.allocationPercent) or 0

            if config and pct and pct > 0 then
                local allocatedStart = tonumber(legacyDay.start)
                local allocatedEnd = tonumber(legacyDay.ending)
                    or allocatedStart

                if allocatedStart ~= nil or allocatedEnd ~= nil then
                    local divisor = pct / 100
                    local rawStart = allocatedStart ~= nil
                        and math.floor((allocatedStart / divisor) + 0.5)
                        or nil
                    local rawEnd = allocatedEnd ~= nil
                        and math.floor((allocatedEnd / divisor) + 0.5)
                        or rawStart

                    RecordSourceSnapshot(
                        config.sourceType,
                        config.sourceKey,
                        dayKey,
                        rawStart,
                        rawEnd,
                        true
                    )
                end
            end
        end

        project.daily = nil
    end

    IRS.db.migrations.projectSourceHistory150 = ServerNow()
end

function IRS:GetProjectSourceHistory(projectId, descending)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    local rows = {}
    if not project then return rows end

    IRS:EnsureProjectSourceHistoryMigration()
    IRS:CaptureDailySourceHistory()

    local startDate = project.startDate or project.createdDay or CurrentDateKey()
    local endDate = project.deadline or CurrentDateKey()
    local today = CurrentDateKey()
    if endDate > today then endDate = today end

    for dayKey, day in pairs(IRS.db.sourceHistory.days or {}) do
        if dayKey >= startDate and dayKey <= endDate then
            local config = IRS:GetProjectConfigForDate(project, dayKey)
            if config then
                local id = ProjectSourceHistoryId(config.sourceType, config.sourceKey)
                local source = day.sources and day.sources[id]
                if source then
                    local pct = (tonumber(config.allocationPercent) or 100) / 100
                    local rawStart = tonumber(source.start) or tonumber(source.ending) or 0
                    local rawEnd = tonumber(source.ending) or rawStart
                    local allocatedStart = math.floor(rawStart * pct)
                    local allocatedEnd = math.floor(rawEnd * pct)

                    table.insert(rows, {
                        key = dayKey,
                        label = dayKey,
                        start = allocatedStart,
                        ending = allocatedEnd,
                        change = allocatedEnd - allocatedStart,
                        sourceStart = rawStart,
                        sourceEnding = rawEnd,
                        sourceType = config.sourceType,
                        sourceKey = config.sourceKey,
                        allocationPercent = config.allocationPercent,
                    })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if descending then return a.key > b.key end
        return a.key < b.key
    end)

    return rows
end

-- Returns savings projects in stable creation order for the Projects sidebar/list.
function IRS:GetSortedProjects()
    if not IRS.db then IRS:EnsureDB() end
    local rows = {}
    for id, project in pairs(IRS.db.projects.items or {}) do
        table.insert(rows, { id = tonumber(id) or id, project = project })
    end
    table.sort(rows, function(a, b)
        local ac, bc = tonumber(a.project.createdAt) or 0, tonumber(b.project.createdAt) or 0
        if ac == bc then return tostring(a.project.name or "") < tostring(b.project.name or "") end
        return ac < bc
    end)
    return rows
end

-- Looks up one persistent project by its numeric/string ID.
function IRS:GetProject(projectId)
    if not IRS.db then IRS:EnsureDB() end
    return IRS.db.projects.items[projectId] or IRS.db.projects.items[tostring(projectId)]
end

-- Records today's observed source balance for a Project.
function IRS:UpdateProjectSnapshot(project)
    if not project then return end
    IRS:EnsureProjectSourceHistoryMigration()

    local sourceBalance, available = IRS:GetProjectSourceBalance(project)
    if available then
        RecordSourceSnapshot(
            project.sourceType or "account",
            project.sourceKey,
            CurrentDateKey(),
            nil,
            sourceBalance
        )
    end

end

-- Refreshes IRS shared source-history observations.
function IRS:UpdateProjectSnapshots()
    local startupTiming = IRS:BeginStartupTiming("Project snapshot update")

    if not IRS.db then IRS:EnsureDB() end
    IRS:EnsureProjectSourceHistoryMigration()
    IRS:CaptureDailySourceHistory()

    IRS:EndStartupTiming(startupTiming)
end

-- Validates form data, creates a persistent project, and records its opening
-- daily balance. Returns projectId/project or an error message.
function IRS:CreateProject(data)
    if not IRS.db then IRS:EnsureDB() end
    data = data or {}

    local target = math.floor(tonumber(data.targetCopper) or 0)
    local allocation = tonumber(data.allocationPercent) or 100
    local startDate = tostring(data.startDate or CurrentDateKey())
    local deadline = tostring(data.deadline or "")
    local validStart = IRS:ValidateProjectDeadline(startDate)
    local validDeadline = IRS:ValidateProjectDeadline(deadline)

    if target <= 0 then return nil, "Target must be greater than 0 gold." end
    if not validStart then return nil, "Start Date must use YYYY-MM-DD." end
    if not validDeadline then return nil, "Deadline must use YYYY-MM-DD." end
    if (DaysBetweenDateKeys(startDate, deadline) or -1) < 0 then
        return nil, "Deadline cannot be before the Start Date."
    end
    if allocation <= 0 or allocation > 100 then
        return nil, "Allocation must be between 1 and 100%."
    end

    local id = IRS.db.projects.nextId
    IRS.db.projects.nextId = id + 1
    local now = ServerNow()
    local project = {
        id = id,
        name = (data.name and strtrim(tostring(data.name))) or "Savings Project",
        targetCopper = target,
        startDate = startDate,
        deadline = deadline,
        sourceType = data.sourceType or "account",
        sourceKey = data.sourceKey,
        allocationPercent = allocation,
        graphInterval = "daily",
        checkpoints = {},
        nextCheckpointId = 1,
        createdAt = now,
        createdDay = CurrentDateKey(),
        configHistory = {
            {
                effectiveDay = startDate,
                changedAt = now,
                sourceType = data.sourceType or "account",
                sourceKey = data.sourceKey,
                allocationPercent = allocation,
            },
        },
    }

    if project.name == "" then project.name = "Savings Project" end
    IRS.db.projects.items[id] = project

    IRS.db.settings.miniProjectVisibility = IRS.db.settings.miniProjectVisibility or {}
    IRS.db.settings.miniProjectVisibility[tostring(id)] = true

    IRS:UpdateProjectSnapshot(project)
    return id, project
end

-- Saves edits to an existing project and refreshes its current-day snapshot.
function IRS:UpdateProject(projectId, data)
    if not IRS.db then IRS:EnsureDB() end
    local project = IRS:GetProject(projectId)
    if not project then return false, "Project not found." end
    data = data or {}

    EnsureProjectConfigHistory(project)

    local target = math.floor(tonumber(data.targetCopper) or project.targetCopper or 0)
    local allocation = tonumber(data.allocationPercent) or project.allocationPercent or 100
    local startDate = tostring(data.startDate or project.startDate or project.createdDay or CurrentDateKey())
    local deadline = tostring(data.deadline or project.deadline or "")
    local validStart = IRS:ValidateProjectDeadline(startDate)
    local validDeadline = IRS:ValidateProjectDeadline(deadline)

    if target <= 0 then return false, "Target must be greater than 0 gold." end
    if not validStart then return false, "Start Date must use YYYY-MM-DD." end
    if not validDeadline then return false, "Deadline must use YYYY-MM-DD." end
    if (DaysBetweenDateKeys(startDate, deadline) or -1) < 0 then
        return false, "Deadline cannot be before the Start Date."
    end
    if allocation <= 0 or allocation > 100 then
        return false, "Allocation must be between 1 and 100%."
    end

    local oldSourceType = project.sourceType or "account"
    local oldSourceKey = project.sourceKey
    local oldAllocation = tonumber(project.allocationPercent) or 100

    project.name = strtrim(tostring(data.name or project.name or "Savings Project"))
    if project.name == "" then project.name = "Savings Project" end
    project.targetCopper = target
    project.startDate = startDate
    project.deadline = deadline
    project.sourceType = data.sourceType or project.sourceType or "account"
    project.sourceKey = data.sourceKey
    project.allocationPercent = allocation

    local configurationChanged =
        oldSourceType ~= project.sourceType
        or oldSourceKey ~= project.sourceKey
        or oldAllocation ~= allocation

    if configurationChanged then
        -- Configuration changes are metadata only. The gold observations live in
        -- db.sourceHistory and cannot be destroyed by saving this project.
        table.insert(project.configHistory, {
            effectiveDay = CurrentDateKey(),
            changedAt = ServerNow(),
            sourceType = project.sourceType,
            sourceKey = project.sourceKey,
            allocationPercent = allocation,
        })
    end

    IRS:UpdateProjectSnapshot(project)
    return true, project
end

-- Lazily initializes checkpoint storage for existing projects.
local function EnsureProjectCheckpointStorage(project)
    if not project then return end
    project.checkpoints = project.checkpoints or {}

    if tonumber(project.nextCheckpointId) == nil then
        local highest = 0
        for _, checkpoint in pairs(project.checkpoints) do
            highest = math.max(highest, tonumber(checkpoint.id) or 0)
        end
        project.nextCheckpointId = highest + 1
    end
end

-- Returns checkpoint references sorted from the smallest gold milestone to the
-- largest. Equal amounts retain stable ID ordering.
function IRS:GetProjectCheckpoints(projectId)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    local rows = {}
    if not project then return rows end

    EnsureProjectCheckpointStorage(project)

    for _, checkpoint in pairs(project.checkpoints) do
        if type(checkpoint) == "table" then
            table.insert(rows, checkpoint)
        end
    end

    table.sort(rows, function(a, b)
        local aa = tonumber(a.amountCopper) or 0
        local bb = tonumber(b.amountCopper) or 0

        if aa == bb then
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
        end

        return aa < bb
    end)

    return rows
end

function IRS:AddProjectCheckpoint(projectId, name, amountCopper)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return nil, "Project not found." end

    EnsureProjectCheckpointStorage(project)

    name = strtrim(tostring(name or ""))
    amountCopper = math.floor(tonumber(amountCopper) or 0)
    local target = math.max(0, tonumber(project.targetCopper) or 0)

    if name == "" then return nil, "Give the checkpoint a name." end
    if amountCopper <= 0 then
        return nil, "Checkpoint gold must be greater than 0."
    end
    if target > 0 and amountCopper >= target then
        return nil, "Checkpoint gold must be below the project's final target."
    end

    local id = project.nextCheckpointId
    project.nextCheckpointId = id + 1

    local checkpoint = {
        id = id,
        name = name,
        amountCopper = amountCopper,
    }

    table.insert(project.checkpoints, checkpoint)

    return id, checkpoint
end

function IRS:UpdateProjectCheckpoint(projectId, checkpointId, name, amountCopper)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return false, "Project not found." end

    EnsureProjectCheckpointStorage(project)

    name = strtrim(tostring(name or ""))
    amountCopper = math.floor(tonumber(amountCopper) or 0)
    local target = math.max(0, tonumber(project.targetCopper) or 0)

    if name == "" then return false, "Give the checkpoint a name." end
    if amountCopper <= 0 then
        return false, "Checkpoint gold must be greater than 0."
    end
    if target > 0 and amountCopper >= target then
        return false, "Checkpoint gold must be below the project's final target."
    end

    checkpointId = tonumber(checkpointId)

    for _, checkpoint in pairs(project.checkpoints) do
        if tonumber(checkpoint.id) == checkpointId then
            checkpoint.name = name
            checkpoint.amountCopper = amountCopper
                    return true, checkpoint
        end
    end

    return false, "Checkpoint not found."
end

function IRS:DeleteProjectCheckpoint(projectId, checkpointId)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return false end

    EnsureProjectCheckpointStorage(project)
    checkpointId = tonumber(checkpointId)

    for index, checkpoint in ipairs(project.checkpoints) do
        if tonumber(checkpoint.id) == checkpointId then
            table.remove(project.checkpoints, index)
                    return true
        end
    end

    return false
end

function IRS:GetProjectCheckpointStatus(projectId, checkpoint)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project or not checkpoint then return nil end

    local stats = IRS:GetProjectStats(project)
    local amount = math.max(0, tonumber(checkpoint.amountCopper) or 0)
    local current = stats and tonumber(stats.current) or 0
    local target = stats and tonumber(stats.target) or 0

    return {
        reached = current >= amount and amount > 0,
        remaining = math.max(0, amount - current),
        aboveTarget = target > 0 and amount >= target,
        current = current,
        amount = amount,
    }
end

-- Permanently removes one savings project and its project-specific history.
function IRS:DeleteProject(projectId)
    if not IRS.db then IRS:EnsureDB() end
    if not IRS:GetProject(projectId) then return false end
    IRS.db.projects.items[projectId] = nil
    IRS.db.projects.items[tostring(projectId)] = nil

    if IRS.db.settings and IRS.db.settings.miniProjectVisibility then
        IRS.db.settings.miniProjectVisibility[tostring(projectId)] = nil
    end

    return true
end

-- Calculates the summary numbers displayed on a project:
-- current allocated gold, remaining gold, days left, daily needed, progress %, etc.
function IRS:GetProjectStats(projectId)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return nil end
    IRS:UpdateProjectSnapshot(project)

    local current, available, sourceLabel, sourceBalance =
        IRS:GetProjectAllocatedBalance(project)

    local target = math.max(0, tonumber(project.targetCopper) or 0)
    local remaining = math.max(0, target - current)
    local todayKey = CurrentDateKey()
    local createdKey = project.startDate or project.createdDay or todayKey
    local totalPlanDays = DaysBetweenDateKeys(createdKey, project.deadline)
    totalPlanDays = totalPlanDays and math.max(1, totalPlanDays + 1) or 1
    local daysLeft = DaysBetweenDateKeys(todayKey, project.deadline)
    if daysLeft ~= nil then daysLeft = math.max(0, daysLeft + 1) else daysLeft = 0 end
    local dailyNeeded = daysLeft > 0 and math.ceil(remaining / daysLeft) or remaining
    local pct = target > 0 and math.max(0, math.min(1, current / target)) or 0

    return {
        current = current,
        available = available,
        sourceLabel = sourceLabel,
        sourceBalance = sourceBalance,
        reserved = IRS.GetProjectReservedBalance
            and IRS:GetProjectReservedBalance(project)
            or 0,
        target = target,
        remaining = remaining,
        daysLeft = daysLeft,
        totalPlanDays = totalPlanDays,
        dailyNeeded = dailyNeeded,
        percent = pct,
        achieved = target > 0 and current >= target,
        overdue = daysLeft == 0 and current < target,
        createdDay = project.createdDay or createdKey,
        startDate = createdKey,
        deadline = project.deadline,
    }
end

-- Converts a project's daily snapshot table into sorted rows for the tracker.
function IRS:GetProjectDailyHistory(projectId, descending)
    return IRS:GetProjectSourceHistory(projectId, descending)
end


-- Returns TODAY'S project contribution goal and whether today's observed change
-- has met that goal.
--
-- Why this is separate from GetProjectStats().dailyNeeded:
--   GetProjectStats() answers "how much per remaining day from RIGHT NOW?"
--   This helper answers "what did THIS DAY need when the day began?"
--
-- The mini dashboard uses this so its MET / SHORT status does not move the
-- goalposts downward every time the player earns some gold during the day.
function IRS:GetProjectDailyGoalStatus(projectId)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return nil end

    IRS:UpdateProjectSnapshot(project)

    local todayKey = CurrentDateKey()
    local rows = IRS:GetProjectSourceHistory(project, false)
    local day
    for _, row in ipairs(rows) do
        if row.key == todayKey then
            day = row
            break
        end
    end

    local current, available = IRS:GetProjectAllocatedBalance(project)
    local target = math.max(0, tonumber(project.targetCopper) or 0)

    if not day then
        return {
            available = available,
            dailyGoal = 0,
            todayChange = 0,
            met = false,
            achieved = target > 0 and current >= target,
            shortfall = 0,
        }
    end

    local startValue = tonumber(day.start) or 0
    local endValue = tonumber(day.ending) or startValue
    local todayChange = endValue - startValue

    local daysLeft = DaysBetweenDateKeys(todayKey, project.deadline)
    if daysLeft ~= nil then
        daysLeft = math.max(0, daysLeft + 1)
    else
        daysLeft = 0
    end

    local remainingAtStart = math.max(0, target - startValue)
    local dailyGoal = daysLeft > 0 and math.ceil(remainingAtStart / daysLeft) or remainingAtStart
    local achieved = target > 0 and current >= target
    local met = achieved or dailyGoal <= 0 or todayChange >= dailyGoal
    local shortfall = met and 0 or math.max(0, dailyGoal - todayChange)

    return {
        available = available,
        dailyGoal = dailyGoal,
        todayChange = todayChange,
        met = met,
        achieved = achieved,
        shortfall = shortfall,
        start = startValue,
        ending = endValue,
        dayKey = todayKey,
    }
end


-- Adds together TODAY'S fixed daily goals and observed progress for every
-- project the player has selected for the floating mini dashboard.
--
-- Important:
--   * This includes ALL selected projects, not only the first five visible rows.
--   * Project allocation percentages are respected before values are summed.
--   * If allocations intentionally overlap, the aggregate follows those
--     configured allocations as written.
--   * Unavailable project sources are excluded from the numeric total and
--     reported separately so stale/unknown balances do not distort the result.
function IRS:GetMiniProjectDailySummary()
    if not IRS.db then IRS:EnsureDB() end

    local totalNeeded = 0
    local totalChange = 0
    local trackedCount = 0
    local availableCount = 0
    local unavailableCount = 0

    for _, entry in ipairs(IRS:GetSortedProjects()) do
        if IRS:IsProjectShownInMini(entry.id) then
            trackedCount = trackedCount + 1

            local daily = IRS:GetProjectDailyGoalStatus(entry.project)
            if daily and daily.available then
                availableCount = availableCount + 1
                totalNeeded = totalNeeded + math.max(0, tonumber(daily.dailyGoal) or 0)
                totalChange = totalChange + (tonumber(daily.todayChange) or 0)
            else
                unavailableCount = unavailableCount + 1
            end
        end
    end

    local difference = totalChange - totalNeeded

    return {
        trackedCount = trackedCount,
        availableCount = availableCount,
        unavailableCount = unavailableCount,
        dailyNeeded = totalNeeded,
        todayChange = totalChange,
        difference = difference,
        met = availableCount > 0 and difference >= 0,
    }
end

-- Returns a project's saved trajectory sampling interval.
function IRS:GetProjectGraphInterval(projectId)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return "daily" end

    local interval = project.graphInterval
    if interval ~= "daily"
        and interval ~= "weekly"
        and interval ~= "monthly"
        and interval ~= "checkpoints" then
        interval = "daily"
        project.graphInterval = interval
    end

    return interval
end

-- Saves the Daily / Weekly / Monthly / Checkpoints trajectory view per project.
function IRS:SetProjectGraphInterval(projectId, interval)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return false end

    if interval ~= "daily"
        and interval ~= "weekly"
        and interval ~= "monthly"
        and interval ~= "checkpoints" then
        return false
    end

    project.graphInterval = interval
    return true
end

-- Packages the ideal trajectory plus sampled actual observations for the graph.
--
-- Daily:
--   one actual point per observed day.
--
-- Weekly:
--   one point per 7-day project bucket, using the last observed balance in the
--   bucket. Buckets begin on the project's creation day.
--
-- Monthly:
--   one point per calendar month, using the last observed balance that month.
--
-- IRS still RECORDS daily snapshots. This setting changes graph density only,
-- so switching intervals never discards history.
function IRS:GetProjectGraphData(projectId, requestedInterval)
    local project = type(projectId) == "table" and projectId or IRS:GetProject(projectId)
    if not project then return nil end

    local stats = IRS:GetProjectStats(project)
    local createdKey = project.startDate or project.createdDay or CurrentDateKey()
    local sourceRows = IRS:GetProjectSourceHistory(project, false)
    local firstObserved = sourceRows[1]
    local startAmount = firstObserved and (tonumber(firstObserved.start) or 0) or stats.current or 0
    local totalDays = DaysBetweenDateKeys(createdKey, project.deadline) or 0
    if totalDays < 1 then totalDays = 1 end

    local interval = requestedInterval or IRS:GetProjectGraphInterval(project)
    if interval ~= "daily"
        and interval ~= "weekly"
        and interval ~= "monthly"
        and interval ~= "checkpoints" then
        interval = "daily"
    end

    local sampledRows = {}

    if interval == "daily" then
        sampledRows = sourceRows

    elseif interval == "weekly" then
        local currentBucket, currentRow

        for _, row in ipairs(sourceRows) do
            local elapsed = math.max(0, DaysBetweenDateKeys(createdKey, row.key) or 0)
            local bucket = math.floor(elapsed / 7)

            if currentBucket ~= nil and bucket ~= currentBucket and currentRow then
                table.insert(sampledRows, currentRow)
            end

            currentBucket = bucket
            currentRow = row
        end

        if currentRow then
            table.insert(sampledRows, currentRow)
        end

    elseif interval == "monthly" then
        local currentMonth, currentRow

        for _, row in ipairs(sourceRows) do
            local monthKey = tostring(row.key or ""):sub(1, 7)

            if currentMonth ~= nil and monthKey ~= currentMonth and currentRow then
                table.insert(sampledRows, currentRow)
            end

            currentMonth = monthKey
            currentRow = row
        end

        if currentRow then
            table.insert(sampledRows, currentRow)
        end

    else -- checkpoints
        -- Checkpoint view still uses TIME on the X axis. Sample Actual by the
        -- same 7-day project buckets used by Weekly so reports remain evenly
        -- chronological from project start to deadline.
        local currentBucket, currentRow

        for _, row in ipairs(sourceRows) do
            local elapsed = math.max(
                0,
                DaysBetweenDateKeys(createdKey, row.key) or 0
            )
            local bucket = math.floor(elapsed / 7)

            if currentBucket ~= nil
                and bucket ~= currentBucket
                and currentRow then
                table.insert(sampledRows, currentRow)
            end

            currentBucket = bucket
            currentRow = row
        end

        if currentRow then
            table.insert(sampledRows, currentRow)
        end
    end

    -- ACTUAL starts on the first date IRS truly has source history for. If the
    -- player chooses a Start Date earlier than IRS's available source history,
    -- the graph leaves that earlier span empty instead of fabricating balances.
    local actual = {}

    if firstObserved then
        local firstElapsed = DaysBetweenDateKeys(createdKey, firstObserved.key) or 0
        table.insert(actual, {
            fraction = math.max(0, math.min(1, firstElapsed / totalDays)),
            amount = tonumber(firstObserved.start) or 0,
            key = "actual:first-observed:" .. tostring(firstObserved.key),
            opening = true,
        })
    end

    for _, row in ipairs(sampledRows) do
        local elapsed = DaysBetweenDateKeys(createdKey, row.key) or 0
        table.insert(actual, {
            fraction = math.max(0, math.min(1, elapsed / totalDays)),
            amount = row.ending or 0,
            key = row.key,
        })
    end

    -- Build interval-specific X-axis checkpoints. These are independent of the
    -- observed balance samples so the selected interval is visible even before
    -- much project history has accumulated.
    local rawTicks = {}

    if interval == "daily" then
        local tickCount = math.min(8, totalDays + 1)

        for i = 1, tickCount do
            local elapsed = 0
            if tickCount > 1 then
                elapsed = math.floor(
                    (((i - 1) * totalDays) / (tickCount - 1)) + 0.5
                )
            end

            local key = AddDaysToProjectDateKey(createdKey, elapsed)
            table.insert(rawTicks, {
                key = key,
                elapsed = elapsed,
                fraction = math.max(0, math.min(1, elapsed / totalDays)),
                label = FormatGraphAxisDate(key, interval, elapsed),
            })
        end

    elseif interval == "weekly" then
        -- Choose the display cadence BEFORE generating ticks. The previous
        -- implementation generated every week and then thinned the list, which
        -- could produce visually irregular gaps (4 weeks, then 5, then 4...).
        --
        -- This keeps every visible weekly marker on one regular whole-week
        -- cadence while still limiting the compact axis to about ten labels.
        local totalWeeks = math.floor(totalDays / 7)
        local maxWeeklyTicks = 10
        local stepWeeks = math.max(
            1,
            math.ceil((totalWeeks + 1) / maxWeeklyTicks)
        )
        local stepDays = stepWeeks * 7
        local elapsed = 0

        while elapsed <= totalDays do
            local key = AddDaysToProjectDateKey(createdKey, elapsed)

            table.insert(rawTicks, {
                key = key,
                elapsed = elapsed,
                fraction = math.max(0, math.min(1, elapsed / totalDays)),
                label = FormatGraphAxisDate(key, interval, elapsed),
            })

            elapsed = elapsed + stepDays
        end

        -- Do not append a partial final week. An off-cadence deadline label was
        -- the other source of uneven spacing. The trajectory line still reaches
        -- the deadline at 100%; the axis labels remain uniformly weekly.

    elseif interval == "monthly" then
        local startY, startM = ParseProjectDateKey(createdKey)
        local deadlineY, deadlineM = ParseProjectDateKey(project.deadline)

        -- Always begin at the project's real creation date.
        table.insert(rawTicks, {
            key = createdKey,
            elapsed = 0,
            fraction = 0,
            label = FormatGraphAxisDate(createdKey, interval, 0),
        })

        if startY and deadlineY then
            local y, m = startY, startM + 1
            if m > 12 then m = 1; y = y + 1 end

            while y < deadlineY or (y == deadlineY and m <= deadlineM) do
                local monthKey = string.format("%04d-%02d-01", y, m)
                local elapsed = DaysBetweenDateKeys(createdKey, monthKey) or 0

                if elapsed > 0 and elapsed < totalDays then
                    table.insert(rawTicks, {
                        key = monthKey,
                        elapsed = elapsed,
                        fraction = math.max(0, math.min(1, elapsed / totalDays)),
                        label = FormatGraphAxisDate(monthKey, interval, elapsed),
                    })
                end

                m = m + 1
                if m > 12 then m = 1; y = y + 1 end
            end
        end

        if project.deadline ~= createdKey then
            table.insert(rawTicks, {
                key = project.deadline,
                elapsed = totalDays,
                fraction = 1,
                label = FormatGraphAxisDate(project.deadline, interval, totalDays),
            })
        end

        rawTicks = ThinProjectGraphTicks(rawTicks, 10)

    else -- checkpoints
        -- X AXIS: weekly time cadence, evenly spaced from project creation.
        local totalWeeks = math.floor(totalDays / 7)
        local maxWeeklyTicks = 10
        local stepWeeks = math.max(
            1,
            math.ceil((totalWeeks + 1) / maxWeeklyTicks)
        )
        local stepDays = stepWeeks * 7
        local elapsed = 0

        while elapsed <= totalDays do
            local key = AddDaysToProjectDateKey(createdKey, elapsed)

            table.insert(rawTicks, {
                key = key,
                elapsed = elapsed,
                fraction = math.max(
                    0,
                    math.min(1, elapsed / totalDays)
                ),
                label = FormatGraphAxisDate(key, "weekly", elapsed),
            })

            elapsed = elapsed + stepDays
        end

    end

    -- Y AXIS: custom gold milestones for Checkpoints mode.
    local yTicks = {}

    if interval == "checkpoints" then
        local target = math.max(1, tonumber(stats.target) or 0)
        local checkpoints = IRS:GetProjectCheckpoints(project)

        table.insert(yTicks, {
            amount = 0,
            fraction = 0,
            label = "0g",
            endpoint = true,
        })

        for _, checkpoint in ipairs(checkpoints) do
            local amount = tonumber(checkpoint.amountCopper) or 0

            if amount > 0 and amount < target then
                local state = IRS:GetProjectCheckpointStatus(project, checkpoint)
                local name = strtrim(tostring(checkpoint.name or "Checkpoint"))

                if #name > 18 then
                    name = name:sub(1, 15) .. "..."
                end

                table.insert(yTicks, {
                    amount = amount,
                    fraction = math.max(0, math.min(1, amount / target)),
                    label = name .. "  " .. FormatCheckpointAxisGold(amount),
                    checkpointId = checkpoint.id,
                    reached = state and state.reached or false,
                })
            end
        end

        table.sort(yTicks, function(a, b)
            return (tonumber(a.amount) or 0) < (tonumber(b.amount) or 0)
        end)

        table.insert(yTicks, {
            amount = target,
            fraction = 1,
            label = "GOAL  " .. FormatCheckpointAxisGold(target),
            endpoint = true,
        })

        -- Keep the endpoints and up to eight representative milestones if a
        -- project has a very large checkpoint list.
        if #yTicks > 10 then
            local firstTick = yTicks[1]
            local lastTick = yTicks[#yTicks]
            local interior = {}

            for i = 2, #yTicks - 1 do
                table.insert(interior, yTicks[i])
            end

            interior = ThinProjectGraphTicks(interior, 8)

            yTicks = {firstTick}
            for _, tick in ipairs(interior) do
                table.insert(yTicks, tick)
            end
            table.insert(yTicks, lastTick)
        end
    end

    return {
        startAmount = startAmount,
        target = stats.target,
        current = stats.current,
        createdDay = project.createdDay or createdKey,
        startDate = createdKey,
        historyAvailableFrom = firstObserved and firstObserved.key or nil,
        deadline = project.deadline,
        interval = interval,
        actual = actual,
        xTicks = rawTicks,
        yTicks = yTicks,
    }
end

-- ============================================================================
-- SECTION 10 — SETTINGS / FORMATTING
-- Small shared utilities and user preferences.
-- ============================================================================
-- Returns whether one savings project is allowed to appear in the floating
-- mini dashboard. A project is visible by default unless explicitly disabled.
function IRS:IsProjectShownInMini(projectId)
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.settings.miniProjectVisibility = IRS.db.settings.miniProjectVisibility or {}

    local key = tostring(projectId)
    return IRS.db.settings.miniProjectVisibility[key] ~= false
end

-- Saves the per-project mini-dashboard visibility checkbox.
function IRS:SetProjectMiniVisibility(projectId, enabled)
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.settings.miniProjectVisibility = IRS.db.settings.miniProjectVisibility or {}

    local key = tostring(projectId)
    IRS.db.settings.miniProjectVisibility[key] = enabled and true or false

    if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    if IRS.RefreshSettingsPage then IRS:RefreshSettingsPage() end
end

-- Resolves semantic style keys and supported numerical compatibility tiers.
function IRS:ResolveFontStyle(scope, styleKey)
    scope = scope == "mini" and "mini" or "main"
    local raw = tostring(styleKey)
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    if defaults[raw] ~= nil then
        return raw
    end

    return (IRS.FONT_STYLE_LEGACY_MAP[scope] or {})[raw]
end

-- Returns the rendered size for one semantic font style.
function IRS:GetFontSize(scope, styleKey)
    scope = scope == "mini" and "mini" or "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)

    -- A few hidden compatibility FontStrings intentionally use size 1.
    if not key then
        return tonumber(styleKey) or 10
    end

    if not IRS.db then IRS:EnsureDB() end

    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}
    local saved = IRS.db.settings.fontSizes
        and IRS.db.settings.fontSizes[scope]
        and tonumber(IRS.db.settings.fontSizes[scope][key])

    return saved or tonumber(defaults[key]) or 10
end

-- Registers a FontString so a style change updates every matching text element.
function IRS:RegisterFontString(scope, styleKey, fontString, fontPath, flags)
    if not fontString then return end

    scope = scope == "mini" and "mini" or "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    if not key then return end

    IRS._fontRegistry[scope] = IRS._fontRegistry[scope] or {}
    IRS._fontRegistry[scope][key] = IRS._fontRegistry[scope][key] or {}

    table.insert(IRS._fontRegistry[scope][key], {
        fontString = fontString,
        fontPath = fontPath or STANDARD_TEXT_FONT,
        flags = flags or "",
    })

    fontString:SetFont(
        fontPath or STANDARD_TEXT_FONT,
        IRS:GetFontSize(scope, key),
        flags or ""
    )
end

local function ApplyRegisteredFontStyle(scope, styleKey)
    scope = scope == "mini" and "mini" or "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    if not key then return end

    local size = IRS:GetFontSize(scope, key)

    for _, entry in ipairs(
        IRS._fontRegistry[scope]
        and IRS._fontRegistry[scope][key]
        or {}
    ) do
        if entry.fontString then
            entry.fontString:SetFont(
                entry.fontPath or STANDARD_TEXT_FONT,
                size,
                entry.flags or ""
            )
        end
    end
end

-- Changes one shared semantic style.
function IRS:SetFontSize(scope, styleKey, value)
    if not IRS.db then IRS:EnsureDB() end

    scope = scope == "mini" and "mini" or "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    if not key or defaults[key] == nil then return false end

    value = math.floor((tonumber(value) or tonumber(defaults[key]) or 10) + 0.5)
    value = math.max(6, math.min(40, value))

    IRS.db.settings.fontSizes[scope][key] = value
    ApplyRegisteredFontStyle(scope, key)

    if scope == "main" then
        if IRS.RefreshUI then IRS:RefreshUI() end
    else
        if IRS.RefreshSettingsPage then IRS:RefreshSettingsPage() end
        if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    end

    return true
end

-- Restores all semantic styles for one interface scope.
function IRS:ResetFontSizes(scope)
    if not IRS.db then IRS:EnsureDB() end

    scope = scope == "mini" and "mini" or "main"
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    for key, defaultSize in pairs(defaults) do
        IRS.db.settings.fontSizes[scope][key] = defaultSize
        ApplyRegisteredFontStyle(scope, key)
    end

    if scope == "main" then
        if IRS.RefreshUI then IRS:RefreshUI() end
    else
        if IRS.RefreshSettingsPage then IRS:RefreshSettingsPage() end
        if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
    end
end

-- Returns the player's chosen mini-dashboard resize/position anchor.
function IRS:GetMiniDashboardAnchor()
    if not IRS.db then IRS:EnsureDB() end

    local anchor = IRS.db.settings.miniDashboardAnchor
    if anchor ~= "TOPLEFT"
        and anchor ~= "TOPRIGHT"
        and anchor ~= "BOTTOMLEFT"
        and anchor ~= "BOTTOMRIGHT" then
        anchor = "TOPLEFT"
        IRS.db.settings.miniDashboardAnchor = anchor
    end

    return anchor
end

-- Changes which mini-dashboard corner remains fixed while the panel grows or
-- shrinks. The mini-dashboard UI preserves its current on-screen position while
-- converting to the new anchor.
function IRS:SetMiniDashboardAnchor(anchor)
    if not IRS.db then IRS:EnsureDB() end

    if anchor ~= "TOPLEFT"
        and anchor ~= "TOPRIGHT"
        and anchor ~= "BOTTOMLEFT"
        and anchor ~= "BOTTOMRIGHT" then
        return
    end

    IRS.db.settings.miniDashboardAnchor = anchor

    if IRS.ApplyMiniDashboardAnchor then
        IRS:ApplyMiniDashboardAnchor(anchor)
    end

    if IRS.RefreshSettingsPage then
        IRS:RefreshSettingsPage()
    end
end

-- Saves one boolean addon setting. Settings are account-wide.
function IRS:SetSetting(key, value)
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.settings[key] = value and true or false
    if key == "showMinimapButton" and IRS.RefreshMinimapButton then
        IRS:RefreshMinimapButton()
    elseif key == "showMiniProjects" and IRS.RefreshMiniDashboard then
        IRS:RefreshMiniDashboard()
        if IRS.RefreshSettingsPage then IRS:RefreshSettingsPage() end
    end
end

-- Converts an internal copper value into readable gold/silver/copper text.
-- Supports negative values because IRS tracks net profit/loss.
function IRS:FormatMoney(copper, compact)
    copper = math.floor(tonumber(copper) or 0)
    local negative = copper < 0
    local absolute = math.abs(copper)
    local gold = math.floor(absolute / 10000)
    local silver = math.floor((absolute % 10000) / 100)
    local copperOnly = absolute % 100
    local sign = negative and "-" or ""

    if compact then
        if gold >= 1000000 then
            return string.format("%s%.2fm g", sign, gold / 1000000)
        elseif gold >= 1000 then
            return string.format("%s%.1fk g", sign, gold / 1000)
        end
        return string.format("%s%dg %02ds %02dc", sign, gold, silver, copperOnly)
    end

    local formattedGold = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return string.format("%s%s g %02d s %02d c", sign, formattedGold, silver, copperOnly)
end

-- Adds normal large-number formatting to a simple count.
function IRS:FormatCount(number)
    number = math.floor(tonumber(number) or 0)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(number) or tostring(number)
end

-- Debug/chat helper that prints all known characters and their tracking state.
function IRS:PrintCharacters()
    local rows = IRS:GetSortedCharacters()
    print("|cff46d9ffIRS — Income Records System|r — scanned characters:")
    for _, entry in ipairs(rows) do
        local record = entry.record
        local state = record.trackingEnabled ~= false and "TRACKING" or "IGNORED"
        print(string.format("  %s — %s — current %s; earned since tracking %s",
            record.label or "Unknown",
            state,
            IRS:FormatMoney(record.money or 0, true),
            IRS:FormatMoney(record.earnedSinceTracking or 0, true)))
    end
end

-- ============================================================================
-- SECTION 11 — WOW EVENTS / SLASH COMMANDS
-- The runtime entry points that make IRS react while you play.
-- ============================================================================
-- EVENT MAP
-- ---------
-- ADDON_LOADED                  -> initialize SavedVariables.
-- PLAYER_LOGIN                  -> first delayed full character scan.
-- PLAYER_MONEY                  -> immediately record net wallet gain/loss.
-- CRITERIA/QUEST/MAIL events    -> rescan Blizzard source statistics.
-- Account-bank events           -> refresh Warband Bank + projects.
-- Guild-bank events             -> refresh Guild Bank + projects.
-- Level/guild updates           -> refresh character metadata.
-- Transmog events                -> capture pending cost + successful spend.

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("CRITERIA_UPDATE")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
eventFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
eventFrame:RegisterEvent("GUILDBANK_UPDATE_MONEY")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("TRANSMOGRIFY_OPEN")
eventFrame:RegisterEvent("TRANSMOGRIFY_UPDATE")
eventFrame:RegisterEvent("TRANSMOGRIFY_SUCCESS")
eventFrame:RegisterEvent("TRANSMOGRIFY_CLOSE")

local scanGeneration = 0
local loginScanPending = false

-- Debounces delayed full scans. WoW often updates related APIs a fraction of a
-- second after an event fires, so IRS waits briefly before reading them.
local function QueueScan(delay)
    scanGeneration = scanGeneration + 1
    local generation = scanGeneration
    C_Timer.After(delay or 0.25, function()
        if generation == scanGeneration and IRS.db and not loginScanPending then
            IRS:ScanCurrentCharacter()
        end
    end)
end

-- Schedules two source-stat scans after money-related activity. The second scan
-- catches Blizzard statistics that lag slightly behind the wallet update.
-- Bursts are debounced so only the newest pair of scans is allowed to run.
local moneyScanGeneration = 0
local function QueueMoneyScans()
    -- The Statistics counters can trail the wallet event slightly. Two reads
    -- make the tracker resilient without continuously polling the client.
    QueueScan(0.20)

    moneyScanGeneration = moneyScanGeneration + 1
    local generation = moneyScanGeneration
    C_Timer.After(1.00, function()
        if generation == moneyScanGeneration and IRS.db and not loginScanPending then
            IRS:ScanCurrentCharacter()
        end
    end)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        IRS:EnsureDB()

        local minimapTiming = IRS:BeginStartupTiming("Minimap button refresh")
        if IRS.RefreshMinimapButton then IRS:RefreshMinimapButton() end
        IRS:EndStartupTiming(minimapTiming)
        return
    end

    if event == "PLAYER_LOGIN" then
        IRS:ScheduleStartupTimingFinish(4.0)
        loginScanPending = true

        -- The initial login scan must not be canceled or postponed by the burst
        -- of CRITERIA_UPDATE and other startup events some characters receive.
        C_Timer.After(1.0, function()
            if IRS.db then
                IRS:ScanCurrentCharacter()
            end
            loginScanPending = false
        end)
    elseif event == "BANKFRAME_OPENED" or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        IRS:ScanWarbandGold()
        QueueScan(0.2)
    elseif event == "GUILDBANKFRAME_OPENED" then
        IRS.guildBankRuntime.isOpen = true
        IRS.guildBankRuntime.hasMoneyUpdate = false

        -- Bank money can populate a fraction of a second after the frame opens.
        -- Never replace a useful cache with a transient 0 during that window.
        C_Timer.After(0.25, function()
            if IRS.db and IRS.guildBankRuntime.isOpen then
                IRS:ScanGuildBankGold(false)
                IRS:UpdateProjectSnapshots()
                if IRS.RefreshUI then IRS:RefreshUI() end
            end
        end)

        C_Timer.After(1.00, function()
            if IRS.db and IRS.guildBankRuntime.isOpen then
                IRS:ScanGuildBankGold(false)
                IRS:UpdateProjectSnapshots()
                if IRS.RefreshUI then IRS:RefreshUI() end
            end
        end)

    elseif event == "GUILDBANK_UPDATE_MONEY" then
        IRS.guildBankRuntime.isOpen = true
        IRS.guildBankRuntime.hasMoneyUpdate = true

        IRS:ScanGuildBankGold(true)
        IRS:UpdateProjectSnapshots()
        if IRS.RefreshUI then IRS:RefreshUI() end

        C_Timer.After(0.20, function()
            if IRS.db and IRS.guildBankRuntime.isOpen then
                IRS:ScanGuildBankGold(true)
                IRS:UpdateProjectSnapshots()
                if IRS.RefreshUI then IRS:RefreshUI() end
            end
        end)

    elseif event == "GUILDBANKFRAME_CLOSED" then
        IRS.guildBankRuntime.isOpen = false
        IRS.guildBankRuntime.hasMoneyUpdate = false

    elseif event == "PLAYER_GUILD_UPDATE" then
        QueueScan(0.35)
    elseif event == "TRANSMOGRIFY_OPEN" then
        IRS.transmogRuntime.isOpen = true
        IRS.transmogRuntime.pendingCost = 0
        IRS.transmogRuntime.armedCost = 0
        IRS.transmogRuntime.transactionRecorded = false
        IRS:RefreshPendingTransmogCost()
    elseif event == "TRANSMOGRIFY_UPDATE" then
        IRS:RefreshPendingTransmogCost()
    elseif event == "TRANSMOGRIFY_SUCCESS" then
        IRS:HandleTransmogSuccess()
    elseif event == "TRANSMOGRIFY_CLOSE" then
        IRS.transmogRuntime.isOpen = false
        IRS.transmogRuntime.pendingCost = 0
        IRS.transmogRuntime.armedCost = 0
        IRS.transmogRuntime.transactionRecorded = false
    elseif event == "PLAYER_MONEY" then
        IRS:HandleMoneyChange()
        QueueMoneyScans()

        if IRS.guildBankRuntime and IRS.guildBankRuntime.isOpen then
            C_Timer.After(0.20, function()
                if IRS.db and IRS.guildBankRuntime.isOpen then
                    IRS:ScanGuildBankGold(false)
                    IRS:UpdateProjectSnapshots()
                    if IRS.RefreshUI then IRS:RefreshUI() end
                end
            end)
        end
    elseif event == "CRITERIA_UPDATE" or event == "QUEST_TURNED_IN" or event == "MAIL_INBOX_UPDATE" then
        QueueMoneyScans()
    else
        QueueScan(0.35)
    end
end)

SLASH_INCOMERECORDSSYSTEM1 = "/irs"
SLASH_INCOMERECORDSSYSTEM2 = "/incomerecords"
-- Compatibility aliases; /irs is the primary command.
SlashCmdList.INCOMERECORDSSYSTEM = function(msg)
    msg = strtrim((msg or "")):lower()

    if msg == "scan" then
        IRS:ScanCurrentCharacter()
        print("|cff46d9ffIRS:|r current character rescanned.")
    elseif msg == "chars" or msg == "characters" then
        if IRS.ShowUI then IRS:ShowUI("characters") else IRS:PrintCharacters() end
    elseif msg == "help" then
        if IRS.ShowUI then IRS:ShowUI("help") end
    elseif msg == "projects" or msg == "project" or msg == "goals" then
        if IRS.ShowUI then IRS:ShowUI("projects") end
    elseif msg == "reserves" or msg == "reserve" or msg == "buffers" then
        if IRS.ShowUI then IRS:ShowUI("reserves") end
    elseif msg == "tools" or msg == "tool" or msg == "manual" or msg == "distribution" then
        if IRS.ShowUI then IRS:ShowUI("tools") end
    elseif msg == "mini" or msg == "minidashboard" then
        if IRS.ToggleMiniDashboard then IRS:ToggleMiniDashboard() end
    elseif msg == "reports" or msg == "report" then
        if IRS.ShowUI then IRS:ShowUI("reports") end
    elseif msg == "settings" or msg == "options" then
        if IRS.ShowUI then IRS:ShowUI("settings") end
    elseif msg == "timing" or msg == "startup" then
        IRS:PrintStartupTiming()
    elseif msg == "debug" then
        local key = IRS:CharacterKey()
        local record = IRS.db and IRS.db.characters and IRS.db.characters[key]
        local tracker = record and record.earningsTracker or {}
        local stats = record and record.stats or {}
        local sourceTracked = record and SumTrackedSources(record.sourceEarningsSinceTracking) or 0
        local debugDayKey = select(1, IRS:GetPeriodKeys())
        print(string.format("|cff46d9ffIRS debug:|r day %s • wallet %s • day opening %s • last wallet %s • today %s • total acquired %s • tracked source deltas %s",
            tostring(debugDayKey),
            IRS:FormatMoney(GetMoney and GetMoney() or 0, true),
            IRS:FormatMoney(tracker.walletDayStartMoney or 0, true),
            IRS:FormatMoney(tracker.walletLastMoney or 0, true),
            IRS:FormatMoney(IRS:GetCurrentEarnings().today or 0, true),
            IRS:FormatMoney(stats.totalAcquired or 0, true),
            IRS:FormatMoney(sourceTracked, true)))
    elseif msg == "status" then
        local e = IRS:GetCurrentEarnings()
        print(string.format("|cff46d9ffIRS:|r today %s • week %s • month %s • tracked total %s",
            IRS:FormatMoney(e.today, true), IRS:FormatMoney(e.week, true),
            IRS:FormatMoney(e.month, true), IRS:FormatMoney(e.total, true)))
    elseif msg == "reset confirm" then
        IncomeRecordsSystemDB = nil
        IRS:EnsureDB()
        IRS:ScanCurrentCharacter()
        if IRS.RefreshUI then IRS:RefreshUI() end
        print("|cffff5555IRS:|r saved earnings history and scanner data reset.")
    elseif msg == "reset" then
        print("|cffff5555IRS:|r type |cffffffff/irs reset confirm|r to clear IRS saved data and earnings history.")
    elseif msg == "" then
        if IRS.ToggleUI then
            IRS:ToggleUI()
        else
            print(
                "|cffff8c66IRS:|r Core loaded, but the interface did not finish loading. "
                .. "Enable Lua errors or report the first IRS Lua error after /reload."
            )
        end
    else
        if IRS.ShowUI then IRS:ShowUI("help") end
    end
end

IRS:EndStartupTiming(_irsCoreModuleTiming)
