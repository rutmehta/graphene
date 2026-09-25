# Graphene Arc-look verification — 2026-09-25

**Not accepted.** The main geometry and command bar are close to the design tokens, but this run does not establish all eight acceptance items. The required folder-child seed was blocked, hover/held-key states were not capturable with the available computer-use API, motion could not be observed between settled frames, and the dark top sample misses the actual Arc reference by 13 red levels. These are distinguished below from observed product failures. A FAIL marked “unverified” means the acceptance claim is unsupported, not that a contrary animation was observed.

## Build, ownership, and setup

- Branch: `master`, tracking `origin/master`. HEAD: `40762f2cdf0e24fa3530de7f264bae93210160a0`.
- Initial `git status --short --branch`: `## master...origin/master`, with **no tracked changes or untracked files**. Output files created by this run are listed in `final-git-status.txt`. No commit, stash, reset, or deletion of pre-existing repository work was performed.
- Build: `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`. The installed `~/Applications/Graphene.app` was not touched.
- Verified isolated PID: **31781**, main CGWindowID **9355**, profile `/tmp/graphene-arc-look-verify-2`. The shell was kept alive with `wait` after the requested background launch so it would not reap the app.
- Launch incident: the first background PID **31624** exited with its short-lived shell before onboarding. Selecting the verification bundle through computer use then launched PID **31651** without the environment override and showed pre-existing browsing state. No seeding or screenshots were made in that state; it was quit through ⌘Q. The successful second launch showed fresh onboarding and created the isolated directory. The profile contents from the unintended launch were not copied into this report.
- Default onboarding completed (Sidebar / Tide; no default-browser change or import). The default profile already has Research and Personal. ⌘⌥N created an additional space; it was named Personal through Settings. Therefore there are **three spaces**, two named Personal, rather than exactly two. The tested destination is the newly created third space.
- Native browser bounds were already **1280×820 points**, at screen origin (469,315). No resizing was necessary. All main-window PNGs are **2560×1640**. Native Settings is non-resizable (zoom disabled), **820×652 points / 1640×1304 pixels**, an explicit exception to the requested size.
- All seven requested URLs were opened through ⌘T. GitHub redirected publicly from `apple/swift` to `swiftlang/swift`. Favorites: Wikipedia, Swift repository, Apple Developer, Hacker News. Pins: Example Domain, Apple, Swift Forums. Four additional Today tabs use public `example.com/?today=1` through `?today=4`.
- Reading was created through the space context menu and renamed. **Moving a pin into Reading failed:** the computer-use drag returned `windowNotFoundAtPosition`; the Move submenu did not expand on click. Reading remains empty. Folder captures show only disclosure-state changes, not successful grouping.
- Iris preset readback: normalized hue **0.6928571428571429 = 249.43°**, saturation **0.64**. Reference is 243° / 0.60: deltas **+6.43° / +0.04**. Preset was not manually overridden. Settings → Appearance explicitly read **Dark**, then **Light** for `main-light.png`; dark mode was restored afterward.

Build log tail (`build.log`):

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.13s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

This was an incremental debug build, not a clean rebuild. `swift test` completed: **141 tests, 1 skipped, 0 failures**. See `tests.log`. No build warnings were emitted.

## Section 6 acceptance

