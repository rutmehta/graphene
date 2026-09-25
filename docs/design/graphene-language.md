# Graphene design language

Status: design spec, September 25, 2026. This is the identity layer on top of `docs/design/arc-look.md`, which stays the base grammar (chrome, sidebar tiers, page card, command bar, type scale, motion). `docs/design/graphene-identity.md` (D6) holds the first five build packages; this document is the language they belong to and adds the surfaces D6 left out: the navigation graph, annotations, the AI panel, Board and Mail. The companion artifact renders each surface from the same tokens.

## 1. The idea in one line

Arc is a beautiful container for pages. Graphene is a container that remembers how the pages relate. Everything Graphene adds to the Arc base is one visual primitive applied consistently: **the thread**, a 1pt hairline that joins things that came from each other.

The thread is the only new drawing. It joins a child tab to its parent in the sidebar, a visit to its predecessor in the map, a citation to the passage it came from, a Vault note to the page it was cut from, a Board card to the page it embeds. When you see a hairline in Graphene, it always means "this came from that." Nothing decorative is ever drawn with a line.

## 2. Material

**Graphite.** The default space colour is a graphite neutral (hue 232°, saturation 0.12): dark chrome is warm-cool charcoal, light chrome is a faint blue-grey, and the accent derived from the same hue is a soft steel blue. That single accent is the only colour Graphene owns. Space presets add Arc's pastels as choices, never as the default.

**Two textures, both quiet.** The Arc grain (2%) on chrome, and the hex lattice (4% ink, 28pt cells) in exactly four places: empty new-tab page, empty Threads, empty Vault, and the Board canvas where a grid earns its keep. The lattice fades to nothing across its bottom third. It never sits behind rows, text or chrome.

**Two inks.** `ink` for content, `ink2` for secondary rows, `ink3` for glyphs and metadata, exactly as the Arc look. Provenance lines are `threadLine` (ink at 18% dark, 14% light), and the branch that contains the selection turns `threadLineActive` (accent 60%). Highlights in a page are `highlight` (accent 22%) and `highlightActive` (accent 38%).

**Cards only where a thing is separate.** A page card, a chat panel, a Board card, a Peek. Quotes, notes, thread rows and mail rows are rows, not cards.

## 3. Type

System sans (SF Pro) for chrome at the Arc scale: 11 label, 12 secondary, 13 row, 15 title, 18 input. One addition:

**Quoted page text is set in the system serif (New York) at 13/1.45.** A Vault note, a highlighted passage echoed in the chat panel, a snippet under a thread node, a Board text card that was clipped from a page: all serif. Chrome that talks about pages is sans; text that came from pages is serif. That one rule tells the reader what is theirs and what is the web's, and it's the only place a second face appears. Reader mode keeps its own reading face unchanged.

Numbers that cross surfaces (citation indices, branch counts) are `label` 11 semibold, tabular.

## 4. Tokens

All in `Theme.swift`, in addition to D6 section 2.

| Token | Value | Use |
|---|---|---|
| `ShellType.quote` | New York 13 regular, line height 1.45 | Page text quoted anywhere in chrome |
| `ShellType.quoteSmall` | New York 12 regular | Snippets, shelf chips |
| `ShellLayout.threadNodeSize` | 20 | Map node: favicon 16 in a 20 slot |
| `ShellLayout.threadColumn` | 180 | Map column pitch per depth |
| `ShellLayout.threadRowPitch` | 40 | Map row pitch; same as sidebar rows |
| `ShellLayout.markInset` | 1 | Padding of the in-page mark |
| `ShellLayout.annotationBarHeight` | 36 | Selection bar in the page |
| `ShellLayout.boardCardRadius` | 12 | Equals `popoverRadius` |
| `Palette.markText` | page ink | Marks never change text colour |
| `Palette.quoteRule` | `threadLine` | Left rule beside a quote block |

## 5. Surfaces

Each subsection is a build spec. "Base" means the Arc-look surface it modifies; "Now" means the current implementation.

### 5.1 Sidebar (base: Arc look 3.3; build: D6 G1 and G5)

The sidebar is Arc's, plus two things that appear only with data: provenance connectors under Today rows, and the Vault shelf above the footer. Both are fully specified in D6. The one language rule to add: the connector's horizontal tick enters the child's icon slot, never its title, so the favicon column reads as the spine of the thread.

### 5.2 Navigation graph, called the Thread map (base: Threads library view; new package G6)

**Now:** `ThreadMap` in `LedgerView.swift` draws a force-directed graph of nodes with x/y from the store. Force graphs read as generic and hide order.

