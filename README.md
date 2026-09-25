# Graphene

A native macOS browser for pages, research threads and local notes.

Version 0.3.0 is a local development build, not a completed release-readiness sign-off. The WP9 regression sweep remains partial. See `docs/parity/shots/wp9/verification.md` for observed failures and unverified workflows.

WP10 shell polish and evidence: [glance-test report](docs/parity/shots/wp10/diff-notes.md). Idle CPU and the main visual changes are verified; benign-page AI refusals and unconfigured Gmail OAuth still prevent full acceptance.

![Graphene sidebar, WP10 isolated profile](docs/parity/shots/wp10/main-light.png)

## Run

Requires Swift 6.2 and macOS 14 or newer. On-device AI additionally requires macOS 26, Apple Intelligence and an available FoundationModels model. Language mode is Swift 5.

```sh
./scripts/build-app.sh
GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile .build/Graphene.app/Contents/MacOS/Graphene
```

The script builds a debug executable into `.build/Graphene.app` and ad-hoc signs the bundle. It does not install, notarize or publish the app. `swift build -c release` separately builds the optimized executable; it does not change the bundle script's configuration. For ordinary use, opening the app without `GRAPHENE_DATA_DIR` uses your normal profile. Development and smoke tests must always set it.

## What works

These are implemented capabilities, not a claim that every gesture or dialog passed WP9. Previous work-package reports distinguish model tests, source inspection and actual desktop observations.

