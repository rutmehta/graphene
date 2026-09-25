# WP5 implementation and verification

## Result

Built with `swift build`, passed `swift test`: 54 tests, zero failures, zero warnings in the final build/test logs. `./scripts/build-app.sh` succeeded and produced `.build/Graphene.app`. No git commits were made. Existing unrelated work was retained. Little Graphene was not changed or exercised.

Implemented site controls, persistent host zoom, camera/microphone/motion policy, certificate metadata, compiled network blocking, CSS/JS Boosts and Zap, native Reader, profile assignment and persistent cookie stores, Safari/Chrome/Arc import, web-archive export, browser escape hatch, approximate Find counts, renderer failure state, and confirmation for external app links. README lists the public API boundaries.

## Runtime evidence

Only owned app instances launched with `GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile` and `GRAPHENE_DEBUG=1` were operated. Existing development data was retained. No production profile was launched by this work.

- Wikipedia loaded over HTTPS. Certificate summary returned subject `*.wikipedia.org`, issuer Let's Encrypt YE2, validity August 5–November 3, 2026.
- Registered Zoom In changed zoom to 1.1. The per-host override disabled blocking; the latest generated list later compiled and enabled successfully, with an empty blocker error.
- Boost CSS changed `.mw-page-container` to `rgb(246, 240, 226)` according to computed style.
- Zap installed its picker. A scripted click through the actual picker on `#firstHeading` persisted a selector and returned computed display `none`.
- Restart restored zoom 1.1, the blocking override, Boost CSS and the hidden heading.
- Reader opened on Wikipedia. A screenshot revealed excessive blank lines; a failing WebKit extraction test reproduced it, whitespace normalization fixed it, and a new screenshot shows readable article paragraphs.
- Default-profile example.com returned `graphene_wp5=default`. A newly assigned profile initially returned no cookie, then `graphene_wp5=isolated`. Switching back returned `graphene_wp5=default`. No login was performed.
- The actual Arc sidebar file imported 11 bookmarks. Repeating the same application path imported zero and skipped all 11 duplicates. Source files were not modified. Session data was read back to verify persisted pins/profiles.
- Cmd+Q delivered with System Events successfully terminated the final smoke-test PID 15870. Readback confirmed it no longer existed. The requested `pkill -f graphene-dev-profile` cleanup found no remaining match. Pre-existing Graphene PIDs 14394 and 66950 were left untouched.

`runtime-results.json` contains the raw scalar results, cookie checks, import summaries, and cleanup readback. Test cookies are synthetic. Personal imported URLs/titles are not included in this report.

## Input and visual limits

Computer-use captured the real app and site controls. Its first click returned `approval prompt timed out`; it was not retried. The requested System Events fallback could not locate the nested button by a direct window path, and a coordinate click timed out. Further failed input attempts were stopped. Model/command-driven verification used the existing local debug driver, extended for this work; screenshots used computer-use and `screencapture -x`.

One later computer-use capture hit its 20-second AX-tree timeout on Wikipedia; screencapture continued to work. Native click/type/scroll interaction, dropdown selection, Save Boost button, import preview/confirmation controls, profile deletion, camera/microphone prompts, print and save dialogs remain hands-on verification items. The application paths and persisted results above are verified, but are not claims that those blocked mouse actions succeeded.

Arc and Dia reference screenshots were loaded with the vision tool. Graphene retains restrained light tinted chrome, hairlines, native controls and rounded sheets. Reader whitespace was the visual defect found and fixed. No new competitor popover screenshots were available, so no pixel-perfect parity is claimed.

Final blank-tab restore and routed-tab profile-isolation regressions were caught/fixed after desktop smoke testing. They passed dedicated regression tests and the final full suite; the final rebundled binary was not relaunched after those last fixes.

## Screenshots

- `site-controls-blocking-on.png`
- `site-controls-zoom110-blocking-off.png`
- `wikipedia.png`
- `boost-editor-style.png`
- `boost-recolored-zapped-heading.png`
- `reader-wikipedia.png`
- `profiles-assignment.png`
- `import-settings.png`

## Deliberate boundaries / incomplete acceptance items

- No system Passwords AutoFill integration or password import. No public Safari-equivalent WKWebView configuration toggle was used or fabricated.
- Location and notifications are documented as WebKit/macOS-managed rather than inert permission choices. Camera/microphone Allow still requires OS consent; policy changes do not terminate an existing stream.
- Invalid certificates fail closed. No “visit anyway” is provided, because a reliable public HSTS-policy check is unavailable. This requested exception mechanism is not implemented.
- Find counts/index are approximate main-document text bookkeeping; WebKit reports matchFound, not an authoritative match index. Cross-frame and hidden-text differences can affect counts.
- External-app remembered decisions are scoped to the current tab lifetime. Non-click script-driven external navigation is canceled rather than silently opening another app.
- Profiles isolate website storage, not the shared knowledge library. macOS manages persistent WebKit data outside the Graphene JSON directory, with development UUID namespacing.
- Blocking is a 2,000-rule third-party EasyList adserver subset, not full EasyList/EasyPrivacy. It is 258,094 bytes. Source/license notices and GPL text are bundled. No request counter exists.
- Arc import uses the observed alternating-array sidebar format, maps pins/favorites and colors, and skips Today tabs. Safari/Chrome live imports and Full Disk Access interaction were not exercised against user history. Chrome's automatic source is its Default profile.
- Reader uses SwiftUI styling, so no unused `reader.css` stub was added.

## Files touched by this work

- `Package.swift`, `README.md`
- `Sources/Graphene/App/{AppState,DebugDriver,GrapheneApp}.swift`
- `Sources/Graphene/Model/{BrowserLibrary,Commands,Profile,Settings,Space,Tab}.swift`
- `Sources/Graphene/Web/{WKWebEngine,SiteSettings,ContentBlocker,Boosts,ReaderMode,FindCounter}.swift`
- `Sources/Graphene/Store/{Importer,ImportApplication}.swift`
- `Sources/Graphene/UI/{SiteControlsPopover,BoostEditor,ProfileSettings,ImportSettings,SettingsView,RootView,Sidebar,TopTabBar,OnboardingView}.swift`
- `Sources/Graphene/Resources/{reader.js,zap.js,blocklist.json,blocklist-NOTICE.txt,blocklist-COPYING.txt}`
- `scripts/{build-app.sh,make-blocklist.py}`
- `Tests/GrapheneTests/SiteTests.swift`, `Tests/GrapheneTests/Fixtures/{arc-sidebar,chrome-bookmarks}.json`
- This verification report, screenshots and runtime result file under `docs/parity/shots/wp5/`.
