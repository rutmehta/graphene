# WP7b visual parity pass

## Result

**Partial implementation and live audit. The acceptance gate is NOT met.**

Arc, Dia and Graphene main windows were captured live at 1280 × 820 native points. The retained main collage mixes dark Arc/Dia with light Graphene and is explicitly labeled. It is not a light-and-dark parity sign-off. The final collages were generated from real captures, not inspected in a final iteration before this session's runtime limit. Earlier individual Graphene, Arc reference and Dia Chat images were inspected with vision.

## Implemented

- Top-tabs location editing and Cmd+T now use the same command session. Results expand downward from the toolbar address container instead of a RootView floating overlay. The Chat button remains outside the expanding container at the right. URL selection, suggestions, context attachments, Ask/Search and keyboard dispatch remain shared. A regression test covers Cmd+L and unfinished new-tab draft retention.
- Sidebar command palette is 640pt wide, 16pt radius and positioned at 18% of window height.
- Sidebar's separate Ask and labeled native-surface rows became a compact icon row with accessible labels/tooltips and unchanged Cmd+Option+1–4 bindings. Archive is at the footer's left, space dots are centered, and New Tab is at the right. Board remains in menus, palette, Cmd+Option+5 and the footer plus context menu.
- Top-tab chips use fully rounded 8pt corners. Shared native tab context menus now expose Pin/Favorite, Rename/Duplicate, Move to, Split, Copy Link and Archive/Close groups in both layouts. Existing Peek, Threads, batch actions, folder destinations and window handoff remain available. Top-tabs Rename uses the existing commit/persistence path.
- Split title bars have favicon/title/focus and a separate close button wired to the existing close flow. Chat composer radius is 12pt.
- Dark sidebar tint is darkened without rewriting saved themes or altering webpage pixels. Tests enforce deep default dark surfaces, distinct space tints and readable contrast.
- Added identifiers, labels and button traits to key custom shell controls, favorites/tab rows, spaces, surface launchers, command rows, Chat controls, onboarding buttons, Settings navigation/Appearance controls, space swatches and note composer controls. Shared IconButton annotations cover its callers. This is not an exhaustive audit of every sheet and every settings subsection.
- Added close-command routing that closes auxiliary key windows instead of mutating browser tabs behind them. Unit tests cover auxiliary-window protection and ordinary browser tab closing. Desktop verification remains inconclusive as described below.

## Actual interaction evidence

All Graphene launches used GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile. Earlier disposable profiles were preserved rather than deleted. The debug driver was used only to seed public tabs/titles/sections. Final launch did not enable the debug driver.

Confirmed by subsequent computer_use captures:

- Onboarding selected Top tabs, advanced through color and final steps, and completed via foreground clicks. No default-browser or import action was invoked. The sheet's capture returned an empty AX tree despite the new annotations. Its reported sheet size and composited screenshot disagreed: sheet-local coordinates, not apparent parent-window pixels, were required.
- Cmd+T opened the integrated top-tabs command panel. Typing “Switch layout” filtered it; a foreground click on the result switched to Sidebar.
- Favorite Swift, pinned Apple Developer and Today Example Domain rows selected their real pages. Space dots switched Research → Personal → Research.
- New Tab row opened the sidebar palette. Escape dismissed it. Chat icon opened the real panel, including real provider status/context budget. No AI messages were fabricated or submitted.
- A zero-distance foreground drag produced tab hover/close affordance and the existing delayed preview. It also selected the tab, so this is not evidence of a hover-only pointer move or measured fade timing.
- Settings opened with Cmd+comma. The annotated Appearance sidebar button worked via foreground coordinates; arrow-key navigation also changed settings pages. Appearance pickers were present in AX, but a set_value call was rejected and a coordinate click did not open the picker. Those controls are not certified as interacted with.
- Arc palette opened and closed; its tab context menu opened; General Settings was captured. Arc's password-manager prompt stayed untouched. The context-menu PNG expired from the tool's bounded image cache before preservation; its observed menu ordering is not represented by a retained image.
- Dia main, Cmd+T, tab context menu, Chat and Tabs Settings were captured. In this installed Dia, Cmd+T created a new Chat-style tab, not an Arc-style palette. That newly created tab alone was closed; the existing release-notes tab was not navigated or closed. No account/default-browser/sync settings were changed.

## Driver limits and close-command caution

