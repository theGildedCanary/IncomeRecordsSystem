# IRS — Income Records System

**IRS — Income Records System** is an account-wide gold tracking and savings-planning addon for **World of Warcraft Retail**, built around a financial-records theme.

IRS tracks observed gold income and spending while you play, maintains account-wide and per-character history, and provides tools for planning Savings Projects and Reserve Funds.

**Current version: 1.3.3**

## Download

For normal installation, download the latest `IncomeRecordsSystem-vX.Y.Z.zip` file from the [GitHub Releases](https://github.com/theGildedCanary/IncomeRecordsSystem/releases/latest) page.

The attached release ZIP is the packaged addon intended for installation. GitHub's automatically generated **Source code** archives contain repository infrastructure and are not the recommended download for normal users.

## Features

- Tracks observed net gold movement: income adds to the ledger and spending subtracts from it.
- Maintains account-wide and per-character day, week, month, and total history.
- Filters **Account Overview** income, auction activity, and spending by a saved tracking start date; displays Blizzard lifetime Wealth statistics separately in Reports.
- Offers optional active-character session profit per hour in the main and Mini Dashboards.
- Supports **Savings Projects** with targets, deadlines, funding sources, daily allocation splits, checkpoints, daily progress, and trajectory graphs. Changing a split affects future attributed source changes without reallocating gold already attributed to a project.
- Supports **Reserve Funds** for balances you want to maintain rather than spend down.
- Filters transfers between owned storage locations so moving your own gold does not count as profit or loss.
- Includes the last-known balance of Guild Banks marked internal in Transfers in account gold, including the Micro Report's Total Gold and Account Liquid Gold funding sources.
- Includes a floating **Mini Dashboard** for earnings, Savings Projects, and Reserve Funds.
- Includes a movable **Micro Report** showing one gold amount. Enable it under **Settings > Toggles**, choose a display below its description, or right-click the report to change modes and optionally show a label. Position, visibility, and display mode are saved account-wide. Period earnings use net totals; session and profit-per-hour totals restart on login or UI reload.
- Hover over the Micro Report for bank/account balances, token price, profit per hour, and Session/Daily/Weekly/Monthly Earned, Spent, and Net totals. Session totals reset on logout or UI reload. Earned/Spent always show recorded amounts and keep updating; an asterisk marks partial older history. Where gross counters are missing, IRS recovers available transactions from the retained audit log. Net history remains unchanged and can include older amounts absent from the partial breakdown.
- Tracks locally observed **WoW Token prices** and configurable market alerts.
- Includes a **Profit Distribution Calculator** for splitting positive tracked profit across active Savings Projects and Reserve Funds.
- Provides reports, font controls, window resizing, and per-character tracking.
- Choose **IRS Default** or **ElvUI Inspired** under **Settings > Fonts > Layout style**. The ElvUI-inspired style uses translucent dark panels, subtle borders, and neutral text with gold accents. It applies immediately across IRS and saves account-wide; ElvUI is not required.
- IRS never moves gold automatically.

## Installation

1. Exit World of Warcraft.
2. Extract the release ZIP.
3. Place the `IncomeRecordsSystem` folder in:

   `World of Warcraft/_retail_/Interface/AddOns/`

4. Start World of Warcraft.
5. Type `/irs` to open Income Records System.

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

## Account Overview

Enter a tracking start date beside the Account Overview heading as `YYYY-MM-DD`
and press Enter. The date is saved account-wide and includes that day's recorded
activity. Income, auction activity, and spending use available IRS records since
the selected date; Reports keeps Blizzard lifetime Wealth statistics separate.

**Total Account Net** adds the latest known gold on all saved characters,
including characters with income tracking disabled, plus the Warband Bank and
guild banks selected as internal in Transfers. It shows the current known account
balance independently of the tracking start date. Guild Bank and Warband Bank
sit beneath it, above a pale
divider and the individual income sources. Bank amounts show the latest known
balances, rather than activity since the date; access a tracked Guild Bank to
refresh its balance.

Every positive external wallet gain starts in **Other Income**. Recent matching
loot, quest, or vendor statistics move only received amounts into those categories.
**Auction Earnings** requires collected auction-sale mail with a seller invoice
and a matching external wallet gain. Blizzard auction statistics, ordinary mail,
crafting-order mail, and purchase/refund mail cannot classify Auction Earnings.
Earlier auction entries without saved mail evidence are excluded from this row;
the original recorded history remains saved. Unmatched gains, including trades and NPC patron/player crafting-order
commissions, stay in Other Income. Order gold counts when received in the wallet;
item and material rewards do not count as gold. Spending does not reduce gross
Other Income, and recognized internal-transfer corrections remove matching income.
Old source-statistic totals cannot hide new unmatched payouts.

Spending / Coverage lists Flight Paths, Postage, Transmog, Repairs, Auction
Expenses, and Vendor Purchases, followed by a divider and Tracking Coverage.
Repairs, Auction Expenses, and Vendor Purchases begin recording with version
1.3.3. IRS classifies confirmed wallet losses at merchants as repairs (repair
mode or repair-all) or vendor purchases, and at the auction house as auction
expenses (purchases and posting deposits). Guild-paid repairs are excluded.

Missing historical activity cannot be reconstructed. Largest Sale uses the sale
price on confirmed collected auction invoices; Largest Bid uses observed bids and
purchases with a corresponding wallet charge. Both follow the selected tracking
date and show `0g` until a value is recorded. Earlier missing Other
Income may not be recoverable from legacy records.

## Income Adjustments

Open **Tools > Adjustments** and enter a signed amount such as `+500g` or `-500g`.

- **Daily Income Adjustment** corrects Today, This Week, This Month, and Total
  Recorded for both the current character and account.
- **Overall Income Adjustment** corrects **Account Total Recorded only**,
  including account-total displays in Reports and the Micro Report. Character
  totals, daily/weekly/monthly earnings, and distributable profit stay unchanged.

Neither adjustment changes actual wallet or bank balances, Total Account Net,
or income-source categories.

## Character Profit Per Hour

Enable **Show character gold profit per hour** under **Settings > Toggles >
General Toggles**. The active character's session net earnings divided by hours
online appears as a centered gold amount beneath the four dashboard period totals
and beneath the character's Net Today in the Mini Dashboard. It includes spending,
excludes recognized internal transfers, updates every second while visible, and
resets on login or UI reload.

## Savings Projects and Reserve Funds

Savings Projects and Reserve Funds are accounting and planning tools.

They do **not** reserve, lock, withdraw, deposit, or transfer gold in-game.

IRS can calculate how tracked profit should be distributed between your configured Projects and Reserves, but you remain in control of actually moving the gold.

## Transfers

IRS attempts to distinguish transfers between storage locations you own from genuine income or spending.

Guilds are registered as you log in to each character, whether or not a Savings
Project exists. Open each guild bank to refresh its cached balance. In Transfers,
check a bank to mark it **Personal**: its last-known gold counts toward account
funds, and transfers to or from it stay internal. Shared banks remain excluded
from personal funds. Guild banks used by Savings Projects default to Personal;
you can uncheck them if they are shared.

For example, moving gold between your character, Warband Bank, or known Guild Bank storage should not cause that gold to appear as newly earned income or as a loss simply because it changed locations.

Guild Bank balances can only be refreshed when World of Warcraft exposes the bank balance to the addon. Opening the relevant Guild Bank may therefore be required before IRS can synchronize it.

## WoW Token Tracking

IRS builds its Token price history from prices observed while the addon is running.

This is a locally observed history and is **not** intended to be a complete historical market feed.

## Support and Development

- See [CHANGELOG.md](CHANGELOG.md) for release history and work planned for the next release.
- Use [GitHub Issues](https://github.com/theGildedCanary/IncomeRecordsSystem/issues/new/choose) to report bugs or request features.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing code changes.
- See [SECURITY.md](SECURITY.md) for security-sensitive reporting guidance.
- Maintainer release steps are documented in [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).

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

Repair-all, transmog, postage, and flight-path charges are matched to actual
wallet losses, including when the wallet event arrives before the action hook.
Transmog supports the current outfit application API and does not count preview
costs or repeated per-slot success notifications. Postage counts the mailing fee,
excluding any gold enclosed in the message. Flight Paths and Postage no longer
rely on delayed lifetime-statistic changes.
