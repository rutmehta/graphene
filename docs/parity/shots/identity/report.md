# Graphene identity verification — FAIL

The identity layer does not pass real-app acceptance. Branches, Graphite defaults, Resume content, and the Vault shelf are visible. The grounded Ask response has no citations or marks. The specified branch-collapse keys do not collapse the branch on the tested focus path. Opening a new tab over an existing page opens the command bar instead of exposing Resume. Drag and hover acceptance remain blocked by the available computer-use interface.

## Build, ownership, and revision boundary

- Initial branch: `master`, tracking `origin/master`; initial `git status --short --branch` had no changes or untracked files.
- Initial HEAD: `b2592d4073dd5e5a75d721d6092cbadc8849373c`.
- Built using `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`. Build succeeded and the bundle was signed. No normal installed Graphene bundle was targeted.
- Owned PID: **79532**. Main window: **9785**, obtained using `swift scripts/window-id.swift -p 79532`. Launch shell remained alive with `wait` until the app quit.
- Profile: `/tmp/graphene-identity-verify`. The requested `rm -rf` launch prefix was rejected by automatic approval review with “rm -f style commands are not permitted. Use a safer approach.” The path was absent, so launch used an absence guard without deleting anything.
- During this run another writer advanced master to **`e4dee76d8e2d0e95aa20cb7f28edbb5309155e61`**, “D6 follow-ups: shelf drops, empty-state lines, connector length, chat scroll to chip.” I made no commit or source edits. The running bundle was not rebuilt after this change. The screenshots and 184-test log must **not** be claimed as verification of that follow-up revision. There is no embedded revision attestation for the incremental build; initial HEAD is the build-time checkout observation.
- All app interaction used native computer-use clicks/keys/drags. No debug driver, injected UI scripts, delegation, or scheduled jobs. Public Wikipedia and Swift Forums pages only, plus an accidental public Google search described below.
- Capture command: `screencapture -l 9785 -o -x <file>.png`. Every saved PNG was inspected with the image viewer and `sips -g pixelWidth -g pixelHeight`. All **26** are **2560×1640**, representing **1280×820 points at 2×**. See [png-dimensions.txt](png-dimensions.txt). An early capture of the dismissed onboarding sheet failed; it produced no evidence PNG.

## Fixture and interaction limitations

1. The computer-use API exposes no held-modifier mouse click. Exact ⌘-click was not possible. A middle click navigated the same tab. Native link context-menu **Open Link in New Window** created a parented Today tab, so that was used to construct Graphene → Carbon → Element Six and Graphene → Graphite. The resulting tree is real, but this does not verify the ⌘-click gesture.
2. Coordinate scroll and drag attempts failed with `-10005 windowNotFoundAtPosition`. AX clicks worked. No fake drag result or detached screenshot was created.
3. Selection through `selectText` failed because webpage static text is not an editable selected-text range. Triple clicking selected the Graphene paragraph, rather than precisely one sentence. Cmd-D and Save created a real note from that paragraph. Swift's selected sentence was “The Swift Forums are governed by the Swift Code of Conduct”.
4. Typing immediately after Cmd-T lost the leading `ht` from `https://forums.swift.org`; it submitted `tps://forums.swift.org` as a Google search. Cmd-L followed by a fresh state read and URL paste reached Swift Forums. Continue therefore contains a Google-titled thread with **3 pages**, not a clean one-page Swift thread. This run cannot certify the requested pristine page counts.
5. Cmd-T over an existing page displayed the command bar. Escape returned to the old page; the New Tab action returned to the command bar. To inspect actual populated Resume, a blank Personal tab was moved to Research using the UI and selected. Actual Resume captures are clearly distinguished from the failed command route.
6. No hover/mousemove operation is exposed. `shelf-hover.png` is absent. `ask-hover.png` is also absent: there was no citation chip to hover in the first place.

## Acceptance results

PASS means observed for the stated fixture. FAIL (blocked) is unverified, not a claim of product failure. Static test results are explicitly identified.