- Browsing: URLs and web search, back/forward, reload/stop, new-tab links, loading/error states, exact main-document Find counts and next/previous, per-host zoom, native printing, and Save Page As a WebKit web archive.
- Shell: persisted Sidebar and Top tabs layouts, expanding address/command results, light/dark/system appearance, space-tinted chrome (presets Graphite, Iris, Tide, Moss, Clay and Slate; new spaces and a fresh profile default to Graphite, hue 232° at saturation 0.12, while saved spaces keep their colour), page gutters and optional page-font override. Shell geometry follows the Arc-look tokens in `docs/design/arc-look.md`: 36pt rows at 40pt pitch, 13pt labels and 16pt favicons; the space label heads the pins, a hairline heads Today (hover it for Clear), and pinned tabs off their base URL show an accent dot on the favicon (click it to reset). Favorites are 44pt translucent tiles in three columns, four from 300pt of content width, with 10pt gaps. The page is a card with an 8pt gap and a 32pt toolbar holding navigation and the address. The sidebar has an invisible 180–360pt resize strip and collapsed edge-peek. The footer holds archive, the Library (Threads, Vault, Mail, Board, Downloads), space dots and plus. The traffic band is draggable and holds only the sidebar toggle. Settings → Appearance → Address bar can put the address pill back in the sidebar.
- Resume page: a new tab shows the search row, then (only when there is data) Continue (the space's three newest threads with page count and age), Saved here (the space's four newest Vault quotes in serif with a left rule; clicking one opens the source and highlights the passage via `Resources/cite.js`) and, with the sidebar collapsed, the space's favorites. An empty space shows a fading hex lattice instead, as do empty Threads and Vault.
- Organization: named/icon Spaces with CRUD, ordering and themes; separate space-scoped Favorites, pins with resettable base URLs, Today tabs and folders. Tab rename, movement, drag/drop, multi-selection and batch actions are implemented, but the full drag/resize/menu sweep is still unverified. Provenance rows (`docs/design/graphene-identity.md` §3.1): Today tabs opened from another Today tab sit indented under it, joined by a hairline; closing a parent promotes its children in place, dragging a child makes it a root, dropping a tab on a row's icon makes it a child, the context menu adds Close branch and Detach from parent, and ⌥←/⌥→ after clicking a Today row collapses or expands its branch.
- Tab lifecycle: persistent searchable archive and restore/delete; close-tab Undo; optional auto-archive after 12 hours (default), 24 hours, seven days or Never. Lazy background restoration avoids synthetic visits. Background discard defaults to 30 minutes, with recent/visible, audible media, downloading and dirty-form protections. Five minutes idle does not meet that default threshold.
- Windows: shared tab collections with per-window selection and explicit WebView handoff, private windows, MRU and numbered-tab navigation, two-to-four-pane splits (each pane its own page card with its own 32pt toolbar: back/forward/reload, the address, site controls, chat and split) and Peek. Restoring a recently closed whole window as a unit is not implemented.
- Command bar: browser actions, cross-space tabs, history, Vault notes and resumable threads; Ask/Search mode, tab mentions, optional network search suggestions, inline URL completion, new-tab and split submission. Settings → Shortcuts remaps the shared menu/action registry with conflict checks.
- Site controls: certificate metadata, per-host zoom, blocking override, camera/microphone/motion policy and clear-site data. The bundled blocker is a bounded EasyList-derived network subset. Boosts provide per-host CSS, document-end JavaScript, font/scale/presets and persistent Zap selectors. JavaScript changes require reload. Reader is a native text-only view with reading preferences (Light/Sepia/Dark on the shared reading tokens, serif or system reading face), Vault save and Ask.
- Profiles/import: named profiles isolate persistent WebKit website stores and can be assigned to spaces. Existing tabs adopt changed assignments after restart. Import previews Safari/Chrome bookmarks and history or Arc spaces/pins/favorites, using duplicate checks and SQLite backups. Passwords and Arc Today tabs are not imported.
- Settings: native Settings window with a 180pt page list and grouped forms for General, Appearance, Spaces/Routing, Sites, Boosts, Profiles, Import, Privacy, Search, AI, Shortcuts, Mail and Advanced. Settings JSON import/export preserves existing tab/space collections. URL-glob routing uses the first enabled matching destination. Onboarding (a 540×420 sheet) selects layout, picks a space colour from three live swatches (Graphite, selected by default, Iris and Tide) that render the real chrome gradient, and offers default-browser setup/import.
- Threads: navigation visits, originating-page edges, space-scoped list/detail, source text, resumable browsing, streamed summaries and Markdown export. The Thread map draws each thread as a tree in time: roots (and searches, with the query in quotes) in column 0, each page 180pt further right per depth and one 40pt row per page, joined by hairline connectors; the clicked node's ancestor path turns accent. Click a node to open it in the current tab, ⌘-click to open it as a child tab, or hover for the snippet with Open, Resume from here (reopens that branch as linked Today tabs) and Note. Threads opens on the Map with All threads selected at the top of the list: every thread in the space drawn as its own tree, stacked newest first, each under its title (click it to narrow to that thread) and with its start label. The streamed summary sits in a 320pt right-hand column whose numbered citation chips highlight their node; it is asked for the pages in visit order ("Page N: title (host)" and text), and a thread of only search results or blank pages gets one sentence saying there isn't enough content instead of a model summary. List and Map (labelled), Ask (sparkle) and Export sit in the view's 32pt top bar. Ask (⌘K or the glyph) opens over Threads, Vault, Board or Mail without leaving them; on Threads it is grounded on the selected thread ("This thread"). Threads record browsing provenance rather than replacing tab folders. Threads, Vault, Mail and Board render inside the page card under a 32pt bar with the view title and its glyph actions.
- Annotations (`docs/design/graphene-language.md` §5.3): selecting text in a page shows a small card 8pt above it (below when there is no room) with Save (⌘D), Note and Ask; Note opens an editor beside the selection (below when there is no room, Escape cancels) and Ask opens the chat panel with the selection attached. Saved quotes are marked in the page with the citation mark (`note:<uuid>`, `data-graphene-kind="note"`) on every load; hovering one raises it and shows an accent dot in the margin that opens the note card (Edit, Open in Vault). The card, bar and dot take the page's light or dark scheme.
- Vault: a list of notes, newest first: the quote in serif beside a hairline rule, the note under it and a provenance line (favicon, page title, space, relative date). The top bar holds the filter field, a By page toggle (notes under their page on a depth-1 hairline tree), Ask my notes and Open folder; a selected row adds Edit, Delete, Copy as Markdown and Add to Board. Clicking a quote opens the page at the passage, clicking the title opens the page, and rows drag out like shelf chips. Notes are also individual Markdown files. Save notifications offer View. Legacy daily Markdown exports are not rewritten by edits/deletes. The sidebar's Vault shelf, above the footer, shows the current space's latest saves (four, three below 208pt of content width) as serif chips: click opens the source, hover shows the whole quote, drag out drops the note as Markdown. It is hidden with no notes, in the archive view and in private windows.
- Boards: persistent space-scoped page, note and quote cards on the 28pt hex lattice (no fade), snapping to the lattice on drop and resize, with two-finger pan. Page cards show favicon, title, host and an open tab's cached thumbnail; quote cards set Vault text in the serif quote face beside a rule with a provenance line. Dropping a sidebar tab, a Vault shelf chip or a Vault row makes the matching card. When the knowledge graph records one card's page as the other's parent, a `threadLine` connector joins them automatically and follows drags. The bar holds Add note, Add link, Export Markdown and Clear. Physical move/resize and full export acceptance remain unverified.
- Chat: streaming multi-turn conversations, tab/context chips, slash skills, Stop, Regenerate, Copy, citations and per-space/profile history (last 50 conversations). Default presentation is a floating panel inset 16pt over the page, with a 420pt default width, 360–560pt resize range and 12pt corners. Settings → Appearance retains Docked as an option. The panel is titled Ask. A line under the title shows what it can see ("This page", "N tabs", "This space's notes", "Nothing yet"). Attached sources sit in a strip with an Add chip. Answers carry numbered citation chips inline, one per cited passage, and a sources line with one entry per source; each citation holds the shortest exact excerpt of what the model received that supports its sentence (a sentence of at most 40 words, or a single infobox row). A sentence the answer repeats verbatim from a passage is set as a serif quote. Scrolling to a mark centres it vertically in the area the floating panel leaves clear; a chip whose mark sits behind the panel says so in its help text. Hovering a Vault-note chip shows its quote. Chips for the current page link to marks in the page, which are cleared on close, regenerate and navigation; the in-page marks come from the G3 `cite.js` API. An answer that cites nothing says so. Header actions and a rounded composer with @, /, skill chips and send/stop controls remain wired. Source search works without a model. Apple is the default provider; optional OpenAI-compatible and Anthropic providers require consent, with keys in Keychain. Personal memory and AI title/download-name suggestions are opt-in.
- Writing: focused text fields, textarea and contenteditable can request drafts with explicit Replace/Insert below/Copy; password/payment fields are excluded. Shift-hover link summaries and note-to-Chat drops are implemented. Rich-editor replacement, hover previews and drag acceptance are not fully verified.
- Media/downloads: audible HTML-media state and Now playing controls; PiP exposes an on-page button for real user activation, but a floating PiP window is not verified on the tested WKWebView. Downloads have progress/history and completed-file actions; interrupted downloads are labelled, not resumed automatically.
- Mail: retained read-only Gmail integration and web fallback when OAuth is not configured (the bar then reads "Read-only. Graphene never sends mail."). The inbox uses 44pt two-line rows without avatars (unread shows an accent dot), grouped into conversations by Gmail thread with replies indented under the first message on the thread connector and collapsed to the latest three. The message body renders on the reader sheet in the reading face, and its links open as child tabs of the current tab. WP9 fixes its local callback listener's completion/socket lifecycle; live Gmail authentication was not tested.

