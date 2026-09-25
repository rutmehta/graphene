# Performance audit: interaction hot paths

September 2026. Scope: the owner's report ("slow to ⌘Tab to, slow for websites to load in the profile with a lot of tabs and pinned tabs, slows the whole computer"). Idle CPU was already fine (0.6%) and restoring a 60-tab session was lazy (114 MB, 0% CPU), so this audit looks at what happens when you interact: switching tabs, ⌃Tab, loading pages, sidebar redraws. A later measurement from the coordinator showed the machine itself under heavy memory pressure (47 GB used, 14 GB compressed, load average 46) while Graphene's main process sat at 112 MB. That moved the WebContent-process items (§8, §1, §2, and the engine-acquisition list) to the top of the list.

All line numbers in "Found" refer to the parent commit `51f28d4`. The method was code reading plus headless `swift test` measurements; the app was not launched.

## Confirmed hot paths, worst first

| # | Path | Cost before | After |
|---|------|-------------|-------|
| 1 | The menu bar rebuilt its action table once per menu item (about 93 builds) on every AppState change, and each build computed the space's full thread list | 427 ms per AppState change (debug build, 2,000-visit history, 60 tabs) | 0.19 ms: one table per change, and an O(1)-ish `hasThreads` check |
| 2 | `WindowAccessor.updateNSView` wrote `window.txt` to disk (atomic write) and reassigned the window's style mask after every RootView update | One synchronous file write on the main thread for every shell change (4 per second while a toast showed) | Written only when the window number changes; window properties assigned only when they differ |
| 3 | Loaded background tabs were never capped, and media polling woke every loaded page every 2 s | One WebContent process per tab ever visited (until 30 min idle), each woken every 2 s | At most 12 background pages stay loaded (LRU, configurable); memory-pressure events discard more; only visible and audible pages are polled |
| 4 | The knowledge graph was JSON-encoded and written on the main thread 1.5 s after every navigation, snippets included | 61 ms per save for 2,000 pages (debug build), growing with history | Encoded and written on a background serial queue |
| 5 | Toasts ticked through `AppState` every 250 ms | 4 full-shell redraws (plus #1 and #2 each time) per second while a toast showed; closing a tab shows one for 5 s | The countdown lives in the overlay; AppState publishes once when the toast leaves |
| 6 | `Tab.engineDidChangeState` republished eight properties on every WebKit KVO callback, progress included | Every view observing the tab (sidebar row, toolbar, page, card) redrew on every progress tick | Properties publish only on change; progress is on its own `LoadProgress` object, throttled to 15 Hz, which only the progress bar observes |
| 7 | Session restore created and threw away a `WKWebView` per restored tab; reopening a closed tab or undoing a branch close loaded every page at once | 60 web views created at launch; N page loads per restore | Restored tabs have no web view until shown |

## 1. Thumbnails (`Store/ThumbnailCache.swift`, `UI/TabSwitcher.swift`, `UI/TabPreview.swift`)

**Found.** `activeTabID.didSet` (`App/AppState.swift:45`) called `captureThumbnail(old)` on every tab switch, synchronously, for the outgoing tab, whether or not its page had changed since the last snapshot. The snapshot was 300pt wide (`Model/TabLifecycle.swift:14`) and used `loadedEngine`, so it never acquired an engine, but it did make the outgoing page's process render a snapshot at the moment of the switch. The cache was bounded (40 entries, `ThumbnailCache.swift:10`). The ⌃Tab switcher built a tile for every tab in a non-lazy `HStack` with a linear `app.tabs.first` search per tile (`TabSwitcher.swift:12–14`), and its state (`switcherIDs`, `switcherIndex`, `AppState.swift:55–56`) was published on `AppState`, so every ⌃Tab press redrew every window.

**Changed.**
- `TabLifecycle.needsThumbnail`: a snapshot is taken only of the selected, finished, loaded, non-private page, and only if the cache has not captured that URL (once per navigation).
- `AppState.scheduleThumbnail` runs 800 ms after a switch (`activeTabID.didSet`) or after a displayed page finishes loading (`Tab.engineDidFinish` → `AppState.tabDidFinishLoad`). A newer request cancels the older one. The outgoing tab is never snapshotted.
- Width is 240pt (`TabLifecycle.thumbnailWidth`). The cache records each entry's URL and forgets it on eviction, or when a snapshot fails.
- ⌃Tab state moved to `TabSwitcherModel`. `RootView` hosts it through `TabSwitcherOverlay`, which observes only that model. Tiles are laid out in a `LazyHStack` with one dictionary lookup per body.

**Expected effect.** No snapshot work on the switch itself. Switching back and forth between tabs takes no further snapshots. ⌃Tab cycling no longer redraws the sidebar, toolbar or menus.

## 2. Media polling (`Model/TabLifecycle.swift`, `UI/RootView.swift`)

**Found.** `pollMediaAndDiscard` (`TabLifecycle.swift:21–31`) ran every 2 s (`AppState.swift:230`) and called `evaluateJavaScript` on every loaded tab (`for tab in tabs`, line 23), so the cost grew with the number of loaded tabs and woke every background WebContent process every 2 s. In addition, `BrowserPage` ran its own 2 s loop for the displayed tab (`RootView.swift:202–209`) and assigned `tab.isPlayingAudio` unconditionally, which republished the tab (and redrew its card, toolbar and sidebar row) every 2 s. AppState was already published only on change (`mediaTabID` guarded; covered by `IdlePublicationTests`).

**Changed.**
- `TabLifecycle.pollSet`: each poll asks only displayed tabs and tabs last known to be audible. Every 15th poll (30 s) sweeps all loaded tabs, so a background page that starts playing on its own still gets its speaker glyph.
- A discard candidate that was not asked in the current poll is asked once before it is discarded (`AppState.discard(_:verified:)`), so a playing page is never put to sleep on stale state.
- The `BrowserPage` loop is removed. The timers have tolerance (0.5 s and 5 s) so the system can coalesce their wake-ups.
- Polling reads only `loadedEngine`, so it never loads a discarded tab (`testPollNeverLoadsADiscardedTab`).

**Expected effect.** Background WebContent processes are woken every 30 s instead of every 2 s. Per poll, JavaScript runs in one or two pages instead of N.

## 3. AppState fan-out

**Found.** `AppState` forwards `library`, `graph`, `boards` and `vault` changes (`AppState.swift:218, 242–244`), and the shell's views hold it as an `EnvironmentObject`, so any publish re-evaluates every sidebar row, the toolbar, the menus and RootView. Frequent publishes that carried no change:
- `persist()` assigned `settingsError = nil` and `sessionError = nil` after every save (`AppState.swift:1095, 1119`). That meant two publishes per tab switch or resize, because `activate` → `persistSoon`.
- `KnowledgeGraph.save` assigned `errorText = nil` (`KnowledgeGraph.swift:304`) after every navigation.
- `BrowserFocus.shared.app` was reassigned on every `didBecomeKey` (`WindowState.swift:31`), including every ⌘Tab back into the app, which rebuilt the whole menu bar (see #1).
- Toast ticks (#5) and ⌃Tab (§1).

Per-tab progress, loading and title never went through AppState (`BrowserLibrary.tabs` holds class references, so changes to a `Tab` do not publish the library). Hover state was already view-local: `hoveredTabID` is a plain var.

Per-body recomputation: `Sidebar.rows` rebuilt `todayProvenance()` on every body (`Sidebar.swift:124`). Every row computed `branchParent` through `app.branchChildren(of:)`, which scans all tabs (`Sidebar.swift:571`), and it did so unconditionally because the accessibility actions read it. That is O(n²) per sidebar redraw. `KnowledgeGraph.threads` was rebuilt from all visits on every body of the Resume page, the Ask panel (twice, `RootView.swift:63–64`), the Threads list (four times) and the command bar. `TabContextMenu` built the full action table once per item (`TabContextMenu.swift:50`).

**Changed.**
- Error fields publish only when they change.
- `BrowserFocus.focus(_:window:)` publishes only when the focused browser changes.
- `todayProvenance` is cached per (Today ids, parents, collapsed set). `ProvenanceLayout.parentIDs` gives each row its `isBranchParent` flag, so no row scans the tab list.
- `KnowledgeGraph.threads` results are cached until `nodes` or `visits` change.
- `GrapheneCommands` and `TabContextMenu` build one `CommandMenuTable` per body. The Export command's enabled state uses `KnowledgeGraph.hasThreads` instead of building the thread list.
- A test counts `objectWillChange` on AppState: saves, ⌃Tab cycling, page progress and loading publish nothing (`testRoutineStateChangesDoNotPublishTheShell`).

**Not changed.** Moving each sidebar row off `AppState` entirely, so rows take values rather than the environment object, would touch every row's actions. It is not needed once publishes are rare and each redraw is cheap. Graph publishes on navigation (`recordVisit`, `attachText`, `setTitle`) still redraw the shell once each; with #1 fixed those redraws are cheap.

## 4. Favicons (`Store/FaviconStore.swift`, `UI/Favicon.swift`)

**Found.** Each `Favicon` view runs `.task(id: url) { await store.fetch(url) }` (`Favicon.swift:49`). When a space with 20 tabs of one site appeared, 20 fetches started together. There was no in-flight dedupe: each call set `requests[key] = UUID()` (`FaviconStore.swift:150`), so every later call orphaned the earlier one, whose downloaded icon was then discarded by `requests[key] == request` (line 154). The later calls skipped their candidates because of the 60 s attempt guard, so the storm could end with no icon until a minute later. Icons loaded from disk had no recorded source (line 146), so every page load that declared an icon re-downloaded it (line 147). Redirects were already restricted to the same origin (`IconRedirectPolicy`).

**Changed.** One fetch per origin runs at a time (`inFlight`), and later callers await it. The disk cache is checked before the network in both paths. A `.source` sidecar records which declared URL the cached bytes came from, so a page that still declares it is served from disk (seven-day freshness). `FaviconStore(directory:loader:)` makes this testable.

**Expected effect.** One network request per origin per week, instead of one per row appearance or per page load.

## 5. Web engine (`Web/WKWebEngine.swift`, `Model/Tab.swift`)

**Found.**
- KVO on `title`, `url`, `canGoBack`, `canGoForward`, `estimatedProgress` and `isLoading` (`WKWebEngine.swift:143–148`) → `Tab.engineDidChangeState`, which assigned eight `@Published` properties unconditionally (`Tab.swift:114–123`).
- `applyBlockingIfReady` ran `removeAllContentRuleLists()` + `add` on every main-frame navigation action and again on the response (`WKWebEngine.swift:85–90, 424, 438, 446`). That is two rule-list swaps per navigation, each resent to the page's process, plus a `notifyState`.
- Saved-note marking after every load (`WKWebEngine.swift:376`, retry loop at 295–302) made two JavaScript calls on pages with no notes. The 3 × 700 ms retries run only while a page's notes are unmatched, which is correct.
- The injected history hook posted a `dirty` message on every keystroke in any input and every second on any page with `onbeforeunload` set (`WKWebEngine.swift:594–598`), for every open tab.
- The citation hover handler is guarded (`CitationLinker.markHovered` publishes only on change).

**Changed.**
- `Tab` publishes each property only when it changes.
- Progress goes through `LoadProgress`, at most 15 publishes a second. Start, restart, finish and `isLoading` changes always publish, and the last throttled value is flushed at the end of its interval.
- The content blocker is swapped only when the host's policy differs from what is installed (`installedBlocker`).
- A page without saved notes gets only the theme call; the notes call is skipped unless this document was sent notes before.
- `dirty` is posted once per document.

**Expected effect.** Page loads no longer redraw the tab's views dozens of times. Navigations stop resending the 50k-rule list to WebContent processes twice each.

## 6. Sidebar rendering (`UI/Sidebar.swift`)

**Found.** Rows sit in a non-lazy `VStack` inside the outer `LazyVStack` (`Sidebar.swift:74–82, 125`), so all rows are built. `.id(app.activeSpaceID)` (line 84) rebuilds the list on a space switch, on purpose, for the slide transition. `ThreadLines` animates on `value: connectors` (line 181), which changes only when the branch geometry or the active branch changes. The connector shapes are cheap `Path`s, not a `Canvas`. The per-row costs are covered in §3.

**Changed.** Only the provenance cache and `isBranchParent` described in §3. The `.id` and the stacks are left alone: making the rows lazy would change the spacing contract, and the rebuild on a space switch is the transition itself.

## 7. Tab switching (`AppState.activate`, `activeTabID.didSet`, `Web/WebContainer.swift`)

**Found.** On switch: `claimTab` (a scan of the windows), `recentIDs` bookkeeping, `revealInBranch`, a synchronous thumbnail of the outgoing tab (§1), `persistSoon` (0.6 s later, then two error publishes, §3), and `focusBrowser`. `WebContainer.makeNSView` acquires the incoming tab's engine and, for a discarded tab, restores its URL, which is required. The citation linker, thread recording and saved-note marking do not run on a switch; they run on navigation. Favicons are served from memory.

**Changed.** The thumbnail is now delayed (§1) and the save no longer publishes (§3). Nothing heavy remains synchronous on the switch.

## 8. Discard policy and memory pressure (`Model/TabLifecycle.swift`, `Model/Settings.swift`)

**Found.** Only time-based discard existed (30 minutes by default), and even that excluded the ten most recent tabs per window. Every tab visited in the last half hour kept its WebContent process, with no memory-pressure response.

**Changed.**
- An LRU cap: `TabLifecycle.lruVictims` keeps the 12 most recently active loaded background tabs (`Settings.backgroundTabLimit`, stored as `loadedTabs` and set under Settings → General → Tabs as 6, 12 or 24). Beyond that, the least recently active are discarded on the next poll. Displayed tabs never count. Playing, downloading, loading and unsaved-form tabs are kept even beyond the cap.
- A memory-pressure path: `DispatchSource.makeMemoryPressureSource([.warning, .critical])` on the main queue (`startMemoryPressureMonitor`). A warning discards down to half the cap; a critical event discards every eligible background page (`relieveMemoryPressure`).
- Discarded tabs stay discarded until shown. Session restore now makes tabs without a web view (`makeTab(loaded: false)`, `Tab(engine: nil)`). Reopening a closed tab and undoing a branch close set the URL and leave loading to the first display.

**Expected effect.** Background memory is bounded by about 12 WebContent processes, whatever the tab count. On a machine under memory pressure, Graphene gives pages back as soon as the system asks.

## Paths that acquire an engine (`tab.engine`) for a tab that is not on screen

`Tab.engine` creates a web view and loads the tab's URL if it was discarded. Audited call sites:

| Call site | Tab | Status |
|-----------|-----|--------|
| `AppState.tab(_:didNavigateTo:)` capture task (`AppState.swift:812, 815`) | The navigating tab, after an `await`. If the tab was discarded meanwhile, the page reloaded just to read its title | **Fixed**: uses `loadedEngine` |
| `ChatView.attach` (`ChatView.swift:373`), from Ask's `request.tabIDs` (multi-selection) and "@all · tabs in this space" | Any tab in the space. "@all" woke and reloaded every sleeping tab | **Fixed**: a sleeping tab is read from its captured graph snippet. It is woken only if nothing was captured |
| `AppState.restore` (`AppState.swift:727`), used by reopen and undo of close and branch close | Every restored tab | **Fixed**: lazy until shown |
| `restoreSession` via `makeTab` (`AppState.swift:635, 1163`) | Every restored tab got a transient `WKWebView` | **Fixed**: no web view |
| `toggleMedia` (`TabLifecycle.swift:37`) | The media tab from the Now Playing row | **Fixed**: `loadedEngine` only |
| `AppState.openTab(activate: false)`: ⌘-click, `window.open`, Mail links, `resumeThread(from:)` | New background tabs | Unchanged, by design (a background tab loads). `resumeThread` opens one tab per branch node; making those lazy would skip recording the revisit, so it is left alone. The LRU cap trims the background tabs once they finish loading |
| `ChatView.link` citations (`ChatView.swift:110`), `AppState.highlightSource` | The answer's tab or a just-activated source tab | Unchanged. Normally the active tab |
| `WebContainer`, `BrowserPage` find, `focusBrowser`, `SiteControlsPopover`, commands (zap, zoom, print, reader, save page, inspector, clear site data), `NoteComposer`, `enterPictureInPicture`, Settings | The displayed or active tab | Correct |
| `LittleArcWindow`, `PeekOverlay` | Their own tabs | Correct |
| `DebugDriver` | Debug only | Not in normal use |

Space switching selects the space's last tab (`selectSpace`) and loads nothing else. Only the tab `WebContainer` shows acquires its engine (`testDiscardedTabsStayDiscardedAcrossSpaceSwitchesAndRestore`). Sidebar rows, favicons, previews, the switcher and polling never acquire an engine.

## Suspected, not confirmed

- **WebKit's process cache.** WebKit can keep a terminated page's WebContent process around for reuse. That is not controllable through public API, so a discarded tab may not free its process immediately. It needs an Activity Monitor check in the real app.
- **`TabKeyboardMonitor`** builds the action table on every key-down in the window, to match the ⌃Tab shortcut, which the user can override. With §3's changes that costs about 0.2 ms per keystroke (debug build), so it was left alone.
- **Graph publishes per navigation** (`recordVisit`, `attachText`, `setTitle`) still redraw the shell three times per page load, background tabs included. That is cheap after #1, but coalescing them would take a separate graph-change channel.
- **Session save** (`persist()`) still encodes the tab list and up to 2,000 archive entries on the main thread, 0.6 s after each change. That was not measured as significant; moving it off-main would complicate the synchronous save at quit.
- **Download progress** publishes per `fractionCompleted` change, but only to the download views, not to AppState.
- The owner's actual graph size and the effect on their machine were not measured, because the app was not run in this pass.

## Verification

`GRAPHENE_DATA_DIR=/tmp/graphene-perf-tests swift build` builds with no warnings. `swift test` passes, including `PerformanceTests`, which covers:
- poll-set selection and never polling discarded tabs
- LRU victim choice, the AppState cap and critical memory pressure
- lazy restore across space switches and reopen
- the thumbnail policy and cache URL tracking, and no synchronous snapshot on switch
- favicon in-flight dedupe and disk reuse
- `LoadProgress` throttling and edge publishing
- a tab not republishing unchanged state
- AppState not publishing on save, ⌃Tab, progress or toast expiry
- the command table and `hasThreads` matching `threads`
- the provenance cache and its parent set

The measurements quoted above come from a throwaway `swift test` case (debug build, 2,000 pages with 16 KB snippets, 60 tabs). They are not checked in.