**Design:** a thread is a tree in time, so draw it as one. Columns are depth, rows are order.

- **Layout.** Roots (a visit with no parent, or a search query) at column 0. Each visit is a node at `x = depth × threadColumn`, `y = row × threadRowPitch`, rows assigned by a depth-first walk so a branch is contiguous and its children sit directly under and to the right of the parent, exactly like the sidebar. The whole map scrolls in both axes inside the page card; it never zooms. A branch deeper than the card is reachable by horizontal scroll, not by shrinking.
- **Node.** Favicon 16 in a `threadNodeSize` slot, title in `row` `ink2` to the right, truncated at 26 characters, host in `caption` `ink3` after a 6pt gap. The current tab's node (if the thread is open) is `rowSelected` with `row` in `ink`. Nodes with a Vault note show a 6pt `accent` dot at the favicon's bottom-right (the same reset-dot geometry the sidebar uses for pinned tabs; the meaning differs, the vocabulary is shared). Hover: `rowHover` on the node and a card (`elev`, `popoverRadius`, hairline, `pageShadow`) 320 wide with the page snippet in `quoteSmall` and "Open · Resume from here" actions in `label`.
- **Connectors.** One `threadLine` path per parent: vertical from the parent's node centre down to the last child's row, then a horizontal into each child's slot, with a 6pt radius at the corner. Selecting a node turns its ancestor path `threadLineActive`. Query roots show the query in `label` `ink3` above the first node, in quotes.
- **Time.** No timestamps on nodes. A single `caption` `ink3` label at the top of each root column shows the thread's start ("Tue 14:05"); the branch order already encodes sequence.
- **Actions.** Click opens the page in the current tab; ⌘-click opens it as a child of the current tab (creating provenance in the sidebar); "Resume" restores the branch from that node forward as Today tabs, with connectors. The Summary (existing streamed summary) sits in a right-hand column 320 wide in `row` with numbered citations that highlight nodes on hover, using the same index chips as the chat panel.
- **Empty state.** The lattice and "Open a page and Graphene will keep the thread." in `secondary` `ink3`.
- **List mode** stays for search and scanning: rows of `rowHeight` with the same node treatment, indented by depth. The List/Map picker moves into the library bar as two glyph buttons.

**Acceptance.** After browsing A, then B and C from A, then D from C: the map shows A at column 0, B and C at column 1 under A, D at column 2 under C, one connector path from A with ticks into B and C and a second from C into D. Clicking D marks A→C→D active. Resume from C opens C and D as Today tabs with D indented under C in the sidebar.

### 5.3 Annotations (base: `annotate.js` selection bar and Vault; new package G7)

**Now:** selecting text shows a system-styled bar ("Save to Graphene", "Add note", "Save") and a note editor; saved highlights are yellow-ish; the Vault view lists notes in a grid.

**Design:** annotation is the act of taking a thread from a page into your own notes, so it uses the same mark and the same provenance line as citations.

- **Selection bar.** A floating `elev` card, `annotationBarHeight` tall, `popoverRadius`, hairline, `pageShadow`, appearing 8pt above the selection: three glyph actions with `label` text, in `ink2`: Save (⌘D), Note, Ask. No brand name in the bar. The bar uses the page's colour scheme (light card on light pages, dark on dark), through the same `page(dark:)` tokens as the toolbar. It is injected CSS, not system controls.
- **Mark.** A saved highlight is a `<mark>` with `highlight` background, `markInset` padding, 2px radius, page ink unchanged. Hovering the mark raises it to `highlightActive` and shows a 6pt `accent` dot in the page margin at the line's left edge; clicking the dot opens the note in a 320-wide `elev` card anchored to the margin with the note text in `row` and the quote in `quote`, plus Edit and Open in Vault in `label`.
- **Note editor.** Same card, with a `body` text field, "Save note" in `label` `accent`, Escape cancels. It never covers the selected text: it opens beside it, or below when there is no room.
- **Vault view.** A list, not a grid. Each note is a row group: the quote in `quote` `ink` with a 1pt `quoteRule` at its left (the thread, vertical, 2pt inset), the note text under it in `row` `ink2` if present, and a provenance line in `caption` `ink3`: favicon 12, page title, space name, relative date. Rows are separated by `sectionGap`, not hairlines. Filter field in the library bar. Clicking the quote opens the page and scrolls to the mark; clicking the title opens the page. Selecting a row shows Edit, Delete, Copy as Markdown, Add to Board in the library bar. Sort is newest first; a "By page" toggle groups notes under their page title with the same hairline tree as the map (depth 1).
- **Empty state.** Lattice and "Select text on any page and press ⌘D." in `secondary` `ink3`.

