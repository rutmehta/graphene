# Graphene visual language: the Arc look

Status: design spec, September 24, 2026. Source of truth for every shell surface. Implementation agents read this file first; when it disagrees with existing code, this file wins. When it disagrees with a measured Arc capture in `docs/parity/ref/arc/`, the capture wins and this file gets corrected.

Reference evidence: `docs/parity/ref/arc-main.png` (Arc 1.163, dark space, user's real window, page content redacted) and the crops/measurements in `docs/parity/measurements.json`. Scale of that PNG is about 1.37 image px per point. The companion design artifact renders the mockups below as HTML so the intended result can be compared side by side with the app.

## 1. What makes Arc look like Arc

Ten things, in priority order. If only the first five land, the app already reads as Arc.

1. **One flooded chrome plane.** The whole window background is the space's colour: a two-stop gradient with fine grain. The sidebar has no separate background; it is content sitting on the window plane. Dark spaces are deep and saturated (navy-indigo to plum, not grey). Light spaces are pastel, not white-grey.
2. **The page is a card.** The web page floats inside the chrome as a single rounded white (or near-black) card with an 8pt gap to the window's top, right and bottom edges, a 10pt radius, a 1px hairline and a soft shadow. Nothing else in the window has that treatment, so the page is unmistakably the bright plane.
3. **Navigation lives on the card.** Back, forward, reload and the URL sit in a 32pt toolbar at the top of the page card, not in the sidebar. The sidebar's top band holds only the traffic lights and the sidebar toggle. Clicking the URL opens the command bar.
4. **A three-tier sidebar with almost no chrome.** Favorites are a grid of equal translucent tiles. Pinned tabs are plain rows under a small space label. Today tabs are plain rows under a hairline and a "+ New Tab" row. No headers, no boxes, no buttons with borders. Hierarchy comes from tiles versus rows, one hairline, and 13pt type.
5. **Translucent white as the only fill.** Tiles, hover, selection and pills are all white at some opacity on dark chrome (black at some opacity on light chrome). No opaque grey panels inside the sidebar.
6. **Quiet, small controls.** Toolbar and footer glyphs are 15 to 16pt monochrome at 60 to 70 percent ink; they never carry colour. Colour comes only from favicons and the space gradient.
7. **A single footer strip.** Archive on the left, space dots in the centre, plus on the right, 36pt tall. Nothing else lives there.
8. **The command bar is a big card.** About 640pt wide, 16pt radius, 18pt input, favicon rows, deep shadow, positioned in the upper third. No chips, no footer legend.
9. **Motion is springy and short.** Sidebar collapse and Little Arc use a spring (response 0.3, damping 0.75). Space switch slides horizontally. Hover states fade in 100ms. Nothing else animates.
10. **System type, tight scale.** SF Pro at 11, 12, 13, 15, 18. Row titles are 13 regular, selected 13 medium. Labels are 11 semibold. Nothing bigger than 18 outside page content.

## 2. Tokens

All values are points. These replace the literals counted in the UI audit (263 font literals, 66 radius literals). Names are the Swift identifiers; implementation package D1 creates them in `Theme.swift`.

### 2.1 Layout (`ShellLayout`)

| Token | Value | Notes |
|---|---|---|
| `windowGap` | 8 | Page card inset from window top, right and bottom. Also the sidebar's outer left inset. |
| `windowOutline` | 1 | 1px inner outline around the window, `ink.opacity(0.10)` dark, `black.opacity(0.06)` light. |
| `pageRadius` | 10 | Page card. |
| `pageToolbarHeight` | 32 | Toolbar inside the page card. |
| `sidebarDefault` | 224 | Includes `windowGap` on the left. Content width is 208 at default. |
| `sidebarRange` | 180…360 | |
| `collapseThreshold` | 160 | |
| `trafficBandHeight` | 44 | Traffic lights centred at y=22, first light centre x=20 from the window edge, 20pt spacing. Sidebar toggle at x=84. |
| `favoriteColumns` | 3 (4 at ≥300 content width) | |
| `favoriteGap` | 10 | |
| `favoriteHeight` | 44 | Width is derived: `(contentWidth − (cols−1)·gap) / cols`, about 62 at default. |
| `favoriteRadius` | 10 | |
| `rowHeight` | 36 | Tab, folder and New Tab rows. |
| `rowPitch` | 40 | So the inter-row gap is 4. |
| `rowRadius` | 8 | |
| `rowInsetLeading` | 8 | Row content starts 8 in from the row's edge; favicon slot 20 wide; 8 gap to title. |
| `iconSize` | 16 | Favicons and row glyphs. |
| `favoriteIconSize` | 20 | |
| `controlSize` | 28 | Hit target for toolbar/footer glyph buttons; glyph 15 medium. |
| `footerHeight` | 36 | |
| `sectionGap` | 12 | Between favorites grid and space label, between pinned rows and the Today hairline. |
| `hairline` | 1 | `ink.opacity(0.10)` dark, `ink.opacity(0.08)` light. |
| `commandWidth` | 640 | |
| `commandRadius` | 16 | |
| `commandInputHeight` | 56 | |
| `commandRowHeight` | 44 | |
| `commandTop` | 0.18 | Fraction of window height from the top to the command bar's top edge. |
| `popoverRadius` | 12 | Peek, site controls, chat panel, toast, Little Arc content. |
| `chatWidth` | 420 (360…560) | Floating chat panel, inset `windowGap·2` from the page card. |
| `minimumPageWidth` | 480 | |

Remove: `toolbarHeight` (36) and `topTabHeight` (40) as chrome concepts; the top-tabs layout keeps a 40pt strip but reads `topTabHeight` from the same file. Remove `rowHeight = 37` and `rowPitch = 41` in favour of 36/40.

### 2.2 Type scale (`ShellType`)

| Token | Size / weight | Used for |
|---|---|---|
| `label` | 11 semibold | Space label, section labels in command bar, keyboard hints |
| `caption` | 11 regular | URL host in toolbar when not focused, secondary metadata |
| `secondary` | 12 regular | Command result detail, settings help text, toast body |
| `row` | 13 regular | Tab titles, folder titles, New Tab, menu items, chat body |
| `rowSelected` | 13 medium | Selected tab title |
| `body` | 13 regular | Settings controls, panels |
| `title` | 15 semibold | Panel titles (Chat, Archive, Settings pages), Little Arc URL |
| `input` | 18 regular | Command bar input |
| `display` | 22 semibold | Onboarding heading only |

Everything is `.system(size:, weight:)` with `.default` design. No rounded, no serif in the shell. Reader mode keeps its own reading face.

### 2.3 Colour (`Palette`)

`Palette` stays a computed struct on `AppState`, but its derivation changes so dark and light chrome match the reference.

Space input: hue `h` (0…1), saturation `s` (0…1, user "intensity"), plus the resolved appearance.

**Dark chrome** (reference sidebar samples #0E0D26 top, #150D26 middle, #200A26 bottom):

| Token | Formula | Reference result for h=243° |
|---|---|---|
| `chromeTop` | HSB(h, 0.55·s′, 0.15) | #0E0D26 |
| `chromeBottom` | HSB(h + 20°, 0.60·s′, 0.16) | #200A26 |
| `chromeGrain` | white 3% noise, 1px | |
| `ink` | white | |
| `ink2` | white 72% | inactive row titles |
| `ink3` | white 48% | glyphs, New Tab, URL host |
| `fill` | white 9% | favorite tiles, address pill |
| `fillHover` | white 14% | |
| `fillSelected` | white 22% + 1px white 25% stroke | selected favorite |
| `rowHover` | white 6% | |
| `rowSelected` | white 12% | |
| `hairline` | white 10% | |
| `pageBg` | #1E1E22 when the site is dark-schemed, else white; the toolbar is always `pageBg` | |
| `pageBorder` | white 12% | |
| `pageShadow` | black 35%, radius 12, y 2 | |
| `windowOutline` | white 10% | |
| `elev` | #26262C | command bar, popovers, toast |
| `accent` | HSB(h, 0.45, 0.85) | focus rings, links inside chrome, progress bar |

where `s′ = 0.5 + 0.5·s` so even a "neutral" space keeps a whisper of hue. A user-chosen neutral (grey) space sets `s = 0` and gets `s′ = 0`.

**Light chrome** (Arc pastel):

| Token | Formula |
|---|---|
| `chromeTop` | HSB(h, 0.22·s′, 0.95) |
| `chromeBottom` | HSB(h + 25°, 0.26·s′, 0.92) |
| `chromeGrain` | black 2.5% noise |
| `ink` | #1B1B22 |
| `ink2` | ink 75% |
| `ink3` | ink 50% |
| `fill` | white 45% |
| `fillHover` | white 60% |
| `fillSelected` | white 85% + 1px black 8% stroke |
| `rowHover` | black 4% |
| `rowSelected` | white 60% |
| `hairline` | black 8% |
| `pageBg` | white |
| `pageBorder` | black 8% |
| `pageShadow` | black 10%, radius 10, y 1 |
| `windowOutline` | black 6% |
| `elev` | white |
| `accent` | HSB(h, 0.55, 0.62) |

Semantic colours (download progress, media playing, destructive) stay system: `.red`, `.green` at 70% only where state matters. They are never used for decoration.

The `neutralChrome` flag for top-tabs layout keeps `s′ = 0`.

## 3. Surfaces

Each subsection is a build spec. "Reference" means the Arc capture; "Now" means the current Graphene build (`docs/parity/shots/wp10/main-dark.png`).

### 3.1 Window and page card

- Window: `.hiddenTitleBar`, full-size content view, transparent title bar, standard macOS corner radius. Draw `windowOutline` as an inner 1px stroke over the whole content view (ignores safe areas).
- Background: `LinearGradient(chromeTop → chromeBottom, topLeading → bottomTrailing)` plus the grain canvas at the token opacity, over the entire content view. Reduce Transparency drops the grain only.
- Page card: frame `x = sidebarWidth`, `y = windowGap`, width `window − sidebar − windowGap`, height `window − 2·windowGap`. Fill `pageBg`, corner `pageRadius`, 1px `pageBorder` inside, `pageShadow`. The WKWebView is clipped to the card below the toolbar.
- Collapsed sidebar: the card's x becomes `windowGap`; traffic lights then overlap the card's toolbar, so the toolbar reserves 84pt on the left for them (same reservation the sidebar band uses).
- Split view: each pane is its own card with the same treatment; panes are separated by `windowGap`. The focused pane's border is `accent` at 60%.

Now: the page card has a heavy tinted border and the window background is a flat colour. Fix both.

### 3.2 Page toolbar (new)

32pt strip at the top of the page card, fill `pageBg`, bottom hairline.

Left group, starting at x=8 (or 84 when the sidebar is collapsed): back, forward, reload/stop. Each is a `controlSize` button with a 15pt medium glyph in `ink3`; disabled at 25%. Gap 2.

Centre: the address. A flat text run, not a pill: page host in `caption` `ink2`, the rest of the path in `caption` `ink3`, truncated in the middle, centred in the remaining width, max width 60% of the card. Lock glyph at 11pt before the host when the connection is secure; no glyph otherwise. Hover shows `rowHover` behind it with `rowRadius`; click opens the command bar seeded with the URL selected. `⌘L` does the same.

Right group, ending at x = width − 8: site controls (the favicon acts as the button, 16pt), chat toggle (15pt "sparkle" glyph, `ink3`, `accent` when the panel is open), split (15pt). Same control style as the left.

Loading: a 2pt `accent` progress bar along the toolbar's bottom edge, replacing the hairline while loading, fading out over 200ms at completion.

Setting: Appearance → "Address bar: On page (default) / In sidebar". "In sidebar" restores today's `SidebarAddress` pill, restyled to `fill` with `rowRadius`, and the toolbar then shows nav buttons only.

### 3.3 Sidebar

Width `sidebarWidth`, content inset `windowGap` on the left and 8 on the right, so content width is `sidebarWidth − 16`. No background of its own.

Top band, `trafficBandHeight`: traffic lights (system-positioned by `WindowAccessor` to centre y=22, x=20/40/60), sidebar toggle glyph at x=84 (15pt, `ink3`). The whole band is a window drag region. Nothing else in it.

Favorites grid: `favoriteColumns` columns, `favoriteGap`, tiles `favoriteHeight` tall, `favoriteRadius`, fill `fill`, hover `fillHover`, selected `fillSelected`. Icon `favoriteIconSize` centred. A red 6pt dot at the tile's bottom-right (inset 8) when the tab has an unread badge. The grid is shown only when the space has at least one favorite; it is not a placeholder. Drag reorders tiles. Tooltip is the site title.

Space label, `sectionGap` below the grid: the space's glyph (emoji or SF Symbol, 12pt) and name in `label` `ink2`, leading inset 8, row height 24. Hover reveals a `…` glyph at the trailing edge opening the space menu. No "Research ⋯" header row; the label is the header.

Pinned rows: `rowHeight`/`rowPitch`, `rowRadius`. Leading inset 8, favicon 16 in a 20 slot, 8 gap, title `row` in `ink2` (selected: `rowSelected` in `ink`). No close button on pinned rows; hover shows nothing but `rowHover`. Folders: chevron glyph 10pt `ink3` in the icon slot, children indented 20 further. Reset-tab affordance: when a pinned tab is off its base URL, its favicon gets a 6pt `accent` dot at its bottom-right; clicking the favicon resets.

Today section: hairline (full content width) `sectionGap` below the last pinned row. Hovering the hairline reveals "Clear" in `label` `ink3` at the trailing end (archives all Today tabs). No permanent "Tidy | Clear" row. "+ New Tab" row directly under the hairline: plus glyph 15pt in the icon slot, "New Tab" in `row` `ink3`, no shortcut hint. Today rows as pinned rows but with a close glyph (12pt `xmark`, `ink3`, 24×24 target) at the trailing edge on hover and on the selected row; audio glyph before it when playing.

Selection and hover: `rowSelected` and `rowHover`, 100ms ease-out, no shadow, no left bar.

Footer, `footerHeight`, pinned to the bottom of the sidebar: archive glyph (15pt `archivebox`, `ink3`) at leading; space dots centred (6pt dots at 14pt pitch, active dot `ink`, others `ink3`; a space with a custom glyph shows the glyph at 12pt instead of a dot); plus glyph at trailing. Space dots scroll horizontally when there are more than fit. The "Ask Graphene ⌘K" row is removed from the footer; Ask lives in the page toolbar and `⌘K`.

Library (Threads/Vault/Mail/Board): not tiles in the sidebar. They are reached from the command bar, the menu, `⌘⌥1–4`, and a single `books.vertical` glyph next to the archive glyph in the footer that opens the existing Library popover. Downloads and Now Playing keep their footer slots but use the same 15pt `ink3` style and appear only when active.

Resize divider: invisible 8pt strip at the sidebar's trailing edge; cursor changes; no drawn handle.

Collapsed: the sidebar animates to 0 width with the spring; the page card slides left. Moving the pointer to the left window edge peeks the sidebar over the card as a floating panel: same content, `elev` background at 96%, `popoverRadius`, `pageShadow`, inset `windowGap`.

### 3.4 Command bar

Overlay centred horizontally at `commandTop` from the top, width `min(commandWidth, window − 80)`, `elev` fill, `commandRadius`, 1px `hairline` stroke, shadow black 30% radius 32 y 12. Scrim over the page card only: black 20% dark, black 10% light.

Input row `commandInputHeight`: search glyph 18pt `ink3` at x=20, input `input` type in `ink`, placeholder "Search or enter URL…" in `ink3`. No trailing chips. Inline URL completion draws the completed remainder as selected text. When opened from the URL, the current URL is prefilled and selected.

Results: hairline under the input, then rows of `commandRowHeight`: icon slot 20 (favicon, or a glyph in `ink3` for actions), title `row` `ink`, detail `secondary` `ink3` after a 8pt gap on the same line, truncated tail; trailing hint in `label` `ink3` ("⌘↩", "Tab", or the section verb such as "Switch to Tab"). Selected row fills `rowHover` with `rowRadius`, inset 8 horizontally. Section labels ("Tabs", "History", "Commands") in `label` `ink3` at 24 height only when more than one section is present. Max 8 rows before scrolling. Bottom padding 8. No footer legend.

Ask/Search mode toggle: `Tab` switches; the placeholder changes to "Ask about this page…" and the search glyph becomes the sparkle. No visible pill.

Top-tabs layout keeps the integrated variant with `rowRadius` and no shadow.

### 3.5 Chat panel

Floating card over the page card, inset `windowGap·2` from its top, right and bottom, width `chatWidth`, `elev` fill, `popoverRadius`, hairline stroke, `pageShadow`. Header 44: title in `title`, history/new/close glyphs 15pt `ink3` trailing. Context chips 24 tall, `fill`, `rowRadius`. Messages in `row` at 1.45 line height, assistant text in `ink`, user text in `ink2` on a `fill` bubble with `popoverRadius`. Composer: 40 min height, `fill`, `popoverRadius`, `@` and `/` glyph buttons leading, send/stop trailing in `accent`. Docked mode: same card without the shadow, sharing the page card's right edge with a `windowGap` gutter.

### 3.6 Popovers, Peek, Little Arc, toast, switcher

All use `elev`, `popoverRadius`, hairline stroke and `pageShadow`.

- Peek: card 900 max wide, centred, inset 40 from the page card; a 32pt toolbar with the URL and an "Open as tab" button in `label`.
- Little Arc: 760×560 floating panel, `chromeTop` background, page card inside with `windowGap`, its toolbar showing the URL and a "Move to space" glyph. Window appears with the spring, scale 0.96→1.
- Toast: bottom-centre of the page card, inset 24, max 420 wide, 40 tall, `row` text, optional action in `label` `accent`. Slides up 8pt and fades in 160ms.
- Tab switcher (⌃Tab): centred card, rows of `commandRowHeight` with thumbnails 96×60 at `rowRadius`.
- Site controls: 320 wide, standard controls, `body` type, `title` header with the host.
- Context menus: native. Shortcut hints are shown by AppKit.

### 3.7 Settings, onboarding, library views

Settings is native `Settings` scene: 180 sidebar list, pages use `body` and `secondary` type, `title` page headings, `Form` grouped style. No custom colours beyond `accent`. Onboarding sheet 540×420: `display` heading, `body` copy, a live 3-swatch space picker rendering the actual gradient. Threads, Vault, Mail and Board render inside the page card with a 32pt toolbar identical to the web toolbar (title instead of URL), `pageBg` background, `row`/`secondary` type and `hairline` separators. Mail drops its serif headings.

## 4. Motion

| Interaction | Animation |
|---|---|
| Sidebar collapse/expand | spring(response 0.30, dampingFraction 0.75) on width; page card follows |
| Sidebar peek | spring(0.28, 0.8) x-offset from −width to 0, opacity 0→1 |
| Space switch | asymmetric horizontal slide 24pt with opacity, easeOut 180ms; the gradient cross-fades 240ms |
| Row hover/selection | easeOut 100ms |
| Command bar | opacity + scale 0.98→1, easeOut 120ms; dismiss 90ms |
| Chat panel | spring(0.32, 0.8) x-offset 24 + opacity |
| Little Arc | spring(0.32, 0.8) scale 0.96→1 + opacity |
| Toast | easeOut 160ms y 8→0 + opacity |
| Progress bar | width tracks `estimatedProgress` with easeOut 150ms; fade-out 200ms |
| Reduce Motion | every spring and slide becomes opacity-only 120ms |

## 5. Removals

- Sidebar app tiles for Threads/Vault/Mail/Board, the "Ask Graphene ⌘K" footer row, the permanent "Tidy | Clear" row, the "Research ⋯" header, the `SidebarAddress` pill by default, `Palette.wash`, `Palette.c2`, `LegacySourceSearchView`, the compact-row mode (26pt) and its setting.
- Every literal font size, radius and opacity in `Sources/Graphene/UI/*.swift` that has a token above.

## 6. Acceptance

Verification is done on the real app by a computer-use agent, never through `DebugDriver`. A package is accepted when, on an isolated profile (`GRAPHENE_DATA_DIR`) seeded with four favorites, three pinned tabs (one in a folder), and four Today tabs, at a 1280×820 window:

1. `main-dark.png` and `main-light.png` of Graphene placed beside `docs/parity/ref/arc/main-dark.png` (or `arc-main.png` until the capture set exists) read as the same product at a glance. Concretely: page card gap 8±1, radius 10±1, toolbar 32±1 with nav at left and URL centred, favorites three equal tiles per row at 44±2 tall, row pitch 40±1, favicons 16, footer 36 with archive/dots/plus.
2. Sampled sidebar RGB at top/middle/bottom is within 12 per channel of the reference for the default dark space (h = 243°).
3. Hover a Today row: `rowHover` plus close glyph appear within 100ms. Hover the Today hairline: "Clear" appears.
4. `⌘T`, click on the URL, and `⌘L` all open the same command bar at the same position; the URL variant has the URL selected.
5. Collapse and expand the sidebar with `⌘S`: the page card animates with a spring; no layout jump in the toolbar; traffic lights never overlap content.
6. Switch spaces: gradient cross-fades; rows slide.
7. Reduce Motion on: no movement, only fades.
8. `swift build` warning-free, `swift test` green, no new literals of the removed kinds in the touched files (grep gate in the package brief).

## 7. Implementation packages

Run D1 first and merge; D2 to D5 run in parallel worktrees from the merged master. Each package agent commits on its own branch with tests, and reports touched files and screenshots taken via the real app.

- **D1 Tokens and chrome.** `Theme.swift`: `ShellLayout` values above, new `ShellType`, `Palette` derivation, grain. `RootView.swift`/`WindowAccessor.swift`: flooded gradient background, window outline, page card geometry, traffic-light positions, sidebar collapse spring. Replace every literal in `RootView`, `Sidebar`, `CommandBar`, `TopTabBar`, `ChatView`, `SplitView`, `PeekOverlay`, `ToastOverlay`, `LittleArcWindow`, `OnboardingView` with tokens (no visual redesign yet beyond what the tokens force). Delete `LegacySourceSearchView`, `wash`, `c2`.
- **D2 Sidebar.** Section 3.3 in full, plus the address-placement setting and the `SidebarAddress` restyle.
- **D3 Page toolbar and cards.** Section 3.2, split-view cards, Peek and Little Arc restyle, progress bar, collapsed-sidebar reservation, library views' toolbar (3.7 last paragraph).
- **D4 Command bar, chat, overlays, motion.** Sections 3.4, 3.5, 3.6 and 4.
- **D5 Settings, onboarding, library content.** Section 3.7, Mail/Vault/Threads/Board restyle to tokens, dead-code removal, README screenshots and shortcut table update.
