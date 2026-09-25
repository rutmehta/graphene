# WP10 — measured polish and final glance test

## Acceptance status

**Partial, not full WP10 sign-off.** Shell changes and idle-CPU repair are implemented and observed. Ordinary build/tests/bundle/signature checks pass. The opt-in live-model sweep still refuses two benign example.org requests, Gmail OAuth lacks isolated-profile configuration, and some physical geometry controls remain unverified. These are not hidden behind the ordinary green test run.

## Implementation and files touched

- `Sources/Graphene/Model/TabLifecycle.swift`: unchanged media states no longer publish, and media polls no longer invalidate the whole AppState unconditionally. Media detection and discard protections remain.
- `Sources/Graphene/Model/ToastQueue.swift`, `UI/ToastOverlay.swift`: guard empty/paused toast ticks before entering the @Published mutating accessor. A no-op mutating call previously still published four times per second.
- `UI/Theme.swift`: default 37pt row height + 4pt gap = 41pt pitch; 56pt favorite height, 8pt favorite gaps and width-dependent column token; calibrated dark chrome derivation.
- `UI/Sidebar.swift`: tokens applied to Today/New Tab, pins and folder children; 8pt outer inset + 10pt padding puts 16pt favicons at x=18; three-column grid below 280pt and four at/above it. Compact rows remain an explicit nondefault option.
- `Model/Settings.swift`: optional `panelMode` defaults to Floating; optional width defaults to 420 and clamps to 360–560. Existing valid saved widths survive. Existing atomic settings/session persistence remains; no SessionData change was needed because these preferences already live in Settings.
- `UI/ShellContentLayout.swift`, `UI/RootView.swift`: stable-identity floating overlay, 16pt inset from the page surface on top/right/bottom, 12pt corners/shadow; width comes from the layout proposal rather than a fixed frame that defeated narrow-window sizing. Docked remains selectable; existing Cmd+K/menu routes are unchanged.
- `UI/ChatView.swift`: title-left header with 16pt history/new/close controls, context row directly below, requested composer placeholder, @ and / at left, attachment + and send-arrow/Stop circle at right. Source search, citations, history, streaming and existing native surfaces remain.
- `UI/SettingsView.swift`: Appearance exposes Floating/Docked and 360–560pt Chat width.
- `UI/CommandBar.swift`: sidebar input 22pt in a 56pt row, 44pt results with 14/12pt title/subtitle. Top-tabs integrated address styling remains unchanged. Six initial actions and footer remain fully visible.
- `Intelligence/PageContext.swift`, `Intelligence/ChatSession.swift`: shared skill/question request builder; slash expansion occurs in the controller/provider-request path instead of only the view. Current custom skills remain supported; slash intent persists in chat history and regenerates through the same path.
- `Tests/GrapheneTests/IdlePublicationTests.swift` (new), `ShellPolishTests.swift`, `WorkspaceSettingsTests.swift`, `AnswerQualityTests.swift`: idle publication checks, layout/default/range/grid checks, persisted panel mode, common skill builder, and a live harness that fails on explicit benign-page refusals.
- `README.md`: What works, shortcuts, current screenshot and qualified WP10 verification.
- `docs/parity/shots/wp10/`: captures, comparisons, metrics, profiling, live answers, scripts and this report.

`LanguageModelProvider.swift` was temporarily used for a prompt-format experiment, then restored to its incoming content because the change did not fix the refusal. No speculative provider bypass, canned answer, TODO stub, new dependency in the Swift app, commit, or change under `docs/parity/ref/` was left. Little Graphene was not changed or tested.

## Measurements

See `geometry.json`, `measurements.json`, `main-dark.ax.json`, and `drag-after.ax.json`.

