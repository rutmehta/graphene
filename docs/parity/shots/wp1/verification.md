# WP1 shell implementation and evidence

Implemented synchronously without delegation or commits. Existing working-tree changes were preserved. Only `/tmp/graphene-dev-profile` was launched; reference screenshots were not modified.

## Implemented

Space CRUD, icons/emoji, custom hue/saturation/intensity, gradient/grain, automatic appearance, space commands, native tab/space drop targets, distinct favorites/pinned/Today tiers, pinned base URLs and close confirmation, custom titles, folders, archive/reopen persistence, compact labeled surface launchers, sidebar navigation, inset page, resize divider with accessibility adjustment and per-window widths, collapsed peek/floating address, narrow-window Ask overlay, shared surface state views, same-origin favicon discovery/cache, and active-page HTML-media polling.

## Verification

Final `swift build`, `swift test` (12 tests, zero failures), `./scripts/build-app.sh`, and strict/deep code-signature verification all passed. No compiler warnings appeared. The tests include five shell tests plus seven existing knowledge tests. Final output is recorded in `/tmp/graphene-wp1-final.log`.

Real window screenshots are in this directory:
- `00-shell.png`: first iteration, including the subsequently fixed empty-favorites wrapping defect.
- `01-created-space.png`: created Studio space.
- `02-custom-theme.png`: custom theme editor.
- `03-favorite.png`, `04-pinned.png`, `05-folder.png`: separate tab tiers and folder membership.
- `06-resized.png`: resize driver request. The screenshot revealed that a non-key window did not receive the saved width; the final root initialization now sets its width destination. This capture is NOT evidence that the final resize fix works.
- `07-collapsed.png`, `08-peek-driver.png`: collapsed and driver-presented peek overlay.
- `09-ask-overlay.png`: Ask overlays the page at a 940pt window instead of reducing its layout width.

`driver-evidence.json` records commands, capture exit codes and app-state readbacks. Screenshots use live public example.com/example.org/swift.org content, not fabricated website output. The final populated sidebar and Ask-overlay screenshots were visually inspected.

## Incomplete acceptance / limitations

This is not a claim of complete Arc parity. AppleScript initially rejected keystrokes (error 1002). The later Cmd+Q request returned successfully but the owned process remained running. Cleanup used `pkill -f '[g]raphene-dev-profile'`; the subsequent owned-process check returned no matches. Feature smoke actions used the app's debug driver, not physical clicks, drags or keyboard commands. Real edge-hover delay, resize drag and scroll-position preservation, swipe, drag auto-scroll/hold-to-group/cancel, keyboard focus states, fullscreen traffic lights and full shortcut handling remain unverified. Peek rendering was explicitly presented by the driver, not an observed hover. The final small width-focus correction was build/test-verified but not re-smoked.

The requested complete keyboard-focus/pressed-state audit and universal adoption of layout tokens across all existing surfaces are not complete. The downloads affordance opens Finder; it is not a downloads history UI. Surface launchers occupy a compact labeled row immediately above the space footer so names remain visible at 224pt. Media polling misses Web Audio, iframes and changes in background tabs. Favorites are space-scoped. Login/cookie isolation between spaces is outside this work package.

Code touched: AppState, DebugDriver, GrapheneApp, Space, Tab, RootView, Theme, WindowAccessor, Favicon, WKWebEngine, LedgerView, VaultView, MailView. New files: Sidebar, SpaceEditor, WindowInteractions, DragAutoScrollEdge, ShellContentLayout, SurfaceState, FaviconStore and ShellTests. README updated with features, shortcuts and limitations.
