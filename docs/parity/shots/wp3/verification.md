# WP3b verification

## Build and tests

- `swift build`: clean, no warnings in final log.
- `swift test`: 31 tests passed, zero failures. Added insertion-point completion acceptance and Sidebar/Top Tabs session round-trip tests.
- `./scripts/build-app.sh`: succeeded. `codesign --verify --deep --strict .build/Graphene.app`: succeeded.
- `git diff --check`: clean. No commit made; reference files untouched.

## Actual GUI exercise

Launched only with GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile and GRAPHENE_DEBUG=1. Owned process IDs across rebuilds: 62008, 71139, 73144. The profile already contained WP2 test pages and splits; these were reused rather than erased.

Computer-use captures worked. Its Cmd+T input returned approval prompt timed out, so input was switched to the explicitly requested System Events fallback. Subsequent inputs were routed by owned Unix PID and screenshots captured by owned window ID with screencapture.

Important isolation error: the first name-based System Events Cmd+T targeted a pre-existing Graphene instance rather than the owned test process. This may have opened a blank tab in the user's existing instance. No URL was submitted there and no user profile files were intentionally opened or edited. This was not undone by guessing which tab to close. All later input was PID-scoped. Thus this run cannot claim the user's live instance was completely untouched.

Verified with screenshots:
- Command palette Actions section and Pin Tab selection.
- Palette Pin Tab, New Folder and Switch layout actions. Sidebar evidence shows the pinned Example page and New Folder.
- Natural-language Ask row, @ picker, arrow selection and attached-tab chip. Sending to Ask displayed the retained panel with current-page and attached-tab context; successful model output is not claimed.
- Inline grey completion for `exa`, then Right Arrow acceptance as `example.com/`.
- Top-tabs rest state with pinned chip, regular tabs, navigation toolbar, downloads/menu and domain at rest.
- Cmd+L focuses the inline toolbar field and displays `https://example.com/`.
- Switching back restores the sidebar and existing split pages. Session readback after quit reports layout=sidebar and both Little flags=false.

A stale SwiftUI result-list identity bug was found during rapid typing and fixed by using result IDs for rows/scroll targets and resetting the list identity when membership changes. Rebuilt and re-exercised Ask and @ results after the fix.

## Evidence

- command-actions.png
- ask-row.png
- mention-picker.png
- mention-attached.png
- autocomplete-prefix.png
- autocomplete-accepted.png
- top-tabs-rest.png
- top-tabs-focused.png
- sidebar-restored.png

Nine screenshots. Reference Arc/Dia screenshots were viewed with vision. Their quiet native colors, hairlines and restrained framing informed the implementation. The Dia reference is vertical tabs, not a captured horizontal layout, so pixel-perfect horizontal parity is not claimed.

## Remaining verification and implementation limits

- Space-popover clicks did not produce a capturable open popover in two fallback attempts; stopped per the brief. Sidebar content is wired into the popover but its opening and nested presentation remain unverified.
- Drag reorder, middle-click close, physical hover-close interaction and crowded-tab overflow scrolling have handlers but were not successfully exercised with desktop input. Keyboard pinning and layout switching were exercised.
- Settings, downloads, Reader, clear-site confirmation and export have real presentation/handlers, but not every catalogue action was individually GUI-tested. No destructive site-data clearing was attempted.
- Top toolbar questions submit directly to Ask; the explicit Ask/Search chip and question-preview row live in the expanded Cmd+T palette. Typing a non-URL @ query transfers to its context picker. This is not identical to keeping the entire suggestion/Ask list underneath the inline toolbar field.
- Search suggestions use the existing cancellable provider implementation and offline fixture tests; live endpoint delivery was not verified.
- The Ask panel can constrain the top strip to the page column, rather than spanning the full window. This is a remaining layout-polish gap.

## Cleanup

Each owned instance received Cmd+Q. Final `ps -p 62008,71139,73144` returned no processes. Ran the requested profile-targeted pkill cleanup with a self-excluding pattern. Pre-existing Graphene processes were not terminated.
