# Graphene G6–G9 real-app verification

Verified 2026-09-25. **Mixed result; not a design-language sign-off.** All app interaction used the computer-use tool, synchronously, without delegation, debug environment flags, the debug command driver, or in-app scripted automation. Public Wikipedia pages only. No OAuth or private mailbox was opened.

## Run identity and evidence

- HEAD: `78e8636dc1aa7956b8a33958277d027963539c8d`.
- Initial `git status --short`: clean. Final status: only `?? docs/parity/shots/language/`.
- Owned PID: **40754**; window ID: **10225**, obtained with `swift scripts/window-id.swift -p 40754`.
- Built with `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`.
- Fresh profile: `/tmp/graphene-language-verify`, initially absent. Retained for inspection; path also in [profile-path.txt](profile-path.txt).
- Launched the bundle executable with `GRAPHENE_DATA_DIR`, backgrounded within a shell kept alive by `wait`. stdout/stderr captured in [app.log](app.log).
- Default onboarding: Sidebar (Arc), Graphite color, Start browsing. No default-browser change.
- All PNGs are original window captures from `screencapture -l 10225 -o -x`. Every PNG was checked with `sips` and opened for visual inspection. All are **2560×1640 pixels**, matching **1280×820 points at 2×**. No substituted screenshot represents a blocked state.
- No source edits, commits, stashes, or deletions of existing evidence. `~/Applications/Graphene.app` was not touched.

## Seed and material workflow details

Graphene → Carbon and Graphene → Graphite were created with Wikipedia link context menu → **Open Link in New Window**. Carbon → Latin was created the same way. The app represented these as child tabs, not additional native windows. The map correctly retained four visits and their ancestry.

Carbon’s opening paragraph was triple-clicked, ⌘D opened Save to Vault, and **for the intro** was saved. Graphene’s opening paragraph was triple-clicked and ⌘D saved it directly; no separate Save sheet was observed for that action. Both were subsequently verified in Vault.

Clicking Latin in the map navigated the currently selected Graphene tab to Latin and left Threads. Reopening Threads showed the selected ancestor path. Resume from Here on Carbon created an additional Carbon root tab with a Latin child. Later opening Graphene from the thread list reused that resumed Carbon tab, so later sidebar labels differ from the original seed. These are observed navigation effects, not evidence of a different seed.

## Check results

`PASS` means observed for the stated criterion. `FAIL (observed)` means the visible result missed the criterion. `FAIL (blocked)` means the exact result could not be verified; it is not a claim that the product implementation is absent.

