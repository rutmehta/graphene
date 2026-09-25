# Graphene identity: D6

Status: design spec, September 25, 2026. Builds on `docs/design/arc-look.md` (the Arc base) and only adds; nothing here changes an Arc-look token or geometry. Implementation packages are G1 to G5 at the end. When this file disagrees with existing code, this file wins.

## 1. The thesis

Arc's sidebar organises tabs. Graphene's sidebar can show where tabs came from, because every tab already carries `parentTabID`, every visit carries `parentNodeID` and a `threadID`, and every Vault note carries its source page. Arc cannot draw any of that. So the identity is not a colour or a font. It is provenance made visible, in the sidebar, on the new-tab page, in the chat panel and in the Vault, using the Arc grammar without breaking it.

Five rules keep it from turning into a dashboard:

1. **Provenance is drawn with hairlines and indents, never with boxes, badges or colour.** A thread should read like an outline, not a chart.
2. **Nothing new is permanent.** Every identity element appears only when there is data for it. An empty space looks exactly like Arc.
3. **One material, used twice.** The graphite neutral family is the default chrome and the only new colour idea. Arc pastels stay available as presets.
4. **Type carries hierarchy.** Thread rows are the same 13pt rows as tabs; the provenance line is what tells them apart.
5. **The page stays the bright plane.** No new chrome inside the page card except the Ask highlight, which is page content by design.

## 2. Tokens added to `Theme.swift`

| Token | Value | Use |
|---|---|---|
| `ShellLayout.threadIndent` | 20 | Per-depth indent for child rows in Today (same as `folderIndent`) |
| `ShellLayout.threadLineInset` | 17 | x of the vertical hairline from the row's leading edge (centre of the 20pt icon slot minus half a hairline) |
| `ShellLayout.threadMaxDepth` | 3 | Deeper rows clamp to depth 3 and keep drawing the line |
| `ShellLayout.shelfHeight` | 44 | Vault shelf row above the footer |
| `ShellLayout.shelfChipWidth` | 96 | |
| `ShellLayout.shelfChipRadius` | 8 | |
| `ShellLayout.newTabColumnWidth` | 560 | Content column on the new-tab page |
| `ShellLayout.newTabGap` | 24 | Between new-tab sections |
| `ShellLayout.latticeCell` | 28 | Hex lattice cell size for empty states |
| `Palette.threadLine` | `ink` at 18% dark, 24% light | The connector hairline |
| `Palette.threadLineActive` | `accent` at 60% | The connector on the selected row's branch |
| `Palette.highlight` | `accent` at 22% | In-page Ask citation highlight (injected as CSS) |
| `Palette.highlightActive` | `accent` at 38% | Hovered or selected citation |
| `Palette.lattice` | `ink` at 4% | Empty-state lattice strokes |
| `SpaceColor.graphite` | preset, hue 232°, saturation 0.12 | New default preset; see 3.2 |

`SpaceColor.slate` stays neutral at saturation 0 for people who want pure grey.

## 3. Features

### 3.1 Provenance in the Today list (G1)

**What it is.** Today tabs that were opened from another Today tab are drawn as that tab's children: indented `threadIndent` per depth and joined to the parent by a vertical hairline running down the icon column, with a short horizontal tick into each child's icon. Depth is computed by `ThreadBranch.rows(ids:parents:)` over `Tab.parentTabID`, restricted to Today tabs in the current space, exactly as Threads already does for visits. Pinned tabs and favorites never participate.

**Drawing.** The connector is one path per parent: a 1pt `threadLine` vertical from the bottom of the parent's icon slot to the centre of the last child's icon slot, at x = `threadLineInset` relative to the parent's row leading edge, plus a horizontal tick at each child's icon centre that runs `threadTick` (11pt) from the vertical to the child's icon slot edge. When the selected tab is in the branch, the whole branch's connector uses `threadLineActive`. No dots, no arrows, no chevrons. Rows keep `rowHeight`, `rowPitch`, hover and selection exactly as in the Arc look; only `padding.leading` grows by `depth × threadIndent`, capped at `threadMaxDepth`.

