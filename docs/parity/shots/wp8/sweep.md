# WP8 regression sweep — partial, not release sign-off

## Execution and evidence

Work was synchronous in this session. No agents, scheduled jobs, commits, or changes to `docs/parity/ref/`. Only GUI app launches used background processes, as requested. GUI instances used `GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile/wp8`; the existing parent profile and unrelated running Graphene instances were not used for the sweep. Public sources and explicitly named WP8 test fixtures only. No Gmail account, browser passwords, permissions, default-browser registration, or personal browser imports were accessed.

Final build, test and bundle logs are in this directory. `swift build`, `swift test`, `./scripts/build-app.sh`, `codesign --verify --deep --strict .build/Graphene.app`, and `git diff --check` passed. Final XCTest run: **78 tests, zero failures, zero skips**, including the opt-in live-model harness. Build/test/bundle logs contain zero compiler warning lines. The ordinary test command skips the real-model harness unless explicitly opted in.

There are **30 saved PNGs**, verified decodable, with distinct hashes and dimensions in `screenshots.json`. This is not 30 completed acceptance tests. Screenshots document the particular states below, not unperformed interactions.

## Input limitations and cleanup

- Fresh SOM capture followed immediately by element-index click still returned `snapshot_id_required`. The exposed tool does not accept an explicit snapshot token. Foreground pixel fallback and keyboard input worked for several controls.
- `focus_app` first successfully identified owned PID 34653. After restart, it twice reported an ended driver session; captures and other input continued to work for PID 61026.
- Pixel clicks and native popup typing were inconsistent. Some calls reported delivered/confirmed while the intended action did not occur. These are not counted as successful tests.
- A Vault-card-to-composer drag was delivered from screen (499,650) to (1490,985). Afterward, two captures could no longer resolve Graphene. The process remained running, and desktop discovery showed only other applications. No assumption is made that the drag succeeded or caused this desktop change. No operating-system Space switch or System Events/screencapture workaround was attempted.
- The final rebuilt bundle was launched as PID 89187, but capture and focus both returned no on-screen Graphene window. Its launch was verified by the process, not by a fabricated final screenshot.
- PID 34653 exited after computer-use Cmd+Q. Cmd+Q for 61026 and 89187 was blocked by “No active window”. Those exact owned PIDs were terminated with SIGTERM, then the requested self-excluding `pkill -f '[g]raphene-dev-profile'` cleanup was run. Final `ps` verification found none of 34653, 61026, 89187 running. Other Graphene instances were not killed.

## Part A: AI quality

### Prompt and real answers

`AnswerQualityTests.testLiveAnswers` calls the same `PageContext` and `OnDeviceProvider` used by Chat. `inputs.json` contains fetched excerpts, not synthetic model outputs. Six questions span Wikipedia's Graphene article, the Swift GitHub README, NASA's Webb first-images news release, and example.org. Raw final answers and streaming update counts are in `answers.md`; the correctly paired baseline is in `answers-before.md`.

The correctly paired baseline in this session did **not** reproduce the earlier generic refusals. Source framing was simplified as requested, rather than claiming a deterministic causal diagnosis from a non-reproducing baseline. An intermediate revised prompt produced invalid citation numbers and a contradictory graphene/graphite sentence. The final prompt additionally constrains citations to Source labels and asks for concise answers. Final outputs answer all six questions without a refusal or provider error; the README summary has three bullets, and the physics/news facts asked about agree with the supplied excerpts. Citation presence and concision remain inconsistent. This is a small quality check, not a reliability guarantee.

Instructions remain in the FoundationModels session. Excerpts are plain labeled text, with an explicit rule that source content is reference material and cannot issue commands. Output is capped at 700 tokens. A guardrail error retries once with the newest user turn shortened to 2,400 characters. If partial text already streamed, the retry is visibly separated, not silently concatenated. A second guardrail error surfaces `Apple's on-device model declined this request`. No real guardrail error occurred in the final run, so that specific branch is source/build-verified, not live-triggered.

Actual GUI: typed “What is this domain for?” and `/summarize` over example.org. Both received useful on-device answers. Isolated `chats.json` readback confirmed the two user/assistant pairs. Evidence: `chat-domain.png`, `chat-summarize.png`.

### Writing, streaming, drops

