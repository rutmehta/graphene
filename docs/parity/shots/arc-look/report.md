# Arc-look real-app verification — September 25, 2026

**Result: NOT ACCEPTED. This is an incomplete verification run, with one confirmed acceptance failure and substantial capture/tooling blockers. It is not a completed screenshot or measurement set.**

The command bar changes its vertical position with the number of results. Empty Command-T, the selected current URL, and a `swift` query appeared at visibly different heights. Acceptance item 4 fails. Other acceptance items that lack sufficient evidence are marked FAIL (verification blocked), rather than misrepresented as product defects or passes.

## Revision, build, and process provenance

- Initial branch: `master`.
- Initial HEAD, used for the verification bundle: `2b11f27e7cf401385ae610a07ab2cb135761558e`.
- Initial `git status --short`: empty. No tracked changes or untracked files were reported, including under `docs/parity/`.
- HEAD observed later: `a5b8b9fae095eeb00b9a79e8da01f190f327c367`, committed at `2026-09-25T02:18:11-04:00`, “Sidebar peek: watch the pointer against the window edge instead of a 4pt hover strip.” This task did not make that commit. The checkout changed during verification.
- Build command: `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`.
- Main isolated profile: `/tmp/graphene-arc-look-verify`; it did not exist before launch and remains in place.
- Main verification PID: **18506**.
- Fresh onboarding profile: `/tmp/graphene-arc-look-onboarding-verify`; it did not exist before launch.
- Onboarding verification PID: **23425**.
- No installed `~/Applications/Graphene.app` build or modification was performed. No source edits, stashing, or commits were performed by this task.

Build log tail, from [build.log](build.log):

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.16s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

This was an incremental build with no warnings in its log, not a clean recompilation of every source file.

`swift test` completed at 02:18:44: **125 tests executed, one skipped, zero failures**. See [tests.log](tests.log). The checkout had advanced by that time; do not describe the tests and earlier running bundle as validation of one fixed revision.

The supplemental [literal-audit.txt](literal-audit.txt) checks additions between the pre-implementation design revision `cbc00e3` and the built revision, under `Sources/Graphene/UI`. It found no matching added literal font-size, corner-radius, or fractional-opacity expressions outside `Theme.swift`; 12 matches were token definitions in `Theme.swift`. The exact package-brief grep gate was not located or executed. This limited regex is not proof that every prohibited form is absent.

## Setup actually observed

Onboarding was completed with the default Sidebar layout and Tide color, without setting a default browser or importing data. The initial main window's computer-use image was 2560 × 1640 pixels, consistent with 1280 × 820 points at 2×. No independent saved main-window PNG established that scale, and no resize was performed because the displayed window already had those dimensions.

The first launch attempt (PID 18275) exited when its launching shell ended, before the isolated directory appeared. Selecting the verification app path through computer use then launched PID 18310 without the environment override; it showed existing-profile content. That instance was immediately quit with Command-Q and its exit checked. No navigation or settings changes were intentionally made in it. The corrected launch kept the launching shell alive with `wait` and produced fresh onboarding at PID 18506. Existing-profile persistence effects from that accidental launch were not audited.

The seeded Research space was observed with:

- Four Favorites: Wikipedia Graphene, Swift repository (redirected to `github.com/swiftlang/swift`), Apple Developer, and Hacker News.
- Three pinned tabs: Example Domain, Apple, and Swift Forums. Example Domain was moved into the `Reading` folder through its tab context menu.
- Four Today tabs: three Example Domain URLs with distinct `today` query parameters, plus an Apple tab. The Apple Today tab's title later changed to an iPhone product page without an intentional navigation action by this task; the cause was not established.
- An existing second space named Personal, supplied by the fresh profile. It was switched to and back through the footer. A new duplicate Personal space was not created; the requested Command-Option-N creation path was not verified.

Dark appearance was selected and read back in Settings. The Research theme was set using the Iris preset: the visible theme sliders read hue `0.6928571428571429` (about **249.4°**) and saturation `0.3535353263967225`. This is near the requested hue but is **not** the spec's exact 243°/0.6 reference condition. Attempts at precise slider adjustment did not establish the requested value. Light appearance was subsequently exercised using Shift-Command-L and visibly showed pastel chrome.

All app actions used computer-use clicks, keys, paste, or drags. No debug driver, debug environment, or scripted interaction inside Graphene was used.

