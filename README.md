# IRS — Income Records System

**IRS — Income Records System** is an account-wide gold tracking and savings-planning addon for **World of Warcraft Retail**, built around a financial-records theme.

IRS tracks observed gold income and spending while you play, maintains account-wide and per-character history, and provides tools for planning Savings Projects and Reserve Funds.



## Features

- Tracks observed net gold movement: income adds to the ledger and spending subtracts from it.
- Maintains account-wide and per-character day, week, month, and total history.
- Displays Blizzard lifetime Wealth statistics separately from IRS-observed history.
- Supports **Savings Projects** with targets, deadlines, funding sources, allocation percentages, checkpoints, daily progress, and trajectory graphs.
- Supports **Reserve Funds** for balances you want to maintain rather than spend down.
- Filters transfers between owned storage locations so moving your own gold does not count as profit or loss.
- Includes a floating **Mini Dashboard** for earnings, Savings Projects, and Reserve Funds.
- Tracks locally observed **WoW Token prices** and configurable market alerts.
- Includes a **Profit Distribution Calculator** for splitting positive tracked profit across active Savings Projects and Reserve Funds.
- Provides reports, font controls, window resizing, and per-character tracking.
- IRS never moves gold automatically.



## Installation

1. Exit World of Warcraft.
2. Place the `IncomeRecordsSystem` folder in:

   `World of Warcraft/_retail_/Interface/AddOns/`

3. Start World of Warcraft.
4. Type `/irs` to open Income Records System.



## Slash Commands

| Command | Action |
| --- | --- |
| `/irs` | Toggle the main IRS window |
| `/irs projects` | Open Savings Projects |
| `/irs reserves` | Open Reserve Funds |
| `/irs tools` | Open Tools |
| `/irs chars` | Open Characters |
| `/irs reports` | Open Reports |
| `/irs settings` | Open Settings |
| `/irs help` | Open Help |
| `/irs mini` | Toggle the Mini Dashboard |
| `/irs scan` | Rescan the current character |
| `/irs status` | Print current tracked totals |
| `/irs debug` | Print current tracking diagnostics |
| `/irs reset` | Show reset instructions |
| `/irs reset confirm` | Clear IRS SavedVariables and tracked history |



## How IRS Tracks Gold

IRS stores money internally in copper.

Its net ledger is **forward-looking**. IRS can only record wallet changes that it observes while the addon is active. Historical gold activity from before IRS began tracking cannot be reconstructed.

Blizzard lifetime Wealth statistics are displayed as a separate dataset and are not backfilled into the IRS ledger.



## Savings Projects and Reserve Funds

Savings Projects and Reserve Funds are accounting and planning tools.

They do **not** reserve, lock, withdraw, deposit, or transfer gold in-game.

IRS can calculate how tracked profit should be distributed between your configured Projects and Reserves, but you remain in control of actually moving the gold.



## Transfers

IRS attempts to distinguish transfers between storage locations you own from genuine income or spending.

For example, moving gold between your character, Warband Bank, or known Guild Bank storage should not cause that gold to appear as newly earned income or as a loss simply because it changed locations.

Guild Bank balances can only be refreshed when World of Warcraft exposes the bank balance to the addon. Opening the relevant Guild Bank may therefore be required before IRS can synchronize it.



## WoW Token Tracking

IRS builds its Token price history from prices observed while the addon is running.

This is a locally observed history and is **not** intended to be a complete historical market feed.



## Project Structure

The addon is organized into several modules:

- `Core/` — core framework, database, tracking, and shared systems
- `Features/` — individual feature systems such as Transfers, Reserves, Tools, Token Market, and Project Checkpoints
- `UI/` — the main interface and supporting UI systems
- `Media/` — addon icons and other visual assets

`IncomeRecordsSystem.toc` remains in the addon root and defines the addon metadata and file load order.


## License

IRS — Income Records System is proprietary software. You may download, install, and modify the addon for your own personal use, but redistribution, republishing, and distribution of modified versions are not permitted without prior written permission.

See the [`LICENSE`](LICENSE) file for the full terms.


## Author

**Gilded Canary**