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