- Draft cleanup removes common preambles, fenced wrappers and paired outer quotes before insertion/copy, including completed, stopped and errored partial drafts. Four requested preamble variants plus ordinary-text preservation pass unit tests.
- Writing now has its own editing instruction, without citation requirements. Custom instructions submit with Return; action/input/apply controls have stable accessibility IDs.
- The textarea writing affordance and native preview opened through real clicks. Fix-grammar/custom generation/apply were not verified after targeting failures. The initial affordance image expired from the shared screenshot cache before being copied; it is not included in the PNG manifest. The final accessibility/Return changes are compiled and tested but not GUI-exercised.
- Streaming is still incremental for Apple and both remote SSE formats. New tests assert that the bubble receives text before completion and that Stop rejects late tokens. Final real Apple runs yielded multiple updates for every question. No remote account was configured: SSE delta parsing/request tests are not claimed as a live remote service test.
- The visible Chat composer now accepts Vault note drops, deduplicates them and enforces profile/private/excluded-source checks. Those rules pass tests. A real drag was attempted, but the target then became unavailable, so end-to-end drag acceptance remains unverified.

Re-run the harness (Python input-fetcher requires BeautifulSoup 4, installed in the tested python3):

    python3 scripts/ai-quality-inputs.py
    GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile/wp8-tests \
      GRAPHENE_AI_QUESTIONS="$PWD/docs/parity/shots/wp8/inputs.json" \
      GRAPHENE_AI_ANSWERS="$PWD/docs/parity/shots/wp8/answers.md" \
      swift test --filter AnswerQualityTests.testLiveAnswers

## Part B: earlier loose ends

| Item | Result |
| --- | --- |
| WP1 layout tokens | Partial. Shared icon buttons now use ShellButtonStyle, row-radius tokens, pressed state and explicit focus outlines. Universal adoption across every existing surface remains incomplete; no unverified mass restyling was applied. |
| WP1 keyboard focus/pressed audit | Shared icon-control implementation improved. Full keyboard audit, inactive/fullscreen and motion measurements not completed. |
| WP1 resize routing | Existing model/routing tests pass. Physical resize re-verification not completed before desktop targeting was lost. |
| WP2 thumbnail cache | Fixed: one process-wide 40-entry recency-bounded cache, observable by all previews. Private pages are excluded entirely. Eviction test passes. |
| WP2 YouTube PiP | Added a document-end user script that exposes a real clickable request button. Its click handler tries webkitSetPresentationMode, then requestPictureInPicture; unsupported/declined states are visible. No AVPlayerView or private WebKit configuration. YouTube and a floating PiP window were not re-verified in this run. |
| WP2 dialog suppression UI | Existing origin-labeled selectable native dialogs and suppression checkbox retained. A five-dialog fixture was seeded; checkbox interaction was not completed. |
| WP3 inline @ picker | Existing shared integrated command session is wired in the top address container. Typed @ and attached WP8 Tab 1 with Return. `top-tabs-mention-picker.png`, `top-tabs-mention-attached.png`. |
| WP3 crowded tabs | A stopped isolated session was seeded with 16 named public test tabs and a favorite. `top-tabs-crowded.png` proves the populated strip, not successful overflow interaction. |
| WP3 reorder/middle-click/overflow | Middle-click and overflow click did not produce confirmed state changes. Reorder was not completed. Existing tab accessibility labels/IDs were present; failed clicks were not used as proof of a model bug. |
| WP5 Find | Fixed: one WebKit window.find Range walk supplies both selected range and exact count/index; supports inline nodes, case-insensitivity and hidden-text exclusion. Main document only, not frames. Real Cmd+F and Cmd+G show 1 of 3 then 2 of 3: `find-first.png`, `find-next.png`. |
| WP5 certificate exceptions | Not implemented. SecTrust establishes certificate validity, not WebKit's HSTS/preload policy. No reliable public HSTS lookup was found in the existing architecture; inferring “not HSTS” from an absent response header would be unsafe. Certificate failures continue to fail closed. |
| WP6 Settings pages | All 13 sidebar destinations opened and captured, including Profiles, Boosts, Import and Privacy/content blocking. Their existence/reachability is verified; every control is not. |
| WP6 Appearance font | Implemented optional persisted PageFont override, applied to existing/new page text and removable via Website default. Browser chrome/code styling retained. Round-trip test passes. Picker is visible in `settings-appearance.png`; attempted change was not confirmed or persisted. |
| WP6 inline branch tree | Implemented first-parent depth-first inline rows with cycle/orphan safety. Sibling/cycle tests pass. Threads screen opened, but a populated multilevel tree was not visually verified. |
| WP6 universal shortcut remapping | Main browser menu already resolves all registered commands through overrides; retained. Contextual pin/favorite/rename/separate/copy/peek/close entries now display the same current hints without installing duplicate global accelerators. System editing/Services commands remain reserved. Full remapped-key GUI exercise remains incomplete. |

