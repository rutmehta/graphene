# Task: capture Arc browser reference screenshots for a design spec

You are working on macOS with real computer use. Do the work synchronously yourself. Do not delegate, do not schedule jobs, do not ask questions; if something is blocked, note it in the manifest and move on.

## Goal
Produce a set of crisp, window-only PNG screenshots of the Arc browser (installed at /Applications/Arc.app, version 1.163) showing its visual design, saved under `docs/parity/ref/arc/` in this repository, plus `manifest.md` describing each capture. These are design references for a native macOS app that wants Arc's look and feel. The spec they feed is `docs/design/arc-look.md`.

## Privacy rules (hard)
- Arc is the user's real browser with private data. Work ONLY inside a new temporary Space that you create, named `Graphene Ref`. Never switch to, screenshot, or expand any other Space. Never click Favorites tiles (they open the user's personal sites). Never open the user's history, archive contents of other spaces, or profile data.
- Only load public pages: https://example.com, https://en.wikipedia.org/wiki/Graphene, https://github.com/apple/swift, https://developer.apple.com, https://www.apple.com, https://news.ycombinator.com.
- If any capture accidentally shows private content (other spaces' tabs, personal page content, account emails), delete that PNG immediately and re-take it. Settings pages: capture General, Profiles, Links, Shortcuts, Max and the Site Control Center, but if a page shows an account email or name, crop it out or skip it and note that.
- At the end, delete the `Graphene Ref` space (this also closes its tabs) so the user's Arc is unchanged. Do not change any Arc setting; only look. Do not sign into anything.

## Capture method
- Window-only, native Retina resolution. Preferred: find Arc's main window ID (python3 with Quartz `CGWindowListCopyWindowInfo`, or `osascript`) and run `screencapture -l <id> -o <file>.png` (`-o` drops the shadow). For transient UI (command bar, menus, popovers) that lives in separate windows, use `screencapture -x -R x,y,w,h` of the screen region containing the main window plus the popover instead.
- Set the Arc window to roughly 1440x900 points first so all captures share one size.
- Verify each PNG is non-empty and actually shows what the filename says (`sips -g pixelWidth -g pixelHeight`, then view it) before moving on.

## Setup
1. Activate Arc. Open the space switcher (click the space name/icon at the bottom of the sidebar or the current space title) and create a new Space named `Graphene Ref`. Give it the default theme it offers.
2. In that space open these tabs (Cmd+T, type URL, Enter): example.com, the Wikipedia Graphene article, github.com/apple/swift, developer.apple.com, news.ycombinator.com.
3. Pin two of them (drag the tab above the divider, or right-click → Pin). Create a folder in the pinned section (right-click → New Folder) named `Reading` and put one pinned tab in it. Rename one pinned tab to `Swift repo`.

## Captures (filenames exact)
Take each in the space's default (light) theme, then switch the space theme to dark (space settings/theme picker) and re-take the ones marked (both).
1. `main-light.png` / `main-dark.png` (both): resting main window, Wikipedia tab active, sidebar open.
2. `sidebar-hover.png`: mouse hovering over an unselected Today tab so its hover state and close button show.
3. `sidebar-active-pinned.png`: a pinned tab selected.
4. `folder-open.png` and `folder-collapsed.png`.
5. `url-focused.png`: click the URL field so it is in editing state.
6. `command-bar-empty.png` / `command-bar-dark.png` (both): Cmd+T with nothing typed.
7. `command-bar-query.png`: Cmd+T then type `swift`, showing results.
8. `space-switcher.png`: the space switcher expanded. Crop out other space names if they contain private words; names/icons alone are fine.
9. `space-theme-picker.png`: the space theme/colour editor open, if reachable from the space menu.
10. `tab-context-menu.png`: right-click on a Today tab.
11. `new-tab-hover.png`: hover over the `+ New Tab` row.
12. `today-divider-hover.png`: hover over the divider between pinned and Today tabs so the `Clear` control appears.
13. `sidebar-collapsed.png` and `sidebar-peek.png`: Cmd+S to hide the sidebar, then move the mouse to the left screen edge so it peeks over the page.
14. `split-view.png`: open a split (right-click a tab → Open in Split View, or drag a tab onto the page), two panes visible.
15. `little-arc.png`: Option+Cmd+N opens a Little Arc window; type example.com, Enter; capture that small window.
16. `archive.png`: click the archive icon bottom-left; capture, then close. Only if it shows only this space's archived tabs; otherwise skip.
17. `site-control-center.png`: click the site icon in the URL area to open the Site Control Center popover.
18. `settings-general.png`, `settings-profiles.png`, `settings-links.png`, `settings-shortcuts.png`, `settings-max.png`: Cmd+, and each tab. Crop any account identity.
19. `top-band-controls.png`: zoom crop (screencapture -R) of the top band: traffic lights, sidebar toggle, back/forward/reload, URL, at 2x.
20. `favorites-zoom.png`: zoom crop of the favorites grid area (icons only).
21. `footer-zoom.png`: zoom crop of the sidebar footer (archive icon, space dots, + button).
22. `page-corner-zoom.png`: zoom crop of the page frame's top-left corner showing the radius, border and the gap to the sidebar.

## Manifest
Write `manifest.md` listing every file, its pixel size, the theme, the exact UI state, how it was captured, and anything skipped with the reason. Then, in a section `## Measurements`, measure from the PNGs (divide by 2 for points): sidebar width, favorites tile size and gap, tab row height and pitch, tab label font size estimate, favicon size, page corner radius, page inset from sidebar and from window edges, traffic-light positions, footer height, toolbar height, command bar width/height/radius and input font size. Also record the sidebar background RGB sampled at three points (top, middle, bottom) in both themes, the selected-row RGB, the hover-row RGB, and the page border RGB. Where a measurement disagrees with `docs/design/arc-look.md`, list it under `## Spec corrections`.

## Cleanup
Delete the `Graphene Ref` space. Confirm in the manifest that it is gone and that no other Arc state changed. Leave Arc running as you found it.
