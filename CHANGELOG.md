# Changelog

All notable changes to IRS — Income Records System will be documented in this file.

The changelog tracks user-facing changes between releases. Add changes to **Unreleased** while development is in progress, then move them under a version heading when a release is prepared.

## [Unreleased]

## [1.3.5] - 2026-10-15

### Changed

- Transfers now registers each character's guild during character scans, whether or not a Savings Project exists. Log in to each character to discover their guild, then open its bank to cache the balance.
- Labeled guild bank ownership as **Personal** in Transfers, with Personal/Shared status shown for each bank. Personal banks count their last-known balance toward account funds, and transfers to or from them remain internal.

### Fixed

- Confirmed guild bank withdrawals to zero now clear the cached balance, preventing an emptied personal bank from inflating account funds. Unconfirmed zero readings continue to preserve the last-known balance.

## [1.3.4] - 2026-10-15

### Changed

- Replaced Account Overview's Total Gold Acquired row with **Total Account Net**, showing the latest known gold on all saved characters (including those with income tracking disabled), the Warband Bank, and personal guild banks marked internal in Transfers. This balance is independent of the tracking start date.

### Fixed

- Added native transmog-NPC detection, retried transmog hooks when Blizzard UI modules load, and preserved transmog spending context across delayed bank-transfer matching. Added transmog diagnostics to `/irs debug`.
- Fixed Repairs classification when the wallet event arrives before the repair action hook; single-item repairs and guild-paid repair exclusion remain supported.
- Updated Transmog spending for the current outfit-application API and confirmed wallet charges, avoiding dependence on legacy per-slot success events and duplicate counting.
- Matched Postage and Flight Paths to observed wallet charges instead of delayed lifetime statistics. Postage counts only the fee, excluding enclosed gold.
- Fixed Auction Earnings when wallet and inbox updates occur before the secure collection hook; preserved removed seller invoices long enough to match the confirmed payout, and stopped treating empty crafting-mail metadata as evidence against a seller invoice.
- Largest Sale now records confirmed auction-invoice sale prices, and Largest Bid records observed bids/purchases with wallet charges. Removed the asterisks and the requirement to exceed a Blizzard lifetime record.
- Auction Earnings now requires confirmed collection of seller-invoice auction mail and a matching external wallet gain, including manual and bulk collection. Ordinary/player mail, crafting-order payouts, purchase/refund mail, and Blizzard lifetime auction-statistic changes cannot qualify. Earlier auction entries without mail evidence are excluded from the Account Overview row while their original history stays saved.
- Establish fresh Blizzard source-statistic baselines on the first scan after login or UI reload, preventing changes accumulated since a previous session from being classified as newly observed auction income, auction activity, or spending. Existing recorded history remains available for the selected Account Overview date range.

### Maintenance

- Updated the release ZIP and addon validation workflows to `actions/checkout@v7`, which uses Node.js 24, to remove the deprecated Node.js 20 action warning.

## [1.3.3] - 2026-10-14

### Added

- Added a saved, account-wide tracking start date beside Account Overview. Enter `YYYY-MM-DD` and press Enter to filter recorded income, auction activity, and spending from that date onward.
- Added current tracked Guild Bank and last-known Warband Bank balances beneath Total Gold Acquired, with a pale divider separating these amounts from the individual income sources.
- Added Repairs, Auction Expenses, and Vendor Purchases beneath Transmog, with a divider above Tracking Coverage. These spending categories begin recording with this update and follow the selected tracking date.
- Added **Show character gold profit per hour** under Settings > Toggles > General Toggles. The active character's hourly net profit appears as a centered gold amount beneath Today/Week/Month/Total and beneath the character's Net Today in the Mini Dashboard. It updates while visible and resets on login or UI reload.

### Changed

- Account Overview now uses date-filtered IRS records instead of account-wide Blizzard lifetime totals; bank balances continue to show their latest known values.
- Renamed Travel to Flight Paths.
- Largest Sale and Largest Bid display `0g` when no value is recorded. Asterisks identify the limitation that IRS can only detect new Blizzard lifetime records observed during the selected period.
- Other Income includes unmatched external wallet gains, including trades and NPC patron/player crafting-order commissions, when the gold is received.
- Updated the README and in-addon User's Manual for the new dashboard controls and tracking behavior.

### Fixed

- Recorded Other Income directly from external wallet gains, then reclassified only recent matching amounts into loot, quest, vendor, or auction income. Excess or stale Blizzard source statistics can no longer hide new unmatched payouts by forcing the selected period's Other Income to zero.
- Kept recognized Warband Bank and internal Guild Bank transfers out of income; late transfer corrections remove the associated income.
- Adjusted dashboard and Mini Dashboard spacing for the additional rows, dividers, and optional hourly display.

### Tracking notes

- New auction activity and spending records cannot reconstruct activity from before tracking was available. Earlier missing Other Income may also be unrecoverable from legacy records.
- Auction Expenses includes confirmed wallet spending on purchases and posting deposits while the auction house is open. Guild-paid repairs do not reduce the character wallet and are excluded from Repairs.
- Offline checks cover Lua 5.1 syntax, date filtering, wallet income, source matching, transfer corrections, spending classification, and hourly profit calculations. In-game rendering and live event behavior still require verification.

## [1.3.2] - 2026-10-13

### Fixed

- Reanchored Projects button labels with natural text height and no wrapping to address blank labels; project tabs and action buttons now reserve width for the selected font.
- Positioned Projects content below the tab row as fonts change, and cleared stale selection warnings when loading a project.