**Acceptance.** Select a sentence, press ⌘D: the mark appears with the accent tint and the shelf gains a chip. Hover the mark: margin dot appears; click: card shows the quote in serif. Open Vault: the note is a row with a left rule and a provenance line; clicking the quote returns to the page scrolled to the mark.

### 5.4 The AI panel (base: Arc look 3.5 chat panel; new package G8)

**Now:** a floating card with a header, context chips, a transcript, and a composer with @, /, attach and send. It reads as a chat app.

**Design:** Graphene's AI is a research assistant that only knows what you gave it. The panel should make its grounding visible at every step: what it can see, what it said, and where each sentence came from.

- **Header.** Title "Ask" in `title`; trailing glyphs history, new, close (Arc look). Below the title, one `caption` `ink3` line states the grounding: "This page" / "3 tabs" / "This space's notes" / "Nothing yet" with a 6pt dot: `accent` when local sources are attached, `ink3` when the model has nothing. This replaces the sparkle as the panel's identity.
- **Sources strip.** The context chips (24pt, `elevFill`, `rowRadius`) become a horizontal strip under the header: favicon and short title, `xmark` on hover to remove. An "Add" chip opens the @ picker. Chips for Vault notes show a 12pt quotation glyph instead of a favicon.
- **Turns.** The user's question is `row` `ink2` on a `fill` bubble (Arc look). The answer is `row` `ink` on no bubble, 1.45 line height, with citation indices as `label` chips inline (`elevFill`, 16pt tall, 4pt radius, 2pt inset), numbered per answer. A quoted passage the model echoes is rendered in `quote` with the `quoteRule` at its left. Under each answer, a sources line: the numbered chips again with favicon and title, so the reader can scan sources without reading the prose.
- **Page link.** Hovering a chip scrolls the page to its mark and raises it to `highlightActive`; hovering a mark raises its chip (D6 G4). If a source is another tab, hover shows the tab preview, click switches. If the model cites nothing, the answer carries a `caption` `ink3` line: "No sources; this is the model's general knowledge." Never hide that.
- **Skills.** `/summarize`, `/explain`, `/compare`, `/tldr` appear as `label` chips above the composer only while the composer is empty, and disappear once typing starts. They are not a menu.
- **Composer.** Arc look 3.5: `fill`, `popoverRadius`, min 40. Leading glyphs @ and /; trailing send in `accent`, Stop while streaming. Placeholder reflects grounding: "Ask about this page…", "Ask across 3 tabs…", "Ask your notes…".
- **Writing help** (existing draft flow) stays as its own popover but adopts the same card and chip tokens.
- **Empty state.** No lattice here. One `secondary` `ink3` line: "Attach a page with @ or ask about this one." The panel is never blank.

**Acceptance.** Open on the Wikipedia page: header line "This page" with an accent dot. Ask a question: the answer has inline numbered chips; hovering "1" scrolls and highlights in the page; the sources line under the answer lists one chip. Ask something not on the page: the answer carries the "No sources" line.

### 5.5 Resume page (D6 G3)

Fully specified in D6 3.3. Language rules: "Continue" rows use the map's node treatment (favicon, title, host); "Saved here" rows use the Vault's quote treatment in `quoteSmall` with the left rule. The page is the only place both appear together, which is the point: it is the thread and the notes, and nothing else.

### 5.6 Board (base: `EaselView`; new package G9)

**Now:** absolute-positioned cards (link, text, Vault) on a plain surface with edit, drag, resize.

**Design:** the one place the lattice is a working surface.

- **Canvas.** `pageBg` with the lattice at 4%, snapped 28pt cells; cards snap to the lattice on drop. Pan with two-finger scroll, no zoom in v1.
- **Cards.** `elev`, `boardCardRadius`, hairline, `pageShadow`. Three kinds keep their kinds: a **page card** shows favicon, title in `row`, host in `caption`, and a 16:10 thumbnail from the existing thumbnail cache; a **note card** shows text in `row` with a `title` first line; a **quote card** (from Vault or from a mark) shows the quote in `quote` with the left rule and the provenance line beneath. Drag a Vault shelf chip or a sidebar tab onto the canvas to create one.
- **Threads on the board.** When a card's page is the parent of another card's page (per the graph), a `threadLine` connector is drawn between the two cards, from the parent's right edge to the child's left edge, with 6pt corner radii. It is automatic, from provenance; there is no manual connector tool. This is the only place the thread is drawn between cards.
- **Library bar.** Add note, Add link, Export Markdown, Clear as glyph buttons.
- **Empty state.** The lattice is already there; one `secondary` `ink3` line: "Drop tabs, notes and quotes here."

