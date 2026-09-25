# WP2 verification

Implemented synchronously without delegation or scheduled work. No commits. Reference images were read, not modified. The pre-existing Graphene PID 66950 was left running and untouched by cleanup.

## Build and tests

Final `swift build` and `swift test` succeeded. 25 XCTest cases passed, zero failures and no compiler warnings in final output. Thirteen lifecycle tests cover archive timing with an injected clock, pin base-URL restoration, MRU selection, split session round-trip, window selection/shared collections, private no-write behavior, capture exclusion/pause/forget, discard protection, lazy restoration, schema backup, download history, dialog limits and range selection.

`./scripts/build-app.sh` produced `.build/Graphene.app`. `codesign --verify --deep --strict .build/Graphene.app` succeeded. The bundle contains http/https URL registration.

## Isolation and cleanup

Owned direct launches used `GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile GRAPHENE_DEBUG=1` (PIDs 92697 and 9717). Both were quit with System Events Cmd+Q and verified exited. `pkill -f '[g]raphene-dev-profile'` was also run. The development directory already contained WP1 fixture state, so WP2 used an additional named test space rather than deleting the existing fixture data.

An ordinary `open -a` selected the pre-existing instance rather than the owned instance. The successful external-handoff check used:

    open -n -a /Users/rutmehta/Developer/graphene/.build/Graphene.app --env GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile-external --env GRAPHENE_DEBUG=1 https://example.com

Its owned PID 14911 displayed Little Graphene with Example Domain, then was quit with Cmd+Q and verified exited. No launch omitted an explicit isolated data-directory environment.

## UI evidence

The computer_use tool captured the native windows. Its first input action returned `approval prompt timed out`; no further computer_use input approvals were requested. Per the brief, subsequent input used System Events and screenshots used window-scoped `screencapture -x -l`. Several early captures targeted the other owned window; those split captures were overwritten with the correctly identified window. This was a useful distinction between independent window state and failed rendering.

Seven saved screenshots:

- `archive-list.png`: closed Example Domain present in the archive, grouped by date, with Restore/Delete.
- `archive-restored.png`: Cmd+Shift+T restored Example Domain and emptied the archive.
- `mru-switcher.png`: horizontal tab strip captured while Control was held using System Events; Control was then released.
- `split-two-tabs.png`: Swift and Example Domain in two panes with divider and subtle selected-pane border. Final composition was set with the debug driver. A prior keyboard split was also observed in the other owned window.
- `peek-overlay.png`: centered live Example Domain preview with close and Open as tab. Presented using the debug driver.
- `little-graphene-external.png`: external http/https handoff displayed a 760×560 Little Graphene panel.
- `now-playing-youtube.png`: Big Buck Bunny playing on YouTube, audio tab badge, and Now playing row above the space switcher.

Arc/Dia reference images were inspected with vision. Graphene retains quiet tinted chrome, hairlines, system typography and inset page surfaces. Little Graphene's native title/menu appearance appears too pale against the light toolbar in the captured system appearance; that contrast refinement remains unfinished.

## Outstanding acceptance / limitations

This is not a fully completed parity sign-off.

- Actual Picture in Picture is blocked in the tested macOS WKWebView: the playing YouTube video reported `webkitSupportsPresentationMode('picture-in-picture') == false` and remained `inline`. The menu/shortcut/JS request path and unsupported-state message exist, but no floating PiP window was produced. The public SDK's `allowsPictureInPictureMediaPlayback` configuration property is iOS-only; no private WebKit preference workaround was introduced.
- Physical drag-divider/right-edge-drop, hover-thumbnail timing, pinned-link Shift/Command routing, batch context actions, Little promotion/Escape, private-window UI and JavaScript suppression checkbox were not all exercised end to end. Their implementation and model tests must not be confused with verified gestures.
- Download persistence has a tested model and is connected to real WKDownload progress/delegate callbacks and the popover, but an actual downloaded file, Finder/Open actions and completion animation were not smoke-tested.
- Snapshot caching currently caps at 40 per window, not 40 across every window. Private stores are nonpersistent per engine rather than a shared cookie store across the private window's tabs.
- General and Privacy settings are provided through the existing Settings menu, not a new full Settings scene.
- Session writes are individually atomic across session.json and archive.json, not a transactional two-file commit. Archives are capped on insertion; an externally oversized archive file is not trimmed merely by loading it.

## Files

Updated AppState, GrapheneApp, DebugDriver, Tab, KnowledgeGraph, Vault, WKWebEngine, BrowserDownload, WebContainer, RootView, Sidebar, WindowAccessor, Favicon, README and scripts/build-app.sh. Added BrowserLibrary, TabLifecycle, TabSplit, DownloadStore, DialogGuard, ArchiveView, TabSwitcher, SplitView, LittleArcWindow, PeekOverlay, TabPreview, WindowState, CapturePolicy, DownloadsView, BatchTabMenu and LifecycleTests. Existing Threads, Vault, Ask and Mail remain available in normal windows.