| # | Acceptance item | Result | Evidence / limitation |
|---|---|---|---|
| 1 | Same-product appearance, card geometry, toolbar, favorites, rows, favicons, footer | **FAIL — incomplete acceptance** | `main-dark.png`, `main-light.png`, `favorite-selected.png`. Core measured geometry is on target, but required folder child is absent; titlebar has an extra visible horizontal line; light/Arc paired reference unavailable. See visual differences below. |
| 2 | Sidebar RGB within 12/channel of dark Arc reference | **FAIL against actual PNG; PASS against prose samples** | `main-dark.png`, `pixel-samples.txt`; top red difference **13** against `arc-main.png`. All three prose-target comparisons are within 12. Iris is not exactly the reference hue/saturation. |
| 3 | Today row hover and close within 100 ms; hairline reveals Clear | **FAIL — unverified** | API has click/drag but no pointer-move/hover method. No hover files substituted; timing not observed. Selected Today close glyph is visible in `split.png`, which does not prove hover. |
| 4 | ⌘T, URL click, ⌘L share position; URL selected | **PASS** | `command-bar-cmdt.png`, `command-bar-url.png`, `command-bar-cmdl.png`, `command-bar-query.png`. Both URL variants visibly highlight the full URL; all share x≈320, y≈148 pt. |
| 5 | Sidebar spring; no toolbar jump or traffic-light overlap | **FAIL — motion/traffic lights unverified** | `sidebar-collapsed.png` vs `main-dark.png`. Endpoint geometry is sensible, nav moves with reserved left space. Tool returns settled frames; no spring/jump conclusion. Purple system capture indicator covers traffic lights in active captures. |
| 6 | Space gradient cross-fade and row slide | **FAIL — unverified motion** | `space-switch.png` and `space-personal.png` show settled third Personal space. Color/content change succeeded; intermediate frames not observed. |
| 7 | Reduce Motion: only fades, no movement | **FAIL — unverified motion** | System toggle observed off → on; sidebar collapse/expand and space round trip exercised; `reduce-motion.png` is settled. No claim about movement between frames. Toggle restored and read back off. |
| 8 | Warning-free build, green tests, no new removed literals | **PASS with stated gate scope** | `build.log`, `tests.log`, `literal-diff-gate.txt`. Numeric system-font-size, corner-radius, and fractional-opacity additions checked from parent of D1 `43f96ef` through HEAD, excluding token definitions in `Theme.swift`: **0 matches**. Exact separate package grep brief was not found. Existing out-of-scope literals are listed in `literal-audit-all-ui.txt`; the ten D1 named surfaces have zero matches in `literal-audit.txt`. |

## Measurements from PNGs

Coordinates are relative to the window. Graphene pixels / 2 = points. Straight-edge positions are pixel-count measurements; radii and glyph extents are visual estimates, normally ±1 pt. Invisible layout-container boundaries cannot be proved from pixels and are explicitly labeled. No runtime geometry or source token values were substituted for measurements.

The newer `ref/arc/manifest.md` explicitly says it contains **no validated PNGs or measurements**. The comparison therefore falls back to `ref/arc-main.png` (1568×983, redacted content). Its scale is not 2×: `measurements.json` gives 0.7242 image pixels per native unit. The prose spec's “about 1.37 image px per point” conflicts with that file (approximately its reciprocal). Arc point comparisons below are conditional on the existing measurement file, not newly verified live Arc dimensions. There is no light Arc reference.

| Measurement | Graphene observed pt | §2 / §6 target pt | Delta / comparison |
|---|---:|---:|---|
| Window | 1280×820 | 1280×820 | 0 |
| Sidebar/page left edge | 224 | 224 | 0; old Arc estimate 229.2, delta −5.2 |
| Card top / right / bottom gap | 8 / 8 / 8 | 8 / 8 / 8, ±1 | 0 / 0 / 0; edges at y16, x2544, y1624 px |
| Page radius | ≈10 | 10±1 | ≈0; old Arc estimate 9.7, delta ≈+0.3 |
| Toolbar height | 32 | 32±1 | 0; y16–80 px; old Arc 33.1, delta −1.1 |
| Nav glyph centres (window x,y) | ≈(246,24), (278,24), (306,24) | (246,24), (276,24), (306,24) from 8 inset / 28 target / 2 gap | ≈0, +2, 0 in x; estimate ±1 |
| URL placement | ≈x748 centre | Page-card centre x748 | ≈0; URL is flat text, not a pill |
| Favorite tile width | ≈62.5–63, equal rasterized columns | (208−20)/3 = 62.67 | ≤0.33 |
| Favorite tile height / gaps / columns | 44 / 10 / 3 | 44±2 / 10 / 3 | 0; 4 tiles occupy 2 rows |
| Tab row height | 36 (selected row in split) | 36 | 0; 72 px fill height |
| Tab row pitch | 40 | 40±1 | 0; 80 px between icon centres; old Arc 41.4, delta −1.4 |
| Tab favicon extent | ≈16 | 16 | ≈0 |
| Favorite icon extent | ≈20 | 20 | ≈0 |
| Space label | ≈24 allocated band; ink ≈11 tall | 24 band, 11 type | Band boundary invisible: approximate, not independently exact |
| Footer | Controls centred at y≈802; implied 36-high strip | 36 | No drawn top boundary; exact height unmeasurable from PNG. Archive/library/dots/plus present. |
| Traffic-light centres | ≈(20,22),(40,22),(60,22) in dimmed onboarding | (20,22),(40,22),(60,22) | ≈0 in onboarding; active main captures occluded by system indicator |
| Command-bar width / radius | 640 / ≈16 | 640 / 16 | 0 / ≈0 |
| Command input height | 56 | 56 | 0 |
| Command result row height | 44 | 44 | 0; selected fill 88 px |
| Command top | ≈148; 148/820≈0.1805 | 0.18 (147.6 pt) | ≈+0.4 pt / +0.0005 fraction |
| Chat width | 420 | 420 | 0; 840 px |
| Chat inset from card top/right/bottom | 16 / 16 / 16 | 16 / 16 / 16 | 0; chat bounds ≈(836,24) to (1256,796) |
| Onboarding sheet | ≈540×420 | 540×420 | ≈0 |
| Settings sidebar | ≈180 | 180 | ≈0; whole Settings window is smaller than capture brief |

