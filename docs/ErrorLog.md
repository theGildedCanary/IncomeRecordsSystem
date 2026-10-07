# IRS Error Log

## Open / Intermittent

### Execution Time Limit on Login

**Status:** Investigating — startup timing instrumentation active  
**First observed:** October 6, 2026

#### Occurrence 1
- Character: Elasara - Earthen Ring
- Trigger: Login
- Error:
    `Script from "IncomeRecordsSystem" has exceeded its execution time limit.`
- Count: 61
- Stack: None
- Locals: None
- Reproduction:
    - Relog 1: No error
    - Relog 2: No error

#### Occurrence 2
- Character: Mythaelias - Earthen Ring
- Trigger: Login
- Error:
    `Script from "IncomeRecordsSystem" has exceeded its execution time limit.`
- Count: 61
- Stack: None
- Locals: None
- Reproduction:
    - Relog 1: No error

#### Occurrence 3
- Character: Not recorded
- Trigger: Login
- Error:
    `Script from "IncomeRecordsSystem" has exceeded its execution time limit.`
- Reproduction: Intermittent

### Current Assessment

The same execution-time-limit error has now occurred three times during login and has affected at least two different characters.

The first two occurrences did not reproduce on immediate relog attempts. This makes persistent character-specific SavedVariables corruption less likely and continues to suggest an intermittent startup/login performance problem.

The error has not provided a usable Lua stack or locals trace, so the specific operation responsible cannot currently be identified from the error itself.

Inspection of the current codebase shows that the login initialization path includes database initialization/migrations, a delayed full character scan, Warband Bank and project snapshot updates, and a master UI refresh. The master UI refresh in turn updates the Dashboard, Projects, Reserves, Tools, Characters, Reports, Settings, Mini Dashboard, and supporting layout/UI systems. Reserves and Tools also perform their own startup UI initialization.

### Diagnostic Result — October 6, 2026

The first captured timing report after instrumentation showed **281 full character scans during a single startup window**.

The same report showed:

- `Character scan`: 281 calls, 6312.67 ms total
- `Master UI refresh`: 281 calls, 6024.18 ms total
- `UI: Page scroll refresh`: 281 calls, 3548.65 ms total

No individual scan or page refresh was unusually slow by itself. The problem was the number of repeated scans.

Inspection of `QueueScan()` found that its debounce condition used:

`generation <= scanGeneration`

That condition allows every older queued timer to run because every previous generation is less than or equal to the newest generation. Login event bursts can therefore queue many delayed full scans instead of collapsing them into one.

The debounce condition has been corrected to:

`generation == scanGeneration`

This means only the newest queued scan is allowed to execute. The timing instrumentation remains active temporarily so the fix can be verified on subsequent logins before the diagnostics are removed.

### Follow-up Diagnostic Result — Mythaelias

A subsequent login on Mythaelias still produced **558 full character scans** despite the corrected `QueueScan()` comparison.

That report showed:

- `Character scan`: 558 calls, 19887.41 ms total
- `Master UI refresh`: 558 calls, 19299.13 ms total
- `UI: Page scroll refresh`: 558 calls, 13219.32 ms total
- startup timing window still active because the UI event loop was saturated by queued scans

Inspection of `QueueMoneyScans()` found a second independent cause. Its one-second follow-up used a direct `C_Timer.After()` callback that called `IRS:ScanCurrentCharacter()` without any debounce or generation check.

Every money/stat-related event in a login burst could therefore create its own delayed full scan even after `QueueScan()` itself had been corrected.

`QueueMoneyScans()` now has its own generation counter. The normal early scan still uses `QueueScan(0.20)`, and the delayed one-second follow-up now runs only when it belongs to the newest money-event burst.

This preserves the intended two-read behavior while preventing hundreds of stale delayed scans from executing.

### Follow-up Diagnostic Result — Mythaelias After Delayed-Scan Debounce

After the delayed money-scan debounce was added, Mythaelias no longer produced a scan storm. However, the next startup timing report contained **no completed character scan at all** during the four-second diagnostic window.

The reason is that the initial login scan still used the same generation-based `QueueScan()` path as ordinary event-driven scans. A sufficiently long burst of startup events could continuously advance the generation counter and invalidate the login scan before it ran.

The login scan is now separated from the normal debounce path:

- `PLAYER_LOGIN` schedules one guaranteed scan after one second;
- ordinary queued scans are temporarily suppressed while that login scan is pending;
- after the guaranteed login scan completes, normal event-driven debounce behavior resumes.

This prevents startup event bursts from either multiplying the login scan or starving it entirely.

### Current Diagnostic Step

Temporary lightweight startup timing instrumentation is now active.

The diagnostic uses WoW's profiling timer and runtime-only state. Timing information is **not** written to `IncomeRecordsSystemDB` or any other SavedVariables data.

The instrumentation measures major startup/login stages independently, including:

- database initialization and migrations;
- character identity/wallet scanning;
- Blizzard statistics scanning;
- Warband Bank scanning;
- account totals;
- project snapshot updates;
- main UI/module initialization;
- Dashboard refresh;
- Projects refresh;
- Reserves initialization and refresh;
- Tools initialization and refresh;
- Characters refresh;
- Reports refresh;
- Settings initialization and refresh;
- Mini Dashboard initialization and refresh;
- Token Market startup work;
- page layout/scroll refresh work.

A temporary watchdog also reports a startup stage if execution is aborted before that stage can record its completion time. This is intended to preserve a useful clue if the execution-time-limit error interrupts the measured function itself.

Use `/irs timing` (or `/irs startup`) after login to print the captured startup timing report.

No suspected function has been optimized or behaviorally changed. The current goal is evidence collection only.

## Fixed

### Profit Distributor C Stack Overflow When Marking Allocation

**Status:** Fixed  
**Observed:** October 7, 2026  
**Trigger:** Tools → Profit Distribution → mark the current allocation checkpoint as allocated

The error reported:

`Interface/AddOns/IncomeRecordsSystem/Core/Core.lua:2361: C stack overflow`

The repeating stack path showed `Features/Tools.lua` repeatedly entering the checkpoint appearance refresh through `Disable()`. `Core.lua:GetSortedProjects()` was where the stack finally overflowed, but it was not the source of the recursion.

### Cause

After an allocation checkpoint was marked, available profit became 0 and `RefreshToolsPage()` refreshed the checkpoint button. `RefreshCheckpointAppearance()` called `checkpoint:Disable()` while the button was still being interacted with. Disabling the hovered button fired its `OnLeave` handler, which called `RefreshCheckpointAppearance()` again and attempted another `Disable()`, recursively repeating until the C stack overflowed.

### Fix

The checkpoint appearance refresh now:

- uses a local re-entry guard so nested `OnEnter`/`OnLeave` appearance refreshes are ignored while the current refresh is still running;
- calls `Enable()` only when the button is currently disabled;
- calls `Disable()` only when the button is currently enabled;
- preserves the existing enabled, disabled, hover, and allocation behavior.

No changes were made to `GetSortedProjects()` or the Profit Distributor allocation calculations.