| Acceptance | Result | Observation and evidence |
|---|---|---|
| A: fresh dark and light Graphite main captures | PASS | [main-fresh-dark.png](main-fresh-dark.png), [main-fresh-light.png](main-fresh-light.png); appearance toggled with ⇧⌘L. |
| A: Graphite preselected during default onboarding | PASS | AX selected Graphite; other swatches Iris and Tide. Sidebar layout/default onboarding completed. Observation recorded during run; no onboarding PNG. |
| A: Settings → Spaces hue/saturation and six presets/custom controls | PASS | Research hue slider `0.6444443712632189` = approximately **232°**, saturation **0.12**. Graphite, Iris, Tide, Moss, Clay, Slate and custom sliders visible. No setting edits. |
| D6 3.2: in-process color within six channels; contrast ≥4.5 | PASS | `VisualPaletteTests.testGraphiteChromeTopMatchesSpecInBothSchemes` passed, including both contrast assertions. This is test evidence, not a live-process sample. Composited PNG values are separately reported below. |
| B: empty new tab, search/lattice and exact line | PASS | [resume-empty.png](resume-empty.png): “Open a page and Graphene will keep the thread.” |
| B: exact ⌘-click browsing sequence | FAIL (blocked) | Modifier-click unsupported by exposed API; native context-menu substitute created real branch. See fixture note 1. |
| B: select exactly a sentence and Cmd-D | FAIL (blocked) | Graphene selection was a paragraph. Cmd-D + Save succeeded, but sentence-granular selection was not verified. |
| B: new-tab action exposes populated Resume | FAIL (observed) | [resume-newtab-command.png](resume-newtab-command.png), [resume-collapsed-command.png](resume-collapsed-command.png): command bar over existing page. Actual Resume required blank-tab workaround. |
| B: Continue has two rows | PASS | [resume-populated.png](resume-populated.png): two threads, Graphene and accidental search/Swift thread. |
| B: correct clean-fixture counts | FAIL (blocked) | Graphene shows **4 pages**; search/Swift shows **3 pages**. Search contamination prevents certifying requested clean counts. |
| B: Saved here quote in serif with left rule | PASS | [resume-populated.png](resume-populated.png). One saved Graphene paragraph, source title beneath. |
| B: click saved note opens/scrolls to highlighted source | PASS | [resume-open-note.png](resume-open-note.png): existing Graphene tab selected and paragraph brought into view with accent tint. Exact single-sentence condition remains blocked above. |
| B: favorites row appears only while collapsed | PASS | Added Swift Forums as a favorite via context menu. [resume-collapsed.png](resume-collapsed.png) shows Pinned in this space; [resume-expanded.png](resume-expanded.png) removes it from Resume and shows the sidebar favorite. These were taken after note deletion. |
| C: Graphene root, Carbon/Graphite children, Element Six grandchild | PASS | [sidebar-branch.png](sidebar-branch.png), [sidebar-branch-active.png](sidebar-branch-active.png); depth and order visible. |
| C: continuous parent hairline | PASS | Root line continues to Graphite; nested Carbon line reaches Element Six. Same captures. |
| C / language tick enters child's icon slot | FAIL (observed) | The 6pt tick stops short of the next-depth icon slot. It is a small elbow hanging in the indent, rather than a continuous connection into that favicon. See measurements. |
| C: deepest selected branch turns accent | PASS | [sidebar-branch-active.png](sidebar-branch-active.png); both ancestor connectors become steel blue. |
| C: close Carbon with Cmd-W promotes child to Graphene at same position | PASS | [sidebar-promoted.png](sidebar-promoted.png): Element Six becomes depth 1, before Graphite. The user acceptance governs here; D6 prose separately says promote to roots. |
| C: context menu Close branch | PASS | [context-branch.png](context-branch.png). Menu presence verified; destructive branch action not exercised. |
| C: Option-Left collapse with trailing count, Option-Right expand | FAIL (observed) | [sidebar-collapsed-branch.png](sidebar-collapsed-branch.png): selected Graphene still has visible children and no count. Row click left focus in webpage; Option-Left changed page scroll. Retried with Reduce Motion and still no collapse. No assertion about other focus routes. |
| C: drag deepest above root detaches and shortens line | FAIL (blocked) | Drag failed at computer-use coordinate targeting. `sidebar-detached.png` absent. Unit test is not live drag evidence. |
| C: no-branch sidebar exactly Arc capture | FAIL (blocked) | [sidebar-no-branches.png](sidebar-no-branches.png) inspected against `../arc-look-2/main-dark.png`. Reference has favorites, pinned/folder content and three space dots; fresh Personal fixture has none and two dots. Cannot establish pixel identity with different fixtures. |
| D: Vault label plus two correctly sourced serif chips | PASS | [shelf.png](shelf.png): Swift orange favicon and Wikipedia W, quoted fragments, above footer. |
| D: hover shows full quote | FAIL (blocked) | No hover operation available; `shelf-hover.png` absent. |
| D: chip opens source scrolled to mark | PASS | [shelf-open.png](shelf-open.png): Graphene paragraph visibly tinted and centered. |
| D: deleting both notes removes shelf and restores footer geometry | PASS | Deleted both disposable profile notes in Vault with confirmation. [vault-before-delete.png](vault-before-delete.png), [shelf-gone.png](shelf-gone.png). Footer remains at same bottom position; shelf vanishes. |
| E: Ask header This page with accent dot | PASS | [ask-empty.png](ask-empty.png). Status help reports “Apple · on device · Ready”. |
| E: page source strip, skills above composer, exact placeholder | PASS | [ask-empty.png](ask-empty.png): Wikipedia source, four skills, “Ask about this page…”. Also displays **1 source warnings**. |
| E: answer has inline numbered chips and sources line | FAIL (observed) | [ask-answer.png](ask-answer.png): no citation chips or sources list. General-knowledge disclaimer instead. |
| E: matching highlighted passages and superscripts | FAIL (observed) | No Ask marks produced. No linked 130 GPa passage. Existing Wikipedia blue/lavender boxes and footnotes are site content, not Graphene citations. |
| E: hover chip 1 scrolls/activates mark | FAIL (blocked) | There is no chip 1, and hover API unavailable. No `ask-hover.png`. |
| E: Peru question shows exact No sources line | PASS | [ask-nosources.png](ask-nosources.png): “No sources; this is the model's general knowledge.” appears. Response content itself is wrong: repeats graphene answer. |
| E: close panel leaves no marks | PASS | [ask-closed.png](ask-closed.png) shows panel gone and no visible Ask marks. |
| E: prove existing citation marks are removed on close | FAIL (blocked) | No citation marks were created, so this screenshot cannot establish removal behavior. |
| F: enable Reduce Motion, show shelf state, restore off | PASS | System Settings AX off → on → off; [reduce-motion.png](reduce-motion.png) captured with two chips. Final AX explicitly `AX_REDUCE_MOTION Value: off`. |
| F: branch collapsed with Reduce Motion | FAIL (observed) | Branch stayed expanded in [reduce-motion.png](reduce-motion.png). |
| F: verify 120ms fade-only behavior | FAIL (blocked) | Static captures do not establish duration or animation trajectory. |
| D6 3.6: lattice on empty Threads/Vault/Resume, fades down | PASS | [threads-empty.png](threads-empty.png), [shelf-gone.png](shelf-gone.png), [resume-empty.png](resume-empty.png). Lattice absent from populated Resume and inspected chrome. |
| D6 3.6: Reduce Transparency removes lattice | PASS | [reduce-transparency.png](reduce-transparency.png): empty Threads lattice gone. Setting verified off → on → off; restored. |
| D6 6.1 / language 7.4: fresh main pixel-identical except color | FAIL (blocked) | Supplied Arc capture is a populated fixture. No controlled matching baseline; no pixel-parity claim. |
| D6 6.2: swift test green and G1–G5 coverage | PASS | 184 tests, 1 skipped, 0 failures. Promotion/drag model, passage matching, shelf visibility, Graphite contrast and Resume rules covered. Live drag/answer failures remain independent. |
| D6 6.3: no new font/radius/opacity literals in UI | PASS | Source audit of **initial HEAD**, excluding token definitions: no numeric `.font(.system(size:)`, `cornerRadius:`, `.cornerRadius(...)`, `.opacity(...)` matches. G3 token-gate test passed. [source-audit.txt](source-audit.txt). No claim about every possible syntactic form. |
| Language 7.1: every added hairline is provenance/quote rule | PASS | In inspected identity surfaces: branch connectors and Saved here rule have meaning. Sidebar section divider, toolbar border, panel/source-strip separator and page card outline are Arc-base lines; website rules excluded. No additional unexplained identity line observed. |
| Language 7.2: serif only on page-derived text, no chrome serif | PASS | Inspected chrome headings/labels sans; Resume and shelf quotes serif. Wikipedia serif is page content. Vault quote remains sans: converse type-consistency defect noted below. |
| Language 7.3: lattice only in four allowed places | PASS | No out-of-scope lattice observed in captured surfaces. Empty three checked; Board allowance does not require Board lattice for G1–G5. This is not an exhaustive review of private Mail or every app surface. |
| Language 7.5: all six named test areas covered | FAIL (observed) | Initial HEAD covers sidebar connector geometry and citation index assignment. No tests found for map visit-tree rows/columns, Vault row provenance formatting, Board graph connector derivation, or Mail conversation grouping. Persistence/drop tests do not substitute for those requirements. |