**Ordering.** Today keeps its current ordering rule (newest at the top of its section) for roots. Children are listed directly under their parent, oldest first, so a research branch reads top-down. Drag reorder of a child moves it to the drop position and clears `parentTabID` (it becomes a root); dropping a tab onto another Today row's icon slot sets it as that row's child. Closing a parent promotes its children to roots at the parent's position (no orphan gap). Archiving a parent archives the whole branch with a single Undo toast ("Archived 4 tabs").

**Behaviour when it does not apply.** A space with no child tabs renders pixel-identical to the Arc look. Tabs restored from an archive or session keep their `parentTabID` only if the parent is also present; otherwise they are roots.

**Context menu.** Today rows gain "Close branch" (when the row has children) and "Detach from parent" (when it is a child). Nothing else changes.

**Keyboard.** `⌥←`/`⌥→` on a selected Today row collapse or expand that branch (collapsed branches show a `label`-type count "3" at the trailing edge in `ink3`; children hide; state is per tab, not persisted).

**Acceptance.** Open A, ⌘-click two links from A, one link from the second child: the sidebar shows A, then an indented pair, then a doubly indented row, with one continuous hairline from A's icon to the last child. Close the first child: its child becomes A's child at the same position. Drag the deepest row above A: it becomes a root and the line shortens. Space with no branches: identical capture to the Arc-look main capture.

### 3.2 Graphite chrome (G2)

**What it is.** A new default preset, `graphite`: hue 232°, saturation 0.12, so the flooded gradient reads as a warm-cool graphite rather than a colour, with the accent still derived from the hue. Onboarding's three swatches become Graphite, Iris and Tide, Graphite selected. Existing profiles keep whatever they have.

**Derivation.** No change to the `Palette` formulas. With s = 0.12, s′ = 0.56; dark `chromeTop` is HSB(232°, 0.46, 0.15) and light `chromeTop` is HSB(232°, 0.12, 0.95). The accent at HSB(232°, 0.45, 0.85) dark is a soft steel blue, which is the one colour a graphite space shows. Reviewers should confirm `inkContrast ≥ 4.5` in both schemes (add the preset to `VisualPaletteTests`).

**Where graphite shows.** Nowhere else. It is a preset, not a mode. The point is that a Graphene screenshot defaults to something no Arc space looks like, while every Arc pastel remains one click away.

**Acceptance.** Fresh profile, default onboarding: the main window's sidebar samples in-process are within 6 per channel of HSB(232°, 0.46, 0.15) at the top in dark and HSB(232°, 0.12, 0.95) in light. Space editor still offers all six presets and custom hue.

### 3.3 Resume page (G3)

**What it is.** The new-tab page becomes the place a thread is picked up. It replaces `NewTabView` and keeps its accessibility identifiers. Content column `newTabColumnWidth` centred, `newTabGap` between sections, all on `pageBg`, all type from `ShellType`, all rows `rowHeight`. Sections appear only when non-empty, in this order:

