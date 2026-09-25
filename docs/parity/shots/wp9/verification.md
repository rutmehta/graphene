# WP9 — partial end-to-end and release-readiness pass

Date: September 11, 2026, EDT. Swift 6.2.4, Swift 5 language mode, macOS 26.1. **Not release sign-off.** Work remained synchronous; no agents, cron/kanban tasks, commits, or changes under `docs/parity/ref/`. Only the explicitly requested GUI app launches ran in the background.

## Bugs fixed

`Sources/Graphene/Mail/LoopbackServer.swift`:

1. **Double-resume crash:** the old callback/timeout closures both resumed directly when their weak server reference was nil. The regression baseline actually emitted `SWIFT TASK CONTINUATION MISUSE: waitForCode(timeout:) tried to resume its continuation more than once`. Completion now atomically takes and clears one stored continuation under a lock; late completions cannot resume it again.
2. **Successful callback leaked its listening socket:** the baseline second connection connected but timed out instead of being refused. Completion now shuts down/closes the listener, including successful completion. The new callback test receives the exact fixture code and then proves a new connection is refused.
3. **Repeated start leaked/replaced socket state:** a second `start()` previously succeeded. A listener is now explicitly one-shot and rejects repeated starts. Repeat stop/wait completes safely.
4. **Unsynchronized socket access / release concurrency warnings:** accept and timeout accessed mutable `fd` from separate queues without synchronization. Mutable state is now lock-protected with a documented `@unchecked Sendable` contract. The reader owns a duplicated listener descriptor; completion shuts down pending socket I/O without closing/reusing the reader's client descriptor. The client disables SIGPIPE so a disconnected caller cannot terminate the app during its response. Both release compiler warning locations are gone.

No live Gmail account or credentials were used. Local socket fixtures are test inputs, not fabricated OAuth-service responses. The callback's broader OAuth/authentication behavior is not certified by these tests.

`Tests/GrapheneTests/LoopbackServerTests.swift` adds five tests: successful callback/closed listener, repeated start rejection, timeout, successful callback followed by deallocation/late timeout, and repeated stop/wait. `loopback-red.log` contains the failing baseline; `loopback-green.log` contains the initial three passing tests, and `tests-final.log` contains all five plus the full suite.

## Build and packaging

- `swift build`: pass. Final debug build also runs inside the bundle script.
- `swift test`: 87 XCTest cases executed, one skipped, zero failures. Skip: opt-in `AnswerQualityTests.testLiveAnswers`. A separate actual UI model invocation below failed quality; a green ordinary test suite does not erase it.
- `swift build -c release`: pass, zero compiler warnings in `release-final.log`.
- `./scripts/build-app.sh`: pass, zero compiler warnings in `bundle-final.log`.
- `codesign --verify --deep --strict .build/Graphene.app`: exit 0, `signature.log`.
- Bundle Info.plist readback: `CFBundleShortVersionString=0.3.0`, `CFBundleVersion=3`.
- `git diff --check`: pass.

The bundle script still packages **debug**, with ad-hoc signing. The optimized SwiftPM build is separate. No Developer ID signing, notarization, installation, update feed or distribution was performed.

## Isolated profiles and desktop targeting

- `/tmp/graphene-dev-profile/wp9`: fresh first launch, PID 60482. Main window 102915 and onboarding sheet 102916 existed in CoreGraphics enumeration, but exact computer-use captures returned 0×0.
- `/tmp/graphene-dev-profile/wp9-stress`: copied from that isolated root, never from the real profile. Seed process 71092; final rebuilt relaunch 76158, window 103039. Debug driver was used **only to seed** space/tab state. Final relaunch did not enable the driver.
- `/tmp/graphene-dev-profile/wp9-ui`: second fresh empty root, PID 81225, main window 103052. Real keyboard and attempted pointer interaction, no debug driver.
- `/tmp/graphene-dev-profile/wp9-tests`: isolated environment for test processes. Individual tests also use their own temporary directories.

No real browser profile, account data, password exports or API keys were read. A `focus_app(app=com.graphene.browser, pid=76158)` request returned **pre-existing PID 66950/window 100544**, not the owned PID. The tool's PID field is only guaranteed for capture. This raised another window; it is not a claim that foreground focus was untouched. No subsequent keys or clicks were sent to that instance: the next call explicitly captured owned PID 76158/window 103039. Subsequent input was routed from exact owned captures.