Additional D6 prose constraints not established by this run: max-depth clamp, roots newest-first under all insertion paths, archive-whole-branch Undo, session restoration, icon-slot adoption, private/editor citation exclusions, regenerated-answer mark cleanup, shelf drag-out and all responsive widths. They are **FAIL (blocked)** for live verification, even where unit tests cover their models. In the observed tree, later Swift root appears after Graphene, not newest first.

## Measurements from PNGs

Coordinates below are image pixels; divide by two for points. Color values were read from PNGs with AppKit and converted to sRGB, not sampled from the app renderer. Edge measurements have about ±0.5pt raster uncertainty. [measurements-raw.txt](measurements-raw.txt) retains color probes; pixel scan ranges for shelf chips were x84–246 and x258–420 at y1508.

| Measurement | Expected | Observed from PNG | Delta / result |
|---|---:|---:|---|
| Window | 1280×820pt | 2560×1640px / 2 | 0, 0 |
| Child indent per depth | 20pt | Icon centers approximately x52 →92 →132px | 20pt, delta 0 |
| Connector from parent row leading edge | 17pt | Row starts x16px; connector center ~51px | 17.5pt, +0.5pt raster center |
| Connector tick | enters child icon slot | Root x~51 to~63px; next-depth icon slot starts about x72px | ~4.5pt visible gap to slot; fails language relationship |
| Shelf reserved height | 44pt | Chips visibly 32pt tall; no painted shelf boundary and short Today list | Reservation not independently measurable; delta unknown |
| Shelf chip size | 96×32pt nominal | 162×64px = **81×32pt** | −15×0pt vs nominal; within D6 adaptive 72–96pt rule at 224pt sidebar |
| Resume column | 560pt | Search fill x936–2056px =1120px | 560pt, delta 0 |
| Lattice cell width | 28pt | Repeated cell vertical edges approximately 56px apart in empty captures | ~28pt, delta ~0 (visual estimate) |
| Footer center | Arc base | Approximately y1604px in shelf-present and shelf-gone captures | ~802pt; no vertical shift observed |
| Saved mark vs page | accent tint, page ink retained | Mark background at (800,900)/(750,1000) **RGB 198,202,224**; adjacent page **255,255,255** | ΔRGB **−57,−53,−31** from page. Dark page ink still visible; annotation mark, not Ask mark |
| Ask highlight 22% / active38% | compare matched marks | None created | Unmeasurable; FAIL (blocked) |
| Dark Graphite top PNG | HSB target approximately RGB21,23,38 | sRGB PNG (300,20): **29,31,49** | +8,+8,+11; composited grain/gradient/color management, not in-process token measurement |
| Light Graphite top PNG | HSB target approximately RGB213,217,242 | sRGB PNG (300,20): **221,223,242** | +8,+6,0; same distinction. Unit token tolerance test passes; literal PNG probe is not within6 for every channel |

