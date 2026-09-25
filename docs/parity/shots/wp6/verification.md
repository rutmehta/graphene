# WP6 implementation and verification — partial

This is not a claim that every WP6 acceptance criterion is complete.

## Final build

- `swift build`: exit 0.
- `swift test`: 39 tests, zero failures, including eight new workspace/settings tests.
- `./scripts/build-app.sh`: exit 0; ad-hoc signed `.build/Graphene.app` produced.
- No warnings in the final build, test or bundle logs. Logs are saved alongside this report.
- No commits were made. Existing unrelated working-tree changes were preserved.

## Implemented

Native Settings scene with General, Appearance, Spaces/Routing, Sites, Privacy, Search, AI, Shortcuts, Mail and Advanced. Optional Codable settings fields, atomic writes, corrupt-file preservation, settings import/export without removing existing tabs/spaces. Startup new-tab preference, chosen download starting folder, compact rows, System/Light/Dark, page gutter, custom `%s` search URLs, capture exclusions, website-data removal by time/type, account connection status, grouped shortcut remapping/conflicts/reset/Markdown copy.

Ordered enabled/disabled URL globs route new links and external URLs to a matching space. A palette action adds a rule for the current site. Deleted-space destinations are ignored. Rule tester does not navigate.

Queued notifications with icon, title, optional action, hover pause and expiry. Closing a saved page offers a five-second Undo bound to that exact archive entry.

Boards per space in `boards.json`: current-tab links, editable text, Vault picker, persisted geometry, drag/resize, delete, tab/note drop handlers and Markdown export. Open via sidebar bottom icon, palette or Option-Command-5.

Threads retain provenance and list/map views, with day headings, favicon stacks, duration, keyboard selection, Summarize, page breadcrumb and tab-menu Show in Thread. Vault uses a card grid with kind/site/current-space filters, editable detail and explicit source provenance. New Mail saves carry account scope from Gmail's profile endpoint and an account-addressed source URL. Mail headings use system sans and expose Ask about this message. Ask has removable attached sources, model status, note-drop handling and persisted 320–520pt resize controls. Source search remains independent of model availability.

Skippable first-run layout/color/default-browser onboarding. Conventional File/Edit/View/History/Spaces/Tabs/Help organization, print and Find commands, with standard macOS app/window menus retained. Inspector uses public `isInspectable` and tells the user to choose Inspect Element; no private inspector selector is used.

## Desktop evidence

Only `/tmp/graphene-dev-profile-wp6` was used. No real profile, personal mail or credentials were read. No default-browser or destructive website-data changes were performed for screenshots. No Little Graphene implementation or settings were added.

Computer-use captures worked; the first input action returned `approval prompt timed out`. Following the explicitly authorized fallback, subsequent inputs used AppleScript System Events, screenshots used `screencapture -x`, and the existing isolated debug driver exercised actual app actions. The initial computer capture with only a PID required a window ID; app-scoped capture succeeded.

- Fresh-profile onboarding: layout and color steps, completion, then native Settings via Command-comma. Relaunch confirmed onboarding false.
- Every implemented Settings page was selected and its displayed heading read back. `settings-pages.json` contains ten matching page/heading records. AXPress on SwiftUI list rows was a no-op; setting the row's selected property worked.
- Added `https://example.org/* → Personal` through Settings. Settings JSON and visible rule confirmed the write. The matching external URL created a Personal tab. AppleScript open-location also caused a separate empty window; the debug-driver external command verified the destination without that extra window.
- Command-W displayed the close notification. UI Undo activation was not confirmed after retries. The debug driver's `toast-undo` invoked the actual displayed toast closure; `undo-result.json` confirms the correct page restored and archive count decremented.
- Option-Command-2/3/4/5 opened Threads/Mail/Vault/Board. `surface-checks.json` records the latter three with live state read-back. Threads, Vault and Board contain only public Example Domain fixtures and explicit test notes.
- Board's Add → From Vault picker added the saved highlight; persisted board data confirmed it. Text-field typing was not confirmed after two attempts. Drag/resize/drop gestures were not verified.
- Compared captures visually with `docs/parity/ref/arc-main.png` and `dia-main.png`. Fixed an oversized breadcrumb that consumed half the page; corrected screenshot shows a compact row and dominant page. Also fixed the dark-sheet/light-text-context mismatch found in the Vault picker.
- `screenshots.json` enumerates 23 PNGs. They include onboarding, ten Settings pages, routing, Undo, native surfaces and Ask. Captures span intermediate smoke builds. The final sheet-color, Ask-on-native-surfaces, shortcut-grouping and menu-alias refinements were built/tested, but were not re-smoked after the last rebuild.
- Owned processes 17973 and 39335 were quit with Command-Q. Final `ps -p 39335` returned no process; the requested profile-pattern cleanup was also run.

## Still incomplete / unverified

The synchronous execution budget ended before full WP6 completion. No fake controls were added to suggest these features exist:

- Profiles and per-space cookie-profile assignment, Boosts, browser-data Import and content-blocking controls are absent. The corresponding WP4/WP5 integration surfaces were not present in this working tree. Onboarding explicitly reports import unavailable.
- Font selection is absent; system font is retained.
- Ask has no persistent chats list or slash-command system. The existing on-device assistant remains a single-answer workflow. Mail's action is about one message, not an aggregated Gmail conversation.
- Threads keep their map and parent labels, but do not have the requested new inline branch-tree drawing. Keyboard selection is wired but not keyboard-only audited.
- Shortcut remapping covers registered browser commands, not macOS Services/editing/window commands or every contextual menu entry. Platform-reserved shortcuts are disclosed, not claimed fully remappable. Imported override conflict validation is less strict than the editor.
- Connected Gmail, model generation, default-browser registration, printing, clear-data ranges, custom download folder, settings JSON transfer dialogs, all remapped keys, hover-paused toast input, resize/drop gestures and every menu item were not exercised end-to-end.
- Board text editing has passing persistence/model coverage but failed automation attempts; user-input verification is outstanding.
- Settings captures precede the final General/Search additions and grouped shortcut layout. They prove page navigation, not every final control.

## Files touched by this work

- `README.md`
- `Sources/Graphene/App/{AppState,GrapheneApp,DebugDriver}.swift`
- `Sources/Graphene/Model/{Settings,RoutingRule,ToastQueue,CommandShortcut,Commands,BrowserLibrary,Omnibox}.swift`
- `Sources/Graphene/Store/{BoardStore,Vault,DownloadStore}.swift`
- `Sources/Graphene/UI/{SettingsView,OnboardingView,EaselView,ToastOverlay,RootView,Theme,Sidebar,TopTabBar,ShellContentLayout,TabSwitcher,LedgerView,VaultView,MailView,KnowledgeSearchView}.swift`
- `Sources/Graphene/Mail/{GmailClient,MailStore}.swift`
- `Sources/Graphene/Web/BrowserDownload.swift`
- `Tests/GrapheneTests/WorkspaceSettingsTests.swift`
- Evidence and logs under `docs/parity/shots/wp6/`; reference images were not changed.
