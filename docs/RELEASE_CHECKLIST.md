# IRS Release Checklist

Use this checklist when preparing a new public release.

## Before Release

- [ ] Finish and test the intended changes in World of Warcraft Retail.
- [ ] Run `bash scripts/validate-addon.sh` with Lua 5.1 installed.
- [ ] Run `python scripts/smoke-test.py` with Python and `lupa` installed for offline ledger, project, reserve, allocation, and transfer checks.
- [ ] In game, verify Projects tab/action labels, switching between Management and Allocation, selecting/creating projects, and changing font sizes. Offline tests do not verify rendering or live Blizzard events.
- [ ] In game, verify Account Overview start-date entry, bank/source grouping and dividers, expense rows, and new external payouts appearing in Other Income. Check approved-source reclassification and internal bank-transfer exclusion.
- [ ] In game, toggle character profit per hour in General Toggles; verify both dashboards, font scaling, live updates, and session reset after reload.
- [ ] Update `## Version:` in `IncomeRecordsSystem.toc`.
- [ ] Move entries from **Unreleased** in `CHANGELOG.md` into a new version heading with the release date.
- [ ] Add a fresh empty **Unreleased** section at the top of the changelog.
- [ ] Confirm the version follows `X.Y.Z` format.
- [ ] Commit all release changes.
- [ ] Push to GitHub.
- [ ] Confirm the **Validate Addon** workflow passes on `main`.

## Publish Release

- [ ] Create a GitHub release using a tag matching the TOC version, prefixed with `v`.
      Example: TOC `0.18.0` → tag `v0.18.0`.
- [ ] Confirm the tag points to the committed release changes, including the matching TOC version; a version edited only in the local working copy is not part of the tag.
- [ ] Write release notes summarizing the user-facing changes.
- [ ] Publish the release.

## After Publishing

- [ ] Confirm the **Build Release ZIP** workflow succeeds.
- [ ] Confirm `IncomeRecordsSystem-vX.Y.Z.zip` is attached to the release.
- [ ] Download the generated ZIP once and verify it contains a top-level `IncomeRecordsSystem` folder.
- [ ] Confirm the packaged addon contains the TOC, Core, Features, UI, Media, README, LICENSE, and CHANGELOG.
- [ ] Confirm the release is marked as the latest release when appropriate.

The release workflow builds the addon ZIP automatically. Do not manually package the working Git repository.

## Recover a Version-Mismatch Failure

If **Verify TOC version matches release tag** fails, compare the release tag with
the TOC version printed in the job log. The workflow checks out the tagged commit,
so rerunning the same job does not include newer branch or local changes.

Commit and push the intended release changes first. If the failed release has not
been distributed, correct its tag to point to that release commit and republish
the release to trigger a fresh ZIP build. If the release has already been
distributed, prepare a new patch version and matching tag instead of replacing
its existing contents.
