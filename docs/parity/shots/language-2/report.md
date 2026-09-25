# Graphene design-language verification — Threads and Board

Verified on 2026-09-25 through the real macOS app. **Threads largely passes; Board fails connector visibility and quote provenance visibility.** This is an observation report, not an implementation change.

## Run identity and isolation

- HEAD before and after: `ddd64b067ad100dc068d8d78f07be4aff4ac5a54`.
- Initial `git status --short`: empty (clean). Final: only `?? docs/parity/shots/language-2/`.
- Build: `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`.
- Owned PID: **52466**. App launched directly with `GRAPHENE_DATA_DIR=/tmp/graphene-language-verify-2`, backgrounded inside a shell retained by `wait`. That directory did not exist before launch.
- Default onboarding: Sidebar (Arc), Graphite color, Start browsing. No import or default-browser change.
- Window: **1280 × 820 pt**; all seven PNGs are **2560 × 1640 px**, Retina 2×. No resize was necessary.
- `swift scripts/window-id.swift -p 52466` initially returned onboarding sheet ID `10293`; after onboarding the valid app window ID was **10292**. The first capture against the expired sheet ID failed and produced no PNG. All evidence below uses `10292`.
- All app interactions used computer use. No debug environment, debug command driver, injected scripts, or delegated work. Shell use was limited to build/tests, file work, the requested PID/window helper and launch lifecycle, and `screencapture`.
- `~/Applications/Graphene.app` was not touched. No other Graphene process was quit.

## Evidence and checks

Every PNG was captured using `screencapture -l 10292 -o -x`, checked with `sips`, and opened for visual inspection. Dimensions are also recorded in [png-verification.txt](png-verification.txt). Coordinates below refer to original PNG pixels; divide by two for points. Approximate visual bounds are marked ≈. Source tokens corroborate the layout sizes but are not substituted for rendered evidence.

