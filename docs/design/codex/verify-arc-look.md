# Task: verify Graphene's Arc-look rebuild on the real app

You are Codex running on macOS with the computer-use tool. Use it for every interaction with the apps (screenshots, clicks, keys, drags); use the shell only for builds, file work and `screencapture`. Do the work synchronously yourself. Do not delegate, do not schedule jobs, do not ask questions; if something is blocked, record it and move on. Never use `GRAPHENE_DEBUG`, the `cmd.txt` debug driver, or any scripted UI automation inside the app: every interaction is a real click, key press or drag through computer use, exactly as a user would do it.

## Goal
Build the current `master` of this repository, run it on an isolated profile, exercise the surfaces in `docs/design/arc-look.md` section 6 (Acceptance), capture evidence, and write a report that says plainly which acceptance items pass, which fail, and what looks wrong compared with Arc. Output goes in `docs/parity/shots/arc-look/` (PNGs plus `report.md`). Do not commit.

## Build and launch
1. Run `git status` and note the HEAD hash and any untracked files in the report. Untracked files under `docs/parity/` are expected and are not a blocker; never delete, stash or commit anything.
2. Build with `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`. Never build into or touch `~/Applications/Graphene.app`, and never quit a Graphene process you did not start.
3. Launch: `GRAPHENE_DATA_DIR=/tmp/graphene-arc-look-verify .build/Graphene-verify.app/Contents/MacOS/Graphene &` (fresh directory; delete it first if it exists). Record the PID. Complete onboarding with default choices. Resize the window to 1280×820 points.

## Seed through the UI (public pages only)
- Open tabs with ⌘T: https://en.wikipedia.org/wiki/Graphene, https://github.com/apple/swift, https://developer.apple.com, https://news.ycombinator.com, https://example.com, https://www.apple.com, https://forums.swift.org.
- Make four of them Favorites (tab context menu → Add to Favorites, or drag to the favorites area).
- Pin three others (context menu → Pin); create a folder (context menu → New Folder) named `Reading` and move one pinned tab into it.
- Leave four Today tabs. Create a second space with ⌘⌥N named `Personal`, then return to the first space.
- Set the first space's theme through Settings → Spaces → Theme: choose the Iris preset, then read back the hue/saturation values shown and record them (hue near 243° and saturation 0.6 are the reference; if the sliders cannot be set precisely, record what they read) and confirm Appearance is Dark for the dark captures, then Light for the light captures (Settings → Appearance, or ⇧⌘L).

## Captures (window-only, Retina, `screencapture -l <windowid> -o`)
Get the window id with `swift scripts/window-id.swift -p <PID>` (the PID you launched). Capture with `screencapture -l <id> -o -x <file>.png`; this is a shell command that needs no UI focus, so run it right after putting the app into the wanted state via computer use. Do not use `screencapture -i` (interactive) or `-R` for whole-window shots. All at 1280×820. Verify each PNG with `sips -g pixelWidth -g pixelHeight` and by viewing it. If a state cannot be held (a hover, a held key), say so and skip it; never substitute a wrong-surface capture.
1. `main-dark.png`, `main-light.png`: Wikipedia tab active, sidebar open, page loaded.
2. `row-hover-dark.png`: pointer over an unselected Today row (hover fill and close glyph must show).
3. `today-hairline-hover.png`: pointer over the hairline between pinned and Today (the "Clear" label must appear).
4. `favorite-hover.png` and `favorite-selected.png`.
5. `folder-open.png` / `folder-collapsed.png`.
6. `command-bar-cmdt.png`: ⌘T, nothing typed. `command-bar-url.png`: click the URL in the page toolbar (the bar must open with the URL prefilled and selected). `command-bar-cmdl.png`: ⌘L. `command-bar-query.png`: type `swift`.
7. `toolbar-zoom.png`: `screencapture -R` crop of the page card's top-left 400×60 at 2x showing nav buttons, the URL and the card corner.
8. `page-corner-zoom.png`: crop of the page card's bottom-right corner showing the gap to the window edge.
9. `sidebar-collapsed.png` (⌘S) and `sidebar-peek.png` (pointer at the left window edge while collapsed). Then ⌘S again.
10. `space-switch.png`: capture mid-way through switching to `Personal` if you can, else after; then `space-personal.png`.
11. `split.png`: open a split (⇧⌥⌘→ or context menu → Open in Split View).
12. `chat.png`: ⌘K opens the floating chat panel.
13. `toast.png`: close a Today tab with ⌘W (Undo toast).
14. `tab-switcher.png`: hold ⌃ and press Tab.
15. `little-arc.png`: if a Little Arc / transient window shortcut exists in Settings → Shortcuts, use it; otherwise skip and say so.
16. `settings-appearance.png`, `settings-general.png`, `onboarding.png` (relaunch into a fresh empty `GRAPHENE_DATA_DIR` for the onboarding shot, then quit that instance).
17. `reduce-motion.png`: enable System Settings → Accessibility → Display → Reduce Motion, collapse/expand the sidebar and switch spaces, capture, then turn Reduce Motion back off. Note whether anything still moved.

## Measurements
From the PNGs (divide by 2 for points), record in `report.md`: page card gap to window top/right/bottom, page radius, toolbar height, nav button positions, favorites tile width/height/gap and columns, tab row height and pitch, favicon size, space label height, footer height, traffic-light centres, command bar width/radius/input height/row height and its top offset as a fraction of window height, chat panel width and inset. Sample the sidebar RGB at top/middle/bottom and the page border RGB in dark and light. Compare every number with `docs/design/arc-look.md` section 2 and section 6 item 1–2, and with `docs/parity/ref/arc/manifest.md` if it exists (else `docs/parity/ref/arc-main.png`).

## Report
`report.md` with: HEAD hash, PID, build log tail, a table of the eight acceptance items from section 6 with PASS/FAIL and evidence file names, the measurement table with deltas, a "What still doesn't look like Arc" list ordered by visual impact (be blunt and specific: colours, weights, spacing, alignment, anything that jumps or flickers), and any crash, hang, console error or layout jump you saw. Do not soften failures. Do not claim anything you did not observe.

## Cleanup
Quit the Graphene instance you launched (⌘Q on it, confirm the PID is gone). Leave `/tmp/graphene-arc-look-verify` in place. Delete `.build/Graphene-verify.app`. Confirm Reduce Motion is back to its original state.