## What still doesn't read as one product

1. **Ask advertises a source but does not use it visibly.** The graphite accent dot and page chip promise grounding, yet the requested answer has no citations, source line, or linked passage. “1 source warnings” is visible before asking. The reply says: “Graphene has a tensile strength of 130 GPa. It was first theorized in 1947 by Philip R. Wallace.” It does not answer who first isolated it. The Peru question returns the same graphene text. This is not an unavailable-model placeholder: the panel reports Ready and produces responses. No model/provider was changed and no answer was fabricated.
2. **Resume is a real designed surface behind an unreliable entry route.** Cmd-T from a loaded page exposes the command bar, not the requested Resume page. The available Resume looks coherent once reached via a blank tab, but a feature users cannot reach through its primary command does not pass.
3. **The branch is visible but not reliably operable through its stated keyboard grammar.** Option-Left on the selected row left the branch expanded and acted on page focus. The short ticks also stop before the child's icon slot, weakening the intended provenance relationship.
4. **Vault and its entry points use different typography and structure.** Resume and shelf quote fragments are serif; full Vault is a card grid with sans quote text and a separate editor. [vault-before-delete.png](vault-before-delete.png) shows the mismatch. G7 is outside this build package, but the shared-product impression is already inconsistent.
5. **Empty library surfaces are heavier than Resume.** Threads and Vault show a large heading, explanatory copy and action buttons below the lattice; Resume uses the single quiet line. This observation concerns the tested bundle; later checkout changes to empty-state lines were not rebuilt.
6. **The shelf has almost no readable quote at default width.** Two compliant 81pt chips leave “The S…” and “Grap…” beside the favicons. Hover must carry the meaning, and hover was not verifiable here.
7. **The supplied parity comparison cannot prove the foundational promise.** Empty Graphene versus populated Arc is not a controlled comparison. The prominent purple top-left control also remains visually more saturated than the quiet Graphite identity, although it belongs to the existing shell.