## Shortcuts

Defaults below can be remapped in Settings → Shortcuts. Native editor and system shortcuts remain reserved. An implementation mapping is not proof that every focused-control combination was exercised.

| Shortcut | Action |
| --- | --- |
| ⌘T / ⌘W | Open navigation palette / close tab |
| ⇧⌘T | Reopen closed tab |
| ⌘L | Edit location (expanding address container in Top tabs, palette in Sidebar) |
| Tab / Right Arrow in palette | Toggle Ask/Search / accept inline completion |
| Enter / ⌘Enter / ⇧Enter in palette | Open / open new tab / open split |
| ⌘, | Native Settings and shortcut remapping |
| ⌘⌥5 | This space’s Board |
| ⌘P | Print the focused webpage |
| ⌘G / ⇧⌘G / ⌘E | Find next / previous / use page selection for Find |
| ⇧⌘W | Close window |
| ↑ / ↓ / Enter in Threads list | Select thread / resume browsing |
| ⌘= / ⌘− / ⌘0 | Zoom in / out / reset |
| ⌘+ | Zoom in (alternative) |
| ⇧⌘R | Toggle Reader |
| Menu / command bar | Site Controls, Edit Site Boost, Zap an Element, Save Page As…, Open in Default Browser |
| ⌥⇧⌘C | Copy URL as Markdown |
| ⇧⌥⌘→ | Add a new split pane |
| ⌘K | Toggle floating Chat (or Docked, per Settings → Appearance) |
| ⇧⌘F | Ask on Page |
| @ / @all in chat | Attach open tabs / tabs in this space |
| @, + and / buttons in chat | Open tab attachments / skill picker without submitting |
| /summarize, /explain, /compare, /tldr | Run an editable skill in chat |
| Return in writing-help custom instructions | Generate a draft for explicit preview and insertion |
| Drop a Vault card into Chat | Attach that note, subject to the current profile and capture policy |
| ⌘D | Save the page's selected text to Vault and mark it; with no selection, open the Save to Vault sheet |
| ⌘F | Find in page |
| ⌘R | Reload |
| ⌘[ / ⌘] | Back / forward |
| ⌘⌥1–4 | Web / Threads / Mail / Vault (also Library popover and command bar) |
| ⌘1–8 / ⌘9 | Select numbered tab / last tab in this space |
| ⌘N / ⇧⌘N | New window / private window |
| ⇧⌘A | Archived tabs |
| Library / command bar | Threads, Vault, Mail, Board and Downloads |
| Command bar “Tidy Stale Tabs” / Today hairline menu | Archive stale Today tabs now, respecting Settings → General |
| ⌘S | Show or hide sidebar |
| ⇧⌘L | Toggle light / dark |
| ⇧⌘[ / ⇧⌘] | Previous / next tab in this space |
| ⌘⌥N | Create a space |
| ⌃1–9 | Switch to a space (may conflict with Mission Control) |
| ⌃Tab / ⇧⌃Tab | Recent-tab switcher; release Control to select |
| ⌃⌘P | Pin / unpin current tab |
| ⌥⌘← / ⌥⌘→ | Previous / next tab |
| ⌥⌘↑ / ⌥⌘↓ | Add vertical / horizontal split (up to four panes) |
| ⌃⌥⌘↑ / ⌃⌥⌘↓ | Reorder current tab within its section/folder |
| ⌥⌘P | Request Picture in Picture for the largest playing video |
| Space over a pin/favorite / Escape | Peek / close Peek |
| ⇧⌘C | Copy current link |

