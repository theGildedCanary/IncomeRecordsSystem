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
local overview = IRS:GetOverviewTotals()
assert(overview.auctionsPosted == 4 and overview.travelSpent == 2000)
assert(overview.transmogSpent == 3000 and overview.largestSale == 500000)
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
