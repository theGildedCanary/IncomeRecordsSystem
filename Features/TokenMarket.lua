--[[
IRS — WoW Token Market
Stores locally observed Token prices and manages configured buy/sell alerts.
]]

local IRS = IRS
local _irsStartupModuleTiming = IRS:BeginStartupTiming("Module load: Token Market")

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
    IRS:SetLayoutColor(fs, "SetTextColor", color[1], color[2], color[3], color[4] or 1)
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
    IRS:SetLayoutColor(frame, "SetBackdropColor", c[1], c[2], c[3], c[4] or 1)
    IRS:SetLayoutColor(frame, "SetBackdropBorderColor", unpack(COLORS.border))
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

local TOKEN_ALERT_STATUSES = {
    ["GOOD BUY"] = true,
    ["EXTREME BUY"] = true,
    ["GOOD SELL"] = true,
    ["EXTREME SELL"] = true,
}

local function IsTokenAlertStatus(status)
    return TOKEN_ALERT_STATUSES[tostring(status or "")] == true
end

function IRS:IsTokenAlertStatus(status)
    return IsTokenAlertStatus(status)
end

-- Dedicated visual Token alert shown when the Mini Dashboard is not open.
local tokenSplash = MakePanel(UIParent, COLORS.panelAlt)
IRS:RegisterFormattingRoot(tokenSplash, "main")
tokenSplash:SetSize(460, 94)
tokenSplash:SetPoint("TOP", UIParent, "TOP", 0, -165)
tokenSplash:SetFrameStrata("DIALOG")
tokenSplash:SetClampedToScreen(true)
tokenSplash:Hide()

tokenSplash.title = MakeText(
    tokenSplash,
    "section",
    COLORS.goldSoft,
    "CENTER",
    "OUTLINE"
)
tokenSplash.title:SetPoint("TOPLEFT", 20, -16)
tokenSplash.title:SetPoint("TOPRIGHT", -20, -16)

tokenSplash.detail = MakeText(
    tokenSplash,
    "helper",
    COLORS.muted,
    "CENTER"
)
tokenSplash.detail:SetPoint("TOPLEFT", 20, -52)
tokenSplash.detail:SetPoint("TOPRIGHT", -20, -52)

local tokenSplashClose = CreateFrame(
    "Button",
    nil,
    tokenSplash,
    "UIPanelCloseButton"
)
tokenSplashClose:SetPoint("TOPRIGHT", -2, -2)

local tokenSplashGeneration = 0

local function HideTokenSplash()
    tokenSplashGeneration = tokenSplashGeneration + 1
    tokenSplash:Hide()
end

tokenSplashClose:SetScript("OnClick", HideTokenSplash)

local function ShowTokenSplash(summary)
    if not summary or not IsTokenAlertStatus(summary.status) then
        HideTokenSplash()
        return
    end

    local market = IRS:EnsureTokenMarketDB()
    local settings = market.settings
    local color = StatusColor(summary.status)

    tokenSplash.title:SetText(
        "WOW TOKEN ALERT — " .. tostring(summary.status)
    )
    SetColor(tokenSplash.title, color)

    local detailPrefix = summary.preview and "TEST PREVIEW  •  " or ""
    tokenSplash.detail:SetText(
        detailPrefix
        .. string.format(
            "%s  •  %+.1f%% vs %d-day average",
            IRS:FormatMoney(summary.current or 0, true),
            summary.differencePercent or 0,
            tonumber(settings.averageDays) or 7
        )
    )

    IRS:SetLayoutColor(tokenSplash, "SetBackdropBorderColor",
        color[1],
        color[2],
        color[3],
        color[4] or 1
    )

    tokenSplashGeneration = tokenSplashGeneration + 1
    local generation = tokenSplashGeneration

    tokenSplash:Show()

    C_Timer.After(9, function()
        if generation == tokenSplashGeneration then
            tokenSplash:Hide()
        end
    end)
end

-- Routes the Screen alert to the Mini Dashboard when it is open; otherwise
-- use the temporary general splash notification.
function IRS:ShowTokenVisualAlert(summary)
    local market = IRS:EnsureTokenMarketDB()

    if market.settings.screenAlert == false then
        return false
    end

    summary = summary or IRS:GetTokenMarketSummary()

    if not summary or not IsTokenAlertStatus(summary.status) then
        return false
    end

    local miniOpen = IRS.miniDashboardFrame
        and IRS.miniDashboardFrame:IsShown()

    if miniOpen and IRS.RefreshMiniTokenAlert then
        HideTokenSplash()
        IRS:RefreshMiniTokenAlert(summary)
    else
        ShowTokenSplash(summary)
    end

    return true
end