Initial 0×0 captures and the seed process's black capture are preserved as failures, not proof of UI success. Later exact captures resolved the main window and AX tree. Fresh SOM capture → element click still returned `snapshot_id_required`; the wrapper exposes no token argument. Existing onboarding and Vault Save controls already have identifiers, labels and button traits. Two foreground coordinate attempts at Save did not dismiss the sheet or create a verified save; source inspection confirmed `note.save` and its handler rather than adding redundant accessibility modifiers. Return in the note editor inserted a newline; this is not counted as Save. Escape cancelled the sheet.

No osascript, System Events, screencapture or debug-driver replacement of feature interaction was used.

## Part A — actual coverage and remaining work

| Requested area | Actual WP9 result | Still incomplete |
| --- | --- | --- |
| 1. Onboarding | Fresh three-step sheet; Return advanced layout, color and finish; settings.json readback `completed=true`. Three screenshots. | Non-default layout/color selection, independent completed-onboarding relaunch check. The initial pointer attempt was rejected by snapshot-token transport. |
| 2. Browsing | Cmd+L/type/Return loaded example.org. Cmd+F `domain` showed 1 of 2; Cmd+G showed 2 of 2. Escape dismissed Find. Cmd+P opened a real Print window with page preview; Escape cancelled it, no print job. | Address-pill click, search, back/forward/reload, zoom, Save Page As and a real raw.githubusercontent.com download/popover workflow were not completed. |
| 3. Sidebar | Stress seed/restoration displayed four spaces and populated Today tabs. This is not interactive CRUD verification. | Create/rename/delete through UI, custom theme, Favorites add/remove/reorder, pin/unpin/base reset, folder create/rename/drag, Tidy/Clear, archive restore/delete, Ctrl+Tab, Cmd+1–9, Command-click batch close, tab/favorite/folder menus, resize/collapse/edge peek and dark-mode retest. |
| 4. Windows/tabs | Final stress process restored its visible selected page without extra visits. | Split/close pane, pinned Peek, private-window no-write UI, discard/restore, YouTube Now playing and PiP attempt. Existing unit tests do not substitute for these interactions. |
| 5. Command bar | Cmd+L URL submission exercised. | Action/tab/history/note/thread sections, suggestions, autocomplete, Cmd+Enter/Shift+Enter, Ask row/@ picker, Top tabs expanding bar and switch-back were not swept. |
| 6. Site | No fresh interactive site-controls certification. | Zoom/blocking/permissions, Boost apply, Zap, Reader, cookie isolation, Arc/Chrome/Safari Import UI, certificate popover. No personal import data was accessed. |
| 7. Settings | Source inventory confirms 13 pages; onboarding completion read back. | Every page's controls and relaunch persistence, remapped menu accelerator, real routed link and default-browser prompt. No default browser was changed. |
| 8. Native surfaces | Cmd+Option+2 opened populated Threads list/detail, one real visit and source excerpt. Cmd+D opened Save to Vault with the Find-selected word `domain`; save attempts were unconfirmed and sheet cancelled. Cmd+Option+3 showed Mail disconnected/read-only state. Cmd+Option+5 opened empty Board. | Threads Map/summarize/export; Vault grid/detail/edit/delete/Ask my notes; Board add/move/resize/delete/export. Save-to-Vault is not marked passed merely because its sheet opened. |
| 9. AI | Cmd+K opened Chat; typing `/summarize` and Return sent the actual skill prompt with Example Domain source. It returned **“I cannot fulfill that request.”** Screenshot and isolated chats.json agree. | This benign-page refusal is an unresolved model-quality failure. Two-tab mentions, Stop, Regenerate, history, memory toggle, remote-consent sheet, textarea/contenteditable Replace and Shift-hover preview were not completed. No remote key was entered. |
| 10. Toasts | No fresh verified toast action. | Close → Undo and Save → View remain unverified in this pass. Existing implementation/model tests are retained. |

This is a bounded partial sweep after repeated desktop targeting failures, not exhaustive acceptance. Later keyboard interaction did work, so the untouched items above must not all be called individually “tool-blocked.” They were not completed in this session. There are no deferred jobs that will finish them later.

