# Arc reference capture manifest

Attempted September 25, 2026. Target: `/Applications/Arc.app` (requested version 1.163; installed version not independently verified). Design target: `docs/design/arc-look.md`.

**Status: blocked; no deliverable PNGs produced. Do not use this attempt as visual parity evidence.**

## Blocking condition and privacy

The computer-use accessibility state and visible window stopped agreeing, and private page content unexpectedly appeared as a Today tab inside `Graphene Ref`. Subsequent observations showed further navigation between private pages without corresponding navigation actions from this task. This is evidence of concurrent activity or unstable window targeting; its source was not established. Capture work was stopped to avoid retaining private content or interacting with another workflow.

A computer-use inspection screenshot unexpectedly displayed private content. It was not written to a repository PNG or retained as a reference artifact. There was no saved PNG to delete. No private page titles, account identities, URLs, or content are reproduced in this manifest.

No Favorites tiles were intentionally clicked. No history or archive contents were opened. No settings were changed. Settings and global command-bar results were not captured. Space management was opened solely to attempt removal of the temporary Space; other Space contents were not intentionally expanded or captured.

## Setup actually completed

- Created `Graphene Ref` using Spaces > New Space. It inherited a dark-looking purple theme, rather than the requested assumed light default. No theme change was made.
- Loaded the five requested public URLs using Command-T. The requested GitHub URL redirected to its public successor repository. No sign-in was performed.
- Pinned the Swift repository and Example Domain using Command-D; renamed the former `Swift repo`.
- Created an expanded `Reading` folder using the sidebar add menu. Moving a pinned tab into it was not completed.
- Window resizing was attempted through computer-use drags. Initial enumerated Arc window bounds were 2056 x 1289 points at (0, 40). Later enumeration returned two Arc windows: ID 7942 at (308, 40), 1748 x 1289 points; ID 7941 at (0, 40), 2056 x 1289 points. Stable identity of the capture target was not established. The requested approximately 1440 x 900 size was not reached.
- An unintended blank/incognito window opened after Command-Shift-N while looking for a folder action. Command-Shift-W returned the accessibility window title to Example Domain. No URL was loaded into that unintended window by this task.

## Capture inventory

Every filename below is an intended output, **not an existing file**. Pixel dimensions and actual capture method are N/A because no PNG was saved. All were blocked by the loss of safe, exclusive control described above. Intended full-window method was `screencapture -l <verified-window-id> -o`; transient UI and zoom crops would use `screencapture -x -R x,y,w,h`, with native resolution verified before measurement.

| Intended file | Pixels | Intended theme | Exact intended UI state | Capture / skip result |
|---|---|---|---|---|
| `main-light.png` | N/A | Light | Wikipedia active, sidebar open | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `main-dark.png` | N/A | Dark | Wikipedia active, sidebar open | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `sidebar-hover.png` | N/A | Light | Unselected Today tab hovered with close button | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `sidebar-active-pinned.png` | N/A | Light | Pinned tab selected | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `folder-open.png` | N/A | Light | Reading folder expanded with pinned child | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `folder-collapsed.png` | N/A | Light | Reading folder collapsed | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `url-focused.png` | N/A | Light | URL editing state | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `command-bar-empty.png` | N/A | Light | Empty Command-T command bar | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `command-bar-dark.png` | N/A | Dark | Empty Command-T command bar | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `command-bar-query.png` | N/A | Light | Command bar query swift and results | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `space-switcher.png` | N/A | Light | Space switcher expanded | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `space-theme-picker.png` | N/A | Light | Space colour editor | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `tab-context-menu.png` | N/A | Light | Today tab context menu | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `new-tab-hover.png` | N/A | Light | New Tab row hovered | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `today-divider-hover.png` | N/A | Light | Today divider hovered with Clear | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `sidebar-collapsed.png` | N/A | Light | Sidebar hidden | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `sidebar-peek.png` | N/A | Light | Collapsed sidebar peeking | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `split-view.png` | N/A | Light | Two public pages in split panes | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `little-arc.png` | N/A | Light | Little Arc displaying example.com | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `archive.png` | N/A | Light | Archive limited to temporary Space | Skipped: archive isolation could not be established; concurrent activity also blocked capture. |
| `site-control-center.png` | N/A | Light | Site Control Center popover | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `settings-general.png` | N/A | Unchanged app appearance | General settings without identity | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `settings-profiles.png` | N/A | Unchanged app appearance | Profiles settings without identity | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `settings-links.png` | N/A | Unchanged app appearance | Links settings without identity | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `settings-shortcuts.png` | N/A | Unchanged app appearance | Shortcuts settings without identity | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `settings-max.png` | N/A | Unchanged app appearance | Max settings without identity | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `top-band-controls.png` | N/A | Light | 2x native top-band crop | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `favorites-zoom.png` | N/A | Light | Favorites icons and tile geometry only | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `footer-zoom.png` | N/A | Light | Sidebar footer crop | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |
| `page-corner-zoom.png` | N/A | Light | Page top-left frame corner crop | Blocked before capture: unsafe concurrent activity / inconsistent window targeting. |

## Measurements

No measurements were taken: there are no validated PNGs, no established pixel-to-point scale, and no stable capture window. Dividing unverified screenshot dimensions by two would not establish valid measurements.

| Requested measurement | Result |
|---|---|
| Sidebar width | Unavailable |
| Favorites tile width, height, and gap | Unavailable |
| Tab row height and pitch | Unavailable |
| Tab label font size estimate | Unavailable |
| Favicon size | Unavailable |
| Page corner radius | Unavailable |
| Page inset from sidebar and window edges | Unavailable |
| Traffic-light positions | Unavailable |
| Footer height | Unavailable |
| Toolbar height | Unavailable |
| Command bar width, height, radius, and input font size | Unavailable |
| Light sidebar background RGB at top, middle, bottom | Unavailable |
| Dark sidebar background RGB at top, middle, bottom | Unavailable |
| Selected-row RGB | Unavailable |
| Hover-row RGB | Unavailable |
| Page-border RGB | Unavailable |

## Spec corrections

None established. `docs/design/arc-look.md` was read but left unchanged. Its tokens, colour samples, and geometry have not been verified by this attempt. The new Space's inherited dark appearance demonstrates only that creating a Space did not yield a light theme in this session; it does not establish a universal Arc default or justify a token correction.

## Cleanup

**Incomplete: `Graphene Ref` was still present in the last verified Space-management accessibility state. Its deletion is not confirmed.** The temporary Space contains the created public tabs, two pinned tabs, and an empty Reading folder. Unexpected private activity also appeared within it; this task did not deliberately create that private tab.

Attempts to open the temporary Space's action menu did not yield a reliable menu while unrelated navigation continued. Further UI interaction was stopped to avoid interfering with another workflow. The Space-management surface may remain open. Arc remains running; it was not quit.

**It is not possible to confirm that no other Arc state changed.** Resizing was attempted and one enumerated window's bounds changed; the original sidebar was collapsed and was opened for setup. These states were not restored because safe window targeting was lost. The unintended blank/incognito window was closed as described above, but a complete final window audit was not performed. No claims are made about changes produced by concurrent activity.

A future capture attempt requires exclusive, stable control of the Arc window and cleanup of the remaining temporary Space before creating a new reference session.
