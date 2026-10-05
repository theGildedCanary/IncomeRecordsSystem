--[[
IRS — WoW Token Market
Stores locally observed Token prices and manages configured buy/sell alerts.
]]

local IRS = IRS

local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.980},
    panelAlt = {0.225, 0.170, 0.112, 0.985},
    border = {0.46, 0.36, 0.22, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {0.43, 0.60, 0.36, 1},
    red = {0.63, 0.29, 0.25, 1},
    blue = {0.40, 0.63, 0.65, 1},
}

local function Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function SetColor(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function MakeText(parent, style, color, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontFlags = flags or ""
    fs:SetFont(
        STANDARD_TEXT_FONT,
        IRS:GetFontSize("main", style),
        fontFlags
    )
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
    frame:SetBackdropBorderColor(unpack(COLORS.border))
    return frame
end

function IRS:EnsureTokenMarketDB()
    if not IRS.db then IRS:EnsureDB() end

    IRS.db.tokenMarket = IRS.db.tokenMarket or {}
    local market = IRS.db.tokenMarket

    market.history = market.history or {}
    market.settings = market.settings or {}

    local s = market.settings
    if s.enabled == nil then s.enabled = true end
    s.intervalMinutes = tonumber(s.intervalMinutes) or 5
    s.averageDays = tonumber(s.averageDays) or 7
    s.buyPercent = tonumber(s.buyPercent) or 8
    s.extremeBuyPercent = tonumber(s.extremeBuyPercent) or 15
    s.sellPercent = tonumber(s.sellPercent) or 8
    s.extremeSellPercent = tonumber(s.extremeSellPercent) or 15
    if s.chatAlert == nil then s.chatAlert = true end
    if s.screenAlert == nil then s.screenAlert = true end
    if s.soundAlert == nil then s.soundAlert = false end
    s.soundKey = tostring(s.soundKey or "ready_check")

    return market
end

local function PruneHistory()
    local market = IRS:EnsureTokenMarketDB()
    local cutoff = Now() - (31 * 86400)
    local kept = {}

    for _, sample in ipairs(market.history) do
        if tonumber(sample.t) and tonumber(sample.p)
            and sample.t >= cutoff
            and sample.p > 0 then
            table.insert(kept, sample)
        end
    end

    market.history = kept
end

local function AverageForDays(days)
    local market = IRS:EnsureTokenMarketDB()
    local cutoff = Now() - (math.max(1, tonumber(days) or 1) * 86400)
    local total, count = 0, 0

    for _, sample in ipairs(market.history) do
        if (tonumber(sample.t) or 0) >= cutoff then
            total = total + (tonumber(sample.p) or 0)
            count = count + 1
        end
    end

    if count == 0 then return nil, 0 end
    return math.floor(total / count), count
end

function IRS:GetTokenMarketSummary()
    local market = IRS:EnsureTokenMarketDB()
    local settings = market.settings
    local current = tonumber(market.lastPrice) or 0
    local average, sampleCount = AverageForDays(settings.averageDays)
    local average30, sampleCount30 = AverageForDays(30)

    local differencePercent
    local status = "LEARNING MARKET"

    if current > 0 and average and average > 0 and sampleCount >= 3 then
        differencePercent = ((current - average) / average) * 100

        if differencePercent <= -math.abs(settings.extremeBuyPercent) then
            status = "EXTREME BUY"
        elseif differencePercent <= -math.abs(settings.buyPercent) then
            status = "GOOD BUY"
        elseif differencePercent >= math.abs(settings.extremeSellPercent) then
            status = "EXTREME SELL"
        elseif differencePercent >= math.abs(settings.sellPercent) then
            status = "GOOD SELL"
        else
            status = "NORMAL"
        end
    end

    return {
        current = current,
        average = average,
        average30 = average30,
        sampleCount = sampleCount,
        sampleCount30 = sampleCount30,
        differencePercent = differencePercent,
        status = status,
        lastSample = market.lastSample,
        enabled = settings.enabled ~= false,
    }
end

local runtime = {
    generation = 0,
    lastZone = nil,
}

-- Sound choices deliberately reference SOUNDKIT names instead of hard-coded
-- numeric IDs. IRS only exposes entries that exist in the player's current WoW
-- client, which keeps the dropdown resilient across Retail client changes.
local TOKEN_SOUND_CHOICES = {
    {key = "ready_check", label = "Ready Check", kits = {"READY_CHECK"}},
    {key = "raid_warning", label = "Raid Warning", kits = {"RAID_WARNING", "RAID_BOSS_WHISPER_WARNING"}},
    {key = "auction", label = "Auction House", kits = {"AUCTION_WINDOW_OPEN"}},
    {key = "whisper", label = "Whisper", kits = {"TELL_MESSAGE"}},
    {key = "quest_complete", label = "Quest Complete", kits = {"QUEST_COMPLETE"}},
    {key = "map_ping", label = "Map Ping", kits = {"MAP_PING"}},
    {key = "soft_click", label = "Soft Click", kits = {"IG_MAINMENU_OPTION_CHECKBOX_ON"}},
}

local function ResolveSoundChoice(choice)
    if not choice or not SOUNDKIT then return nil end

    for _, kitName in ipairs(choice.kits or {}) do
        local sound = SOUNDKIT[kitName]
        if sound then return sound end
    end

    return nil
end

function IRS:GetTokenSoundChoices()
    local choices = {}

    for _, choice in ipairs(TOKEN_SOUND_CHOICES) do
        local sound = ResolveSoundChoice(choice)
        if sound then
            table.insert(choices, {
                key = choice.key,
                label = choice.label,
                sound = sound,
            })
        end
    end

    return choices
end

function IRS:GetTokenAlertSound()
    local market = IRS:EnsureTokenMarketDB()
    local wanted = tostring(market.settings.soundKey or "ready_check")
    local firstAvailable

    for _, choice in ipairs(IRS:GetTokenSoundChoices()) do
        firstAvailable = firstAvailable or choice
        if choice.key == wanted then
            return choice.sound, choice.label, choice.key
        end
    end

    if firstAvailable then
        return firstAvailable.sound, firstAvailable.label, firstAvailable.key
    end

    return nil, "Unavailable", nil
end

function IRS:SetTokenAlertSound(key)
    local market = IRS:EnsureTokenMarketDB()
    local settings = market.settings

    if key == nil or key == "off" then
        settings.soundAlert = false
    else
        local found
        for _, choice in ipairs(IRS:GetTokenSoundChoices()) do
            if choice.key == key then
                found = choice
                break
            end
        end

        if not found then return false end

        settings.soundKey = found.key
        settings.soundAlert = true

        -- Selecting a sound doubles as a preview so the player knows what they
        -- chose before waiting for the next Token alert.
        if PlaySound and found.sound then
            PlaySound(found.sound)
        end
    end

    if IRS.RefreshTokenSettingsSection then
        IRS:RefreshTokenSettingsSection()
    end

    return true
end

local function StatusColor(status)
    if status == "GOOD BUY" or status == "EXTREME BUY" then
        return COLORS.green
    elseif status == "GOOD SELL" or status == "EXTREME SELL" then
        return COLORS.gold
    elseif status == "NORMAL" then
        return COLORS.text
    end
    return COLORS.muted
end

local function AlertIfNeeded(summary)
    local market = IRS:EnsureTokenMarketDB()
    local settings = market.settings
    local status = summary.status

    if status == "NORMAL" or status == "LEARNING MARKET" then
        runtime.lastZone = status
        return
    end

    if runtime.lastZone == status then return end
    runtime.lastZone = status

    local direction =
        (status == "GOOD BUY" or status == "EXTREME BUY")
        and "BUY WITH GOLD"
        or "SELL FOR GOLD"

    local diff = summary.differencePercent or 0
    local message = string.format(
        "IRS WoW Token: %s — %s (%+.1f%% vs %d-day average)",
        status,
        direction,
        diff,
        market.settings.averageDays
    )

    if settings.chatAlert and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFD1B06B" .. message .. "|r")
    end

    if settings.screenAlert and UIErrorsFrame then
        local c = StatusColor(status)
        UIErrorsFrame:AddMessage(message, c[1], c[2], c[3], 1)
    end

    if settings.soundAlert and PlaySound then
        local sound = IRS:GetTokenAlertSound()
        if sound then
            PlaySound(sound)
        end
    end
end

function IRS:CaptureTokenMarketPrice()
    local market = IRS:EnsureTokenMarketDB()
    if market.settings.enabled == false then return nil end
    if not C_WowTokenPublic or not C_WowTokenPublic.GetCurrentMarketPrice then
        return nil
    end

    local ok, price = pcall(C_WowTokenPublic.GetCurrentMarketPrice)
    if not ok or type(price) ~= "number" or price <= 0 then
        return nil
    end

    local now = Now()
    local minGap = math.max(
        60,
        (tonumber(market.settings.intervalMinutes) or 5) * 60 * 0.75
    )

    if not market.lastSample or (now - market.lastSample) >= minGap then
        table.insert(market.history, {t = now, p = price})
        market.lastSample = now
        PruneHistory()
    end

    market.lastPrice = price

    local summary = IRS:GetTokenMarketSummary()
    AlertIfNeeded(summary)

    if IRS.RefreshTokenDashboardCard then
        IRS:RefreshTokenDashboardCard()
    end
    if IRS.RefreshTokenSettingsSection then
        IRS:RefreshTokenSettingsSection()
    end

    return price
end

function IRS:RequestTokenMarketPrice()
    local market = IRS:EnsureTokenMarketDB()
    if market.settings.enabled == false then return false end

    if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
        pcall(C_WowTokenPublic.UpdateMarketPrice)
        return true
    end

    return false
end

local function ScheduleNext()
    local market = IRS:EnsureTokenMarketDB()
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation

    if market.settings.enabled == false then return end

    local minutes = math.max(
        1,
        math.min(60, tonumber(market.settings.intervalMinutes) or 5)
    )

    C_Timer.After(minutes * 60, function()
        if generation ~= runtime.generation then return end
        if not IRS.db then return end

        IRS:RequestTokenMarketPrice()
        ScheduleNext()
    end)
end

function IRS:SetTokenMarketSetting(key, value)
    local market = IRS:EnsureTokenMarketDB()
    local s = market.settings

    if key == "enabled"
        or key == "chatAlert"
        or key == "screenAlert"
        or key == "soundAlert" then
        s[key] = value and true or false
    elseif key == "intervalMinutes" then
        s[key] = math.max(1, math.min(60, tonumber(value) or 5))
    elseif key == "averageDays" then
        s[key] = math.max(1, math.min(30, tonumber(value) or 7))
    elseif key == "soundKey" then
        s.soundKey = tostring(value or "ready_check")
    elseif key == "buyPercent"
        or key == "extremeBuyPercent"
        or key == "sellPercent"
        or key == "extremeSellPercent" then
        s[key] = math.max(0.5, math.min(50, tonumber(value) or 8))
    else
        return false
    end

    if s.extremeBuyPercent < s.buyPercent then
        s.extremeBuyPercent = s.buyPercent
    end
    if s.extremeSellPercent < s.sellPercent then
        s.extremeSellPercent = s.sellPercent
    end

    ScheduleNext()

    if s.enabled then
        IRS:RequestTokenMarketPrice()
    end

    if IRS.RefreshTokenSettingsSection then
        IRS:RefreshTokenSettingsSection()
    end

    return true
end

-- ============================================================================
-- TOKEN SETTINGS SECTION
-- ============================================================================

local settingsUI

local function MakeCheck(parent, labelText, x, y, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(28, 28)
    check:SetPoint("TOPLEFT", x, y)

    local label = MakeText(parent, "body", COLORS.text, "LEFT")
    label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    label:SetText(labelText)

    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked())
    end)

    return check, label
end

local function MakeNumberSetting(parent, labelText, x, y, width, callback)
    local label = MakeText(parent, "helper", COLORS.muted, "LEFT")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 74, 24)
    box:SetPoint("TOPLEFT", x, y - 20)
    box:SetAutoFocus(false)
    box:SetNumeric(false)
    box:SetMaxLetters(6)

    box:SetScript("OnEnterPressed", function(self)
        callback(tonumber(self:GetText()))
        self:ClearFocus()
    end)

    box:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then callback(value) end
    end)

    return box