- Arc's alpha-cropped dark reference is approximately 1280×820pt. Consecutive ordinary tab centers are 41pt apart; selected rows approximately 36–37pt tall. Favicons are approximately 16pt, leading x=18pt. Graphene AX shows New Tab at y=643, Example tab at y=684, both 37pt tall, favicon at window-relative x=18, 16×16pt.
- Arc favorites in this capture are about 66×48pt, with 8pt gaps. The brief's chosen 56pt height wins over the reference's 48pt. Graphene's visible default tile is 64×56pt at a 224pt sidebar; the column breakpoint and gap are tested. Only one favorite was present in the retained isolated fixture; a populated multi-row/physical 280pt transition is not visually established.
- Dark sidebar sample x=0–225 across the normalized 820pt height, including content: Arc mean RGB **52.47,49.67,68.76**; Graphene **55.00,48.01,70.94**. Absolute differences **2.53,1.66,2.18**, all below 8. These are whole-region means, not pure paint-color identity. Other hues remain distinct and text contrast tests remain above 4.5:1.
- `ref/arc-main.png` has a dark navy-purple sidebar despite its unqualified filename. It is not usable for light-sidebar RGB matching. Light Graphene was inspected for readable contrast, not falsely calibrated to a dark reference.
- Traffic-light and reload AX center lines both sit at window-relative y=24. Pixel segmentation on the normalized capture gives light centers y=23.5, back/forward/reload y=24/23/24, within 2pt. Disabled-arrow pixel measurements are less robust than AX because their neutral foreground is faint.
- A real foreground computer_use drag in blank traffic-band space moved the window **(388,275,1280,820) → (469,315,1280,820)**. The existing WindowDragRegion was already functional; no speculative drag rewrite was needed. This verifies a representative blank-band drag, not exhaustive per-pixel hit testing/fullscreen behavior.

## Glance-test verdict by region

| Region | Light | Dark | Remaining difference / evidence boundary |
| --- | --- | --- | --- |
| Tab rows | Readable, comfortable pitch, active row contained | Same geometry, quiet selection | Measured 41pt now matches Arc; sidebar content/section positions differ. Compact mode deliberately differs. |
| Favorites | 56pt tile and quiet fill | Same, colored favicon | Three/four-column policy tested, but only one tile in UI fixture. Reference tile height is 48pt, brief requested 56pt. |
| Sidebar tint | Pastel chrome remains readable | Whole-region RGB within ±8 of Arc | No usable light-sidebar competitor reference. Not every custom hue is intended to equal Arc purple. |
| Footer | Single utility row and Ask entry clear | Same | Ask and Library retain Graphene's features; Arc has no equivalent Ask row. No control collision seen. |
| Page frame | Inset rounded page dominates | No loud dark border | Navigation remains in Graphene's sidebar; competitors have page-top toolbars. This is the brief's architecture, not an uncorrected defect. |
| Traffic band | Controls fit | Pixel and AX centerline check passes | Actual window movement verified. Not exhaustive fullscreen/edge hit testing. |
| Sidebar command | Larger input, six full actions, footer intact | Same | Arc reference contains different result kinds; Dia reference is a new-tab chat page, not a command palette. Footer hints are still deliberately small. |
| Top tabs | Clean, neutral, no overlap | Same | No supplied horizontal competitor reference; lightly populated strip is not a crowded-tab stress test. |
| Chat | Floating inset panel, contained header/context/composer | Same, shadow separates panel from page | Page occlusion is intentional. Docked selection and physical width adjustment were not successfully observed. |

All eight generated comparisons were inspected, along with full-size Chat and command captures. No glaring control clipping/overlap remained in these states. Files: `main-{light,dark}.png`, `chat-{light,dark}.png`, `command-{light,dark}.png`, `top-tabs-{light,dark}.png` and matching `compare-*.png`. README uses the current light main capture.

## Idle CPU investigation and verification

Baseline owned PID 16632 was launched without GRAPHENE_DEBUG. `idle-before.sample.txt` shows main-thread SwiftUI/AttributeGraph/layout work, including repeated SidebarTab bodies. Early `ps` readings were 5.7% and 14.7%, rather than a claim that the historical exact 25% was reproduced.

The source contained two concrete unchanged-state publication paths: the 0.25-second toast callback mutated @Published AppState even with no toasts, and media polling both rewrote identical tab state and unconditionally sent AppState.objectWillChange. A red regression test observed an idle media poll publishing once; after the fix, it publishes zero times. Empty/paused toast regression tests verify the same guard boundary and confirm live toasts still expire.

Updated owned PID 31872 restored the same idle isolated fixture without debug polling. Two five-second `sample` captures began 60.009 seconds apart. `ps` afterward reported **0.8%**, then **0.1%** CPU. Process accumulated CPU time increased from 0:00.79→0:00.82 and 0:01.09→0:01.12 during the respective capture intervals. Logs: `idle-after.json`, `idle-after-{1,2}.sample.txt`.