## Local data

Normal root: `~/Library/Application Support/Graphene`. With `GRAPHENE_DATA_DIR`, the files below live under that directory instead.

| Path under data root | Contents |
| --- | --- |
| `session.json` | Schema-v2 tabs, spaces, profiles, splits, selection and workspace state |
| `settings.json` | Settings, routing, shortcut overrides, onboarding and AI configuration (not API keys) |
| `graph.json` | Pages, visits, edges, captured text and thread summaries |
| `annotations.json` | Vault note index and provenance |
| `archive.json` | Archived tab metadata |
| `boards.json` | Board cards and geometry |
| `downloads.json` | Download history and destination paths |
| `sites.json` | Host zoom, permission and blocking policies |
| `boosts/<host>.json` | Site CSS/JavaScript, presets and Zap selectors |
| `chats.json`, `skills.json`, `memory.json` | Conversation history, editable skills and opt-in personal context |

Normal Markdown notes live at `~/GrapheneVault/notes/<id>.md`; isolated development notes live under `<GRAPHENE_DATA_DIR>/Vault/notes/`. Earlier `~/GrapheneVault/annotations/YYYY-MM-DD.md` exports remain historical files. WebKit cookie/cache stores are managed by macOS outside this directory; development roots namespace their store IDs separately from production. Copying a development root therefore does not clone its cookies. Provider/Gmail credentials use Keychain rather than these JSON files. Diagnostic `window.txt`/OAuth logs and, when `GRAPHENE_DEBUG=1`, the local `cmd.txt` driver can also be present.

Session/settings extensions use optional Codable fields for compatibility. Writes are atomic per file, not a transaction spanning every file. Schema-v1 sessions are backed up before migration; unreadable or newer-version sessions are preserved instead of overwritten. Back up your data before using development builds.

Favicons use same-origin discovery/redirect policy, bounded responses and a disk cap of 128 icons/8 MiB. Thumbnail memory is capped at 40 across windows and excludes private pages. Browser pages, suggestions and configured Gmail still make network requests. Captured text remains local unless explicitly sent to a selected remote AI provider. Shift-hover summaries may fetch the link target without browser cookies.

## Boundaries

