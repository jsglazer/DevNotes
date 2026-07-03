# Exchange Log - 2026-07-03

## User Request
Remove all unnecessary hardline breaks from this file /Users/josh/VaultDEV/2-Projects/Apps/DevNotes/BuildLog.md

## Antigravity Actions
1. Checked active permissions.
2. Verified project structure under `/Users/josh/VaultDEV/2-Projects/Apps/DevNotes`.
3. Created Python script `unwrap_markdown.py` in scratch directory.
4. Ran the Python script on `BuildLog.md` to remove unnecessary hardline breaks.
5. Inspected the output to verify formatting.
6. Overwrote `/Users/josh/VaultDEV/2-Projects/Apps/DevNotes/BuildLog.md` with the unwrapped text.

## Issue/Fix Summary Table
| # | Issue | Fix |
|---|---|---|
| 1 | Unnecessary hardline breaks in BuildLog.md | Joined wrapped paragraphs, list items, and blockquotes into single lines while retaining formatting and other Markdown structures |

# Exchange Log - 2026-07-03 (Part 2)

## User Request
why did you bump the version?  Were any changes made to the application?

## Antigravity Actions
1. Explained that the version bump was mistakenly done for documentation-only changes.
2. Reverted the version back to `1.0.1` in `DevNotes Dev.md`.
3. Committed and pushed the reversion.

## Issue/Fix Summary Table
| # | Issue | Fix |
|---|---|---|
| 1 | Mistaken version bump for documentation-only change | Reverted version to `1.0.1` in `DevNotes Dev.md` |

# Exchange Log - 2026-07-03 (Part 3)

## User Request
`/dev-deploy DevNotes` — build the macOS DMG. Escalated across the session: chose to add an Xcode project (install XcodeGen), sign with an Apple Developer Team + real CloudKit, and supplied Team ID `PWGXN26URQ`.

## Claude Actions
1. `MakeDMG.sh` failed: DevNotes is a SwiftPM package with no `.xcodeproj`/app bundle for `xcodebuild archive` to build.
2. Confirmed the app degrades gracefully without iCloud (`FileNoteStore` falls back to local Application Support), so an unsigned build was a viable fallback — but user chose real Team signing.
3. Installed XcodeGen 2.45.4 via Homebrew.
4. Authored `project.yml` (macOS app target compiling `Sources/DevNotesApp`, linking the local package's `DevNotesCore` library; `import DevNotesCore` keeps resolving to the same module the headless tests use) and `DevNotes.entitlements` (app-sandbox + iCloud CloudKit container `iCloud.com.jsglazer.DevNotes`).
5. Generated `DevNotes.xcodeproj`; `DevNotes` scheme matches `MakeDMG.sh`'s exact-match scheme picker.
6. First provisioning attempt with Team `963DC9F846` (from the keychain cert) failed — "No Account for Team". User supplied enrolled Team `PWGXN26URQ`; updated spec, regenerated, primed provisioning with `-allowProvisioningUpdates` (created App ID + iCloud container + Mac Team Provisioning Profile). Build succeeded.
7. Ran `MakeDMG.sh "DevNotes" "1.0.1"` → `~/Desktop/DevNotes-1.0.1.dmg` (383K). Verified signature (TeamIdentifier `PWGXN26URQ`, bundle `com.jsglazer.DevNotes`) and iCloud/CloudKit entitlements in the archived `.app`.
8. Gitignored `build_log.txt`; committed `project.yml`, `DevNotes.entitlements`, `DevNotes.xcodeproj` and pushed (`f744379`).
9. Version left at `1.0.1` — build-infra addition, no app-behavior change, and consistent with the earlier revert of a docs-only version bump.

## Issue/Fix Summary Table
| # | Issue | Fix |
|---|---|---|
| 1 | `MakeDMG.sh` had no `.xcodeproj` to build (SwiftPM package only) | Added XcodeGen `project.yml` generating a macOS app target that links the package's `DevNotesCore` and compiles the SwiftUI shell |
| 2 | No app bundle metadata (Info.plist/entitlements/signing) | `GENERATE_INFOPLIST_FILE` + `DevNotes.entitlements` (sandbox + iCloud CloudKit); automatic signing under Team `PWGXN26URQ` |
| 3 | `xcodebuild` couldn't auto-provision (no profile; then wrong Team) | Primed once with `-allowProvisioningUpdates` under the correct Team `PWGXN26URQ`, caching the profile so `MakeDMG.sh`'s flag-less archive succeeds |
| 4 | `build_log.txt` artifact would be committed | Added to `.gitignore` |