### Added

- Added contributor acknowledgments for Lithevampy and Kraken Latte below Open IRS Dashboard in the addon options, and a Contributors page between Settings and Help in the IRS Dashboard.

## [1.3.1] - 2026-10-12

### Added

- Added an account-wide Layout style selector under Settings > Fonts, with IRS Default and ElvUI Inspired appearances. The dark translucent style applies immediately to IRS windows, panels, and popups without requiring ElvUI.

### Fixed

- Fixed text overlap when increasing font sizes, with improved spacing, wrapping, and control sizing across IRS panels and floating displays.
- Improved font formatting consistency for input fields and tooltips.
- Hotfix: Raised and uniformly aligned the Reset Main and Reset Mini buttons in Settings > Fonts, and adjusted spacing to prevent overlap with description text at larger font sizes.

## [1.3.0] - 2026-10-12

### Added

- Added a movable, account-wide Micro Report with selectable gold displays, optional labels, and saved settings.
- Added Micro Report hover details covering bank balances, WoW Token prices, profit per hour, and session, daily, weekly, and monthly earned, spent, and net figures.
- Added right-click display-mode controls for the Micro Report.


- Added a seven-day Transaction Log that records each observed wallet change, its IRS ledger effect, transfer classification, and diagnostic reason.
- Added `/irs transactions` and expanded `/irs debug` with transaction-audit summaries.
- Added a Tools control for applying signed corrections to the current character's and account-wide net earnings across Today, This Week, This Month, and Total Recorded.

### Changed

- Clickable controls now share a gold hover highlight and muted disabled state across IRS pages and feature panels.
- Mini Dashboard's Daily Gold Target now sums selected Projects' deadline-based daily contribution goals and no longer changes when allocation percentages change.
- Project allocation splits apply to daily source changes instead of reassigning each project's entire current source balance; changing a split affects attributed progress, not the Mini Dashboard's fixed daily target.
- Savings Projects now use separate Project Management and Allocation tabs.
- Profit Distribution moved from Tools into Savings Projects > Allocation.
- Each Savings Project now has its own linked Distribution % slider; changing one slider automatically redistributes the remaining percentage across the other Projects so Project Distribution always totals 100%.
- Project Distribution sliders now use whole-number percentages only; Split % can still display decimals after the Reserve carve-out.
- Added a manual Reserve % carve-out. Reserve % is removed from total profit first, and each Project's read-only Split % shows its effective share of the total after reserves.
- Project Management no longer exposes a per-project Allocation % field; the calculated Split % is used internally for shared-source Project accounting.

### Fixed

- Existing Profit Distribution percentages are migrated into the new linked Project Distribution plan so current project priorities are preserved when upgrading.
- Shared-source Project accounting now follows the calculated Split % rather than conflating Project Distribution with the post-Reserve effective allocation.
- Corrected Micro Report daily spending tracking.

## [1.1.0] - 2026-10-06

### Added

- Added a Blizzard AddOns Options entry with a button to open the IRS Dashboard.
- Added per-character Mini Dashboard open-state persistence and an optional account-wide auto-open setting.
- Added the active character's daily net to the Mini Dashboard.
- Added selectable Mini Dashboard net statistics for Character, Today, Week, Month, and Total.
- Added WoW Token visual alerts: a persistent Mini Dashboard banner while an alert zone is active, or a temporary splash alert when the Mini Dashboard is closed.
- Added Test Buy Alert and Test Sell Alert controls to preview WoW Token visual alerts from Settings.
- Added startup timing diagnostics for troubleshooting login performance.

### Changed

- Changed the Mini Dashboard Daily Gold Target to compare selected Projects' combined daily requirement against today's account-wide net income.
- Reworked the Projects page so Project Trajectory and Daily Gold Tracker are stacked vertically at full available width.
- Expanded Daily Gold Tracker columns to use the full-width layout more effectively.
- Simplified internal addon filenames while preserving the existing module structure.
- Updated the in-addon User's Manual for the expanded Mini Dashboard behavior.

### Fixed

- Fixed Blizzard Settings panel closing so it uses the managed UI panel flow correctly.
- Fixed General Toggles layout bounds when settings text or font sizes expand.
- Improved login character-scan scheduling and debouncing to avoid redundant delayed scans while preserving the initial login scan.
- Fixed Reserve History graph labels being clipped when Target or Warning Floor values reach larger gold amounts.
- Fixed WoW Token Mini Dashboard alert text overlap.



## [1.0.0] - 2026-10-05

### Changed

- Declared IRS — Income Records System stable for its first major public release.
- Added project documentation, issue reporting, validation, and automated release packaging infrastructure.



## [0.17.3] - 2026-10-05

### Added

- Initial public GitHub release of IRS — Income Records System.
- Account-wide and per-character gold tracking.
- Daily, weekly, monthly, and total IRS history.
- Savings Projects with targets, deadlines, funding sources, allocation percentages, checkpoints, and progress tracking.
- Reserve Funds for maintaining designated balances.
- Transfer filtering for owned gold storage locations.
- Floating Mini Dashboard.
- WoW Token price tracking and configurable alerts.
- Profit Distribution Calculator.
- Character, report, settings, and diagnostic tools.

[Unreleased]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.2.0...v1.3.0
[1.1.0]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v0.17.3...v1.0.0
[0.17.3]: https://github.com/theGildedCanary/IncomeRecordsSystem/releases/tag/v0.17.3