- This is WKWebView, not Chromium. Chrome extensions, cross-device sync, connected work-tool automation and a scheduled digest are absent. Little Graphene is disabled and out of scope, with no menu or settings entry.
- Profiles isolate website storage, not the shared Threads/Vault library. AI context additionally filters private, excluded and other-profile sources. Private windows use nonpersistent website stores and do not persist browser knowledge/session/chat data.
- Password-manager integration equivalent to Safari AutoFill is not implemented. Graphene does not read Apple Passwords or import passwords. Embedded sign-in compatibility depends on the site/WebKit; an external-browser escape hatch is available.
- Camera/microphone Allow does not bypass macOS consent. Policy changes do not revoke an already running stream. Location and notifications are disclosed as WebKit/macOS-managed, not exposed as fake per-site toggles. Clear-site data can include a parent-domain WebKit bucket and sign sibling sites out.
- Certificate errors fail closed. No unsafe “visit anyway” bypass is provided without a reliable HSTS policy. Certificate details depend on WebKit serverTrust, not merely HTTPS in the address.
- Blocking uses a GPL-3.0-or-later EasyList-derived third-party network subset, not full EasyList/EasyPrivacy. Notices ship in Resources; `scripts/make-blocklist.py` rebuilds it. No invented blocked-request counter is shown.
- Reader/capture are DOM-text extraction, not PDF/image/video understanding or Mozilla Readability. Find excludes embedded frames. Media detection excludes cross-origin frames and Web Audio, and only reports unmuted playback.
- AI is fallible, not an autonomous web-research agent. The WP9 `/summarize` check on example.org returned “I cannot fulfill that request.” This remains an unresolved model-quality failure despite earlier successful answers. Remote context is capped at 24,000 characters; Apple uses a 6,000-character source budget and up to 700 response tokens. Real remote providers, arbitrary rich editors and live Gmail still require separate verification.
- Production signing/notarization, updater/distribution, exhaustive keyboard/accessibility, Reduce Motion and full end-to-end regression sign-off remain outstanding. Ad-hoc signing is not a production release signature.

## Verification

Arc-look pass (D1–D5, September 2026): the design tokens in `docs/design/arc-look.md` replaced the WP10 geometry. Rows are now 36pt at 40pt pitch, favorite tiles 44pt, the page card sits 8pt from the window edges, and the page toolbar (and the library views' top bar) is 32pt. WP10 screenshots and measurements above describe the earlier geometry. D5 restyled Settings, onboarding, Threads, Vault, Mail, Board, Archive, Downloads, writing help and Reader to the tokens and adds a source grep gate (`ArcLookSurfaceTests`) against literal font sizes, radii, opacities and raw colours in those files. Builds and XCTest pass; visual verification of the Arc-look surfaces is pending the computer-use pass and is not claimed here.

WP10: ordinary XCTest run executes 91 tests, one opt-in live-model test skipped, zero failures. Empty/paused toast ticks and unchanged media polls no longer invalidate the shell. On an idle isolated profile, two five-second `sample` captures started 60 seconds apart; `ps` read 0.8% then 0.1% CPU. This is not a loaded-site or 60-tab stress benchmark.

The separate real-model harness exercised nine page/skill combinations. Example.org `/summarize` and `/explain` still refused, while the other seven produced responses; generated-answer factual/citation quality is not a blanket pass. Skills and ordinary questions now use the same tested request builder, but that does not solve the provider refusal. Settings → Mail was observed with Connect disabled because the isolated profile has no OAuth configuration. See the WP10 report and `answers.md` for those failed/blocked acceptance gates.

```sh
GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile/tests swift build
GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile/tests swift test
swift build -c release
./scripts/build-app.sh
codesign --verify --deep --strict .build/Graphene.app
```

WP9 (September 11, 2026): debug/release builds and strict ad-hoc signature verification pass with no compiler warnings in the final logs. XCTest executes 87 tests, with one opt-in live-model test skipped and zero failures. Five new local loopback tests cover callback completion, timeout, repeated start/stop/wait and a late timeout after deallocation. The baseline tests reproduced both leaked-listener behavior and a double-resume continuation crash.

The copied isolated stress profile contains 60 public test pages, 15 in each of four spaces. A relaunch registered its window in 1.82 seconds, preserved all 60 visits, and remained alive after more than five minutes. This does not establish under-three-second interactive readiness or default auto-discard after only five minutes. Memory/CPU samples and exact measurement boundaries are in the WP9 report.

Actual desktop evidence includes onboarding with default choices, browsing, Find counts, native Print, populated Threads, disconnected Mail, empty Board and the failed real-model summary. The complete requested interaction sweep is not finished. See `docs/parity/shots/wp9/verification.md`; earlier captures remain in the other work-package directories, with their original limits intact. `docs/parity/matrix.md` preserves the historical baseline and adds an honestly qualified Graphene now column.