| Check | Result | Evidence and observation |
|---|---|---|
| Build and launch isolated bundle | PASS | [build.log](build.log); PID/window/profile above; default onboarding completed. |
| Window 1280×820 | PASS | Every PNG is 2560×1640 at 2×; no resize was necessary. |
| Seed ancestry | PASS | [map.png](map.png), [seed-carbon.png](seed-carbon.png): Graphene root, Carbon and Graphite children, Latin grandchild of Carbon. |
| Seed saved paragraphs and Carbon note | PASS | [vault.png](vault.png): both original quotes and **for the intro** are present. Graphene’s ⌘D saved directly rather than showing a second Save step. |
| A: tree columns and depth | PASS | [map.png](map.png): root column 0; Carbon/Graphite column 1; Latin column 2. |
| A: Graphene connector and two child ticks; Carbon connector | PASS | [map.png](map.png): shared Graphene vertical path into Carbon and Graphite, separate Carbon→Latin path. |
| A: full map legibility at target window size | FAIL (observed) | [map.png](map.png): Latin is clipped at the right summary-pane boundary. Large blank summary pane competes with the tree. |
| A: note accent dots, 6pt | PASS | [map.png](map.png): Graphene and Carbon both have dots; measured diameter 12px / 2 = 6pt. |
| A: start-time label above root | PASS | [map.png](map.png): **Fri 06:21** above root column. Clock/timezone correctness was not independently checked. |
| A: no node timestamps; no zoom control | PASS | [map.png](map.png): neither is visible. The thread-list summary has duration, distinct from map nodes. |
| A: selected grandchild ancestor path | PASS | [map-selected.png](map-selected.png): both Graphene→Carbon and Carbon→Latin segments are accent-colored after reopening Threads. |
| A: selection stays in map after click | FAIL (observed) | Click navigates current tab and exits Threads. `map-selected.png` required reopening Threads; it is not the immediate post-click screen. |
| A: Resume from Here | PASS | Carbon context menu exposed **Resume from Here**. [map-resumed.png](map-resumed.png) is the map reopened after resume, with Carbon selected. |
| A: resumed Today tabs, child indentation | PASS | [map-resumed-sidebar.png](map-resumed-sidebar.png): new Carbon and Latin tabs, Latin one level indented with connector. Today category is exposed by accessibility, though no literal Today heading is visible. Existing tabs are retained. |
| A: List depth indentation | PASS | [map-list.png](map-list.png): Graphene, Carbon, Latin, Graphite depths are 0,1,2,1. |
| A: 180pt column / 40pt row pitch | PASS | [map.png](map.png), raster measurements below. |
| B: saved Graphene paragraph marked in accent tint | PASS | [mark.png](mark.png): full opening paragraph has lavender accent marks. Same visual family as citation marks in `ask-click.png`. |
| B: exact sentence selection | FAIL (blocked) | Coordinate drag returned `windowNotFoundAtPosition`. Keyboard attempt did not narrow the paragraph. **No `selection-bar.png` was fabricated.** |
| B: floating selection card contents, placement, height, page scheme | PASS | Supplemental [selection-bar-paragraph.png](selection-bar-paragraph.png): actual paragraph selection; **Save ⌘D**, **Note**, **Ask**, no brand name; light card above selection; approximately 36pt tall. Exact sentence state remains blocked separately. |
| B: Note editor, type test, Save note | PASS | [note-editor.png](note-editor.png) before saving, with **test** entered. [vault.png](vault.png) confirms persisted note text. This is attached to the selected paragraph, not a single sentence. |
| B: hover mark margin dot | FAIL (blocked) | API has no pointer-only move. Skipped; no `margin-dot.png`. |
| B: Vault list rather than grid | PASS | [vault.png](vault.png): three vertically stacked notes. |
| B: serif quote and left rule; note underneath | PASS | [vault.png](vault.png): quotes serif; note text sans below, including **test** and **for the intro**. |
| B: favicon/title/space/relative date provenance | PASS | [vault.png](vault.png): Wikipedia W, title, Research, relative ages. |
| B: no hairlines between Vault rows | PASS | [vault.png](vault.png): whitespace separates rows; only quote rules within note content. Library-bar divider is a separate F failure. |
| B: first quote opens page at mark | PASS | [vault-open.png](vault-open.png): clicked technical paragraph is marked, with page scrolled to center that passage. |
| B: By page depth-1 hairline tree | PASS | [vault-by-page.png](vault-by-page.png): Graphene group has two notes, Carbon one, with depth-1 connectors. |
| B: selected-row bar actions | PASS | [vault-by-page.png](vault-by-page.png): pencil/trash/copy/board glyphs. Accessibility labels: **Edit note**, **Delete note**, **Copy as Markdown**, **Add to Board**. |
| C: requested question and claim chips | PASS | [ask-answer.png](ask-answer.png): 130 GPa and Geim/Novoselov in 2004, chips 1 and 2 respectively. An extra Source 1 preamble and combined source row also appear. |
| C: tensile mark is infobox row only | FAIL (blocked) | Accessibility showed marker 1 in the Tensile strength cell, but the infobox was hidden behind Ask. Clicking chip scrolls while leaving panel over it. Closing Ask removes marks; [ask-tensile-closed.png](ask-tensile-closed.png) records that limitation, **not proof of row-only highlighting**. |
| C: isolation claim marks 2004 sentence | PASS | [ask-answer.png](ask-answer.png), [ask-click.png](ask-click.png): marking begins at **In 2004** and extends through **adhesive tape**, leaving earlier 1947/1987 and following 2010 text unmarked. Portions remain under the panel. |
| C: isolation click active tint and vertical centering | PASS | [ask-click.png](ask-click.png): marked sentence moves to approximately mid-height and uses active tint. |
| C: sentence centered in uncovered page | FAIL (observed) | [ask-click.png](ask-click.png): right ends of the first two marked lines remain covered by Ask. Vertical centering alone does not satisfy the uncovered-page requirement. |
| C: chip help texts | PASS | Recorded verbatim below from accessibility. No hover-only substitute used. |
| C: exact new-chat empty-state line | PASS | [ask-empty-new.png](ask-empty-new.png), after New chat: **Attach a page with @ or ask about this one.** It is the sole conversation empty-state sentence; source/composer controls remain. |
| D: empty lattice and exact copy | PASS | [board-empty.png](board-empty.png): **Drop tabs, notes and quotes here.** |
| D: two page cards with favicon/title/host/thumbnail | PASS | [board-cards.png](board-cards.png). Used Add link for selected Graphene page, selected original Carbon tab, returned to Board, Add link again. Add link adds the selected page directly, with no URL entry sheet. |
| D: Graphene right-edge → Carbon left-edge connector | PASS | [board-cards.png](board-cards.png): very faint horizontal segment. Raster check found a continuous 40px sample at y=346 between the card edges. Initial visual judgment missed it; pixel inspection corrected that judgment. |
| D: cards snap to 28pt cells | FAIL (blocked) | Horizontal card pitch is 280pt (10×28), but layout alignment alone does not demonstrate snapping after a move. Coordinate dragging was unavailable. |
| D: move Carbon / connector follows | FAIL (blocked) | Drag API failure; Add note fallback did not move Carbon. [board-add-note-comparison.png](board-add-note-comparison.png) is explicitly comparison evidence, not `board-moved.png`. Connector-follow behavior unverified. |
| D: Add note comparison layout | FAIL (observed) | [board-add-note-comparison.png](board-add-note-comparison.png): new note overlaps Carbon’s right edge. |
| D: Vault → Add to Board gives serif quote card/rule/provenance | FAIL (observed) | [board-quote.png](board-quote.png): selected **test** note was added through Vault bar, count grew to 4, but resulting item is a Graphene **page card with thumbnail**, not a quote card. No quote, quote rule, note text, or full provenance line. |
| D: delete original Graphene card and its connector | PASS | [board-deleted.png](board-deleted.png): original left Graphene card gone, count 4→3, x=1044…1083/y=346 connector sample gone. A different connection to the extra Graphene page card remains; do not read this as all connectors disappearing. |
| E: disconnected fallback and read-only bar line | PASS | [mail-disconnected.png](mail-disconnected.png): exact **Read-only. Graphene never sends mail.**, disabled Connect Gmail, Open Gmail on the web fallback. |
| E: connected rows and threaded conversation | FAIL (blocked) | Fresh profile has no OAuth account. Not attempted; public-pages-only boundary retained. |
| F: no unrelated hairlines | FAIL (observed) | Per-capture inventory below. Repeated bar/sidebar/pane dividers and selected-node outlines violate the stated rule. |
| F: no serif on chrome | FAIL (observed) | Sidebar Vault shelf quote-preview chips use serif in every capture with that shelf. If these are intended as quote content, this is an exception that needs to be explicit. Other labels/buttons are sans. Wikipedia W favicons are branding, not chrome typography. |
| F: lattice only in allowed surfaces | PASS | Across captured states, lattice appears only on Board canvas. None visible in populated Threads/Vault, Ask, annotation editor, Mail, or page chrome. Empty Threads/Vault/new-tab were not separately tested. |

