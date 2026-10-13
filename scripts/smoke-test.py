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