## Capture integrity and inventory

**Only `settings-general.png` is a validated deliverable PNG.** It was produced using `screencapture -i -w -o -x` and an interactive window-selection attempt, rather than the requested `-l <windowid>` method. `sips` reports **1640 × 1304**, or 820 × 652 at 2×. It was viewed and confirmed to show Graphene General settings. It therefore fails the requested 1280 × 820 capture size.

The documented computer-use API did not expose a numeric macOS window ID, a pointer-move/hover action, or a way to keep Control held across a separate capture. Its native app screenshots and the shell's desktop capture did not reliably target the same surface. A second interactive capture stayed pending while Graphene-directed actions continued; a region capture and that delayed interactive capture captured unrelated content. Those two task-created files were moved out of the repository into `~/.Trash/graphene-verify-invalid-captures/`. Their contents are not reproduced here. No measurements use them. No further desktop-region capture was attempted.

Computer-use screenshots of many states were inspected during the run, but they were **not saved as the requested repository PNG files**. The distinction matters: an inspected state is not a delivered capture.

| Requested files | Observation / disposition |
|---|---|
| `main-dark.png`, `main-light.png` | Wikipedia loaded; dark and light chrome visually inspected. Files absent: capture blocked. |
| `row-hover-dark.png`, `today-hairline-hover.png` | Not verified. No supported pointer-only hover control; do not infer hover or 100 ms timing from clicks. |
| `favorite-hover.png` | Not verified; same hover limitation. |
| `favorite-selected.png` | Selected Wikipedia tile inspected, including pale fill and outline; file absent. |
| `folder-open.png`, `folder-collapsed.png` | Reading expanded with its child and collapsed without its child were observed. Files absent. |
| `command-bar-cmdt.png` | Empty bar inspected; eight action rows visible. File absent. |
| `command-bar-url.png` | Toolbar URL click opened bar with the full Wikipedia URL selected; selection verified in accessibility text and screenshot. File absent. |
| `command-bar-cmdl.png` | Command-L opened the same selected URL state. File absent. |
| `command-bar-query.png` | `swift` showed Swift Forums, Swift repository, Threads, and search suggestions. File absent. |
| `toolbar-zoom.png`, `page-corner-zoom.png` | Region capture stopped after wrong-surface result. Neither crop exists. |
| `sidebar-collapsed.png` | Collapsed state inspected; page moved left, navigation remained to the right of the reserved control area. File absent. |
| `sidebar-peek.png` | Not verified; pointer-only move unavailable. The later HEAD also changed the peek implementation. |
| `space-switch.png`, `space-personal.png` | Settled Personal state inspected. No mid-transition evidence. Files absent. |
| `split.png` | Shortcut produced no visible change. Context menu → Open in split view worked, showing Wikipedia and Example Domain in separate cards. File absent. |
| `chat.png` | Command-K opened a floating chat card with composer and context chip. No message was sent. File absent. |
| `toast.png` | Closing a Today tab via Command-W exposed “Closed Example Domain” and Undo in accessibility output. The toast had disappeared by the subsequent screenshot. File absent. Tab was reopened with Shift-Command-T. |
| `tab-switcher.png` | Control-Tab changed the active recent tab. Holding Control for a capture was unavailable; the switcher card was not verified. |
| `little-arc.png` | Skipped: no Little Arc / transient-window shortcut was listed in Settings → Shortcuts. |
| `settings-appearance.png` | Appearance page inspected with Dark, On page address bar, Floating chat, and 420 pt chat width. The saved capture was invalid and removed from deliverables. |
| `settings-general.png` | **Exists, viewed, dimension checked: 1640 × 1304.** Valid General settings image, wrong requested size/method. |
| `onboarding.png` | Fresh instance showed onboarding step 1. Inspected image had substantial white space beneath the browser preview; no compliant PNG saved. |
| `reduce-motion.png` | Reduce Motion was enabled, sidebar collapsed/expanded, and Personal selected. Settled state inspected; motion itself not observed. File absent. |

## Section 6 acceptance

FAIL (blocked) means the acceptance criterion was **not demonstrated**, not that its implementation is necessarily defective.

