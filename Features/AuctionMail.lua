-- Auction income requires collected seller-invoice mail plus observed wallet gold.
-- Inbox snapshots preserve invoice evidence when collection clears mail data.
local IRS = IRS
local state = {snapshot = {}, totals = {}, attempts = {}, receipts = {}, open = false}

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
        local crafting = C_Mail and C_Mail.GetCraftingOrderMailInfo
            and C_Mail.GetCraftingOrderMailInfo(index)
        if invoice == "seller" and not crafting and money > 0 and (tonumber(cod) or 0) == 0 then
            local signature = table.concat({tostring(sender), tostring(subject), tostring(item),
                tostring(buyer), tostring(bid), tostring(buyout), tostring(deposit), tostring(cut)}, "\031")
            rows[index] = {signature = signature, money = money}
            totals[signature] = (totals[signature] or 0) + money
        end
    end
    return rows, totals
end

function IRS:BeginAuctionMailCollection(index)
    if not self.db then return end
    local row = state.snapshot[index]
    if not row then return end
    -- Do not queue the same still-pending native mail command twice.
    for _, attempt in ipairs(state.attempts) do
        if attempt.index == index and attempt.signature == row.signature then return end
    end
    state.attempts[#state.attempts + 1] = {
        index = index, signature = row.signature, amount = row.money,
        at = Now(), characterKey = self:CharacterKey(),
        minimumSequence = (self.incomeSourceSequence or 0) + 1,
    }
end

function IRS:FlushAuctionMailIncome()
    if not self.db then return end
    local kept, changed = {}, false
    for _, receipt in ipairs(state.receipts) do
        if Now() - receipt.at <= 5 then
            local matched = self:RecordEarnings(0, {auctionGold = receipt.amount},
                receipt.characterKey, false, receipt) or 0
            receipt.amount = receipt.amount - matched
            changed = changed or matched > 0
            if receipt.amount > 0 then kept[#kept + 1] = receipt end
        end
    end
    state.receipts = kept
    if changed and self.RefreshUI then self:RefreshUI() end
end

function IRS:RefreshAuctionMailInbox()
    local rows, totals = ReadInbox()
    local removed = {}
    for signature, money in pairs(state.totals) do
        removed[signature] = math.max(0, money - (totals[signature] or 0))
    end
    local kept = {}
    for _, attempt in ipairs(state.attempts) do
        if Now() - attempt.at <= 5 then
            local available = removed[attempt.signature] or 0
            local confirmed = math.min(available, attempt.amount)
            if confirmed > 0 then
                removed[attempt.signature] = available - confirmed
                state.receipts[#state.receipts + 1] = {
                    kind = "auctionMail", amount = confirmed, at = attempt.at,
                    characterKey = attempt.characterKey,
                    minimumSequence = attempt.minimumSequence,
                }
                attempt.amount = attempt.amount - confirmed
            end
            if attempt.amount > 0 then kept[#kept + 1] = attempt end
        end
    end
    state.attempts, state.snapshot, state.totals = kept, rows, totals
    self:FlushAuctionMailIncome()
end

function IRS:CancelAuctionMailCollection()
    state.attempts = {}
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
    elseif event == "PLAYER_MONEY" then
        IRS:FlushAuctionMailIncome()
    elseif event == "MAIL_SHOW" then
        state.open = true
        IRS:RefreshAuctionMailInbox()
    elseif state.open then
        IRS:RefreshAuctionMailInbox()
    end
end)