| Check | Status | Observed result / evidence |
|---|---|---|
| Isolated build and launch | PASS | PID 52466; default onboarding; requested app path and fresh data directory. [build.log](build.log), [pid.txt](pid.txt). |
| 1280 × 820 window and PNG verification | PASS | Seven valid 2560 × 1640 PNGs, all viewed. [png-verification.txt](png-verification.txt). |
| Graphene → Carbon and Graphite via link context menu | PASS | Both created child tabs through “Open Link in New Window.” In this app this action creates tabs, not separate native windows. [map.png](map.png). |
| Carbon → one grandchild via link context menu | PASS | Chemical element created as Carbon's child. [map.png](map.png). |
| Save Graphene opening paragraph | PASS | Triple-click produced the full opening-paragraph selection; quote later appeared in Vault. The exact requested final Save click was not observed for this paragraph: it was already saved after the combined triple-click/⌘D interaction. See deviations below. |
| Save Carbon paragraph with “for the intro” | PASS | Triple-click → ⌘D opened Save to Vault; entered exact note and clicked Save to Vault. Vault subsequently showed quote and note; Board AX text retained both. [board-quote.png](board-quote.png) shows the quote's beginning. |
| A: thread list 260 pt | PASS | Rendered list region x≈448–968 (520 px); search/row backing x≈464–952 (244 pt plus 8 pt inset on each side). `ShellLayout.threadListWidth = 260` corroborates. [map.png](map.png). |
| A: one 44 pt header below library bar | PASS | Single title/counts/Continue browsing row; y≈80–168 (88 px). `threadHeaderHeight = 44` corroborates. [map.png](map.png). |
| A: title, counts, Continue browsing | PASS | “Graphene - Wikipedia”, “4 pages · 1 site · 3 notes”, Continue browsing all visible. Three notes include the accidental extra seed described below. [map.png](map.png). |
| A: tree directly below header | PASS | Tree/date region follows header with normal internal padding; no second summary/header block. [map.png](map.png). |
| A: no empty summary column | PASS | Tree uses remaining width before summary action. [map.png](map.png). |
| A: summary action is library-bar glyph | PASS | Glyph exposed as “Summarize thread” in AX; no text summary button occupying a separate pane. [map.png](map.png). |
| A: no vertical pane dividers | PASS | No vertical divider between list and map. Outer rounded surface boundary remains. [map.png](map.png). |
| A: deepest node fully visible | PASS | Chemical element node, favicon and host fit before right edge. Title uses ellipsis, so this is a pass for node bounds, not full title text. [map.png](map.png). |
| A: single click stays in Threads | PASS | Chemical element selected without opening page. [map-selected.png](map-selected.png). |
| A: ancestor path accent | PASS | Graphene → Carbon → Chemical element path turns muted indigo; Graphite branch stays gray. [map-selected.png](map-selected.png). |
| A: selected node filled, no outline | PASS | Light gray rounded fill; no selection stroke. [map-selected.png](map-selected.png). |
| A: double click opens in current tab | PASS | Chemical element opened in former Carbon tab; same tab ID `6A1B0479-D671-4A64-80BE-2CDA43B1473B`, four tabs remained. Existing grandchild tab remained separate. [map-open.png](map-open.png). |
| A: summary column appears / refusal captured | PASS | Column appears on right with exact response: “The attached sources don't cover this.” No useful summary generated. [map-summary.png](map-summary.png). |
| A: map remains readable with summary open (additional observation) | FAIL (observed) | Right column clips deepest node and host around x≈1880 px; horizontal scrolling exists in AX but initial summary state is clipped. [map-summary.png](map-summary.png). |
| D: Graphene then Carbon in first free cells | PASS | Clean Personal Board: Graphene first, Carbon second. Both titles verified in UI. [board-cards.png](board-cards.png). Space deviation below. |
| D: two link cards do not overlap | PASS | Graphene x≈478–978; Carbon x≈1038–1538; 60 px / 30 pt clear horizontal gap. Both y≈130–564. [board-cards.png](board-cards.png). |
| D: clearly visible connector | FAIL (observed) | Connector exists, but is too faint to read clearly against white/hexagon canvas; measured ≈1.33:1 against adjacent canvas. Details below. [board-cards.png](board-cards.png). |
| D: Add note uses next free cell without overlap | PASS | Third card to right, x≈1598–2042, y≈130–418, again 60 px / 30 pt gap from Carbon. [board-note.png](board-note.png). |
| D: Vault selected Carbon → Add to Board | PASS | Carbon note selected; exact Add to Board toolbar action used; Personal Board count changed 3 → 4. [board-quote.png](board-quote.png). |
| D: quote is a quote card, not page card | PASS | Serif quotation text with left rule, no page-thumbnail layout. [board-quote.png](board-quote.png). |
| D: serif quote and left rule | PASS | Both visible in fourth card x≈1570–2070, y≈470–806; rule x≈1592. [board-quote.png](board-quote.png). |
| D: visible provenance line | FAIL (observed) | Long quote is clipped at bottom of fixed-height card; note and provenance are below visible bounds. AX includes “for the intro Carbon - Wikipedia · en.wikipedia.org”, but screenshot does not show them. AX presence is not a visual pass. [board-quote.png](board-quote.png). |
| Pointer-only hover, held-modifier clicks, card drag/resize | FAIL (blocked) | Skipped as instructed: API does not offer pointer-only movement or held-modifier clicks; coordinate input failed in this run. No alternate state is claimed as their evidence. |
| Cleanup | PASS | Quit through computer-use ⌘Q; owned launch shell exited 0; PID no longer present; verification bundle removed. No commit/stash/source edits. |

## Measurements

The Board connector crosses the 30 pt gap at y≈346–347 px (≈173 pt). At pixel **(1000,346)** its RGB is **(219,219,220)**. Adjacent canvas at **(1000,344)** and **(1000,350)** is **(250,250,250)**; unobstructed white canvas at **(1600,800)** is **(255,255,255)**. Relative-luminance contrast is **1.326:1** against the local canvas and **1.384:1** against white. The connector's darkest horizontal row across x=990…1025 is predominantly (219,219,220), with nearby pixels (218,218,219)/(217,217,218). It is slightly darker than the hex grid but reads as another hairline, not a clear relationship.

The requested baseline map fits. Opening the summary consumes roughly the rightmost 320 pt and visibly truncates the deepest node. The selected node fill and accent ancestry are visible in the separate selected-state capture, before the summary is opened.

The quote card is roughly **250 × 168 pt**. Its text continues below the clipped lower edge; the full opening paragraph plus annotation and provenance cannot fit at the observed serif size. No resize was attempted to conceal that default-state failure.