| # | Acceptance item | PASS / FAIL | Evidence and limits |
|---|---|---|---|
| 1 | Arc-like main dark/light geometry and overall appearance | **FAIL — blocked** | Required main PNGs and measured comparison absent. `settings-general.png` is the only valid saved image and cannot establish shell geometry. |
| 2 | Sidebar RGB within 12 per channel of the 243° dark reference | **FAIL — blocked** | No valid sampled main PNG; hue/saturation also differed from the reference condition. |
| 3 | Today hover fill/close within 100 ms; hairline reveals Clear | **FAIL — blocked** | Pointer-only hover unavailable. No hover filenames exist. |
| 4 | Command-T, URL click, Command-L use same bar position; URL selected | **FAIL — observed defect** | URL selection worked. The empty bar, URL bar, and query bar moved vertically as their heights changed. Inspected computer-use images, but requested evidence PNGs absent. |
| 5 | Sidebar spring, no toolbar jump, no traffic-light overlap | **FAIL — blocked** | Settled collapsed/expanded layouts worked. Spring and transient jumps not captured. Screen-sharing badge obscured traffic lights in most images. |
| 6 | Space gradient cross-fade and row slide | **FAIL — blocked** | Space selection worked; only final frames were observed. |
| 7 | Reduce Motion: no movement, fades only | **FAIL — blocked** | System switch on was verified; interactions completed. Frame-by-frame movement was not observed, so neither “no movement” nor “still moved” is established. |
| 8 | Warning-free build, green tests, no new removed literals | **FAIL — incomplete gate** | `build.log` has no warnings; `tests.log` is green (125/1 skipped/0 failed). Limited literal audit found no non-Theme additions matching its regex. Exact gate absent and revision advanced between bundle build and test completion. |

## Measurements and deltas

No numerical shell measurement below is claimed from a validated saved Graphene PNG. “N/A” is intentional. Reading token constants or reusing old screenshots would not satisfy this task.

| Measurement | Spec §2 / §6 target (points unless stated) | Valid saved-PNG measurement | Delta |
|---|---|---|---|
| Page top/right/bottom gaps | 8 / 8 / 8, tolerance ±1 | N/A | N/A |
| Page radius | 10 ±1 | N/A | N/A |
| Toolbar height | 32 ±1 | N/A | N/A |
| Nav button centers, relative to page card | x 22 / 52 / 82; y 16 (28 pt targets, 2 pt gaps, 8 pt inset) | N/A | N/A |
| Favorites width / height / horizontal gap | 62.67 derived / 44 ±2 / 10 | N/A | N/A |
| Favorite columns | 3 at 208 pt content width | 3 visually observed, no valid main PNG | N/A formal |
| Tab row height / pitch | 36 / 40 ±1 | N/A | N/A |
| Favicon / Favorite icon | 16 / 20 | N/A | N/A |
| Space label height | 24 (§3.3) | N/A | N/A |
| Footer height | 36 | N/A | N/A |
| Traffic-light centers | (20,22), (40,22), (60,22) | N/A; sharing badge obscured controls | N/A |
| Command width / radius | 640 / 16 | N/A | N/A |
| Command input / row height | 56 / 44 | N/A | N/A |
| Command top offset | 0.18 × height = 147.6 at 820 high | N/A formally; clearly varied across inspected states | N/A formal; fails constant-position requirement |
| Chat width / top-right-bottom inset | 420 / 16 | N/A; Settings value read back as 420 | N/A formal |
| Dark sidebar top / middle / bottom RGB | (14,13,38) / (21,13,38) / (32,10,38), each channel ±12 | N/A | N/A |
| Light sidebar top / middle / bottom RGB | HSB formulas in §2.3; depends on hue/saturation and sampling position | N/A | N/A |
| Dark / light page-border RGB | White 12% / black 8%, composited on the underlying color | N/A | N/A |

For locating the command-bar bug only, manual estimates from the inspected 2560 × 1640 computer-use images put the top edge near 526 px for empty Command-T, 766 px for the URL state, and 478 px for `swift`. At an assumed 2× these are about **263, 383, and 239 pt**, or **0.321, 0.467, and 0.291** of the window height, versus 0.18. Approximate offsets from the spec are **+115, +235, and +91 pt**. These are inspection estimates, **not** `sips`-validated deliverable measurements.

Reference comparison: `docs/parity/ref/arc/manifest.md` explicitly reports a blocked capture attempt with no usable PNGs or measurements. The fallback `docs/parity/ref/arc-main.png` was viewed; it is redacted and scaled. The design text describes its scale as about 1.37 image px/point, while `docs/parity/measurements.json` reports 0.7242 image px/AX unit (1489/2056). Those are not interchangeable calibration statements. The old JSON estimates are toolbar 33.1, radius 9.7, and row pitch 41.4 in its reported native units; they are not newly validated measurements. No precise Graphene-to-Arc delta is asserted.

