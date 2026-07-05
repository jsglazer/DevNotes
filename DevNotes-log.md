# Exchange Log - 2026-07-04

## User Request
Deploy DevNotes to my iPhone. "DevNotes" isn't unique in the App Store, so deploy directly to the phone. Per `iOSDeploy.md`, build a `MakeTestFlight.sh`-style script/system to automate deploying apps to iOS.

## Claude Actions
1. Read `iOSDeploy.md`; found the `DevNotes-iOS` target (bundle `com.jsglazer.DevNotes`) already exists in `project.yml` alongside `DevNotes-iOS.entitlements`.
2. Surveyed the environment: iPhone 15 Pro Max "Gp15" paired; Apple **Development** signing identity present; **no** Apple Distribution cert and **no** App Store Connect API key on disk; Xcode 26.6.
3. Asked which mechanism to automate. User chose **direct device install** (matches the "name isn't unique" concern — never touches the store, no ASC record, no API key).
4. Regenerated `DevNotes.xcodeproj` via `xcodegen`; confirmed the `DevNotes-iOS` scheme builds and signs for the device (cross-platform code compiles — no AppKit-only TextKit breakage). Auto-provisioning created `iOS Team Provisioning Profile: com.jsglazer.DevNotes`.
5. Wrote `MakeiOSDeploy.sh`: auto-detects the single paired iPhone (bash-3.2-safe, no `mapfile`), `xcodegen generate`, `xcodebuild build` against **generic/platform=iOS** (so the build doesn't need the phone awake), then `xcrun devicectl device install` (+ optional launch). Flags: `--device <UDID>`, `--no-launch`, `--build-only`. Reusable — copy to another iOS app and change the PROJECT/SCHEME/BUNDLE_ID header.
6. Ran it end-to-end: **build + signing succeeded**; the install step could not complete because the phone dropped to `unavailable` (asleep/disconnected) — devicectl error 1011. Hardened the script to (a) build against the generic destination, (b) wait for a real connected state, and (c) abort loudly on install failure instead of falsely reporting success.
7. Left version at 1.0.5 — deploy-tooling addition, no app-behavior change (consistent with the prior build-infra precedent in this log). `.build/` and `build_log.txt` already gitignored.

**Pending (physical, user action):** connect + unlock the iPhone, then re-run `./MakeiOSDeploy.sh` — the build is already done; only the install/launch remains.

## Issue/Fix Summary Table
| # | Issue | Fix |
|---|---|---|
| 1 | No automated iOS deploy path (dev-deploy only covers Obsidian/Apps-DMG/Zotero) | Added `MakeiOSDeploy.sh` — build-sign-install to a paired device via `xcrun devicectl` |
| 2 | `mapfile` for device detection fails under macOS bash 3.2 | Rewrote detection with a portable `python3` JSON parse + newline count |
| 3 | Build required the phone to be awake (destination `platform=iOS,id=...` failed when device slept) | Build against `generic/platform=iOS`; only the install step needs the device |
| 4 | Install failure (error 1011) was masked by `\| grep ... \|\| true`, script falsely printed "Done" | Check `PIPESTATUS`, add a connect-readiness wait loop, abort with guidance on failure |

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
