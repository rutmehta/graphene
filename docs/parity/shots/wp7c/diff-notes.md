# WP7c resumed visual pass

## Status

Implementation and capture follow-up completed, but **full parity acceptance is not met**. This report distinguishes live observations, source checks and failed verification. No commit, delegation, cron job or task queue was used. Only the explicitly requested GUI app ran asynchronously.

The previous run already landed the single-row footer, 30pt rows, deep tint, removed single-pane header, traffic band and wide Chat. This run inspected those files and the retained captures before changing anything.

## Changes in this resumed session

- `Sources/Graphene/UI/TopTabBar.swift`: equal-width leading/trailing navigation groups keep the address container centered even when the recent-download icon changes. Reload now becomes Stop while a page loads. Existing 40pt strip, 32pt chips, 8pt chip radii, 4pt gaps and 40pt second row remain.
- `Sources/Graphene/UI/ChatView.swift`: aligned header/message/composer outer insets at 16pt, removed redundant empty-conversation explanatory heading. Retained real errors, provider-unavailable reason, context controls, citations, source search and all chat actions. Existing 500pt default width, 40pt header, 34pt context row, subtle user bubbles, flush assistant and 12pt composer remain. Saved widths are not rewritten.
- `Sources/Graphene/UI/CommandBar.swift`: removed the repeated generic “Browser action” subtitle, retained the meaningful archive warning and source details, made plain action rows 36pt and detailed rows 50pt, and sized the initial list to six complete plain actions plus its section heading. Explicit scroll indicators and keyboard scrolling retain access to remaining results. This fixed the visibly cut-off final action found during comparison in both layouts and appearances.
- `README.md`: current WP7c behavior, footer command routes, 40pt top-tabs description and current screenshots.
- `docs/parity/shots/wp7c/`: this report, resumed captures, comparison generator, derived collages, hashes, measurements and execution logs. Prior WP7c images were preserved under their original names.

No model/schema/persistence change was required for these refinements. Existing optional settings, atomic session persistence, shortcut registry and menu routes remain. No files under `docs/parity/ref/` or Little Graphene code were changed.

## Reference corrections and measurements

The brief's estimates do not literally describe the supplied competitor captures:

- Vision measurement of live `wp7b/arc-main-dark.png` gives approximately **41pt tab pitch**, approximately 36–37pt selected-row height, 228pt sidebar and a roughly 44pt top band. The brief explicitly asks for **30pt** pitch; Graphene keeps that target rather than claiming it matches Arc exactly.
- `dia-main-dark.png`, `dia-chat-dark.png` and `dia-cmd-t-dark.png` all show **vertical tabs**. Dia Cmd+T shows its central new-tab Chat page, **not an expanding address bar**. Consequently the 40pt horizontal-tab target comes from the brief, not a measured horizontal-Dia reference.
- Dia's pictured Chat is approximately 500pt wide, an inset floating overlay occupying about 46% of the non-sidebar region. Graphene's 500pt default matches its approximate width, but uses a docked full-height split when space allows. It is not an identical compositing/layout treatment.
- `measurements-resumed.json` samples the same normalized sidebar box (8,80)–(220,790). Including text/icons/selection, Arc mean RGB is (53.47,50.46,69.61), median (42,37,56); Graphene mean is (44.31,39.12,59.40), median (39,34,54). Graphene is somewhat darker; the predominant purple depth is close. Means are not pure background-color estimates because the populated content differs.
- Earlier driver PNGs contain transparent shadow margins; resumed PNGs are window-only. The generator crops the alpha>=250 bounds before normalization, then resizes to 1280×820. This fixes the previous comparison script's canvas-versus-window scaling error. Antialiased boundaries make this approximate to a few pixels, not proof of ±2pt equivalence. No webpage is recolored or re-rendered.

## Glance-test verdict by region

| Region | Light Graphene | Dark Graphene | Honest remaining difference |
| --- | --- | --- | --- |
| Footer | Single quiet row, dots and plus clear; Ask above | Same, without a second surface-icon row | Library content retained from source/earlier capture; resumed popover capture failed. Arc has no Ask row. |
| Tab rows | Compact, readable, no overlapping labels | Translucent selected pill and deep background read clearly | 30pt pitch intentionally denser than live Arc's ~41pt. Favorite grid remains four-column rather than the user's Arc three-column arrangement. |
| Sidebar tint | Pastel lavender intact | Saturated purple close in depth, somewhat darker | Not an exact RGB clone; own space hue/gradient and content differ. |
| Page frame/header | Inset page, no extra title/close bar in sidebar mode | No conspicuous dark border; no extra header | Arc capture itself has a horizontal address/navigation row above its web content. The brief deliberately asks Graphene to put that in the sidebar. |
| Traffic band | Lights and navigation appear vertically aligned | Same geometry; inactive capture can mute lights | ±2pt match not established. Two foreground drag attempts left window bounds unchanged; full drag-band acceptance remains open. |
| Sidebar command | Compact list, final action/footer intact | Same, selected accent remains quiet | Arc reference primarily shows tab-switch results rather than browser actions. Graphene footer has more keyboard hints. |
| Top tabs | Equal-height compact rows; centered domain; no clipping | Same, neutral dark chrome | No horizontal competitor screenshot exists in supplied references. Do not call this measured Dia parity. |
| Top address expansion | Expands downward from same address container; six full actions | Same, clear rounded lower edge | Dia supplied Cmd+T is a different new-tab interaction, not this expansion. |
| Chat | Header/context/messages/composer fit cleanly | Same hierarchy, subtle user bubble, flush answer | Width close to Dia, but full-height docked instead of inset floating. Dia capture is onboarding while Graphene shows a restored conversation. Secondary controls remain small. |

