# Landing page and Tidy: addendum to the Graphene design language

Status: design spec, September 25, 2026. Answers two hands-on findings: "the default landing page is kind of weird / nothing to it, the whole thing is very white, there's no design, life or taste to it, not super clear where all of the Graphene features are" and "there needs to be a grouping function like Tidy in Arc." Supersedes `graphene-identity.md` §3.3 where they differ.

## 1. Why the current page fails

The resume page was specified as a quiet list: search, threads, notes. On a fresh profile that is a white card with one grey field and a faint lattice, and even on a busy profile it never says what Graphene is. Arc's new tab is also empty, but Arc's chrome carries the personality. Graphene's does not yet, because graphite light chrome is deliberately pale. So the landing page has to carry it.

Three rules replace "sections appear only with data":

1. **The page carries the space.** Its top band is the space's own gradient, bleeding from the chrome into the page card, so a new tab in Research looks like Research. The card is never a white sheet from edge to edge.
2. **The page names the product.** One row shows the four Graphene surfaces with live counts. It is the answer to "where are the features."
3. **Empty is still designed.** A fresh profile shows the band, the surface row with zero counts and one line of copy, not a lattice alone. The lattice moves behind the band as texture.

## 2. Layout (`UI/ResumePage.swift`)

Column `newTabColumnWidth` (560) centred, sections separated by `newTabGap` (24), `pageBg` below the band.

1. **Space band**, 160pt tall, full card width, drawn from `chromeTop → chromeBottom` at 55% opacity over `pageBg` with the lattice at `lattice` opacity inside it and a 24pt bottom fade into `pageBg`. Inside the band, left-aligned to the column: the space glyph at 24pt, the space name in `ShellType.display` (22 semibold) in `ink`, and under it in `caption` `ink3` a one-line status: "12 tabs · 3 threads · 5 notes · Tuesday 14:05". Right-aligned: the search row from before (`fill`, 44pt, ⌘T chip), vertically centred in the band. The band replaces the old search-first layout.
2. **Surfaces row**, `newTabGap` below the band: four equal tiles, `favoriteHeight × 2` (88pt) tall, `fill` background, `favoriteRadius`, each with a 20pt glyph in `ink2` (Threads `point.3.connected.trianglepath.dotted`, Vault `tray.full`, Board `rectangle.3.group`, Mail `envelope`), the name in `row` `ink`, and a count line in `caption` `ink3` ("3 threads", "5 notes", "2 cards", "Read-only"). Hover `fillHover`; click opens the surface. Mail shows "Not connected" when there is no OAuth config and opens Settings → Mail.
3. **Continue** (threads, up to 3) and **Saved here** (notes, up to 4), as specified in `graphene-identity.md` §3.3; when both are empty, one `secondary` `ink3` line under the surfaces row: "Open a page and Graphene will keep the thread. Select text and press ⌘D to save it."
4. **Pinned in this space** (favorites tiles) only when the sidebar is collapsed, as before.

Dark appearance: the band uses the dark chrome colours at 70%, the tiles `fill`; the page below stays `pageBg` (#1E1E22).

## 3. Chrome presence (`Theme.swift`)

Light graphite is too pale to carry the window. Two token changes, both inside the existing formulas:

- Light `chromeTop` saturation multiplier 0.22 → 0.30 and brightness 0.95 → 0.93; light `chromeBottom` 0.26 → 0.34, 0.92 → 0.90. Graphite light becomes a visible cool grey-blue, Iris a clear lavender.
- Light `fill` (favorite tiles, pills) white 45% → white 55%, so tiles read on the deeper chrome.

`inkContrast ≥ 4.5` must hold; the palette tests assert it.

## 4. Tidy (`Intelligence/AITidy.swift`, `App/AppState.swift`, `UI/Sidebar.swift`, `Model/Commands.swift`)

Arc's Tidy groups Today tabs into named folders. Graphene has provenance, so it can tidy better than by title alone.

- **Command**: "Tidy Today" in the command bar, the Today hairline's context menu, and the Tidy glyph that appears at the trailing end of the Today hairline on hover next to "Clear". Shortcut ⌃⌥⌘T.
- **Algorithm** (pure, testable, `Model/TidyPlan.swift`): input the space's Today tabs with title, host, `parentTabID` and thread id. Step 1: a provenance branch is one group (never split a branch). Step 2: remaining single tabs group by thread id, then by host when the thread has one page. Step 3: groups of size 1 stay loose. Step 4: name each group: the branch root's title trimmed to 3 words; for host groups the site name; when the on-device model is available and `Settings.ai.tidyTitles` is on, ask it for a 1–3 word name from the group's titles (existing `AITidy.answer`), falling back to the heuristic. Output: an ordered list of `(name, tabIDs)` plus the loose tabs.
- **Apply**: creates a folder per group in the Today section (folders already exist for pins; extend `placeTab(folderID:)` to Today), moves the tabs, preserves `parentTabID` inside the folder, and shows one toast "Tidied 14 tabs into 4 groups" with Undo (reverses all moves). Nothing is closed or archived.
- **Preview**: none in v1. Undo is the preview.
- **Rows**: a Today folder row uses the folder row treatment from the Arc look; its children keep their connectors.

## 5. Acceptance

1. Fresh profile, new tab: band with the space name and "0 tabs · 0 threads · 0 notes", the four tiles with zero counts, the one-line copy, no bare lattice page.
2. After browsing and saving: counts update; Continue and Saved here render under the tiles.
3. Light graphite chrome samples in-process within 6 of HSB(232°, 0.168, 0.93) at the top.
4. Tidy on 12 Today tabs from three threads plus two loose tabs: three folders named from their roots, two loose tabs untouched, one toast, Undo restores the exact order and parents. Branches never split (test).