-- Visual-only preview used by the Settings buttons. It deliberately bypasses
-- Screen alert enablement and does not touch history, lastZone, chat, or sound.
function IRS:TestTokenVisualAlert(direction)
    local market = IRS:EnsureTokenMarketDB()
    local settings = market.settings
    local realSummary = IRS:GetTokenMarketSummary()
    local isBuy = tostring(direction or ""):lower() == "buy"

    local fallbackPrice = realSummary.current
    if not fallbackPrice or fallbackPrice <= 0 then
        fallbackPrice = realSummary.average
    end
    if not fallbackPrice or fallbackPrice <= 0 then
        fallbackPrice = 300000 * 10000
    end

    local difference = isBuy
        and -math.max(1, tonumber(settings.buyPercent) or 8)
        or math.max(1, tonumber(settings.sellPercent) or 8)

    local preview = {
        status = isBuy and "GOOD BUY" or "GOOD SELL",
        current = fallbackPrice,
        differencePercent = difference,
        enabled = true,
        preview = true,
    }

    local miniOpen = IRS.miniDashboardFrame
        and IRS.miniDashboardFrame:IsShown()

    if miniOpen and IRS.PreviewMiniTokenAlert then
        HideTokenSplash()
        IRS:PreviewMiniTokenAlert(preview, 9)
    else
        ShowTokenSplash(preview)
    end

    return true
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

    if settings.screenAlert then
        IRS:ShowTokenVisualAlert(summary)
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

    if not IsTokenAlertStatus(summary.status) then
        HideTokenSplash()
    end

    if IRS.RefreshMiniTokenAlert then
        IRS:RefreshMiniTokenAlert(summary)
    end

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

    if IRS.RefreshMiniTokenAlert then
        IRS:RefreshMiniTokenAlert(IRS:GetTokenMarketSummary())
    end

    if key == "screenAlert" and s.screenAlert == false then
        HideTokenSplash()
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
    check.label = label

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
    box.label = label
    IRS:RegisterFontString("main", "body", box, STANDARD_TEXT_FONT, "")

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
        off.fontObject = IRS:GetControlFont("main")
        off.text = "Off"
        off.checked = s.soundAlert ~= true
        off.func = function()
            IRS:SetTokenAlertSound("off")
        end
        UIDropDownMenu_AddButton(off, level)

        for _, choice in ipairs(IRS:GetTokenSoundChoices()) do
            local info = UIDropDownMenu_CreateInfo()
            info.fontObject = IRS:GetControlFont("main")
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

    local testLabel = MakeText(
        alertPanel,
        "helper",
        COLORS.muted,
        "LEFT"
    )
    testLabel:SetPoint("TOPLEFT", 332, -142)
    testLabel:SetText("VISUAL ALERT TEST")

    settingsUI.testBuy = CreateFrame(
        "Button",
        nil,
        alertPanel,
        "UIPanelButtonTemplate"
    )
    settingsUI.testBuy:SetSize(112, 24)
    settingsUI.testBuy:SetPoint("TOPLEFT", 332, -162)
    settingsUI.testBuy:SetText("Test Buy Alert")
    settingsUI.testBuy:SetScript("OnClick", function()
        IRS:TestTokenVisualAlert("buy")
    end)

    settingsUI.testSell = CreateFrame(
        "Button",
        nil,
        alertPanel,
        "UIPanelButtonTemplate"
    )
    settingsUI.testSell:SetSize(112, 24)
    settingsUI.testSell:SetPoint("TOPLEFT", 454, -162)
    settingsUI.testSell:SetText("Test Sell Alert")
    settingsUI.testSell:SetScript("OnClick", function()
        IRS:TestTokenVisualAlert("sell")
    end)

    local help = MakeText(alertPanel, "helper", COLORS.muted, "LEFT")
    help:SetPoint("BOTTOMLEFT", 12, 12)
    help:SetPoint("RIGHT", -12, 0)
    help:SetText(
        "BUY WITH GOLD = unusually low Token price.  SELL FOR GOLD = unusually high Token price. Alerts trigger when the market enters a zone."
    )

    settingsUI.layout = function()
        local width = math.max(1, marketPanel:GetWidth() - 24)
        local function Below(object, previous, gap)
            object:ClearAllPoints()
            object:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap or 10))
        end
        local function FitButton(button)
            local text = button:GetFontString()
            text:SetFontObject(IRS:GetControlFont("main"))
            text:SetWordWrap(false)
            button:SetSize(text:GetUnboundedStringWidth() + 24,
                math.max(28, text:GetStringHeight() + 12))
        end
        marketPanel:ClearAllPoints()
        marketPanel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -14)
        marketPanel:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
        local previous = settingsUI.price
        settingsUI.price:SetWidth(width)
        for _, text in ipairs({settingsUI.average, settingsUI.context, settingsUI.status}) do
            Below(text, previous)
            text:SetWidth(width)
            text:SetWordWrap(true)
            text:SetJustifyH("LEFT")
            previous = text
        end
        FitButton(settingsUI.refresh)
        Below(settingsUI.refresh, previous, 12)
        marketPanel:SetHeight(12 + settingsUI.price:GetStringHeight()
            + settingsUI.average:GetStringHeight() + settingsUI.context:GetStringHeight()
            + settingsUI.status:GetStringHeight() + 30 + 12 + settingsUI.refresh:GetHeight() + 12)

        local y = 10 + alertTitle:GetStringHeight() + 12
        for _, check in ipairs({settingsUI.enabled, settingsUI.chat, settingsUI.screen}) do
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", 10, -y)
            check.label:SetWidth(width - 38)
            check.label:SetWordWrap(true)
            y = y + math.max(28, check.label:GetStringHeight()) + 10
        end
        settingsUI.soundLabel:ClearAllPoints()
        settingsUI.soundLabel:SetPoint("TOPLEFT", 12, -y)
        settingsUI.soundLabel:SetWidth(width)
        y = y + settingsUI.soundLabel:GetStringHeight() + 8
        settingsUI.soundDropdown:ClearAllPoints()
        settingsUI.soundDropdown:SetPoint("TOPLEFT", -4, -y)
        y = y + math.max(32, IRS:GetFontSize("main", "label") + 16) + 14
        local columns = {settingsUI.interval, settingsUI.averageDays, settingsUI.buy,
            settingsUI.extremeBuy, settingsUI.sell, settingsUI.extremeSell}
        local columnWidth = math.max(1, (width - 16) / 2)
        for i = 1, #columns, 2 do
            local labelHeight = 0
            for j = i, i + 1 do
                local box = columns[j]
                box.label:ClearAllPoints()
                box.label:SetPoint("TOPLEFT", 12 + (j - i) * (columnWidth + 16), -y)
                box.label:SetWidth(columnWidth)
                box.label:SetWordWrap(true)
                labelHeight = math.max(labelHeight, box.label:GetStringHeight())
            end
            local inputHeight = math.max(26, IRS:GetFontSize("main", "body") + 12)
            for j = i, i + 1 do
                local box = columns[j]
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", box.label, "TOPLEFT", 2, -(labelHeight + 8))
                box:SetSize(math.min(columnWidth - 4, math.max(80, IRS:GetFontSize("main", "body") * 4 + 16)), inputHeight)
            end
            y = y + labelHeight + 8 + inputHeight + 16
        end
        testLabel:ClearAllPoints()
        testLabel:SetPoint("TOPLEFT", 12, -y)
        y = y + testLabel:GetStringHeight() + 8
        FitButton(settingsUI.testBuy)
        FitButton(settingsUI.testSell)
        settingsUI.testBuy:ClearAllPoints()
        settingsUI.testBuy:SetPoint("TOPLEFT", 12, -y)
        settingsUI.testSell:ClearAllPoints()
        if settingsUI.testBuy:GetWidth() + settingsUI.testSell:GetWidth() + 12 <= width then
            settingsUI.testSell:SetPoint("LEFT", settingsUI.testBuy, "RIGHT", 12, 0)
            y = y + math.max(settingsUI.testBuy:GetHeight(), settingsUI.testSell:GetHeight())
        else
            Below(settingsUI.testSell, settingsUI.testBuy)
            y = y + settingsUI.testBuy:GetHeight() + 10 + settingsUI.testSell:GetHeight()
        end
        help:ClearAllPoints()
        help:SetPoint("TOPLEFT", 12, -(y + 14))
        help:SetWidth(width)
        help:SetWordWrap(true)
        alertPanel:SetHeight(y + 14 + help:GetStringHeight() + 12)
    end
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
    settingsUI.layout()
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
    IRS:SetLayoutColor(panel.divider, "SetVertexColor", unpack(COLORS.border))
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

        local startupTiming = IRS:BeginStartupTiming("Token Market startup")
        IRS:EnsureTokenMarketDB()
        ScheduleNext()
        IRS:EndStartupTiming(startupTiming)
        return
    end

    if event == "PLAYER_LOGIN" then
        C_Timer.After(2.0, function()
            if IRS.db then
                local startupTiming = IRS:BeginStartupTiming("Token Market price request")
                IRS:RequestTokenMarketPrice()
                IRS:EndStartupTiming(startupTiming)
            end
        end)
    elseif event == "TOKEN_MARKET_PRICE_UPDATED" then
        IRS:CaptureTokenMarketPrice()
    end
end)


IRS:EndStartupTiming(_irsStartupModuleTiming)