All ten comparisons were inspected for visible issues. The final command refinement was recaptured and its four comparisons re-inspected; final margin-normalized main/chat/top-tabs/top-command samples were inspected again. No glaring overlap or clipped command action remains in these recorded states. This does not establish drag, hover timing, every narrow-window state or full accessibility compliance.

## Live verification and limits

All launches used `GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile`; neither resumed launch enabled `GRAPHENE_DEBUG`. Public test tabs and the previous run's persisted conversation were restored, not invented or generated for this pass. The visible question/answer is an existing stored exchange; this run did not submit a new model request.

Verified by subsequent computer_use captures:

- Footer plus opens the sidebar command palette; Cmd+T opens it in both layouts.
- Escape dismisses command UI.
- Cmd+K opens/closes Chat; Ask row disappears while Chat is open and reappears when closed.
- Cmd+Shift+L switches both ways, captured in light and dark.
- Typing “Switch layout” and Return changes layouts; subsequent captures show the actual horizontal/vertical chrome.
- Top-tabs address expansion stays aligned with the resting container.
- Restart restores top-tabs layout and dark mode; isolated session JSON readback also confirms them.
- Sidebar main images re-observe items 1–5 at rest: footer, tab density, tint, header removal and traffic-band appearance. This is not a complete interactive re-test of Tidy, space dots, hover chevrons, download expiry or native surface routes. Existing unit tests cover Tidy and download expiry.

Driver limits, without pretending these are application success:

- `focus_app` could not resolve the owned instance by name, including with the PID supplied. Exact capture using **app bundle ID + PID + window ID** established the right target. Omitting the app string left subsequent input without an active target.
- Every SOM capture returned an empty AX tree, despite existing identifiers/labels/button traits in inspected Graphene controls. Foreground coordinate/keyboard delivery worked for the paths above. This is not proof of app-wide accessibility; adding duplicate identifiers would not fix an empty whole-window transport response.
- Library was clicked by fresh-capture coordinates. Its auxiliary window existed in CG window enumeration, but the next two captures returned 0×0; a popover-target capture also failed. Escape/quit routing failed while that unresolved window was targeted. Returning to the exact main-window capture recovered input. No resumed Library-entry selection is claimed; previous `graphene-library-dark.png` remains explicitly historical evidence.
- Two traffic-band foreground drags reported delivered but did not change CG window bounds: (388,275,1280,820) before and after. Source uses `WindowDragRegion`/`performDrag`; whether the failure is hit testing or synthetic delivery is unresolved. Stopped after two attempts per brief. No speculative app change was made for an unproven cause.
- No Arc/Dia state or system appearance preference was changed. Only their retained references were used. Thus **no live light competitor captures or horizontal Dia captures were acquired**, and light collages visibly retain the dark competitors. Those missing references prevent the full same-appearance gate.

## Evidence inventory

Ten resumed captures (`resumed-*.png`): main, sidebar command, Chat, top tabs, expanded top address, each light and dark. Ten `compare-*.png` collages use Arc | Dia | Graphene ordering. Arc main is explicitly labeled a non-Chat reference in Chat collages; Dia new-tab is explicitly labeled not address expansion. `screenshots.json` validates **28 PNGs**: 10 resumed + 10 comparisons + 8 retained earlier WP7c captures.

Main/chat/top-tab captures: PID 18111, window 102793. Refined command captures: PID 45456, window 102810. Command captures were replaced only after actual recapture on the refined binary; the other views did not change in that refinement.

Regenerate with:

    uv run --with pillow python docs/parity/shots/wp7c/make-comparisons.py

## Build, tests, cleanup

- `swift build`: success, no warnings in final build log.
- `swift test`: **82 tests, 1 skipped, 0 failures**. Skipped test is the existing opt-in real-model harness, `AnswerQualityTests.testLiveAnswers`; no live-model pass is claimed.
- `./scripts/build-app.sh`: success, ad-hoc signed `.build/Graphene.app`.
- Full logs: `build-resumed.log`, `test-resumed.log`, `bundle-resumed.log`. Commands captured combined stdout/stderr and printed their final 30 lines via Python, preserving subprocess exit status.
- `git diff --check`: passed.
- Previous WP7c owned PID 31743 had no discoverable on-screen window and was terminated before restarting its profile. Unrelated Graphene instances were not targeted.
- Both resumed owned PIDs **18111 and 45456 exited after computer_use Cmd+Q**, verified with `ps`. Requested `pkill -f graphene-dev-profile` cleanup ran afterward. No owned Graphene process is left running.

## Remaining acceptance work

1. Verify the Library popover's actual entries and traffic-band dragging with a reliable exact-window input/AX path. Two failed captures/drags are disclosed above.
2. Obtain authorized light Arc/Dia and horizontal Dia references before claiming same-appearance/horizontal parity. The brief's stated reference files do not provide those states.
3. Exact traffic-light coordinate matching, hover-only chevrons and all items 1–5 behavioral re-tests are not fully established by the resting captures. The code and regression tests remain, but screenshots are not substitutes for those interactions.