One intermediate contextual-shortcut implementation registered duplicate accelerators. During GUI testing, closing Settings was followed by an unexpectedly closed page. Duplicate contextual registrations were removed; the existing auxiliary-window close test and full suite pass. The final fix was not independently re-exercised in the GUI, so this remains an explicit regression recheck rather than an asserted cure.

## Part C: requested sweep inventory

| Requested workflow | Actual result / evidence |
| --- | --- |
| Browse | Loaded example.org through Cmd+L/type/Return. `browse.png`. Search navigation also loaded real Google results during a mistaken command-title attempt. Full back/forward/reload suite not repeated. |
| Spaces | Both default spaces and routing editor shown in `settings-spaces.png`; CRUD/switching not re-exercised. |
| Favorites/pins/folders | Seeded favorite and tabs only; `top-tabs-crowded.png`. Physical organization workflows not completed. |
| Archive/restore | Not completed in this sweep; existing persistence/model tests pass. |
| Split | Not completed in this sweep; existing split tests pass. |
| Peek | Not completed in this sweep. Little Graphene was not exercised. |
| Private window | Not GUI-exercised; existing private no-write tests pass. |
| Command bar actions | @ picker and attached chip verified. Site Controls selection produced a new native popup window, but its content was not successfully captured. An attempted “Switch to Sidebar” was actually searched: the existing command is “Switch layout”, now corrected in README. |
| Top-tabs layout and back | Top-tabs seeded/restored and captured; native switch back not confirmed. |
| Site controls | Popup launch observed, interactive controls unverified. Settings → Sites captured. |
| Boost | Settings page reached. Actual edit/save/zap not completed. |
| Reader | Not GUI-exercised in this sweep; extractor tests pass. |
| Profiles | `settings-profiles.png`; creation/assignment/cookie login not exercised. |
| Import from Arc | `settings-import.png`; no personal Arc data read. Existing Arc fixture/idempotence tests pass; chooser/preview/import not GUI-exercised. |
| Settings pages | All 13 reached using clicks and arrow-key selection, with `settings-*.png` evidence. |
| Routing rule | Editor shown, but no new rule created/tested via UI. Model tests pass. |
| Toast Undo | Not completed in this sweep. |
| Board | Cmd+Option+5 opens empty Board: `board-empty.png`. Add/edit/resize/drop not completed. |
| Onboarding | All three steps advanced with Return, completed, and did not repeat on restart. `onboarding-layout.png`, `onboarding-color.png`, `onboarding-finish.png`; settings readback has completed=true. |
| Threads | Cmd+Option+2 opens recorded threads: `threads.png`. Multilevel branch and summary interaction remain unverified. |
| Vault | Empty surface, Cmd+D note sheet, typed note and Save via Return, then populated Vault. `vault-empty.png`, `vault-save.png`, `vault-saved-and-chat.png`. `annotations.json` readback contains exactly the entered note and correct public source URL. |
| Mail | Cmd+Option+3 shows honest disconnected/read-only surface: `mail.png`. No OAuth configuration; connected flow cannot be verified without account setup. |
| Chat with @ and / | Real domain answer and slash summary verified; top-address @ attachment verified. Chat-side note drag not confirmed. |
| Writing help | Affordance/preview opened; generation and insert not verified after targeting failures. Unit cleanup is verified. |

## Visual comparison

Arc and Dia reference images and the live Graphene chat screenshot were inspected with the vision tool. The Graphene capture retains light tinted chrome, quiet hairlines, compact controls, and a dominant page. Chat messages, citations and composer were not clipped in the inspected capture. Faint secondary controls remain a polish concern. No pixel-perfect parity, complete token adoption, or light/dark/fullscreen acceptance is claimed.

## Files changed for WP8

- Intelligence: `PageContext.swift`, `LanguageModelProvider.swift`, `ChatSession.swift`.
- UI: `ChatView.swift`, `WritingHelpView.swift`, `RootView.swift`, `TabPreview.swift`, `WindowState.swift`, `SettingsView.swift`, `LedgerView.swift`, `TabContextMenu.swift`.
- State/model: `App/AppState.swift`, `Model/TabLifecycle.swift`, `Model/Settings.swift`; new `Model/PageFont.swift`, `Model/ThreadBranch.swift`.
- Web/resources: `Web/FindCounter.swift`, `Web/WKWebEngine.swift`; new `Resources/find.js`, `Resources/pip.js`.
- New `Store/ThumbnailCache.swift`.
- Tests: new `AnswerQualityTests.swift`, `WP8RegressionTests.swift`; updated `IntelligenceTests.swift`.
- New `scripts/ai-quality-inputs.py`; README; this WP8 evidence directory.

The remaining work is not deferred to a background job. This session ends with a clean build and passing tests, but **WP8 overall is incomplete**, especially the exhaustive real-interaction regression gate.
