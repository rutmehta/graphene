# Task: verify the Graphene identity layer (D6, packages G1–G5) on the real app

You are Codex running on macOS with the computer-use tool. Use it for every interaction with the app (clicks, keys, drags); use the shell only for builds, file work and `screencapture`. Do the work synchronously yourself. Do not delegate, do not schedule jobs, do not ask questions; if something is blocked, record it and move on. Never use `GRAPHENE_DEBUG`, the `cmd.txt` debug driver, or any scripted UI automation inside the app.

## Goal
Build `master`, run it on an isolated profile, exercise the acceptance lines from `docs/design/graphene-identity.md` (sections 3.1 to 3.6 and 6) and `docs/design/graphene-language.md` section 7, save window-only PNG evidence, and write a blunt report to `docs/parity/shots/identity/report.md`. Do not commit.

## Build and launch
1. `git status`; note HEAD and untracked files (untracked files under `docs/parity/` are expected, not a blocker). Never delete, stash or commit anything.
2. `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`. Never touch `~/Applications/Graphene.app`; never quit a Graphene process you did not start.
3. Launch from a shell that stays alive: `rm -rf /tmp/graphene-identity-verify; GRAPHENE_DATA_DIR=/tmp/graphene-identity-verify .build/Graphene-verify.app/Contents/MacOS/Graphene & wait`. Record the PID. Complete onboarding with defaults; note which colour swatch was preselected. Window 1280×820.
4. Window id: `swift scripts/window-id.swift -p <PID>`. Capture with `screencapture -l <id> -o -x <file>.png`; verify each PNG with `sips -g pixelWidth -g pixelHeight` and by viewing it. All at 1280×820, 2×.

## Checks and captures (public pages only)
**A. Graphite default (G2).** `main-fresh-dark.png` and `main-fresh-light.png` of the empty fresh profile (toggle appearance with ⇧⌘L). Record whether the onboarding default was Graphite and the space's hue/saturation read back in Settings → Spaces.

**B. Resume page and lattice (G3).** `resume-empty.png`: a new tab in the fresh profile (search field plus lattice only, and the line "Open a page and Graphene will keep the thread."). Then browse: open https://en.wikipedia.org/wiki/Graphene, from it ⌘-click two links (Carbon and Graphite), then from Carbon ⌘-click one link. Open https://forums.swift.org in a new tab. Select a sentence on the Graphene page and press ⌘D. Open a new tab: `resume-populated.png` must show "Continue" with two threads and correct page counts, and "Saved here" with the note in serif with a left rule. Click the note: `resume-open-note.png` must show the Graphene page scrolled to the highlighted sentence. Collapse the sidebar (⌘S) and open a new tab: `resume-collapsed.png` must show the favorites row; expand: it must not.

**C. Provenance rows (G1).** With the tabs from B: `sidebar-branch.png` must show Graphene at the root, Carbon and Graphite indented under it, the third link doubly indented under Carbon, with one continuous hairline from Graphene's icon to the last child and ticks into each child's icon slot. Select the deepest tab: `sidebar-branch-active.png` (the branch's connector turns accent). Close Carbon with ⌘W: `sidebar-promoted.png` (its child becomes Graphene's child at the same position). Right-click Graphene: `context-branch.png` shows "Close branch". Press ⌥← on Graphene: `sidebar-collapsed-branch.png` shows the count at the trailing edge; ⌥→ expands. Drag the deepest row above Graphene: `sidebar-detached.png` (it becomes a root, the line shortens). Then switch to a space with no child tabs: `sidebar-no-branches.png` must look exactly like the Arc-look sidebar (compare with `docs/parity/shots/arc-look-2/main-dark.png`).

**D. Vault shelf (G5).** After the ⌘D save in B (and a second ⌘D on forums.swift.org): `shelf.png` shows the "Vault" word and two chips with the right favicons and serif quote fragments above the footer. Hover a chip: `shelf-hover.png` (full quote card) if hover is capturable; else state it. Click a chip: the source page opens scrolled to the mark (`shelf-open.png`). Open Vault and delete both notes: `shelf-gone.png` shows the footer back at the Arc geometry.

**E. Ask citations (G4).** On the Graphene Wikipedia tab press ⌘K. `ask-empty.png`: header grounding line "This page" with an accent dot, sources strip with the page chip, skills chips above the composer, placeholder "Ask about this page…". Ask "What is graphene's tensile strength and who first isolated it?" Wait for the answer. `ask-answer.png`: inline numbered chips, a sources line under the answer, and highlighted passages in the page with matching superscripts. Hover chip 1 (if possible): `ask-hover.png` shows the page scrolled to and the mark active. Ask "What is the capital of Peru?": `ask-nosources.png` must show the "No sources; this is the model's general knowledge." line. Close the panel: `ask-closed.png` shows no marks left in the page. If the on-device model is unavailable or refuses, capture the exact panel state and say so; do not fake an answer.

**F. Reduce Motion.** Enable it, collapse a branch and open the shelf state, `reduce-motion.png`, then turn it back off and confirm.

## Measurements
From PNGs (÷2 for points): child row indent (20 per depth), connector x from the row's leading edge (17), shelf height (44), chip size (96×32), resume column width (560), lattice cell (28), mark colour vs page colour. Note any hairline that is not a provenance connector or a quote rule, any serif on chrome text, and any lattice outside the four allowed places.

## Report
`docs/parity/shots/identity/report.md`: HEAD, PID, build/test log tails (`swift test` output), a table of every acceptance line above with PASS / FAIL (observed) / FAIL (blocked) and evidence file names, the measurement table with deltas, a "What still doesn't read as one product" list ordered by visual impact, crashes/hangs/console errors, and cleanup (quit your PID, delete `.build/Graphene-verify.app`, Reduce Motion restored). Do not soften failures. Do not claim what you did not observe.
