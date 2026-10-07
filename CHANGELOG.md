# Changelog

All notable changes to IRS — Income Records System will be documented in this file.

The changelog tracks user-facing changes between releases. Add changes to **Unreleased** while development is in progress, then move them under a version heading when a release is prepared.

## [Unreleased]

### Added

### Changed

### Fixed

### Removed



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

[Unreleased]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/theGildedCanary/IncomeRecordsSystem/compare/v0.17.3...v1.0.0
[0.17.3]: https://github.com/theGildedCanary/IncomeRecordsSystem/releases/tag/v0.17.3
