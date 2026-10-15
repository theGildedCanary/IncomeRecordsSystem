"""Offline Lua 5.1 checks. Requires Python and lupa; does not simulate rendering."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("""function(source, name)
    local f, e = loadstring(source, name)
    if not f then error(e) end
    return f
end""")
files = [p for folder in ('Core', 'Features', 'UI') for p in (root / folder).glob('*.lua')]
for path in files:
    compile_lua(path.read_text(encoding='utf-8-sig'), str(path))
print(f'PASS Lua 5.1 syntax: {len(files)} files')
for line in (root / 'IncomeRecordsSystem.toc').read_text().splitlines():
    if line.strip() and not line.startswith('#'):
        assert (root / line).is_file(), line
print('PASS all TOC file references')

lua.execute('''
C_AddOns = {GetAddOnMetadata = function() return 'test' end}
C_Timer = {After = function() end}
SlashCmdList = {}
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function GetServerTime() return 1791907200 end
function time(t) if t then return os.time(t) end return GetServerTime() end
function date(f,t) return os.date(f,t or GetServerTime()) end
function UnitGUID() return 'Player-Test' end
function UnitName() return 'Tester' end
function GetRealmName() return 'TestRealm' end
function UnitClass() return 'Warrior','WARRIOR',1 end
function UnitLevel() return 80 end
function UnitFactionGroup() return 'Alliance' end
function GetGuildInfo() return nil end
function GetMoney() return TEST_MONEY end
function GetStatistic() return '--' end
function strtrim(s) return s:match('^%s*(.-)%s*$') end
TEST_MONEY = 1000000
''')
def load(path, *args):
    compile_lua((root / path).read_text(encoding='utf-8-sig'), path)(*args)

load('Core/Core.lua', 'IncomeRecordsSystem')
lua.execute('''
IRS:EnsureDB()
IRS:ScanCurrentCharacter()
assert(IRS.db.characters['Player-Test'].money == 1000000)
TEST_MONEY=1250000; IRS:HandleMoneyChange()
assert(IRS:GetCurrentEarnings().today == 250000)
TEST_MONEY=1150000; IRS:HandleMoneyChange()
assert(IRS:GetCurrentEarnings().today == 150000)
IRS:ScanCurrentCharacter()
assert(IRS:GetCurrentEarnings().today == 150000)
print('PASS scan, wallet income/expense, no double counting')
local ok,p=IRS:CreateProject({name='Test',targetCopper=10000000,deadline='2027-07-01',sourceType='account'})
assert(ok,p)
local stats=IRS:GetProjectStats(p)
assert(stats.remaining == math.max(0,stats.target-stats.current))
assert(stats.dailyNeeded == math.ceil(stats.remaining/stats.daysLeft))
for _,interval in ipairs({'daily','weekly','monthly','checkpoints'}) do
    assert(IRS:GetProjectGraphData(p,interval))
end
local ok,cp=IRS:AddProjectCheckpoint(p.id,'Milestone',2000000); assert(ok,cp)
assert(#IRS:GetProjectCheckpoints(p) == 1)
assert(IRS:DeleteProjectCheckpoint(p.id,cp.id))
assert(IRS:SetProjectAllocationPercent(p.id,50))
assert(IRS:DeleteProject(p.id))
print('PASS projects, summaries, graph intervals, checkpoints, allocation, deletion')
''')
for name in ('Transfers', 'Reserves', 'Tools'):
    load(f'Features/{name}.lua')
lua.execute('''
local before = IRS:GetCurrentEarnings()
local character = IRS:GetCharacterEarnings('Player-Test')
local funds = IRS:GetAccountLiquidGoldAllCharacters()
local distribution = IRS:GetProfitDistribution()
local oldOffset = IRS.db.tracking.overallIncomeAdjustment
local oldHistory = IRS.db.tracking.overallIncomeAdjustmentHistory
assert(not IRS:AdjustAccountTotalEarnings(0))
assert(not IRS:AdjustAccountTotalEarnings('invalid'))
assert(not IRS:AdjustAccountTotalEarnings(math.huge))
assert(not IRS:AdjustAccountTotalEarnings(0/0))
assert(IRS:AdjustAccountTotalEarnings(5000000))
assert(IRS:GetCurrentEarnings().total == before.total + 5000000)
for _, field in ipairs({'today', 'week', 'month'}) do
    assert(IRS:GetCurrentEarnings()[field] == before[field])
end
for _, field in ipairs({'today', 'week', 'month', 'total'}) do
    assert(IRS:GetCharacterEarnings('Player-Test')[field] == character[field])
end
assert(IRS:GetAccountLiquidGoldAllCharacters() == funds)
assert(IRS:GetProfitDistribution().availableProfit == distribution.availableProfit)
assert(IRS:GetProfitDistribution().netSince == distribution.netSince)
assert(IRS:AdjustAccountTotalEarnings(-7000000))
assert(IRS:GetCurrentEarnings().total == before.total - 2000000)
IRS:EnsureDB()
assert(IRS:GetCurrentEarnings().total == before.total - 2000000)
assert(#IRS.db.tracking.overallIncomeAdjustmentHistory >= 2)
IRS.db.tracking.overallIncomeAdjustment = oldOffset
IRS.db.tracking.overallIncomeAdjustmentHistory = oldHistory
print('PASS account-only total corrections preserve character, periods, funds and distributable profit')
''')
lua.execute('''
local oldInGuild, oldGuildInfo = IsInGuild, GetGuildInfo
local oldMoney, oldBank, oldEnum = GetGuildBankMoney, C_Bank, Enum
local oldProjects = IRS.db.projects.items
IRS.db.projects.items = {}
IsInGuild = function() return true end
GetGuildInfo = function() return 'NoProjectGuild', nil, nil, 'TestRealm' end
IRS:ScanCurrentCharacter()
local key = 'NoProjectGuild@TestRealm'
assert(IRS.db.characters['Player-Test'].guildKey == key)
assert(IRS.db.guildBanks[key] and IRS.db.guildBanks[key].money == nil)
local found = false
for _, row in ipairs(IRS:GetSortedGuildBanks()) do
    if row.key == key then found = true end
end
assert(found and not IRS:IsInternalGuildBank(key))
GetGuildBankMoney = function() return 400000 end
C_Bank, Enum = nil, nil
assert(IRS:ScanGuildBankGold(false) == 400000)
local baseline = IRS:GetAccountLiquidGoldAllCharacters()
IRS:SetInternalGuildBank(key, true)
assert(IRS:GetAccountLiquidGoldAllCharacters() == baseline + 400000)
local oldOpen, oldUpdate = IRS.guildBankRuntime.isOpen, IRS.guildBankRuntime.hasMoneyUpdate
IRS.guildBankRuntime.isOpen, IRS.guildBankRuntime.hasMoneyUpdate = false, false
GetGuildBankMoney = function() return 0 end
assert(IRS:ScanGuildBankGold(false) == nil)
assert(IRS.db.guildBanks[key].money == 400000)
IRS.guildBankRuntime.isOpen, IRS.guildBankRuntime.hasMoneyUpdate = true, true
assert(IRS:ScanGuildBankGold(true) == 0)
assert(IRS:GetAccountLiquidGoldAllCharacters() == baseline)
IsInGuild = function() return false end
IRS:ScanCurrentCharacter()
assert(IRS.db.characters['Player-Test'].guildKey == nil)
assert(IRS.db.guildBanks[key])
IRS.guildBankRuntime.isOpen, IRS.guildBankRuntime.hasMoneyUpdate = oldOpen, oldUpdate
IRS.db.guildBanks[key] = nil
IRS:EnsureInternalTransferDB().ownedGuildBanks[key] = nil
IRS.internalTransferRuntime.pendingStorage = {}
IRS.db.projects.items = oldProjects
IsInGuild, GetGuildInfo = oldInGuild, oldGuildInfo
GetGuildBankMoney, C_Bank, Enum = oldMoney, oldBank, oldEnum
print('PASS project-free guild registration, personal funds, confirmed empty bank and retained guild discovery')
''')
lua.execute('''
local baseline=IRS:GetCurrentEarnings().today
local delta,deferred=IRS:FilterInternalWalletChange(-200000,'Player-Test',100000,300000)
assert(delta == 0 and not deferred)
assert(IRS:GetCurrentEarnings().today == baseline)
local delta=IRS:FilterInternalWalletChange(250000,'Player-Test',300000,100000)
assert(delta == 50000)
print('PASS Warband transfer exclusion and additional income')
local ok,r=IRS:CreateReserve({name='Reserve',targetCopper=1000000,warningFloorCopper=800000,sourceType='account'})
assert(ok,r)
assert(IRS:GetReserveStats(r).status == 'FUNDED')
assert(IRS:DeleteReserve(r.id))
local ok,a=IRS:CreateProject({name='A',targetCopper=10000000,deadline='2027-07-01',sourceType='account'}); assert(ok)
local ok,b=IRS:CreateProject({name='B',targetCopper=10000000,deadline='2027-07-01',sourceType='account'}); assert(ok)
IRS:SyncProjectDistributionPlan()
assert(IRS:SetProjectDistributionPercent(a.id,75))
assert(IRS:SetProfitDistributionReservePercent(10))
local total,split=0,0
for _,g in ipairs(IRS:GetProfitDistributionGoals()) do
    total=total+g.weight; split=split+g.splitPercent
    if g.objectId==a.id then assert(g.weight==75 and g.splitPercent==67.5) end
end
assert(total == 100)
assert(split == 90)
TEST_MONEY=TEST_MONEY+1000000; IRS:HandleMoneyChange()
local distribution=IRS:GetProfitDistribution()
assert(distribution.reserveSuggested==math.floor(distribution.availableProfit*0.1))
assert(IRS:MarkProfitsAllocated())
assert(IRS:GetProfitDistribution().availableProfit==0)
print('PASS reserves, distribution totals, reserve carve-out, allocation checkpoint')
''')

# Dashboard dates filter observed flows, never import lifetime wealth counters.
lua.execute('''
local day = select(1, IRS:GetPeriodKeys())
assert(not IRS:SetOverviewStartDate('2026-02-30'))
assert(not IRS:SetOverviewStartDate('2099-01-01'))
assert(not IRS:SetOverviewStartDate('bad'))
assert(IRS:SetOverviewStartDate(day))
local before = IRS:GetOverviewTotals().totalAcquired
IRS:RecordEarnings(100000, {}, IRS:CharacterKey())
assert(IRS:GetOverviewTotals().totalAcquired == before + 100000)
IRS:RecordEarnings(-100000, {}, IRS:CharacterKey(), true)
assert(IRS:GetOverviewTotals().totalAcquired == before)
IRS:RecordOverviewStatistics({auctionsPosted=104,travelSpent=9000,largestSale=500000}, {auctionsPosted=100,travelSpent=7000,largestSale=400000})
IRS:RecordTransmogSpend(3000, IRS:CharacterKey())
IRS.expenseRuntime.pending = {category="travelSpent", untilTime=GetServerTime()+3}
IRS:RecordOverviewWalletExpense(2000)
local overview = IRS:GetOverviewTotals()
assert(overview.auctionsPosted == 4 and overview.travelSpent == 2000)
assert(overview.transmogSpent == 3000 and overview.largestSale == 0)
IRS.db.account.overview.days['2000-01-01'] = {travelSpent=99999}
assert(IRS:GetOverviewTotals().travelSpent == 2000)
IRS.characterRateStarted = GetServerTime() - 1800
IRS.characterRateNet = 50000
assert(IRS:GetCharacterProfitPerHour() == 100000)
print('PASS overview dates, external gross income, transfer correction, observed activity/spending, character hourly rate')
''')

lua.execute('''
local state = IRS.expenseRuntime
state.merchantOpen = true
IRS:RecordOverviewWalletExpense(12000)
state.repairUntil = GetServerTime() + 1
IRS:RecordOverviewWalletExpense(4000)
assert(state.repairUntil == nil)
InRepairMode = function() return true end
IRS:RecordOverviewWalletExpense(1000)
InRepairMode = function() return false end
state.merchantOpen = false
state.auctionOpen = true
IRS:RecordOverviewWalletExpense(9000)
state.auctionOpen = false
IRS:RecordOverviewWalletExpense(50000)
local totals = IRS:GetOverviewTotals()
assert(totals.vendorSpent == 12000)
assert(totals.repairsSpent == 5000)
assert(totals.auctionSpent == 9000)
IRS.db.account.overview.days['2000-01-01'].vendorSpent = 77777
assert(IRS:GetOverviewTotals().vendorSpent == 12000)
print('PASS vendor, repair-all, individual repair, auction spending and date exclusion')
''')

lua.execute('''
local before = IRS:GetOverviewTotals()
local npcCommission, playerCommission = 250000, 175000
-- Order payouts use the same wallet path as any uncategorized external income.
TEST_MONEY = TEST_MONEY + npcCommission
IRS:HandleMoneyChange()
TEST_MONEY = TEST_MONEY + playerCommission
IRS:HandleMoneyChange()
local after = IRS:GetOverviewTotals()
assert(after.totalAcquired - before.totalAcquired == npcCommission + playerCommission)
assert(after.otherIncome - before.otherIncome == npcCommission + playerCommission)
IRS:ScanCurrentCharacter()
assert(IRS:GetOverviewTotals().otherIncome == after.otherIncome)
-- Ordinary classified income remains outside Other income.
IRS:RecordEarnings(10000, {vendorGold=10000}, IRS:CharacterKey())
assert(IRS:GetOverviewTotals().otherIncome == after.otherIncome)
print('PASS uncategorized NPC/player order wallet payouts in Other income, no scan double counting, vendor separation')
''')

lua.execute('''
-- Reproduce the real failure: legacy approved-source totals exceed wallet gross.
local day = select(1, IRS:GetPeriodKeys())
local bucket = IRS.db.tracking.days[day]
bucket.sources.auctionGold = (bucket.income or 0) + 10000000
IRS:EnsureOtherIncome(bucket)
local before = IRS:GetOverviewTotals().otherIncome
TEST_MONEY = TEST_MONEY + 345678
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().otherIncome == before + 345678)
IRS:ScanCurrentCharacter()
assert(IRS:GetOverviewTotals().otherIncome == before + 345678)
-- Known sources can claim only recent wallet gains, never preexisting Other.
IRS.pendingIncomeSources = {}
local oldOther = bucket.otherIncome
IRS:RecordEarnings(0, {auctionGold=999999999}, IRS:CharacterKey())
assert(bucket.otherIncome == oldOther)
IRS:RecordEarnings(10000, {}, IRS:CharacterKey())
IRS:RecordEarnings(0, {questGold=10000}, IRS:CharacterKey())
assert(bucket.otherIncome == oldOther)
IRS:RecordEarnings(0, {questGold=10000}, IRS:CharacterKey())
assert(bucket.otherIncome == oldOther)
-- Spending does not undo gross external income; internal withdrawals do.
IRS:RecordEarnings(20000, {}, IRS:CharacterKey())
IRS:RecordEarnings(-5000, {}, IRS:CharacterKey())
assert(bucket.otherIncome == oldOther + 20000)
IRS:RecordEarnings(-20000, {}, IRS:CharacterKey(), true)
assert(bucket.otherIncome == oldOther)
IRS.pendingIncomeSources = {}
local originalNow = GetServerTime
TEST_NOW = originalNow()
GetServerTime = function() return TEST_NOW end
IRS:RecordEarnings(30000, {}, IRS:CharacterKey())
TEST_NOW = TEST_NOW + 10
IRS:RecordEarnings(0, {vendorGold=30000}, IRS:CharacterKey())
assert(bucket.otherIncome == oldOther + 30000)
GetServerTime = originalNow
print('PASS excess legacy statistics cannot hide Other income; recent source matching, duplicate scans, spending, transfer reversals, stale statistics')
''')

lua.execute('''
-- Persisted lifetime baselines must not classify income during a fresh login.
local record = IRS.db.characters[IRS:CharacterKey()]
local day = select(1, IRS:GetPeriodKeys())
local bucket = IRS.db.tracking.days[day]
record.earningsTracker.lastStats.auctionGold = 1000000
record.earningsTracker.lastStats.auctionsPosted = 10
record.earningsTracker.lastStats.travelSpent = 1000
IRS.sessionStatBaselines = setmetatable({}, {__mode='k'})
IRS.pendingIncomeSources = {}
local beforeAuction = bucket.sources.auctionGold or 0
local beforeOther = bucket.otherIncome
local beforeOverview = IRS:GetOverviewTotals()
IRS:RecordEarnings(50000, {}, IRS:CharacterKey())
IRS:UpdateEarningsLedger(record, {auctionGold=2000000, auctionsPosted=50, travelSpent=20000})
assert((bucket.sources.auctionGold or 0) == beforeAuction)
assert(bucket.otherIncome == beforeOther + 50000)
assert(record.earningsTracker.lastStats.auctionGold == 2000000)
local afterOverview = IRS:GetOverviewTotals()
assert(afterOverview.auctionsPosted == beforeOverview.auctionsPosted)
assert(afterOverview.travelSpent == beforeOverview.travelSpent)
IRS:UpdateEarningsLedger(record, {auctionGold=2000000, auctionsPosted=50, travelSpent=20000})
assert((bucket.sources.auctionGold or 0) == beforeAuction)
-- Auction statistic changes remain unverified even after the session baseline.
IRS.pendingIncomeSources = {}
IRS:RecordEarnings(25000, {}, IRS:CharacterKey())
IRS:UpdateEarningsLedger(record, {auctionGold=2025000, auctionsPosted=51, travelSpent=20000})
assert(bucket.sources.auctionGold == beforeAuction)
assert(bucket.otherIncome == beforeOther + 75000)
print('PASS fresh login ignores saved statistic jumps; auction statistic changes cannot classify wallet income')
''')

lua.execute('''
MAIL_TEST_HOOKS = {}
function TakeInboxMoney() end
function AutoLootMailItem() end
function hooksecurefunc(name, callback) MAIL_TEST_HOOKS[name] = callback end
function CreateFrame()
    return {
        RegisterEvent=function() end,
        SetScript=function(_, name, callback) if name == 'OnEvent' then MAIL_TEST_EVENT = callback end end,
    }
end
''')
load('Features/AuctionMail.lua')
lua.execute('''
MAILS = {}
function GetInboxNumItems() return #MAILS end
function GetInboxHeaderInfo(i)
    local m = MAILS[i]
    return nil,nil,'Auction House','Mail subject',m.money,0
end
function GetInboxInvoiceInfo(i)
    local m = MAILS[i]
    return m.invoice,'Test item','Buyer',m.price or m.money,0,0,0
end
C_Mail = {GetCraftingOrderMailInfo = function(i) return MAILS[i].crafting and {} or nil end}
IRS.pendingIncomeSources = {}
local baseline = IRS:GetOverviewTotals()
-- Seeing seller mail alone must not count as income.
MAILS = {{invoice='seller', money=50000, price=50000}}
IRS:RefreshAuctionMailInbox()
assert(IRS:GetOverviewTotals().auctionGold == baseline.auctionGold)
MAIL_TEST_HOOKS.TakeInboxMoney(1)
MAIL_TEST_HOOKS.AutoLootMailItem(1) -- duplicate requests must not double count
TEST_MONEY = TEST_MONEY + 50000
IRS:HandleMoneyChange()
IRS:FlushAuctionMailIncome()
assert(IRS:GetOverviewTotals().auctionGold == baseline.auctionGold)
-- Confirm removal after the wallet event (normal collection).
MAILS[1].money = 0
IRS:RefreshAuctionMailInbox()
local after = IRS:GetOverviewTotals()
assert(after.auctionGold == baseline.auctionGold + 50000)
assert(after.totalAcquired == baseline.totalAcquired + 50000)
assert(after.otherIncome == baseline.otherIncome)
IRS:RefreshAuctionMailInbox()
assert(IRS:GetOverviewTotals().auctionGold == after.auctionGold)
-- Confirm mail first, then receive the wallet event.
MAILS = {{invoice='seller', money=25000, price=25000}}
IRS:RefreshAuctionMailInbox()
IRS:BeginAuctionMailCollection(1)
MAILS[1].money = 0
IRS:RefreshAuctionMailInbox()
assert(IRS:GetOverviewTotals().auctionGold == after.auctionGold)
TEST_MONEY = TEST_MONEY + 25000
IRS:HandleMoneyChange()
IRS:FlushAuctionMailIncome()
assert(IRS:GetOverviewTotals().auctionGold == after.auctionGold + 25000)
-- Ordinary mail, crafting-order mail, buyer mail and pending sale invoices
-- must remain Other income, regardless of sender or statistic changes.
for _, m in ipairs({
    {money=10000,price=10000},
    {money=10000,price=10000,crafting=true},
    {invoice='buyer',money=10000,price=10000},
    {invoice='seller_temp_invoice',money=10000,price=10000},
}) do
    local before = IRS:GetOverviewTotals()
    MAILS = {m}
    IRS:RefreshAuctionMailInbox()
    IRS:BeginAuctionMailCollection(1)
    TEST_MONEY = TEST_MONEY + 10000
    IRS:HandleMoneyChange()
    m.money = 0
    IRS:RefreshAuctionMailInbox()
    IRS:RecordEarnings(0, {auctionGold=10000}, IRS:CharacterKey())
    local after = IRS:GetOverviewTotals()
    assert(after.auctionGold == before.auctionGold)
    assert(after.otherIncome == before.otherIncome + 10000)
end
-- Failure or removal without a collection request cannot authorize earnings.
local before = IRS:GetOverviewTotals()
MAILS = {{invoice='seller',money=40000,price=40000}}
IRS:RefreshAuctionMailInbox()
IRS:BeginAuctionMailCollection(1)
IRS:CancelAuctionMailCollection()
TEST_MONEY = TEST_MONEY + 40000
IRS:HandleMoneyChange()
MAILS[1].money = 0
IRS:RefreshAuctionMailInbox()
assert(IRS:GetOverviewTotals().auctionGold == before.auctionGold)
assert(IRS:GetOverviewTotals().otherIncome == before.otherIncome + 40000)
-- Already-pending unrelated income from before the request cannot be claimed.
IRS.pendingIncomeSources = {}
MAILS = {{invoice='seller',money=90000,price=90000}}
IRS:RefreshAuctionMailInbox()
IRS:RecordEarnings(90000, {}, IRS:CharacterKey())
local before = IRS:GetOverviewTotals().auctionGold
IRS:BeginAuctionMailCollection(1)
MAILS[1].money = 0
IRS:RefreshAuctionMailInbox()
assert(IRS:GetOverviewTotals().auctionGold == before)
print('PASS seller-mail proof, both event orders, duplicate refreshes, ordinary/crafting/buyer/pending mail exclusion, failed collections and unrelated prior income')
''')

lua.execute('''
-- Closing the mailbox clears API contents without proving collection.
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
MAIL_TEST_EVENT(nil, 'MAIL_CLOSED')
IRS.pendingIncomeSources = {}
MAILS = {{invoice='seller',money=60000,price=60000}}
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
local before = IRS:GetOverviewTotals().auctionGold
MAIL_TEST_HOOKS.TakeInboxMoney(1)
TEST_MONEY = TEST_MONEY + 60000
IRS:HandleMoneyChange()
MAILS = {}
MAIL_TEST_EVENT(nil, 'MAIL_CLOSED')
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
MAIL_TEST_EVENT(nil, 'PLAYER_MONEY')
assert(IRS:GetOverviewTotals().auctionGold == before)
-- Two identical auction mails can be collected independently in a batch.
IRS.pendingIncomeSources = {}
MAILS = {
    {invoice='seller',money=10000,price=10000},
    {invoice='seller',money=10000,price=10000},
}
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
local before = IRS:GetOverviewTotals().auctionGold
MAIL_TEST_HOOKS.TakeInboxMoney(1)
MAIL_TEST_HOOKS.AutoLootMailItem(2)
TEST_MONEY = TEST_MONEY + 20000
IRS:HandleMoneyChange()
MAILS[1].money, MAILS[2].money = 0, 0
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
assert(IRS:GetOverviewTotals().auctionGold == before + 20000)
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
assert(IRS:GetOverviewTotals().auctionGold == before + 20000)
print('PASS native money/auto-loot hooks, mailbox close exclusion, identical seller-mail batch collection')
''')

lua.execute('''
local originalCharacters = IRS.db.characters
local originalGuilds = IRS.db.guildBanks
local originalAccount = IRS.db.account
local originalOwned = IRS:EnsureInternalTransferDB().ownedGuildBanks
IRS.db.characters = {
    a={money=100000,trackingEnabled=true},
    b={money=200000,trackingEnabled=false},
    c={money=300000},
}
IRS.db.guildBanks = {personal={money=400000},other={money=900000}}
IRS:EnsureInternalTransferDB().ownedGuildBanks = {personal=true,other=false}
IRS.db.account = {warbandGoldSeen=true,warbandGold=500000}
assert(IRS:GetOverviewTotals().totalAccountNet == 1500000)
IRS.db.account.overview.startDate = '2000-01-01'
assert(IRS:GetOverviewTotals().totalAccountNet == 1500000)
IRS:EnsureInternalTransferDB().ownedGuildBanks.personal = false
assert(IRS:GetOverviewTotals().totalAccountNet == 1100000)
IRS.db.account.warbandGoldSeen = false
assert(IRS:GetOverviewTotals().totalAccountNet == 600000)
IRS.db.characters, IRS.db.guildBanks, IRS.db.account = originalCharacters, originalGuilds, originalAccount
IRS:EnsureInternalTransferDB().ownedGuildBanks = originalOwned
print('PASS Total Account Net includes all character wallets, known Warband gold and selected guild banks, independent of tracking dates')
''')

lua.execute('''
-- Reproduce secure post-hook ordering: wallet and inbox can both update first.
MAIL_TEST_EVENT(nil, 'MAIL_CLOSED')
IRS.pendingIncomeSources = {}
MAILS = {{invoice='seller',money=55000,price=60000}}
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
local before = IRS:GetOverviewTotals()
TEST_MONEY = TEST_MONEY + 55000
IRS:HandleMoneyChange()
MAILS[1].money = 0
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
MAIL_TEST_HOOKS.TakeInboxMoney(1)
local after = IRS:GetOverviewTotals()
assert(after.auctionGold == before.auctionGold + 55000)
assert(after.largestSale == math.max(before.largestSale, 60000))
assert(after.otherIncome == before.otherIncome)
MAIL_TEST_HOOKS.TakeInboxMoney(1)
assert(IRS:GetOverviewTotals().auctionGold == after.auctionGold)
MAIL_TEST_EVENT(nil, 'MAIL_CLOSED')
-- A crafting-mail API returning an empty table must not exclude seller invoices.
C_Mail.GetCraftingOrderMailInfo = function() return {} end
MAILS = {{invoice='seller',money=40000,price=45000}}
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
MAIL_TEST_HOOKS.TakeInboxMoney(1)
TEST_MONEY = TEST_MONEY + 40000
IRS:HandleMoneyChange()
MAILS[1].money = 0
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
assert(IRS:GetOverviewTotals().auctionGold == after.auctionGold + 40000)
assert(IRS:GetOverviewTotals().largestSale == after.largestSale)
print('PASS wallet/inbox updates before secure mail hook; invoice gross largest sale, lower subsequent sale, empty crafting mail info')

local testClock = 1000
GetTime = function() return testClock end
IRS.expenseRuntime = {merchantOpen=true}
IRS.transmogRuntime.isOpen = false
local before = IRS:GetOverviewTotals()
-- Repair-all hook arrives after wallet event was provisionally called vendor.
TEST_MONEY = TEST_MONEY - 4000
IRS:HandleMoneyChange()
IRS:ArmWalletExpense('repairsSpent', 4000)
local after = IRS:GetOverviewTotals()
assert(after.repairsSpent == before.repairsSpent + 4000)
assert(after.vendorSpent == before.vendorSpent)
-- Single-item repair before/after hooks, and ordinary vendor purchases.
testClock = testClock + 10
InRepairMode = function() return true end
TEST_MONEY = TEST_MONEY - 1000
IRS:HandleMoneyChange()
InRepairMode = function() return false end
assert(IRS:GetOverviewTotals().repairsSpent == before.repairsSpent + 5000)
testClock = testClock + 10
IRS:ArmWalletExpense('repairsSpent', 2500)
TEST_MONEY = TEST_MONEY - 2500
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().repairsSpent == before.repairsSpent + 7500)
IRS.expenseRuntime.merchantOpen = false
-- Postage counts only the fee, even when sending additional gold.
testClock = testClock + 10
IRS:ArmWalletExpense('postageSpent', 60)
TEST_MONEY = TEST_MONEY - 12060
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().postageSpent == before.postageSpent + 60)
-- Flight path action followed by wallet event.
testClock = testClock + 10
IRS:ArmWalletExpense('travelSpent', 700)
TEST_MONEY = TEST_MONEY - 700
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().travelSpent == before.travelSpent + 700)
-- Modern transmog action: charge once, ignore repeated old success events.
testClock = testClock + 10
IRS:ArmWalletExpense('transmogSpent')
TEST_MONEY = TEST_MONEY - 9000
IRS:HandleMoneyChange()
IRS:HandleTransmogSuccess()
IRS:HandleTransmogSuccess()
assert(IRS:GetOverviewTotals().transmogSpent == before.transmogSpent + 9000)
testClock = testClock + 10
IRS:ArmWalletExpense('transmogSpent') -- free/failed application: no wallet loss
assert(IRS:GetOverviewTotals().transmogSpent == before.transmogSpent + 9000)
-- Actual bid total may exceed the extra wallet charge when raising a bid.
testClock = testClock + 10
IRS.expenseRuntime.pending = nil
IRS.expenseRuntime.auctionOpen = true
IRS:ObserveAuctionBid(80000)
TEST_MONEY = TEST_MONEY - 10000
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().largestBid == math.max(before.largestBid,80000))
-- Commodity purchase/post-hook observes the actual total charged.
testClock = testClock + 10
TEST_MONEY = TEST_MONEY - 90000
IRS:HandleMoneyChange()
IRS:ObserveAuctionBid()
assert(IRS:GetOverviewTotals().largestBid == math.max(before.largestBid,90000))
GetTime = nil
print('PASS spending wallet/action event orders, repair reclassification, single repair, postage fee isolation, flight paths, modern transmog deduplication, bids and commodity purchases')
''')

lua.execute('''
MAIL_TEST_EVENT(nil, 'MAIL_CLOSED')
IRS.pendingIncomeSources = {}
local realInvoice = GetInboxInvoiceInfo
local invoiceReady = false
GetInboxInvoiceInfo = function(i) if invoiceReady then return realInvoice(i) end end
GetInboxText = function() invoiceReady = true; return '',nil,nil,nil,true end
MAILS = {{invoice='seller',money=15000,price=16000}}
MAIL_TEST_EVENT(nil, 'MAIL_SHOW')
local before = IRS:GetOverviewTotals().auctionGold
MAIL_TEST_HOOKS.TakeInboxMoney(1)
TEST_MONEY = TEST_MONEY + 15000
IRS:HandleMoneyChange()
MAILS[1].money = 0
MAIL_TEST_EVENT(nil, 'MAIL_INBOX_UPDATE')
assert(IRS:GetOverviewTotals().auctionGold == before + 15000)
GetInboxInvoiceInfo, GetInboxText = realInvoice, nil
print('PASS bulk-mail invoice data hydration before collection')
''')

lua.execute('''
-- No frame name, no legacy open event, and no application hook: native NPC
-- context must still classify a real charge.
local atTransmogNPC = true
C_Transmog = {IsAtTransmogNPC=function() return atTransmogNPC end}
TransmogFrame, WardrobeFrame = nil, nil
IRS.transmogRuntime.isOpen = false
IRS.expenseRuntime = {merchantOpen=false,auctionOpen=false}
local before = IRS:GetOverviewTotals().transmogSpent
TEST_MONEY = TEST_MONEY - 6100
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().transmogSpent == before + 6100)
-- Install the application API after IRS loaded, and verify idempotent hooks.
local hookCalls = 0
hooksecurefunc = function(api, name, callback)
    local original = api[name]
    api[name] = function(...)
        local result = original(...)
        hookCalls = hookCalls + 1
        callback(...)
        return result
    end
end
C_TransmogOutfitInfo = {CommitAndApplyAllPending=function() end}
IRS:InstallTransmogTrackingHooks()
IRS:InstallTransmogTrackingHooks()
local clock = 100
GetTime = function() return clock end
C_TransmogOutfitInfo.CommitAndApplyAllPending(false)
assert(hookCalls == 1)
atTransmogNPC = false
clock = clock + 10 -- charge after the NPC UI closes, outside the old 3s marker
TEST_MONEY = TEST_MONEY - 7200
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().transmogSpent == before + 13300)
IRS:HandleTransmogSuccess()
assert(IRS:GetOverviewTotals().transmogSpent == before + 13300)
-- A wardrobe collection browser away from the NPC is not spending context.
clock = clock + 10
IRS.expenseRuntime.pending = nil
WardrobeFrame = {IsShown=function() return true end}
assert(not IRS:IsAtTransmogService())
WardrobeFrame = nil
-- Preserve transmog context if transfer matching defers an unmatched charge.
local timers = {}
local originalAfter = C_Timer.After
C_Timer.After = function(_, callback) timers[#timers+1] = callback end
atTransmogNPC = true
IRS.warbandBankRuntime.isOpen = true
local beforeDeferred = IRS:GetOverviewTotals().transmogSpent
TEST_MONEY = TEST_MONEY - 8300
IRS:HandleMoneyChange()
assert(IRS:GetOverviewTotals().transmogSpent == beforeDeferred)
assert(#timers > 0)
atTransmogNPC = false
IRS.warbandBankRuntime.isOpen = false
clock = clock + 10
IRS:FinalizePendingInternalWallet(IRS.internalTransferRuntime.nextWalletId)
assert(IRS:GetOverviewTotals().transmogSpent == beforeDeferred + 8300, tostring(IRS:GetOverviewTotals().transmogSpent)..' expected '..tostring(beforeDeferred+8300)..' pending '..tostring(#IRS.internalTransferRuntime.pendingWallet))
IRS:FinalizePendingInternalWallet(IRS.internalTransferRuntime.nextWalletId)
assert(IRS:GetOverviewTotals().transmogSpent == beforeDeferred + 8300, tostring(IRS:GetOverviewTotals().transmogSpent)..' expected '..tostring(beforeDeferred+8300)..' pending '..tostring(#IRS.internalTransferRuntime.pendingWallet))
C_Timer.After, GetTime = originalAfter, nil
print('PASS native transmog NPC detection without UI flags, late API loading, idempotent hooks, delayed closed-UI payment and transfer-deferred expense context')
''')