## What still doesn't read as one product

Ordered by visual impact:

1. **Quote cards cut off the content that makes them useful.** The quotation ends mid-line, and both the user's annotation and source attribution disappear. The card has the right typography but fails as a readable saved object.
2. **Board relationships are nearly invisible.** The 1.33:1 connector competes with the decorative hex grid. Threads uses a legible accent path for relationships; Board looks like disconnected cards.
3. **Opening a summary breaks the map's fit.** A one-line refusal occupies a large blank column while the selected deepest node is clipped. The baseline layout is substantially better than the summary state.
4. **Page-card thumbnails are inconsistent.** Graphene's thumbnail includes an old Wikipedia hover preview; Carbon remains a blank light-gray placeholder throughout Board captures. Title/host are visible, but the cards do not look equally complete.
5. **Action semantics are hard to predict.** “Open Link in New Window” creates a child tab; “Add link” silently adds the last current page without a picker; clicking the Carbon Vault row also opened its page before returning to the selected row and toolbar. These transitions make the library feel less coherent despite shared glyph styling.

## Seed and execution deviations

- A Wikipedia Graphite hover preview overlapped the Graphene paragraph. One attempted AX triple-click hit the preview and navigated the original tab to Graphite. ⌘D saved an extra short “Graphite” passage associated with the Graphene source. Back restored Graphene; a triple-click on its exposed first text segment then selected the full opening paragraph and it was saved. The extra Vault item was retained. Thus the map reports **3 notes**, not 2.
- The earlier progress statement that ⌘D generally saves immediately was too broad. The later Carbon interaction visibly opened the Save to Vault sheet and required Save. The Graphene interaction's precise save timing was not isolated; only the final saved quote was verified.
- After double-clicking the map grandchild, the current page was Chemical element. The first Board Add link inserted it immediately. Clear was opened but **canceled**, and Undo had no observed effect. To obtain the requested two-card state without deleting data, Board tests continued in the unused **Personal** space. Research Board retains that unintended single card. Personal Board has exactly the requested two links, added note, and Carbon quote. Vault is shared across spaces, so the original Research Carbon note was added to Personal Board.
- A fast typed Carbon URL became a malformed public Google query. After observing that, the command bar was focused in a separate step and the exact URL was pasted; Carbon was visibly loaded before adding its card. No private page was visited.
- Two coordinate-click attempts failed with computer-use `windowNotFoundAtPosition` errors; they did not provide evidence of app interaction. AX-targeted clicks/triple-clicks/double-clicks were used successfully. One AX refresh returned `AXError.failure`; the next refresh showed the expected Library popover. No scripted UI workaround was used.

## Build and test tails

[build.log](build.log):

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.13s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

[test.log](test.log):

```text
Test Suite 'GraphenePackageTests.xctest' passed at 2026-09-25 06:52:00.935.
Executed 254 tests, with 3 tests skipped and 0 failures (0 unexpected) in 6.852 (6.873) seconds
Test Suite 'All tests' passed at 2026-09-25 06:52:00.935.
Executed 254 tests, with 3 tests skipped and 0 failures (0 unexpected) in 6.852 (6.874) seconds
Testing Library Version: 1501
Target Platform: arm64e-apple-macos14.0
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Passing tests do not override the visual failures above.

## Crashes, hangs, console, cleanup

No app crash or sustained hang was observed. The app remained responsive through the final Board state and quit normally. [console.log](console.log) contains a **31-line WebKit navigation-policy stack trace**, beginning `WebKit::WebFramePolicyListenerProxy::ignore(WebKit::WasNavigationIntercepted)` and ending `Graphene_main`. It has no accompanying explicit error message; its cause is not established. Therefore the run is not described as console-clean. No separate web developer console was inspected.

Owned PID 52466 was quit via computer-use ⌘Q. The shell that retained it completed with exit code 0, and `ps -p 52466` returned no process. `.build/Graphene-verify.app` was removed and absence checked. An initial `rm -rf` cleanup command was rejected by the shell safety guard before execution; the safer `rm -r` command succeeded. Fresh data at `/tmp/graphene-language-verify-2` is retained for inspection. Only evidence files were added to the checkout; HEAD is unchanged.