## Part B — robustness measurements

The isolated root was copied, then existing driver commands seeded public URLs `https://example.com/?wp9=01` through `?wp9=60`. Automatic empty-space tabs initially made 64 entries; those four blanks were removed through driver selection/close commands. Readback verified **exactly 60 tabs, four spaces, 15 URL tabs per space**, and 60 real recorded visits before relaunch.

`startup.json` records final bundle PID 76158 and **1.821098290849477 seconds** from process launch until `WindowAccessor` wrote a new `window.txt`. That measures view/window registration, **not** first paint, network completion, menu response or interactive readiness. `stress-restored.png` subsequently shows the restored sidebar and loaded page. Under-three-second interactive startup remains unproven.

`stress-idle.json` records the sample after **338.9531841278076 seconds** without feature interaction in that process:

    PID    STAT  ELAPSED  RSS (KiB)  %CPU
    76158  Ss    05:39    137152     25.7

RSS is about 133.94 MiB for the main process only; WebKit helper-process memory is not included. The nontrivial CPU sample is reported, not dismissed or represented as a performance pass. Its cause was not isolated here.

Before/after visit arrays were identical, not merely equal counts. Final readback after quit again showed 60 tabs, four spaces and identical visits. `stress-after-idle.png` confirms the selected page remained visible; the process remained alive through the idle interval.

Default `discardMinutes=30` was preserved. Five minutes cannot establish default time-based discarding, and lazy restoration is not proof that loaded tabs were discarded. No unsupported five-minute success claim or silent threshold change was made.

**Reduce Motion was not toggled or verified.** System Settings was not changed, so there was nothing to restore. This release gate remains open.

## Visual comparison and screenshots

The original Arc/Dia main references and WP9 light browsing capture were inspected with the vision tool. Graphene preserves a restrained tinted sidebar, dominant inset page, compact system controls and hairlines; the inspected browsing state has no obvious clipping or overlap. Secondary-label/favicon contrast and the relationship of Tidy/Clear to the tab list remain polish concerns, not measured reference mismatches. The supplied competitor main references are dark/vertical; no same-appearance or horizontal pixel-parity claim is made. No speculative mass restyling was applied.

`screenshots.json` contains **15 decoded PNGs**, dimensions and SHA-256 hashes:

- `onboarding-layout.png`, `onboarding-color.png`, `onboarding-finish.png`
- `browse.png`, `find-first.png`, `find-next.png`, `print-dialog.png`
- `threads-list-detail.png`, `vault-save-sheet.png`, `mail-disconnected.png`, `board-empty.png`
- `chat-summarize-refusal.png` — failed answer, not a successful summary
- `stress-restored.png`, `stress-after-idle.png`
- `capture-blocked-black.png` — failed capture, not feature evidence

## Files changed in this pass

- `Sources/Graphene/Mail/LoopbackServer.swift`
- `Tests/GrapheneTests/LoopbackServerTests.swift` (new)
- `scripts/build-app.sh` (version/build metadata only)
- `README.md` (current capability/shortcut/data/boundary/verification rewrite)
- `docs/verification.md` (dated current section, historical reports retained)
- `docs/parity/matrix.md` (78 feature rows have an explicit Graphene now column; original baseline preserved and labelled historical)
- This `docs/parity/shots/wp9/` evidence directory

Existing uncommitted changes and native Threads/Vault/Ask/Mail features were preserved. Little Graphene code/settings were not extended or verified.

## Cleanup and release verdict

PID 60482 received background and foreground Cmd+Q; it remained alive and was terminated with SIGTERM. PIDs 71092, 76158 and 81225 exited after computer-use Cmd+Q, confirmed by `ps`. The requested self-excluding `pkill -f '[g]raphene-dev-profile'` cleanup ran afterward. Final checks found none of those owned PIDs running. Unrelated Graphene processes were not killed.

The concrete deliverable is a tested, warning-free, ad-hoc-signed 0.3.0 development bundle plus a real callback crash/leak fix and an honest current feature inventory. **WP9 as a whole remains incomplete.** The AI refusal, uninvestigated idle CPU sample, incomplete interactive sweep, default-discard observation and Reduce Motion gate prevent release-readiness sign-off.