## What still doesn't look like Arc

Ordered by observed visual impact; visual impressions are separate from unmeasured tolerances.

1. **The command bar floats around the middle of the page and jumps when results change.** It should have a stable top edge in the upper portion of the window. The URL-only version is especially low. This is a directly observed defect, not just a missing test.
2. **The dark toolbar becomes a charcoal slab over a white Wikipedia page.** The card reads as two contrasting planes. The supplied Arc fallback shows a much lighter navigation strip; Graphene's observed dark strip does not reproduce that treatment. The site was visibly light while Graphene's toolbar was dark.
3. **The GitHub Favorite nearly disappears in dark mode.** Its black mark sits on a dark translucent tile with very little separation. Selected Wikipedia also changes from a clear white favicon background to a grayer treatment. The dark icons need visual attention; no contrast ratio was measured.
4. **The sidebar gradient reads weakly in the chosen Iris state.** It looks nearly uniform dark purple over most of the sidebar, compared with the spec's stronger navy-to-plum description. Exact color failure cannot be declared without matching hue/saturation and RGB samples.
5. **The window has a visible horizontal rule through the top band, including the sidebar.** That line interrupts the intended continuous chrome plane. It was visible in both light and dark inspected states, above the Favorites grid.
6. **Several favicons remain letter placeholders.** Example Domain and Swift Forums showed tinted letter squares, rather than recognizable site marks. This is especially conspicuous beside the Wikipedia, GitHub, Apple, and Hacker News icons.
7. **The empty command bar leads with specialist actions.** Site Controls, Edit Site Boost, and Zap an Element dominate the first rows. Although the card's general styling is close to the design, this initial content feels more like a command utility than a browser destination launcher. This is a UX observation, not a numbered acceptance failure.

The purple screen-sharing indicator replacing the traffic lights and the large pointer highlight belong to the inspection environment. They are capture contamination, not reported as Graphene styling defects.

## Errors, surprises, and evidence limits

- Typing a complete Wikipedia URL immediately after Command-T initially left only a trailing fragment and navigated to search. Waiting for the input state and pasting the full URL worked. The exact cause (focus delay versus input delivery) was not isolated.
- Computer use reported “The user changed … Re-query the latest state” during seeding and capture work. Fresh state was obtained before subsequent actions.
- Theme popover coordinate actions twice failed with `windowNotFoundAtPosition`. Settings → Spaces → Theme exposed accessible controls; selecting Iris worked. Precise slider drag did not stick.
- Preview selection timed out twice; saved-image validation used direct file viewing instead of an app interaction.
- Interactive `screencapture` control and app-directed input diverged. The wrong-surface results were excluded from deliverables.
- The initial cleanup command containing `rm -rf` was rejected by automatic command review. The profile did not exist, so deletion was unnecessary and launch proceeded without it. No override was attempted.
- No Graphene crash or sustained hang was observed. Both isolated instance console logs were empty. This does not establish absence of errors outside those redirected streams.
- During onboarding cleanup, the first Command-Q did not end PID 23425. A subsequent state unexpectedly showed additional spaces without an intentional import action. No identities or contents are reproduced here; isolation of that final UI state was not established. The PID was checked as task-owned, a second Command-Q was sent, and exit was confirmed.

## Cleanup

- Main PID 18506: Command-Q sent; process absence confirmed.
- Onboarding PID 23425: second Command-Q required; process absence confirmed.
- Accidental unisolated verification-bundle PID 18310: quit and process absence confirmed.
- `.build/Graphene-verify.app`: removed and absence confirmed. Removal happened after the first onboarding quit attempt, before the retry established final process exit; this sequencing error is recorded explicitly.
- `/tmp/graphene-arc-look-verify`: retained.
- Reduce Motion: original **off**, enabled for checks, restored **off**, and verified through System Settings.
- Invalid task-created captures: moved to Trash; not present in this deliverable directory.
- No existing repository evidence was removed, no stash was made, and this task created no commit. The later HEAD change was external to this task.

The requested PNG suite, measured parity comparison, hover timing, and animation acceptance remain incomplete. This report must not be used to approve the Arc-look rebuild.
