--[[
IRS — Internal Transfers
Matches movement between owned storage so transfers are not recorded as income or spending.
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
}

local MATCH_WINDOW = 1.25
local STORAGE_EXPIRY = 2.00
-- Blizzard can occasionally deliver GUILDBANK_UPDATE_MONEY after the normal
-- defer window. Keep ONLY wallet changes that were deferred while an owned
-- Guild Bank was open for a short grace period. If the matching bank delta
-- arrives, IRS reverses the already-filed ledger entry for both the account and
-- the character, then records the movement as an internal transfer.
local LATE_MATCH_WINDOW = 10.00

IRS.internalTransferRuntime = IRS.internalTransferRuntime or {
    pendingWallet = {},
    pendingStorage = {},
    recentRecordedWallet = {},
    nextWalletId = 0,
}
local runtime = IRS.internalTransferRuntime
runtime.pendingWallet = runtime.pendingWallet or {}
runtime.pendingStorage = runtime.pendingStorage or {}
runtime.recentRecordedWallet = runtime.recentRecordedWallet or {}

local function Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function MakeText(parent, style, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetFont(
        STANDARD_TEXT_FONT,
        IRS:GetFontSize("main", style),
        ""
    )
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    IRS:RegisterFontString("main", style, fs, STANDARD_TEXT_FONT, "")
    return fs
end

local function MakePanel(parent, color)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    local c = color or COLORS.panelAlt
    panel:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    panel:SetBackdropBorderColor(unpack(COLORS.border))
    return panel
end

local function IsProjectGuildSource(guildKey)
    if not guildKey or not IRS.db then return false end

    for _, project in pairs(IRS.db.projects and IRS.db.projects.items or {}) do
        if type(project) == "table" then
            if project.sourceType == "guild"
                and project.sourceKey == guildKey then
                return true
            end

            -- Configuration history may retain a prior guild source.
            for _, config in ipairs(project.configHistory or {}) do
                if config.sourceType == "guild"
                    and config.sourceKey == guildKey then
                    return true
                end
            end
        end
    end

    return false
end

function IRS:EnsureInternalTransferDB()
    if not IRS.db then IRS:EnsureDB() end

    IRS.db.internalTransfers = IRS.db.internalTransfers or {}
    local db = IRS.db.internalTransfers
    db.ownedGuildBanks = db.ownedGuildBanks or {}
    db.days = db.days or {}
    db.totalMoved = math.max(0, tonumber(db.totalMoved) or 0)
    db.events = db.events or {}

    return db
end

function IRS:IsInternalGuildBank(guildKey)
    if not guildKey then return false end
    local db = IRS:EnsureInternalTransferDB()
    local stored = db.ownedGuildBanks[guildKey]

    -- Explicit true/false always wins. Missing values inherit the very useful
    -- default that a Guild Bank used by a Savings Project belongs to IRS's
    -- internal financial ecosystem.
    if stored ~= nil then
        return stored == true
    end

    return IsProjectGuildSource(guildKey)
end

function IRS:SetInternalGuildBank(guildKey, enabled)
    if not guildKey then return end
    local db = IRS:EnsureInternalTransferDB()
    db.ownedGuildBanks[guildKey] = enabled == true

    if IRS.RefreshInternalTransferSettingsSection then
        IRS:RefreshInternalTransferSettingsSection()
    end
end


function IRS:RecordInternalTransfer(amount, fromType, fromKey, toType, toKey)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return end

    local db = IRS:EnsureInternalTransferDB()
    local dayKey = select(1, IRS:GetPeriodKeys())
    db.days[dayKey] = (tonumber(db.days[dayKey]) or 0) + amount
    db.totalMoved = (tonumber(db.totalMoved) or 0) + amount

    table.insert(db.events, {
        at = Now(),
        amount = amount,
        fromType = fromType,
        fromKey = fromKey,
        toType = toType,
        toKey = toKey,
    })

    -- This log is diagnostic only. Bound it so SavedVariables do not grow
    -- indefinitely from normal banking activity.
    while #db.events > 100 do
        table.remove(db.events, 1)
    end
end

function IRS:GetInternalTransferSummary()
    local db = IRS:EnsureInternalTransferDB()
    local dayKey = select(1, IRS:GetPeriodKeys())
    return {
        today = tonumber(db.days[dayKey]) or 0,
        total = tonumber(db.totalMoved) or 0,
        count = #db.events,
    }
end

local function PruneRuntime()
    local now = Now()

    for i = #runtime.pendingStorage, 1, -1 do
        local item = runtime.pendingStorage[i]
        if now - (tonumber(item.at) or 0) > STORAGE_EXPIRY
            or (tonumber(item.amount) or 0) == 0 then
            table.remove(runtime.pendingStorage, i)
        end
    end

    for i = #runtime.pendingWallet, 1, -1 do
        local item = runtime.pendingWallet[i]
        if (tonumber(item.amount) or 0) == 0 then
            table.remove(runtime.pendingWallet, i)
        end
    end

    for i = #runtime.recentRecordedWallet, 1, -1 do
        local item = runtime.recentRecordedWallet[i]
        if (tonumber(item.amount) or 0) == 0
            or now - (tonumber(item.recordedAt) or 0) > LATE_MATCH_WINDOW then
            table.remove(runtime.recentRecordedWallet, i)
        end
    end
end

local function RecordMatched(
    walletAmount,
    matched,
    characterKey,
    storage,
    transactionId,
    reason
)
    if matched <= 0 then return end

    if walletAmount < 0 then
        IRS:RecordInternalTransfer(
            matched,
            "character",
            characterKey,
            storage.storageType,
            storage.storageKey
        )
    else
        IRS:RecordInternalTransfer(
            matched,
            storage.storageType,
            storage.storageKey,
            "character",
            characterKey
        )
    end

    if IRS.RecordTransactionInternalMatch then
        IRS:RecordTransactionInternalMatch(
            transactionId,
            matched,
            walletAmount,
            storage.storageType,
            storage.storageKey,
            reason or "INTERNAL_STORAGE_MATCH"
        )
    end
end

local function ConsumeStorage(walletAmount, characterKey, transactionId)
    walletAmount = math.floor(tonumber(walletAmount) or 0)
    if walletAmount == 0 then return 0 end

    PruneRuntime()
    local remaining = walletAmount

    for i = #runtime.pendingStorage, 1, -1 do
        local storage = runtime.pendingStorage[i]
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        if remaining ~= 0
            and storageAmount ~= 0
            and ((remaining < 0 and storageAmount > 0)
                or (remaining > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(remaining),
                math.abs(storageAmount)
            )

            RecordMatched(
                remaining,
                matched,
                characterKey,
                storage,
                transactionId,
                "STORAGE_MATCH"
            )

            if remaining < 0 then
                remaining = remaining + matched
                storage.amount = storageAmount - matched
            else
                remaining = remaining - matched
                storage.amount = storageAmount + matched
            end

            if storage.amount == 0 then
                table.remove(runtime.pendingStorage, i)
            end
        end
    end

    return remaining
end

-- If a deferred Guild Bank wallet change timed out and was already filed as
-- income/loss, a later bank event can still prove it was an internal transfer.
-- Reverse exactly the matched piece through RecordEarnings so ACCOUNT and
-- CHARACTER ledgers stay paired.
local function ConsumeLateRecordedStorage(storage)
    if not storage or (tonumber(storage.amount) or 0) == 0 then return end

    PruneRuntime()

    for i = #runtime.recentRecordedWallet, 1, -1 do
        local wallet = runtime.recentRecordedWallet[i]
        local walletAmount = math.floor(tonumber(wallet.amount) or 0)
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        local sameStorage =
            wallet.expectedStorageType == storage.storageType
            and wallet.expectedStorageKey == storage.storageKey

        if sameStorage
            and walletAmount ~= 0
            and storageAmount ~= 0
            and ((walletAmount < 0 and storageAmount > 0)
                or (walletAmount > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(walletAmount),
                math.abs(storageAmount)
            )

            -- The wallet entry was already written to both ledgers. Undo the
            -- matched transfer amount before logging it as internal movement.
            local correction = walletAmount < 0 and matched or -matched
            IRS:RecordEarnings(correction, {}, wallet.characterKey)
            if IRS.RecordTransactionLedgerEffect then
                IRS:RecordTransactionLedgerEffect(
                    wallet.transactionId,
                    correction,
                    "GUILD_LATE_MATCH"
                )
            end
            RecordMatched(
                walletAmount,
                matched,
                wallet.characterKey,
                storage,
                wallet.transactionId,
                "GUILD_LATE_MATCH"
            )
            if IRS.UpdateTransactionEvent then
                IRS:UpdateTransactionEvent(
                    wallet.transactionId,
                    { corrected = true }
                )
            end

            if walletAmount < 0 then
                wallet.amount = walletAmount + matched
                storage.amount = storageAmount - matched
            else
                wallet.amount = walletAmount - matched
                storage.amount = storageAmount + matched
            end

            if wallet.amount == 0 then
                table.remove(runtime.recentRecordedWallet, i)
            end
        end
    end
end

local function CurrentInternalGuildOpen()
    if not IRS.guildBankRuntime
        or IRS.guildBankRuntime.isOpen ~= true then
        return nil
    end

    local guildKey = IRS:GetCurrentGuildKey()
    if guildKey and IRS:IsInternalGuildBank(guildKey) then
        return guildKey
    end

    return nil
end

function IRS:FinalizePendingInternalWallet(walletId)
    PruneRuntime()

    local index, entry
    for i, pending in ipairs(runtime.pendingWallet) do
        if pending.id == walletId then
            index, entry = i, pending
            break
        end
    end

    if not entry then return end
    table.remove(runtime.pendingWallet, index)

    local remaining = ConsumeStorage(
        entry.amount,
        entry.characterKey,
        entry.transactionId
    )
    if remaining ~= 0 then
        IRS:RecordEarnings(remaining, {}, entry.characterKey)
        if IRS.RecordTransactionLedgerEffect then
            IRS:RecordTransactionLedgerEffect(
                entry.transactionId,
                remaining,
                "GUILD_MATCH_TIMEOUT"
            )
        end

        -- Do not forget this immediately. The owned Guild Bank money event can
        -- arrive after MATCH_WINDOW on some clients. A matching late event will
        -- reverse this exact ledger amount for both account and character.
        table.insert(runtime.recentRecordedWallet, {
            amount = remaining,
            characterKey = entry.characterKey,
            expectedStorageType = entry.expectedStorageType,
            expectedStorageKey = entry.expectedStorageKey,
            transactionId = entry.transactionId,
            recordedAt = Now(),
        })
    end

    if IRS.UpdateProjectSnapshots then IRS:UpdateProjectSnapshots() end
    if IRS.RefreshUI then IRS:RefreshUI() end
end

local function QueueWallet(
    walletAmount,
    characterKey,
    guildKey,
    transactionId
)
    runtime.nextWalletId = (tonumber(runtime.nextWalletId) or 0) + 1
    local id = runtime.nextWalletId

    table.insert(runtime.pendingWallet, {
        id = id,
        amount = walletAmount,
        characterKey = characterKey,
        expectedStorageType = "guild",
        expectedStorageKey = guildKey,
        transactionId = transactionId,
        at = Now(),
    })

    if IRS.UpdateTransactionEvent then
        IRS:UpdateTransactionEvent(transactionId, {
            disposition = "PENDING",
            reason = "GUILD_PENDING",
            fromType = walletAmount < 0 and "character" or "guild",
            fromKey = walletAmount < 0 and characterKey or guildKey,
            toType = walletAmount < 0 and "guild" or "character",
            toKey = walletAmount < 0 and guildKey or characterKey,
        })
    end

    C_Timer.After(MATCH_WINDOW, function()
        if IRS.db then
            IRS:FinalizePendingInternalWallet(id)
        end
    end)
end

function IRS:ObserveInternalStorageDelta(storageType, storageKey, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false end

    if storageType == "guild"
        and not IRS:IsInternalGuildBank(storageKey) then
        return false
    end

    if storageType ~= "warband" and storageType ~= "guild" then
        return false
    end

    PruneRuntime()

    local storage = {
        storageType = storageType,
        storageKey = storageKey,
        amount = amount,
        at = Now(),
    }

    -- Bank event arrived after PLAYER_MONEY: consume deferred wallet changes.
    for i = #runtime.pendingWallet, 1, -1 do
        local wallet = runtime.pendingWallet[i]
        local walletAmount = math.floor(tonumber(wallet.amount) or 0)
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        if walletAmount ~= 0
            and storageAmount ~= 0
            and ((walletAmount < 0 and storageAmount > 0)
                or (walletAmount > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(walletAmount),
                math.abs(storageAmount)
            )

            RecordMatched(
                walletAmount,
                matched,
                wallet.characterKey,
                storage,
                wallet.transactionId,
                "GUILD_EVENT_MATCH"
            )

            if walletAmount < 0 then
                wallet.amount = walletAmount + matched
                storage.amount = storageAmount - matched
            else
                wallet.amount = walletAmount - matched
                storage.amount = storageAmount + matched
            end

            if wallet.amount == 0 then
                table.remove(runtime.pendingWallet, i)
            end
        end
    end

    if storage.amount ~= 0 then
        ConsumeLateRecordedStorage(storage)
    end

    if storage.amount ~= 0 then
        table.insert(runtime.pendingStorage, storage)
    end

    if IRS.RefreshInternalTransferSettingsSection then
        IRS:RefreshInternalTransferSettingsSection()
    end

    return true
end

function IRS:FilterInternalWalletChange(
    walletDelta,
    characterKey,
    previousWarband,
    currentWarband,
    transactionId
)
    walletDelta = math.floor(tonumber(walletDelta) or 0)
    if walletDelta == 0 then return 0, false end

    IRS:EnsureInternalTransferDB()
    PruneRuntime()

    local remaining = walletDelta

    -- Fast path when PLAYER_MONEY can see the Warband balance change directly.
    if previousWarband ~= nil and currentWarband ~= nil then
        local storageDelta = currentWarband - previousWarband
        if storageDelta ~= 0
            and ((remaining < 0 and storageDelta > 0)
                or (remaining > 0 and storageDelta < 0)) then

            local matched = math.min(
                math.abs(remaining),
                math.abs(storageDelta)
            )

            RecordMatched(
                remaining,
                matched,
                characterKey,
                {
                    storageType = "warband",
                    storageKey = nil,
                },
                transactionId,
                "WARBAND_DIRECT_MATCH"
            )

            if remaining < 0 then
                remaining = remaining + matched
            else
                remaining = remaining - matched
            end
        end
    end

    -- If a bank event arrived first, consume its pending balance change now.
    remaining = ConsumeStorage(
        remaining,
        characterKey,
        transactionId
    )

    -- Guild Bank money often updates a fraction after PLAYER_MONEY. Defer the
    -- unmatched wallet change only while an OWNED Guild Bank is actually open.
    local openGuildKey = remaining ~= 0 and CurrentInternalGuildOpen() or nil
    if remaining ~= 0 and openGuildKey then
        QueueWallet(
            remaining,
            characterKey,
            openGuildKey,
            transactionId
        )
        return 0, true
    end

    return remaining, false
end

-- ============================================================================
-- SETTINGS UI
-- ============================================================================
local settingsUI

local function GuildRows()
    local rows = IRS:GetSortedGuildBanks()
    local seen = {}

    for _, row in ipairs(rows) do
        seen[row.key] = true
    end

    -- Project sources may exist before a successful live Guild Bank scan in the
    -- current session. Include those keys so the ownership setting is visible.
    for _, project in pairs(IRS.db.projects and IRS.db.projects.items or {}) do
        if type(project) == "table"
            and project.sourceType == "guild"
            and project.sourceKey
            and not seen[project.sourceKey] then
            table.insert(rows, {
                key = project.sourceKey,
                record = IRS.db.guildBanks[project.sourceKey] or {
                    key = project.sourceKey,
                    name = project.sourceKey:match("^(.-)@") or project.sourceKey,
                },
            })
            seen[project.sourceKey] = true
        end
    end

    table.sort(rows, function(a, b)
        return (a.record.name or a.key or "")
            < (b.record.name or b.key or "")
    end)

    return rows
end

function IRS:BuildInternalTransferSettingsSection(parent)
    if settingsUI then return settingsUI.frame end
    IRS:EnsureInternalTransferDB()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local title = MakeText(frame, "section", COLORS.goldSoft, "LEFT")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("INTERNAL TRANSFERS")

    local desc = MakeText(frame, "helper", COLORS.muted, "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetPoint("RIGHT", -16, 0)
    desc:SetText(
        "Money moved between your own storage locations is ignored by the IRS income/loss ledger. Project balances still update normally."
    )

    local info = MakePanel(frame, COLORS.panelAlt)
    info:SetPoint("TOPLEFT", 14, -68)
    info:SetPoint("TOPRIGHT", -14, -68)
    info:SetHeight(92)

    local infoTitle = MakeText(info, "label", COLORS.goldSoft, "LEFT")
    infoTitle:SetPoint("TOPLEFT", 12, -11)
    infoTitle:SetText("ALWAYS INTERNAL")

    local infoText = MakeText(info, "body", COLORS.text, "LEFT")
    infoText:SetPoint("TOPLEFT", 12, -36)
    infoText:SetPoint("RIGHT", -12, 0)
    infoText:SetText(
        "Character wallets ↔ Warband Bank transfers are always excluded from net income. Mark your own Guild Banks below to extend that protection to savings transfers."
    )

    local summary = MakeText(info, "helper", COLORS.muted, "LEFT")
    summary:SetPoint("BOTTOMLEFT", 12, 10)

    local guildPanel = MakePanel(frame, COLORS.panelAlt)
    guildPanel:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -12)
    guildPanel:SetPoint("BOTTOMRIGHT", -14, 14)

    local guildTitle = MakeText(guildPanel, "label", COLORS.goldSoft, "LEFT")
    guildTitle:SetPoint("TOPLEFT", 12, -11)
    guildTitle:SetText("OWNED GUILD BANKS")

    local guildDesc = MakeText(guildPanel, "helper", COLORS.muted, "LEFT")
    guildDesc:SetPoint("TOPLEFT", 12, -34)
    guildDesc:SetPoint("RIGHT", -12, 0)
    guildDesc:SetText(
        "Savings Project Guild Banks default to internal. Uncheck a shared Guild Bank if transfers to it should count as money leaving your finances."
    )

    local scroll = CreateFrame(
        "ScrollFrame",
        "IncomeRecordsSystemInternalTransferScroll",
        guildPanel,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", 10, -66)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(570, 1)
    scroll:SetScrollChild(child)

    local empty = MakeText(child, "body", COLORS.muted, "CENTER")
    empty:SetPoint("TOPLEFT", 8, -18)
    empty:SetWidth(550)
    empty:SetText(
        "No Guild Banks are known yet. Open a Guild Bank once and IRS will add it here."
    )

    settingsUI = {
        frame = frame,
        summary = summary,
        scroll = scroll,
        child = child,
        empty = empty,
        rows = {},
    }

    return frame
end

local function EnsureGuildSettingRow(index)
    local ui = settingsUI
    if ui.rows[index] then return ui.rows[index] end

    local row = MakePanel(ui.child, COLORS.panel)
    row:SetHeight(54)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", 8, 0)

    row.name = MakeText(row, "body", COLORS.text, "LEFT")
    row.name:SetPoint("TOPLEFT", 45, -8)
    row.name:SetPoint("RIGHT", -12, 0)

    row.meta = MakeText(row, "helper", COLORS.muted, "LEFT")
    row.meta:SetPoint("TOPLEFT", 45, -29)
    row.meta:SetPoint("RIGHT", -12, 0)

    row.check:SetScript("OnClick", function(self)
        if row.guildKey then
            IRS:SetInternalGuildBank(row.guildKey, self:GetChecked())
        end
    end)

    ui.rows[index] = row
    return row
end

function IRS:RefreshInternalTransferSettingsSection()
    if not settingsUI or not IRS.db then return end
    local ui = settingsUI
    local rows = GuildRows()
    local summary = IRS:GetInternalTransferSummary()

    ui.summary:SetText(string.format(
        "Internal transfers ignored today: %s   •   Since tracking: %s",
        IRS:FormatMoney(summary.today, true),
        IRS:FormatMoney(summary.total, true)
    ))

    ui.empty:SetShown(#rows == 0)
    local width = math.max(520, (ui.scroll:GetWidth() or 560) - 5)

    for i, entry in ipairs(rows) do
        local row = EnsureGuildSettingRow(i)
        local record = entry.record or {}
        row.guildKey = entry.key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * 58))
        row:SetWidth(width)
        row.check:SetChecked(IRS:IsInternalGuildBank(entry.key))
        row.name:SetText(record.name or entry.key or "Guild Bank")

        local parts = {}
        if record.realm then table.insert(parts, record.realm) end
        if record.money ~= nil then
            table.insert(parts, IRS:FormatMoney(record.money, true))
        else
            table.insert(parts, "balance not cached")
        end
        if IsProjectGuildSource(entry.key) then
            table.insert(parts, "Savings Project source")
        end
        row.meta:SetText(table.concat(parts, "  •  "))
        row:Show()
    end

    for i = #rows + 1, #ui.rows do
        ui.rows[i]:Hide()
    end

    ui.child:SetHeight(math.max(1, #rows * 58))
end
