# Changelog

All notable changes to IRS — Income Records System will be documented in this file.

The changelog tracks user-facing changes between releases. Add changes to **Unreleased** while development is in progress, then move them under a version heading when a release is prepared.

## [Unreleased]

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