## Measurements and help text

Measurements use original raster coordinates, top-left origin; divide pixels by 2 for points. They measure actual rendered output, not source constants.

- Map Graphene dot bbox: **x1048…1059, y730…741**. Carbon dot bbox: **x1408…1419, y810…821**. Both 12×12px = **6×6pt**. Center differences **360px x / 80px y = 180pt / 40pt**. Latin and Graphite visibly continue the same row rhythm.
- Map node baselines are approximately y720,800,880,960px: **40pt row pitch**. Root/Carbon/Latin favicon origins differ by about 360px: **180pt column pitch**.
- List indentation is approximately **20pt per depth**; visible row spacing approximately **36pt**. The requested 40pt is met by the map, not by list rows.
- Selection card is approximately **420×72px = 210×36pt**, above the paragraph selection. Rounded corners/shadow introduce about 1pt boundary uncertainty.
- Board first two left edges approximately x534 and x1094px: **280pt pitch**. Card widths approximately **250pt**. No claim of drag snapping.
- Board connector sample: x1044…1083 at **y346px**, 40 contiguous pixels with all RGB channels below 0.89 in `board-cards.png` and `board-quote.png`; no such line in `board-deleted.png`.
- Isolation mark spans approximately y826…961px in `ask-click.png`; midpoint ~447pt, near the page’s vertical center. Right side is occluded by Ask beginning at about x1674px (~837pt).

Ask ran with UI status **Apple · on device · Ready**. The source warning was **Page text trimmed to 6,000 characters**. No provider configuration was changed.

Chip help texts observed after answer:

- Source 1 preamble chip: **Behind the Ask panel; scroll to see**.
- Source 1 tensile-strength chip: **Behind the Ask panel; scroll to see**.
- Source 2 isolation chip: **Show in page**.
- Combined Source 1, 2 row: **Behind the Ask panel; scroll to see**.

## Language-rule inventory for every capture

All captures have a thin horizontal line beneath Research in the sidebar and a thin separator beneath the page/library bar. These are neither provenance connectors nor quote rules. Outer window edges and shadows are not counted as hairlines. Website-owned lines are listed separately so they are not misattributed to Graphene’s design system.