end

function IRS:BuildTokenSettingsSection(parent)
    if settingsUI then return settingsUI.frame end

    IRS:EnsureTokenMarketDB()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    settingsUI = {frame = frame}

    local title = MakeText(frame, "section", COLORS.goldSoft, "LEFT")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("WOW TOKEN")

    local desc = MakeText(frame, "helper", COLORS.muted, "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetPoint("RIGHT", -16, 0)
    desc:SetText(
        "IRS samples Blizzard's current Token price while you are logged in and builds its own rolling market average."
    )

    local marketPanel = MakePanel(frame, COLORS.panelAlt)
    marketPanel:SetPoint("TOPLEFT", 14, -68)
    marketPanel:SetPoint("TOPRIGHT", -14, -68)
    marketPanel:SetHeight(126)

    settingsUI.price = MakeText(marketPanel, "value", COLORS.gold, "LEFT")
    settingsUI.price:SetPoint("TOPLEFT", 12, -12)

    settingsUI.average = MakeText(marketPanel, "body", COLORS.text, "LEFT")
    settingsUI.average:SetPoint("TOPLEFT", 12, -46)

    settingsUI.context = MakeText(marketPanel, "helper", COLORS.muted, "LEFT")
    settingsUI.context:SetPoint("TOPLEFT", 12, -72)

    settingsUI.status = MakeText(
        marketPanel,
        "label",
        COLORS.muted,
        "RIGHT",
        "OUTLINE"
    )
    settingsUI.status:SetPoint("TOPRIGHT", -12, -15)
    settingsUI.status:SetWidth(190)

    settingsUI.refresh = CreateFrame(
        "Button",
        nil,
        marketPanel,
        "UIPanelButtonTemplate"
    )
    settingsUI.refresh:SetSize(120, 25)
    settingsUI.refresh:SetPoint("BOTTOMRIGHT", -12, 10)
    settingsUI.refresh:SetText("Refresh Price")
    settingsUI.refresh:SetScript("OnClick", function()
        IRS:RequestTokenMarketPrice()
    end)

    local alertPanel = MakePanel(frame, COLORS.panelAlt)
    alertPanel:SetPoint("TOPLEFT", marketPanel, "BOTTOMLEFT", 0, -12)
    alertPanel:SetPoint("TOPRIGHT", marketPanel, "BOTTOMRIGHT", 0, -12)
    alertPanel:SetHeight(232)

    local alertTitle = MakeText(alertPanel, "label", COLORS.goldSoft, "LEFT")
    alertTitle:SetPoint("TOPLEFT", 12, -10)
    alertTitle:SetText("MARKET ALERTS")

    settingsUI.enabled = select(1, MakeCheck(
        alertPanel,
        "Track Token market",
        10,
        -37,
        function(v) IRS:SetTokenMarketSetting("enabled", v) end
    ))

    settingsUI.chat = select(1, MakeCheck(
        alertPanel,
        "Chat alert",
        250,
        -37,
        function(v) IRS:SetTokenMarketSetting("chatAlert", v) end
    ))

    settingsUI.screen = select(1, MakeCheck(
        alertPanel,
        "Screen alert",
        390,
        -37,
        function(v) IRS:SetTokenMarketSetting("screenAlert", v) end
    ))

    settingsUI.soundLabel = MakeText(
        alertPanel,
        "helper",
        COLORS.muted,
        "LEFT"
    )
    settingsUI.soundLabel:SetPoint("TOPLEFT", 505, -31)
    settingsUI.soundLabel:SetText("ALERT SOUND")

    settingsUI.soundDropdown = CreateFrame(
        "Frame",
        nil,
        alertPanel,
        "UIDropDownMenuTemplate"
    )
    settingsUI.soundDropdown:SetPoint("TOPLEFT", 475, -43)
    UIDropDownMenu_SetWidth(settingsUI.soundDropdown, 120)

    UIDropDownMenu_Initialize(settingsUI.soundDropdown, function(_, level)
        local market = IRS:EnsureTokenMarketDB()
        local s = market.settings

        local off = UIDropDownMenu_CreateInfo()
        off.text = "Off"
        off.checked = s.soundAlert ~= true
        off.func = function()
            IRS:SetTokenAlertSound("off")
        end
        UIDropDownMenu_AddButton(off, level)

        for _, choice in ipairs(IRS:GetTokenSoundChoices()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice.label
            info.checked = s.soundAlert == true
                and s.soundKey == choice.key
            info.func = function()
                IRS:SetTokenAlertSound(choice.key)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    settingsUI.interval = MakeNumberSetting(
        alertPanel,
        "CHECK INTERVAL (MIN)",
        12,
        -82,
        80,
        function(v) IRS:SetTokenMarketSetting("intervalMinutes", v) end
    )

    settingsUI.averageDays = MakeNumberSetting(
        alertPanel,
        "MARKET AVERAGE (DAYS)",
        142,
        -82,
        80,
        function(v) IRS:SetTokenMarketSetting("averageDays", v) end
    )

    settingsUI.buy = MakeNumberSetting(
        alertPanel,
        "GOOD BUY BELOW AVG %",
        282,
        -82,
        80,
        function(v) IRS:SetTokenMarketSetting("buyPercent", v) end
    )

    settingsUI.extremeBuy = MakeNumberSetting(
        alertPanel,
        "EXTREME BUY %",
        422,
        -82,
        80,
        function(v) IRS:SetTokenMarketSetting("extremeBuyPercent", v) end
    )

    settingsUI.sell = MakeNumberSetting(
        alertPanel,
        "GOOD SELL ABOVE AVG %",
        12,
        -142,
        80,
        function(v) IRS:SetTokenMarketSetting("sellPercent", v) end
    )

    settingsUI.extremeSell = MakeNumberSetting(
        alertPanel,
        "EXTREME SELL %",
        172,
        -142,
        80,
        function(v) IRS:SetTokenMarketSetting("extremeSellPercent", v) end
    )

    local help = MakeText(alertPanel, "helper", COLORS.muted, "LEFT")
    help:SetPoint("BOTTOMLEFT", 12, 12)
    help:SetPoint("RIGHT", -12, 0)
    help:SetText(
        "BUY WITH GOLD = unusually low Token price.  SELL FOR GOLD = unusually high Token price. Alerts trigger when the market enters a zone."
    )

    return frame
end

function IRS:RefreshTokenSettingsSection()
    if not settingsUI then return end

    local market = IRS:EnsureTokenMarketDB()
    local s = market.settings
    local summary = IRS:GetTokenMarketSummary()

    settingsUI.enabled:SetChecked(s.enabled ~= false)
    settingsUI.chat:SetChecked(s.chatAlert ~= false)
    settingsUI.screen:SetChecked(s.screenAlert ~= false)

    local soundText = "Off"
    if s.soundAlert == true then
        local _, label, resolvedKey = IRS:GetTokenAlertSound()
        soundText = label or "Unavailable"

        -- If a previously saved choice disappeared from the client, remember
        -- the first available fallback so the dropdown and actual alert agree.
        if resolvedKey and resolvedKey ~= s.soundKey then
            s.soundKey = resolvedKey
        end
    end
    UIDropDownMenu_SetText(settingsUI.soundDropdown, soundText)

    if not settingsUI.interval:HasFocus() then
        settingsUI.interval:SetText(tostring(s.intervalMinutes))
    end
    if not settingsUI.averageDays:HasFocus() then
        settingsUI.averageDays:SetText(tostring(s.averageDays))
    end
    if not settingsUI.buy:HasFocus() then
        settingsUI.buy:SetText(tostring(s.buyPercent))
    end
    if not settingsUI.extremeBuy:HasFocus() then
        settingsUI.extremeBuy:SetText(tostring(s.extremeBuyPercent))
    end
    if not settingsUI.sell:HasFocus() then
        settingsUI.sell:SetText(tostring(s.sellPercent))
    end
    if not settingsUI.extremeSell:HasFocus() then
        settingsUI.extremeSell:SetText(tostring(s.extremeSellPercent))
    end

    settingsUI.price:SetText(
        summary.current > 0
        and ("Current: " .. IRS:FormatMoney(summary.current, true))
        or "Current: awaiting price"
    )

    settingsUI.average:SetText(
        summary.average
        and string.format(
            "%d-day average: %s  •  %+.1f%%",
            s.averageDays,
            IRS:FormatMoney(summary.average, true),
            summary.differencePercent or 0
        )
        or string.format(
            "%d-day average: learning market",
            s.averageDays
        )
    )

    settingsUI.context:SetText(
        summary.average30
        and (
            "30-day context: "
            .. IRS:FormatMoney(summary.average30, true)
            .. "  •  "
            .. summary.sampleCount30
            .. " samples"
        )
        or (
            "History: "
            .. summary.sampleCount30
            .. " local sample"
            .. (summary.sampleCount30 == 1 and "" or "s")
        )
    )

    settingsUI.status:SetText(summary.status)
    SetColor(settingsUI.status, StatusColor(summary.status))
end

-- ============================================================================
-- DASHBOARD TOKEN STRIP
-- ============================================================================

local dashboardUI

function IRS:AttachTokenDashboardCard(dashboard, leftPanel, rightPanel)
    if dashboardUI then return dashboardUI.panel end

    local panel = CreateFrame("Frame", nil, dashboard)
    panel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -10)
    panel:SetPoint("TOPRIGHT", rightPanel, "BOTTOMRIGHT", 0, -10)
    panel:SetHeight(58)

    panel.divider = panel:CreateTexture(nil, "BORDER")
    panel.divider:SetTexture("Interface/Buttons/WHITE8X8")
    panel.divider:SetVertexColor(unpack(COLORS.border))
    panel.divider:SetHeight(1)
    panel.divider:SetPoint("TOPLEFT", 0, 0)
    panel.divider:SetPoint("TOPRIGHT", 0, 0)

    local heading = MakeText(panel, "label", COLORS.goldSoft, "LEFT")
    heading:SetPoint("TOPLEFT", 0, -8)
    heading:SetText("WOW TOKEN MARKET")

    local value = MakeText(panel, "body", COLORS.text, "LEFT")
    value:SetPoint("TOPLEFT", 0, -31)
    value:SetPoint("RIGHT", -210, 0)

    local status = MakeText(panel, "body", COLORS.muted, "RIGHT", "OUTLINE")
    status:SetPoint("TOPRIGHT", 0, -20)
    status:SetWidth(190)

    dashboardUI = {
        panel = panel,
        heading = heading,
        value = value,
        status = status,
    }

    IRS:RefreshTokenDashboardCard()
    return panel
end

function IRS:RefreshTokenDashboardCard()
    if not dashboardUI then return end

    local summary = IRS:GetTokenMarketSummary()
    dashboardUI.panel:SetShown(summary.enabled)

    if not summary.enabled then return end

    if summary.current <= 0 then
        dashboardUI.value:SetText(
            "Awaiting Blizzard market price • IRS will build history while you are logged in."
        )
    elseif summary.average then
        dashboardUI.value:SetText(
            string.format(
                "%s  •  %+.1f%% vs rolling average",
                IRS:FormatMoney(summary.current, true),
                summary.differencePercent or 0
            )
        )
    else
        dashboardUI.value:SetText(
            IRS:FormatMoney(summary.current, true)
                .. "  •  Learning rolling market average"
        )
    end

    dashboardUI.status:SetText(summary.status)
    SetColor(dashboardUI.status, StatusColor(summary.status))
end

-- ============================================================================
-- EVENTS / SCHEDULING
-- ============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "IncomeRecordsSystem" then return end
        IRS:EnsureTokenMarketDB()
        ScheduleNext()
        return
    end

    if event == "PLAYER_LOGIN" then
        C_Timer.After(2.0, function()
            if IRS.db then IRS:RequestTokenMarketPrice() end
        end)
    elseif event == "TOKEN_MARKET_PRICE_UPDATED" then
        IRS:CaptureTokenMarketPrice()
    end
end)

