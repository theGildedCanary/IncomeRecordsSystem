# IRS Release Checklist

Use this checklist when preparing a new public release.

## Before Release

- [ ] Finish and test the intended changes in World of Warcraft Retail.
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
- [ ] Write release notes summarizing the user-facing changes.
- [ ] Publish the release.

## After Publishing

- [ ] Confirm the **Build Release ZIP** workflow succeeds.
- [ ] Confirm `IncomeRecordsSystem-vX.Y.Z.zip` is attached to the release.
- [ ] Download the generated ZIP once and verify it contains a top-level `IncomeRecordsSystem` folder.
- [ ] Confirm the packaged addon contains the TOC, Core, Features, UI, Media, README, LICENSE, and CHANGELOG.
- [ ] Confirm the release is marked as the latest release when appropriate.

The release workflow builds the addon ZIP automatically. Do not manually package the working Git repository.