| Evidence files | Additional hairlines | Serif on chrome | Lattice |
|---|---|---|---|
| `seed-carbon.png` | Wikipedia title/tab rules and infobox border, website-owned | None observed; W favicon excluded | None |
| `map.png`, `map-selected.png`, `map-resumed.png` | Vertical dividers around tree/summary panes, bottom Saved on this Mac divider, selected-node rounded outline; ancestry paths are permitted | Shelf preview chips serif | None |
| `map-resumed-sidebar.png` | Wikipedia title/tab rules and infobox border | Shelf preview chips serif | None |
| `map-list.png` | Pane dividers, selected Carbon outline, horizontal lines between saved-note excerpts and beneath final note | Shelf preview chips serif; main note excerpts treated as content | None |
| `mark.png`, `selection-bar-paragraph.png`, `note-editor.png`, `vault-open.png` | Wikipedia title/tab rules and infobox border; selection/editor have faint edge/shadow treatment | Shelf preview chips serif; page headings are website-owned | None |
| `vault.png`, `vault-by-page.png` | No note-row separators; quote rules and grouping paths permitted | Shelf preview chips serif; Vault quotations are content | None |
| `ask-empty-new.png`, `ask-answer.png`, `ask-click.png` | Ask header/source-region divider and faint panel edge; Wikipedia content rules/border when visible | Shelf preview chips serif | None |
| `ask-tensile-closed.png` | Wikipedia infobox border; website floating contents button outline | Shelf preview chips serif | None |
| `board-empty.png` | No additional content divider | Shelf preview chips serif | Board canvas only, permitted |
| `board-cards.png`, `board-add-note-comparison.png`, `board-quote.png`, `board-deleted.png` | Faint rounded card outlines; provenance connectors permitted | Shelf preview chips serif; page-card labels sans | Board canvas only, permitted |
| `mail-disconnected.png` | No additional content divider | Shelf preview chips serif | None |

## What still doesn't read as one product

Ordered by visual impact:

1. **Board discards the visible quote treatment when adding a Vault note.** The quote, rule, annotation and provenance become a thumbnail page card. This breaks the strongest visual continuity in the requested system.
2. **Ask hides the evidence it asks the user to inspect.** Isolation is vertically centered but partly covered; the entire tensile target stays behind the panel. “Show in page” overstates the visible outcome.
3. **Threads allocates space poorly.** The small four-node tree is clipped while the right summary pane is mostly empty. Clicking a node also exits the map and overwrites the current tab, making the selected-path state indirect.
4. **Board placement permits overlap and its connectors are too faint to read confidently.** Add note overlaps Carbon; the connection required pixel inspection to distinguish confidently from the lattice.
5. **The surface-wide line rule is not implemented consistently.** Pane dividers, library/header separators, selected-node outlines, and list excerpt separators remain alongside the intended provenance/quote lines.
6. **The serif boundary is ambiguous in the shelf.** Quote previews are serif within sidebar controls, while the rest of chrome is sans. Either explicitly permit quote content there or change the treatment.
7. **Ask includes a redundant Source 1 preamble plus per-claim and combined source chips.** It adds visual noise ahead of a short two-claim answer.

## Build/test tails, errors and cleanup

Build exit **0**, [build.log](build.log):

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.13s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

`swift test` exit **0**, [test.log](test.log):

```text
Test Suite 'GraphenePackageTests.xctest' passed at 2026-09-25 06:36:20.823.
Executed 244 tests, with 3 tests skipped and 0 failures (0 unexpected) in 8.446 (8.467) seconds
Test Suite 'All tests' passed at 2026-09-25 06:36:20.823.
Executed 244 tests, with 3 tests skipped and 0 failures (0 unexpected) in 8.446 (8.469) seconds
```

Skipped: two opt-in real-model answer tests and one opt-in live Wikipedia citation test. These results do not substitute for UI evidence above.

No crash or hang observed. Launch stdout/stderr log was **0 bytes**. No console error appeared there; the system unified log and WebKit developer console were not inspected, so this is not a claim of no errors anywhere.

Computer-use limitations/errors:

- Sentence drag: `windowNotFoundAtPosition((716.5, 984.0))`.
- Board coordinate right-click: `windowNotFoundAtPosition((859.0, 550.0))`.
- Board Graphene container action initially failed because the element was invalidated and multiple matches existed. A fresh full accessibility snapshot and text-node target succeeded; original card deletion was observed.
- No pointer-only move or held-modifier click. Hover margin dot and hover card were skipped. Resume used right-click.
- Exact sentence capture, moved-card capture, and margin-dot capture were omitted rather than mislabeling substitutes.
- A local measurement attempt using Python failed because Pillow was absent; measurements were then made from PNGs using AppKit in a temporary Swift file. No app automation was involved.

Cleanup completed: ⌘Q through computer-use terminated owned PID **40754**; its waiting launch shell returned exit **0**. Removed only `.build/Graphene-verify.app`, then checked that path was absent. No other Graphene process was quit. Fresh test profile and evidence retained. Working tree has only the new evidence directory untracked.
