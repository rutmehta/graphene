## WP9 release-readiness pass — September 11, 2026

Status: partial regression pass, not release sign-off. This section supersedes historical test totals below; earlier sections retain their original dates and scope.

- Fixed the Gmail loopback listener's double-resume continuation crash and socket lifecycle: one-shot start/wait, synchronized descriptor state, shutdown of pending I/O, listener cleanup after success, and safe late timeout completion. Five local callback/timeout/stop/deallocation tests pass without accessing Gmail or credentials. The red baseline reproduced leaked-listener behavior and a continuation double-resume fatal error.
- Updated the bundled version to 0.3.0 (build 3). Final debug build, release build and bundle build succeeded with zero compiler warnings. `codesign --verify --deep --strict .build/Graphene.app` succeeded. The bundle is ad-hoc signed and uses the debug configuration; no notarization/distribution claim.
- `swift test`: 87 XCTest cases executed, one opt-in live-model test skipped, zero failures. The ordinary suite is not a substitute for the UI/model-quality sweep.
- Real computer-use checks: onboarding with default layout/color, URL navigation, Find 1 of 2 → 2 of 2, native Print dialog and cancellation, populated Threads list/detail, Save to Vault sheet and cancellation, disconnected Mail, empty Board, Chat slash invocation. `/summarize` returned “I cannot fulfill that request.” on example.org; this is an unresolved quality failure, also confirmed in isolated chats.json.
- A copy of the isolated profile was seeded through the debug driver with exactly 60 public pages across four spaces. The rebuilt app registered a window in 1.821 seconds, restored visibly and retained the exact 60 visits through relaunch/idle/quit. At 338.95 seconds idle, the main process reported RSS 137152 KiB and 25.7% CPU. This excludes WebKit helper memory and is not a clean-idle CPU sign-off. Default discard is 30 minutes, so five minutes cannot establish that it ran.
- Fifteen PNGs are retained in `parity/shots/wp9/`, including one explicitly failed black capture; `screenshots.json` records dimensions/hashes and each file was decoded with Pillow. No prior/reference screenshots were overwritten.
- Initial exact-window captures returned 0×0; later keyboard-driven UI worked. SOM element clicks still failed with snapshot_id_required. Two coordinate Save attempts did not confirm a save, despite the existing accessible button ID/label/trait. A name-based focus call ignored the requested PID and raised another pre-existing Graphene window; no keys/clicks were sent to that instance afterward. Only explicitly isolated profiles were launched/read.
- Full sidebar/windows/site/settings/AI/editor/drag/export/toast workflows and Reduce Motion remain unverified. No claim that every Settings control survives relaunch or that all WP1–WP8 acceptance criteria pass. See `parity/shots/wp9/verification.md` for the full gap inventory.
- Owned PIDs 60482, 71092, 76158 and 81225 are stopped. The first required SIGTERM after unsuccessful Cmd+Q; the latter three exited after computer-use Cmd+Q. Profile-targeted cleanup was run. No commit, delegation or scheduled job was created.

# Rebuild verification — September 4, 2026

The app was built with Swift 6.2.4 and exercised on macOS 26.1. The final app is `.build/Graphene.app`; `scripts/build-app.sh` rebuilds and ad-hoc signs it, including the icon and annotation script.

## Automated

Seven XCTest cases pass:

- Branching, revisits, workspace scoping, and graph persistence.
- Legacy graph migration and normalized URL matching.
- Editing, reloading, and deleting notes and their Markdown files.
- Retrieving saved notes and correctly escaping web search queries.
- Preserving unreadable data files without overwriting them.
- Explicitly resuming an older thread and starting a separate new search.
- Reporting a failed note write without presenting it as saved.

`git diff --check` and strict app-signature verification pass.

## Exercised in the native app

An isolated profile and a local three-page website were used for functional verification. No test content was written to the user's actual knowledge store.

- Address-bar navigation, real link navigation, and a link opening a child tab.
- Recording the related pages as one thread, reading captured text, and opening the source map.
- Selecting a paragraph and saving it with the injected page toolbar.
- Saving a page through the bookmark button and Command-D.
- Editing a note; checking the persisted JSON and Markdown contents agree.
- Command-F and matching text within the current page.
- Research/Personal workspace separation, switching back, and both appearances.
- Restoring tabs and notes without generating synthetic browsing visits.
- Asking the on-device model about source provenance and receiving a response with links to its input sources.
- Downloading a local file through the system save panel, verifying its contents, and removing the temporary downloaded file.

Opening the real profile exposed a pre-existing startup freeze in synchronous Gmail Keychain lookup. The lookup now runs away from the main thread, only when Mail is opened, with a noninteractive authentication context. The browser was relaunched with the existing profile and responds normally. Existing page and annotation IDs were checked against a backup and are preserved.

## Limits of verification

The Gmail OAuth sign-in, live inbox access, file-upload dialog, and JavaScript dialog interactions were not exercised against third-party services. Thread export uses the native save panel but was not clicked through during this pass. Chrome extensions and a Chromium engine are not implemented. The local model is not a general web-research agent, and its answers still need source review.

Pre-existing uncommitted source changes were preserved and built on. A source snapshot was taken in `/tmp/graphene-before-rebuild`; the existing graph, session, and annotation index were backed up under `.build/profile-backup-*` before opening the real profile.

## Browser feel and shell pass — September 4, 2026

Rebuilt the window around a compact space sidebar, pinned site tiles, a 36pt page toolbar and an inset page frame. Replaced the editorial home/library typography with system type. The Arc reference was inspected locally; Dia's published design notes and Strawberry's release notes informed the restrained navigation and contextual companion.

The navigation palette opens on Command-T without creating a tab until submission. It matches current-space tabs and history, supports arrow selection, preserves cancelled new-tab input, and selects the current URL on Command-L. Ask Graphene is a companion beside the web page, with explicit captured page/space/thread scope. Library navigation temporarily hides the companion while retaining its view state. Notes keep unsaved drafts across filtering and surface changes for the lifetime of the app.

Live checks on an isolated profile:
- Immediate palette focus, typed input, Escape restoring page focus, draft retention, repeated Command-L selecting the edited URL, and reopening a history source.
- On-device page summary with source links; original page context and answer remain after switching tabs, with a visible action to adopt the new tab.
- Light and dark appearance, changing space color, pinned site tile, and actual pointer drag of an unpinned tab to the last row.
- Closing/reopening a tab, remembered active tab after switching spaces, and sidebar collapse with page focus retained.
- Companion and Vault at a reduced window size; opening the library uses the available page width. Unsaved note text survives filtering away and back.

`swift test`: 7 tests passed. The app bundle builds and is ad-hoc signed. These checks establish the implemented interactions; they do not claim parity with every Arc gesture or browser feature.