RGB values below are color-managed **sRGB**, sampled from the saved PNGs using AppKit bitmap reads. Grain varies individual pixels. Graphene sample x=400 px (200 pt), y=40 / 820 / 1520 px avoids text/tiles. Actual Arc x=180, y=40 / 480 / 900 avoids redactions and is near the sidebar's right edge. These are comparable unoccupied regions, not identical screen-coordinate locations. Deltas are Graphene minus reference.

| Sample | Dark Graphene RGB | §2 prose reference | Delta vs prose | Actual Arc RGB | Delta vs Arc |
|---|---|---|---|---|---|
| Top | 23,16,49 | 14,13,38 | +9,+3,+11 | 10,11,39 | **+13,+5,+10** |
| Middle | 26,17,49 | 21,13,38 | +5,+4,+11 | 15,13,39 | +11,+4,+10 |
| Bottom | 28,17,48 | 32,10,38 | −4,+7,+10 | 22,12,39 | +6,+5,+9 |

| Light/border sample | RGB | Target / delta |
|---|---|---|
| Light sidebar top / middle / bottom | 215,209,242 / 215,207,241 / 216,206,240 | §2 specifies gradient formulas, not fixed RGB. At reference h243/s0.6, ideal endpoint colors are approximately (202,200,242) and (208,186,235); these interior, color-managed PNG samples cannot be treated as endpoint formula deltas. No Arc-light measured target exists. |
| Dark page right edge, pixel (2543,800) | 238,238,238 | §2 white12% over a white page would remain 255; observed −17/channel. Page is white Wikipedia, not a dark-schemed page. |
| Light page right edge, pixel (2543,800) | 239,239,239 | Black8% over white gives ideal RGB235; observed +4/channel. Color management/edge compositing applies. |

## What still doesn't look like Arc

1. **A horizontal titlebar line cuts across the whole window at about y32**, including the sidebar and the page toolbar. The card already has its own bottom separator at y40. That extra line breaks the single flooded chrome plane. It is plainly visible in both main captures despite the recent titlebar-separator commit.
2. **The dark sidebar is brighter and more purple than the actual Arc fallback reference.** The top red channel fails the stated tolerance by one level; all three samples carry about ten extra blue levels. The vertical hue change is subtle and the bottom does not reach the prose sample's richer plum.
3. **The light chrome is a fairly uniform lavender field.** The bottom remains cooler/paler than the ideal endpoint formula; without a light Arc shot this is a spec observation, not a verified Arc mismatch.
4. **Generic letter favicons are conspicuous**, especially the repeated Example Domain E badges. Real Wikipedia/GitHub marks have pale backings; those help legibility but produce a different mix of squares and circles from the quieter reference. Hacker News initially displayed an N placeholder, later replaced by Y.
5. **The space label and repeated rows look heavier than the small, quiet reference sidebar.** This is a visual weight judgment, not a font-metric measurement. Favorites and row spacing themselves are close to the intended tokens.
6. **Chat looks like a tall opaque slab over the article**, with a source-warning line and large empty body. Its dimensions match the spec, but the toolbar is partially obscured and the panel is visually dominant. No message was sent and no model response quality was tested.
7. The system's purple sharing/capture indicator replaces the visible traffic lights in active captures. This is **capture-environment contamination**, not evidence that Graphene renders a purple control. It prevents a clean same-product comparison of the top band.