## Build and test evidence

[build.log](build.log), complete tail:

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.16s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

[tests.log](tests.log), `swift test` tail:

```text
Test Suite 'GraphenePackageTests.xctest' passed at 2026-09-25 04:21:47.109.
 Executed 184 tests, with 1 test skipped and 0 failures (0 unexpected) in 5.953 (5.971) seconds
Test Suite 'All tests' passed at 2026-09-25 04:21:47.109.
 Executed 184 tests, with 1 test skipped and 0 failures (0 unexpected) in 5.953 (5.972) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

The skipped test is `AnswerQualityTests.testLiveAnswers`: “Opt-in real-model harness.” Thus green tests did not certify live answer quality. The later checkout adds tests absent from this run; no 184-test result is attributed to that later commit.

## Crashes, hangs, and errors

- No app crash or sustained app hang observed during this session. Owned launch shell exited with code0 after Cmd-Q.
- [console.log](console.log) is empty: no stdout/stderr errors captured. This is not a system unified-log audit.
- Ask shows **1 source warnings**; the exact underlying warning was not opened. Grounding failure is observable; its internal cause is not established.
- Computer-use coordinate actions returned `-10005 windowNotFoundAtPosition`; hover and held-modifier click are not available. Static text selection was not settable. These are verification/tool blockers, not demonstrated Graphene crashes.
- First onboarding-sheet screencapture failed after that window disappeared; subsequent main-window captures succeeded.
- Python Pillow was unavailable during image analysis. Pixel analysis used AppKit on existing PNG files instead; no app scripting.

## Cleanup and final scope

- Sent Cmd-Q through computer-use to the owned verification app. Launch session completed exit0. `swift scripts/window-id.swift -p 79532` returned `no window found`. No unrelated Graphene PID was quit.
- Deleted only `/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app`; confirmed absent.
- Reduce Motion restored to **off**, confirmed through System Settings AX. Reduce Transparency also restored to **off**, confirmed through AX.
- Both disposable notes deleted through Vault. Isolated profile is retained at `/tmp/graphene-identity-verify` for diagnosis; no normal profile was used.
- No stash, commit, or tracked source edits. Only evidence/report files were added by this run. External master advance to `e4dee76…` preserved.
- Missing requested PNGs are deliberately absent: `sidebar-detached.png`, `shelf-hover.png`, `ask-hover.png`. The failed-collapse capture retains its requested filename and shows the failure, not a fabricated collapsed state.
