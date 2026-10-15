-- Auction income requires collected seller-invoice mail plus observed wallet gold.
-- Inbox snapshots preserve invoice evidence when collection clears mail data.
local IRS = IRS
local state = {snapshot = {}, totals = {}, attempts = {}, receipts = {}, open = false, removals = {}, previousSnapshot = {}}

local function Now()
    return GetServerTime and GetServerTime() or time()
end

local function ReadInbox()
    local rows, totals = {}, {}
    if not GetInboxNumItems or not GetInboxHeaderInfo or not GetInboxInvoiceInfo then
        return rows, totals
    end
    local count = GetInboxNumItems() or 0
    for index = 1, count do
        local _, _, sender, subject, money, cod = GetInboxHeaderInfo(index)
        money = tonumber(money) or 0
        local invoice, item, buyer, bid, buyout, deposit, cut = GetInboxInvoiceInfo(index)
        -- Match Blizzard's open-mail path: request the body when invoice data
        -- has not populated yet (common when opening all mail without viewing it).
        if not invoice and money > 0 and GetInboxText then
            GetInboxText(index)
            invoice, item, buyer, bid, buyout, deposit, cut = GetInboxInvoiceInfo(index)
        end
        if invoice == "seller" and money > 0 and (tonumber(cod) or 0) == 0 then
            local signature = table.concat({tostring(sender), tostring(subject), tostring(item),
                tostring(buyer), tostring(bid), tostring(buyout), tostring(deposit), tostring(cut)}, "\031")
            rows[index] = {signature = signature, money = money, salePrice = tonumber(bid) or money,
                wallet = GetMoney and GetMoney() or nil, sequence = (IRS.incomeSourceSequence or 0)+1}
            totals[signature] = (totals[signature] or 0) + money
        end
    end
    return rows, totals
end

function IRS:BeginAuctionMailCollection(index)
    if not self.db then return end
    local row = state.snapshot[index]
    if not row and state.snapshotAt and Now() - state.snapshotAt <= 1 then
        local previous = state.previousSnapshot[index]
        local removal = previous and state.removals[previous.signature]
        if removal and removal.amount > 0 then row = previous end
    end
    if not row then return end
    local minimumSequence = (self.incomeSourceSequence or 0) + 1
    -- Native collection may update the wallet before its secure post-hook runs.
    -- Only recover that entry when the observed balance matches this invoice.
    for _, entry in ipairs(self.pendingIncomeSources or {}) do
        if entry.characterKey == self:CharacterKey() and entry.sequence >= (row.sequence or minimumSequence)
            and entry.walletAfter and row.wallet and entry.walletAfter == row.wallet + row.money
            and entry.remaining >= row.money and Now() - entry.at <= 1 then
            minimumSequence = entry.sequence
            break
        end
    end
    -- Do not queue the same still-pending native mail command twice.
    for _, attempt in ipairs(state.attempts) do
        if attempt.index == index and attempt.signature == row.signature then return end
    end
    state.attempts[#state.attempts + 1] = {
        index = index, signature = row.signature, amount = row.money,
        at = Now(), characterKey = self:CharacterKey(),
        minimumSequence = minimumSequence, salePrice = row.salePrice,
    }
    self:RefreshAuctionMailInbox()
end

function IRS:FlushAuctionMailIncome()
    if not self.db then return end
    local kept, changed = {}, false
    for _, receipt in ipairs(state.receipts) do
        if Now() - receipt.at <= 30 then
            local matched = self:RecordEarnings(0, {auctionGold = receipt.amount},
                receipt.characterKey, false, receipt) or 0
            receipt.amount = receipt.amount - matched
            changed = changed or matched > 0
            if matched > 0 then
                local day = self:GetOverviewDay()
                day.largestSale = math.max(day.largestSale or 0, receipt.salePrice or 0)
            end
            if receipt.amount > 0 then kept[#kept + 1] = receipt end
        end
    end
    state.receipts = kept
    if changed and self.RefreshUI then self:RefreshUI() end
end

function IRS:RefreshAuctionMailInbox()
    local rows, totals = ReadInbox()
    for signature, removal in pairs(state.removals) do
        if Now() - removal.at > 30 then state.removals[signature] = nil end
    end
    for signature, money in pairs(state.totals) do
        local removed = math.max(0, money - (totals[signature] or 0))
        if removed > 0 then
            local previous = state.removals[signature]
            state.removals[signature] = {amount = removed + (previous and previous.amount or 0), at = Now()}
        end
    end
    local kept = {}
    for _, attempt in ipairs(state.attempts) do
        if Now() - attempt.at <= 30 then
            local removal = state.removals[attempt.signature]
            local available = removal and removal.amount or 0
            local confirmed = math.min(available, attempt.amount)
            if confirmed > 0 then
                removal.amount = available - confirmed
                state.receipts[#state.receipts + 1] = {
                    kind = "auctionMail", amount = confirmed, at = attempt.at,
                    characterKey = attempt.characterKey,
                    minimumSequence = attempt.minimumSequence, salePrice = attempt.salePrice,
                }
                attempt.amount = attempt.amount - confirmed
            end
            if attempt.amount > 0 then kept[#kept + 1] = attempt end
        end
    end
    state.previousSnapshot = state.snapshot
    state.snapshotAt = Now()
    state.attempts, state.snapshot, state.totals = kept, rows, totals
    self:FlushAuctionMailIncome()
end

function IRS:CancelAuctionMailCollection()
    state.attempts, state.removals, state.previousSnapshot = {}, {}, {}
end

if hooksecurefunc then
    for _, name in ipairs({"TakeInboxMoney", "AutoLootMailItem"}) do
        if _G[name] then
            hooksecurefunc(name, function(index) IRS:BeginAuctionMailCollection(index) end)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_FAILED" then
        IRS:CancelAuctionMailCollection()
    elseif event == "MAIL_CLOSED" then
        -- Closing the inbox clears its API data; that is not collection proof.
        state.open = false
        state.snapshot, state.totals, state.attempts, state.receipts = {}, {}, {}, {}
        state.previousSnapshot, state.removals = {}, {}
    elseif event == "PLAYER_MONEY" then
        IRS:FlushAuctionMailIncome()
    elseif event == "MAIL_SHOW" then
        state.open = true
        IRS:RefreshAuctionMailInbox()
    elseif state.open then
        IRS:RefreshAuctionMailInbox()
    end
end)