**Acceptance.** Drop A and its child B: two cards with a connector. Move B: the connector follows. Delete A: the connector goes.

### 5.7 Mail (base: `MailView`; new package G9)

**Now:** a read-only Gmail list with avatars and serif headings (removed in D5).

**Design:** Mail is a read-only inbox that lives in the same grammar as tabs: rows, not cards; the thread primitive for conversations.

- **Rows.** `rowHeight` 44 (two lines): sender in `row` `ink` (unread: `rowSelected` weight), subject in `row` `ink2`, preview in `secondary` `ink3` on the second line, date in `caption` `ink3` trailing. Unread shows the 6pt `accent` dot in the icon slot instead of an avatar. No avatars at all.
- **Conversations.** Replies indent 20 under the first message with the `threadLine` connector, collapsed by default to the latest three, "12 more" in `label`.
- **Reading pane.** The message body is page content, so it renders in the reader sheet (`rdBg`, reading face) inside the page card, with the header (from, to, date) in chrome type above it. Links open as child tabs of the mail surface's current tab, so they appear with provenance in the sidebar.
- **Disconnected state.** The existing web fallback, plus the `caption` line "Read-only. Graphene never sends mail." in the library bar.

### 5.8 Command bar and Reader

No new design. The command bar shows threads and notes as sections when typed (already built); their rows use the node and quote treatments respectively. Reader keeps its face; its Ask button opens the panel with grounding "This page (reader)".

### 5.9 Icon and lattice

The app icon is a single graphite hexagon lattice cell with one node in `accent`. The lattice in empty states and on the Board is the same 28pt cell. Nowhere else.

## 6. Motion additions

| Interaction | Animation |
|---|---|
| Map open | nodes fade in by depth, 40ms stagger, max 200ms; connectors draw from parent to child over 200ms |
| Map select | ancestor path recolours over 120ms |
| Mark hover | background 120ms; margin dot scales 0.6→1 with spring(0.25, 0.8) |
| Note card | Arc popover spring |
| Chat chip hover → page scroll | smooth scroll, mark 200ms |
| Board card drop | snap to cell with spring(0.3, 0.75); connector redraws over 160ms |
| Reduce Motion | fades only, 120ms |

## 7. Acceptance for the language

Beyond the per-surface lines above:

1. Every hairline drawn by Graphene outside the Arc base is a provenance connector or a quote rule. A reviewer can point at any line and name the two things it joins.
2. Serif appears only on text that came from a page. No headings, no labels, no chrome in serif.
3. The lattice appears only on empty Threads, empty Vault, the empty new-tab page and the Board canvas.
4. A fresh profile's main window is pixel-identical to the Arc-look capture except for the graphite colour.
5. Tests cover: map layout rows/columns from a visit tree, connector path geometry, Vault row provenance formatting, chat citation index assignment, board connector derivation from the graph, mail conversation grouping.

## 8. Packages

D6's G1 to G5 first (they are the foundation: provenance rows, graphite, resume page and `cite.js`, in-page citations, shelf). Then, in parallel worktrees:

- **G6 Thread map.** `UI/LedgerView.swift` (replace `ThreadMap`, List/Map glyphs in the library bar, summary column), a new `Model/ThreadLayout.swift` (pure layout from visits; tested), hover cards, Resume-from-node in `AppState`.
- **G7 Annotations and Vault.** `Resources/annotate.js` (bar, mark, margin dot, note card as injected CSS/DOM using page-scheme tokens passed in), `Web/WKWebEngine.swift` message plumbing, `UI/VaultView.swift` (list rows, quote rule, provenance line, By page grouping), `Theme.swift` (`ShellType.quote`).
- **G8 AI panel.** `UI/ChatView.swift` and `ChatMarkdown.swift` (grounding line, sources strip, inline index chips, sources line, skills chips, placeholders), `Intelligence/ChatSession.swift` (grounding state, "no sources" flag).
- **G9 Board and Mail.** `UI/EaselView.swift` (lattice canvas, snapping, card kinds, automatic connectors from the graph), `UI/MailView.swift` (rows, conversation tree, reader sheet, child-tab links), `UI/Lattice.swift` shared with G3.

Each package ships with its acceptance lines turned into a Codex verification brief section in `docs/design/codex/verify-identity.md`.
