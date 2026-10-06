# IRS Error Log

## Open / Intermittent

### Execution Time Limit on Login

**Status:** Investigating
**First observed:** October 6, 2026

#### Occurrence 1
- Character: Elasara - Earthen Ring
- Trigger: Login
- Error:
    'Script from "IncomeRecordsSystem" has exceeded its execution time limit.'
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
    'Script form "IncomeRecordsSystem" has exceeded its execution time limit.'
- Count: 61
- Stack: None
- Locals: None
- Reproduction:
    - Relog 1: No error

### Current Assessment

The same timeout has now occurred on two different characters during login, but neither occurrence reproduced immediately afterward.

This makes persistent character-specific SavedVariables corruption less likely and suggests an intermittent IRS startup/login performance issue.

The error provides no Lua stack or locals information.

If the error occurs again, particularly on another character, the next planned diagnostic step is to instrument the IRS startup/login initialization sequence with lightweight timing measurements so I can identify which initialization or UI-refresh operation is consuming excessive execution time.