## Capture inventory and blocked states

All delivered PNGs were checked with `sips` and viewed. `dimensions.txt` records dimensions. Settings captures were also visually inspected through computer use. Window-only captures used `screencapture -l <owned-window-id> -o -x`.

- Delivered: `main-dark.png`, `main-light.png`, `favorite-selected.png`, `folder-open.png`, `folder-collapsed.png`, all four `command-bar-*.png`, `sidebar-collapsed.png`, `space-switch.png`, `space-personal.png`, `split.png`, `chat.png`, `settings-appearance.png`, `settings-general.png`, `onboarding.png`, `reduce-motion.png`.
- `folder-open.png` / `folder-collapsed.png`: **empty Reading folder**. Do not infer child nesting from either.
- `space-switch.png`: **after** switching, not mid-animation; `space-personal.png` is also settled.
- `close-tab-no-toast.png`: immediately attempted after ⌘W on a Today tab, but no toast is visible. **Not named `toast.png` and not accepted as toast evidence.** Closed tabs were reopened to restore four Today tabs.
- Skipped `row-hover-dark.png`, `today-hairline-hover.png`, `favorite-hover.png`, `sidebar-peek.png`: no supported pointer-move/hover operation, and pointer targeting/drag failures. No click/selection screenshot substituted.
- Skipped `tab-switcher.png`: no held-modifier API; a press-and-release chord would not establish the requested held-Control state.
- Skipped `little-arc.png`: the complete Settings → Shortcuts accessibility list contained no Little Arc / transient-window action.
- Rejected `toolbar-zoom.png` / `page-corner-zoom.png`: attempted `-R693,323,400,60` and `-R1649,1035,100,100` from verified CG bounds. Resulting 800×120 / 200×200 crops showed a different foreground surface. Removed from deliverable directory (moved to temporary files); no wrong-surface substitute retained here. Window-only PNG measurements remain valid.

## Runtime issues and cleanup

- No crash or hang was observed in the isolated main session. `console.log` is empty; this is stdout/stderr only, not a claim about all unified system logs.
- Immediate typing after ⌘T once split characters between the command input and GitHub's Go to file field. Waiting for the observed focused command field and pasting resolved it. This is an observed focus race; whether automation latency contributed is unknown.
- Folder Rename exposed a field without focusing it; ⌘A selected webpage text and paste timed out. Clicking the field before typing succeeded. The new-space name edit also needed explicit Settings editing to persist.
- Requested split shortcut did not visibly open a split on the active Favorite. Context menu → Open in split view on an unselected Today tab did work. Closing the extra pane removed that Today tab; it was reopened.
- Several real coordinate actions failed in computer use with `windowNotFoundAtPosition`. No scripted app driver, `GRAPHENE_DEBUG`, or `cmd.txt` was used.
- No transient layout jump/flicker is claimed: settled screenshots do not establish its presence or absence. Wikipedia reflowed between sidebar states, as expected when page width changes.
- Main PID **31781** quit through ⌘Q and was confirmed absent with `ps`.
- Fresh onboarding PID **38225**, window **9523**, used `/tmp/graphene-arc-look-verify-2-onboarding`. Initial ⌘Q while the onboarding sheet was open did not exit; after clicking Skip setup, ⌘Q succeeded. Final `ps` confirmed both owned PIDs absent.
- `.build/Graphene-verify.app` removed and absence verified. The first cleanup check caught onboarding still alive; it was subsequently quit as described. `/tmp/graphene-arc-look-verify-2` remains in place.
- Reduce Motion original state **off**, enabled for the exercise, then restored and read back **off** in System Settings. On this macOS version it is under Accessibility → Motion.
- No process not started by this run was quit. No commit was made.