Fresh capture followed immediately by an AX-index click still returned snapshot_id_required in both Arc and Graphene. set_value did too. The exposed tool does not accept the requested snapshot_id/element_token fields. Foreground coordinates worked for many controls. focus_app intermittently returned an ended-session error while capture and foreground input continued to work.

Cmd+W requested while capturing Graphene Settings brought up the browser pin-close confirmation. Both confirmations were canceled. The close-routing unit test first reproduced tab mutation with the old action, then passed with the new auxiliary-window guard. However, the desktop driver still reached the browser route during the final attempts, even when app was omitted from the key call. This could involve foreground retargeting; it is **not** a verified desktop fix. No further speculative source changes were made after those failed verification attempts.

## Measurements and remaining differences

Native AX measurements take precedence over resized screenshot pixels:

- Arc: sidebar 228pt, tab rows 40pt with 41pt pitch; main window normalized to 1280 × 820.
- Dia: sidebar approximately 192pt; page origin 190pt from window left and 48pt from top; right/bottom page gutters 6pt. Main window normalized to 1280 × 820.
- Graphene: sidebar 224pt plus 4pt resize handle; 48pt favorite squares; 32pt tab rows with 34pt pitch; 8pt sidebar-mode gutter. Integrated palette had 680pt container width. Sidebar palette is 640pt wide.
- Dia's captured Chat width is user-resizable. Vision estimated about 46% of its available content area, appreciably wider than Graphene's default 350pt. This observation is not treated as Dia's universal default.

Remaining acceptance items:

1. Exhaustive custom-control/sheet AX audit and successful element-ID clicks. Key nodes are exposed, but the tool-level snapshot error and empty sheet tree remain.
2. Same-appearance live light AND dark collages, plus a final inspected/iterated glance-test pass. No new Graphene dark main capture was completed, so README retains a clearly labeled earlier WP7 dark image.
3. Arc split reference, retained Arc context-menu evidence, and full live Graphene context-menu/split interaction verification. Arc split was not attempted with the password-manager prompt and existing user tabs.
4. Appearance picker/toggle interaction completion, Chat @ and / clicks on the final binary, and all sheet interactions.
5. Motion timing/interruption checks, Reduce Motion on, and drag/drop acceptance from the prior notes. macOS reported Reduce Motion false; no system preference was changed. Resting screenshots and successful switches do not establish animation timing.
6. Remaining visual differences: the footer still has two rows, Graphene's row density differs from live Arc, the thread breadcrumb adds a header, and Chat context controls/proportions remain Graphene-specific. Native Settings retain a sidebar/form rather than copying Arc's top toolbar. These are visible design differences, not all attributable to driver failures.

## Build, tests and cleanup

- Final swift build succeeded; swift test passed **68 tests, 0 failures**; ./scripts/build-app.sh succeeded. Logs: build.log, test.log, bundle.log. Command output was captured in Python and its last 30 lines printed, preserving subprocess exit status without a shell pipeline.
- git diff --check passed after source changes. No commit or push. No docs/parity/ref file edited. Little Graphene was untouched.
- Final bundle: /Users/rutmehta/Developer/graphene/.build/Graphene.app.
- Graphene owned PIDs 50001, 71456, 98021, 7038 and 10638 exited after computer_use Cmd+Q, checked with ps. The requested pkill -f graphene-dev-profile cleanup ran. Pre-existing Graphene instances were not targeted.
- Dia bounds restored exactly to [392,138,1163,994], verified by AX. Chat/Settings closed and its original release-notes tab remains selected.
- Arc bounds restored to [1,40,2055,1289], **one point narrower** than original [1,40,2056,1289]. The foreground resize hit the display edge. Exact restoration is incomplete by that point. Its Settings and palette were closed; password prompt left untouched. Arc's Today list changed independently during the audit; no archive/close action was invoked on its existing tabs.
- System appearance remained Dark throughout. Reduce Motion remained off. No system appearance or accessibility preference restoration was needed.
- **24 retained captures + 3 derived collages = 27 verified PNGs**, with dimensions, hashes and provenance in screenshots.json. The cache loss is disclosed above; missing evidence was not substituted.

## Files touched

Sources/Graphene/App/AppState.swift; Sources/Graphene/Model/Commands.swift; Sources/Graphene/UI/{Sidebar,TopTabBar,RootView,CommandBar,ChatView,SettingsView,OnboardingView,SpaceEditor,SplitView,TabContextMenu,Theme,VaultView,WindowState}.swift; Tests/GrapheneTests/{VisualPaletteTests,WindowCommandTests}.swift; README.md; docs/parity/shots/wp7b/.