1. **Search field** as today: one `fill` row with the search glyph, placeholder "Search or enter a URL", ⌘T chip. It focuses on appearance so typing goes straight in (same as the command bar's "new tab" mode; if focus cannot be given reliably, the page opens the command bar on first keystroke).
2. **Continue** (label): up to three threads from `app.currentThreads` for this space, each row: favicon of the thread's first host, thread title in `row` `ink`, then in `secondary` `ink3` the visit count and the relative time ("6 pages · 2h ago"). A trailing "Resume" hint in `label` `ink3` on hover. Clicking resumes the thread (existing `openThread`).
3. **Saved here** (label): up to four Vault notes whose `spaceID` matches, newest first: quote text in `row` `ink2` on one line, source title in `secondary` `ink3`. Clicking opens the source page and scrolls to the highlight (existing `annotate.js` highlight by text match).
4. **Pinned in this space** appears only when the sidebar is collapsed: the space's favorites as a row of `favoriteHeight` tiles, so the page is usable without the sidebar.

Nothing else. No weather, no wallpapers, no shortcuts grid. When every section is empty the page shows the search field and, below it, the lattice empty state from 3.6 with the line "Open a page and Graphene will keep the thread." in `secondary` `ink3`.

**Acceptance.** Fresh profile: search field plus lattice only. After visiting four pages in two threads and saving one note: Continue shows two rows with correct counts; Saved here shows the note; clicking it opens the page with the passage highlighted. Sidebar collapsed: the favorites row appears; expanded: it does not.

### 3.4 Ask that points at the page (G4)

**What it is.** When a chat answer cites a source that is the current page (or an open tab), the cited passage is highlighted in the page itself, and the citation chip in the chat panel is linked to it.

**Data.** Citations already carry the source (`KnowledgeSource`) and the quoted text. G4 adds `passage: String?` to the citation (the exact excerpt the model was given, from the request builder's source budget) and a stable `citationID`.

**In the page.** A new `Resources/cite.js` finds the passage with a normalised text search over the document (whitespace-collapsed, case-insensitive, first match), wraps it with `<mark data-graphene-cite="ID">`, and applies injected CSS: background `highlight`, no border, `border-radius: 2px`, `padding: 0 1px`; hovered or active uses `highlightActive`. Marks are removed when the chat panel closes or the answer is regenerated. If the passage is not found, nothing is drawn and the chip is not linked (never highlight an approximate match). When the model writes no `[n]` for a sentence, a finished answer falls back to the attached source sentence sharing the most content words with it (stop words ignored; at least 60% of the sentence's content words and at least 3); that passage becomes the citation's, with the chip drawn after the matched sentence. Explicit markers always win; "No sources" shows only when nothing matched.

**Passages and numbering (G8).** Each cited sentence gets its own passage: the shortest segment of the source (split at sentence ends, newlines and table cells) that holds the claim's content words. A sentence of 8–40 words wins a tie with a table fragment; a passage never exceeds 40 words; when the words only exist in a table row (an infobox), the passage is that row alone, cut from the captured text as the densest short run of words holding them. Numbering is per source: every chip citing one source shows that source's number, and sources are numbered in order of first mention in the answer. Each distinct passage is still its own citation with its own id and page mark, so hovering or clicking a chip goes to that chip's own passage even when several chips read "1"; claims of one source that land on the same passage share a citation. A marker on a restated source label ("Source [1]: Graphene - Wikipedia") joins that source's first passage. The sources line under the answer lists each source once with its single number ("1 Graphene - Wikipedia"); clicking it goes to the source's first passage.

**Quotes in the answer.** The serif quote block (`quote` face beside the `quoteRule`) is for explicit excerpts only: text wholly inside quotation marks whose words the source holds verbatim, a `>` block, or a single sentence of at least 8 words that appears word for word in a cited passage. Sharing a run of words with a passage is not enough. Quotes are taken in reading order only while together they stay within 40% of the answer's words, so a quote always has prose around it; an entire answer is never set as a quote. A chip after an answer's last sentence stays on that sentence's line: a line of chips alone joins the line before it, and a chip wraps with the word before it.

**In the chat panel.** Citation chips are 24pt `elevFill` chips with the source's favicon and a short title, as today. A linked chip gains a `label`-type index ("1", "2") that matches a superscript at the start of the mark in the page (`::before` content of the index, `caption` size, `accent`). Hovering the chip scrolls the page smoothly to the mark and sets it active; clicking the chip focuses the page there. Hovering the mark in the page raises the chip to the active state. For a cited source that is another open tab, hover shows the existing tab preview and click switches tabs, then highlights.

**Rules.** Only passages the model actually received are eligible; never highlight from the model's own paraphrase. Private windows do not inject. Sites with `contenteditable` bodies (editors, mail composers) are skipped.

**Acceptance.** Ask "what is the tensile strength?" on the Wikipedia Graphene page: the answer's citation chip "1" links to a highlighted passage containing "130 GPa"; hover the chip scrolls to it; close the panel and the mark is gone. Ask something the page does not contain: no marks.

### 3.5 Vault shelf (G5)

**What it is.** A single row above the sidebar footer, `shelfHeight` tall, present only when the current space has Vault notes: the last four saves as chips of `shelfChipWidth × 32`, `shelfChipRadius`, `fill` background, the note's source favicon at 12 (6pt padding, 4pt gap) and the first words of the quote in `caption` `ink2` on one line, starting at its first content word (leading "the", "a", "an", "on", "in", "of", "at", "to" are skipped), truncated. A 16pt `tray` glyph button (accessibility label "Vault") at the leading edge in `ink3` opens the Vault view. Hover shows the full quote in a `TabPreview`-style card. Drag a chip out to drop the note as Markdown into any app or into the chat panel (existing drop support). Clicking a chip opens the source page and highlights the passage (as 3.3).

**Rules.** The shelf never scrolls. Chips are 72 to 96pt wide; it shows as many as fit after the 22pt Vault glyph and gap, up to four (two at the default 224pt sidebar, three from 250pt of content width, four from 328). It is hidden while the archive view is open and in private windows. It shifts the Today list up by `shelfHeight`; it does not overlay it.

**Acceptance.** Save two selections with ⌘D on two pages: two chips appear with the right favicons and quotes; clicking one opens its page and highlights; hovering shows the full quote. Delete both notes in Vault: the shelf disappears and the footer geometry is back to the Arc look.

### 3.6 Lattice, sparingly (part of G3)

**What it is.** A hexagonal lattice, `latticeCell` wide cells, 1pt `lattice` strokes, drawn with `Canvas`, fading to transparent over its bottom third. It appears in exactly three places: the empty new-tab page (3.3), the empty Threads view, and the empty Vault view. It never appears in chrome, behind rows, or behind content. Reduce Transparency removes it. It is the only nod to the name, and it is invisible the moment the product has data.

## 4. Motion

Reuses the `Motion` table from the Arc look. Additions:

| Interaction | Animation |
|---|---|
| Branch collapse/expand | rows slide 8pt and fade, easeOut 160ms; connector path animates its length |
| Citation scroll | `scrollIntoView({behavior: "smooth", block: "center"})`, mark fades in 200ms |
| Shelf appear/disappear | height 0→44 with easeOut 180ms; chips fade |
| Reduce Motion | all become 120ms fades |

## 5. Removals

None. D6 adds only. If G1 makes the "Threads" library view's list redundant for the current space, leave the view alone in D6 and note it for later.

## 6. Acceptance for the whole package

Verified on the real app by the Codex brief in `docs/design/codex/verify-identity.md` (to be written from the per-feature acceptance lines above, same capture method as `verify-arc-look.md`), plus:

1. A fresh profile's main capture is pixel-identical to the Arc-look capture except for the graphite colour.
2. `swift test` green with new tests for `ThreadBranch` over tabs (promotion on close, root on drag), citation passage matching, shelf visibility, graphite palette contrast, and resume-page section rules.
3. No new literal font sizes, radii or opacities in UI files (existing grep gate).

## 7. Packages

All five can run in parallel worktrees from master; G3 and G5 both touch Vault opening-with-highlight, so G3 owns `cite.js`'s "highlight by text" entry point and G5 calls it.

- **G1 Provenance rows.** `UI/Sidebar.swift` (rows, connector canvas, drag rules, context menu, keyboard), `App/AppState.swift` (close/archive promotion, parent assignment on drop), `Model/TabLifecycle.swift` if archive touches it, tests.
- **G2 Graphite preset.** `UI/Theme.swift` (`SpaceColor.graphite`), `UI/OnboardingView.swift` swatches, `UI/SpaceEditor.swift` if presets are listed there, `VisualPaletteTests`.
- **G3 Resume page and lattice.** New `UI/ResumePage.swift` replacing `NewTabView`, new `UI/Lattice.swift`, `Resources/cite.js` (shared with G4: passage find, highlight, scroll), empty states in `UI/SurfaceState.swift` (this also clears its remaining font literals), tests.
- **G4 Ask citations in the page.** `Intelligence/ChatSession.swift` and `PageContext.swift` (passage plumbing), `Web/WKWebEngine.swift` (inject `cite.js`, message handlers), `UI/ChatView.swift` (linked chips, hover sync), tests.
- **G5 Vault shelf.** `UI/Sidebar.swift` (shelf above the footer; coordinate with G1 by keeping the shelf in its own view file `UI/VaultShelf.swift` and one insertion line in the sidebar), `Store/Vault.swift` accessors, drag-out, tests.

Order if serial: G2, G1, G3, G5, G4.