The live-model XCTest process ran separately during part of the first interval; the sampled PID was the idle browser, not the model test runner. This is main-process idle evidence with one active simple page, not a guarantee about animated sites, active audio, or the prior 60-tab fixture.

## Skills / model-quality gate — failed

The original binary accepted a real UI `/summarize` on the current example.com page in an existing conversation. Its stored answer was “This page is for documentation examples and should not be used in operations. [1]”. This is a fresh baseline observation, not evidence the example.org new-conversation refusal was fixed.

The opt-in harness fetched actual text from example.org, Wikipedia's Swift article and the public swift-argument-parser GitHub README, then invoked all three requested slash skills through PageContext and OnDeviceProvider. `answers.md` records all nine outputs from the final-equivalent request format. **Example.org summarize/explain refused; seven others produced text.** Some generated answers omit expected citations or include questionable factual claims; mere output is not a factual-quality pass.

Explicit Question/Reference labels and removing a single-turn role prefix were separately tried and did not fix the failures. Their evidence is retained in `answers-labeled-attempt.md` and `answers-role-prefix-attempt.md`; those ineffective changes were reverted. The common builder, user-visible error behavior and stronger failure assertions remain. No safeguards were disabled and no synthetic answer was substituted. This acceptance gate is unresolved.

## Gmail OAuth — blocked before sign-in

Settings → Mail was opened through computer_use (`gmail-unconfigured.png`). It shows Disconnected/read-only, Connect Gmail disabled, and “Gmail OAuth is not configured in this build.” The isolated root has no gmail.json. No real-profile configuration or credentials were opened or copied. Therefore Google-page cancellation and callback-timeout behavior could not be exercised at UI level. Existing LoopbackServer callback/timeout/race tests pass in the ordinary suite, but are not a substitute for this requested flow.

## Desktop method and remaining interaction limits

Owned processes only: 16632 baseline and 31872 updated. Cmd+K, Cmd+T, Cmd+Shift+L, command-palette “Switch layout”, Settings opening, Appearance/Mail page selection and Cmd+Q were real computer_use actions. New controls have identifiers/labels/traits; Settings exposed the native labelled Chat panel popup and width slider in AX.

SOM captures returned AX data, but element/set_value dispatch still rejected missing snapshot tokens (`snapshot_id_required`). Foreground coordinates worked for Settings page selection and the traffic-band drag. The attempted popup switch did not establish Docked selection; subsequent keys moved the Settings list instead. It was not reported as success or replaced with a fake state mutation. Physical Chat resizing, new attachment/send buttons, and populated favorite breakpoint interaction remain unverified. A transient ended-driver-session focus error recovered on a fresh scoped capture. These transport failures are not evidence that the popup lacks accessibility.

## Build, tests and safety

All work ran synchronously here, without agents, cron, task queues or deferred jobs. Only the expressly requested GUI browser was launched asynchronously. No user-profile browser was launched, killed or modified.

A real-profile PID 14394 was running directly from `.build/arm64-apple-macosx/debug/Graphene`, so all SwiftPM work used the verified environment override `SWIFTPM_BUILD_DIR=$PWD/.build/wp10`. This keeps the ordinary `swift build`, `swift test` and build-app script behavior while avoiding replacement of its live executable. Test process data root was `/tmp/graphene-dev-profile/tests`; GUI root was exactly `/tmp/graphene-dev-profile`. The app bundle is `.build/Graphene.app`; no installed bundle was touched.

Final logs preserve combined output and actual return codes; Python printed the final 30 lines rather than a pipeline that masks failures:

- `swift build`: exit 0, no compiler warnings.
- `swift test`: **91 executed, 1 opt-in live-model test skipped, 0 failures**.
- `./scripts/build-app.sh`: exit 0, ad-hoc signed.
- `codesign --verify --deep --strict .build/Graphene.app`: exit 0.
- Separate live-model test: **failed** as described above, not included in the ordinary green claim.
- `git diff --check`: clean.
- Both owned GUI PIDs exited after scoped computer_use Cmd+Q; process checks show the unrelated real-profile instance still alive. No commit was made.
