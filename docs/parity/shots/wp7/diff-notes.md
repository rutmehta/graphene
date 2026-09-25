# WP7 visual audit

## Evidence and limitations

Graphene was bundled and launched only with GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile. The prior disposable profile was preserved as /tmp/graphene-dev-profile-before-wp7-1789095013122471000. Public sites were seeded using the existing debug driver: Wikipedia, GitHub, YouTube and NYTimes, three favorites, two pins, a folder, two spaces. The driver initially produced nine tabs (including an extra blank tab).

Graphene AX window geometry is 1280 × 820 points. Captures are scaled by the driver and must not be treated as point measurements. Arc and Dia resting captures were obtained; their original bounds were not changed. Arc has a password-manager prompt open, left untouched. The installed Dia uses vertical tabs, so a live horizontal-mode reference has not been established. Historical references in ../../ref were examined with vision, never edited.

The onboarding sheet had no AX elements. Background click was refused (off_space_or_ax_unresolved); foreground click did not dismiss it. Following the two-attempt limit, this step was abandoned. Cmd+Q also failed on that sheet; the owned process was terminated. Restart with the seeded session removed onboarding normally. These are driver limits, not passed interaction tests.

## Region-by-region differences before changes

- Sidebar top: Graphene reserves 36pt, but toggle is above the visual traffic-light center. Navigation and site controls compete with domain text in a single 204pt row; Wikipedia truncates to a handful of letters. Give the domain a full-width translucent pill and move navigation to the traffic-light band.
- Space header: Graphene repeats the space name above the favorites and again below. Keep theme/rename reachable but reduce header prominence.
- Favorites: four columns and 24pt icons already exist; 48pt tiles. Empty state wrongly consumes 40pt and says “Drop favorites here.” Hide the empty section but retain a drop target during tab drag.
- Pinned: Graphene shows an empty header and separator. Hide empty pins/folders. Existing 8pt stack gaps turn 32pt rows into 40pt pitch; brief requests 30–32pt density.
- Today and tab typography: inactive labels are regular; use 13pt medium and 32pt rows with 2pt separation. Folder indentation is unnecessarily deep; preserve hierarchy without shrinking titles.
- Hover/active: selected light pill is close, but there is no tab-hover animation. Use palette selection tokens and an 80ms hover fade, with Reduce Motion respected. Keep the close target reserved.
- Footer: long space rows can draw under Downloads/Board/Settings. Constrain the scroller, scroll selection into view, use small inactive space dots and an expanded active name. Preserve utility actions and surface launchers.
- Page frame: Sidebar already has 8pt padding and a 12pt radius. Use 10pt in Sidebar and 12pt in Top tabs; Top tabs currently has zero page inset. Preserve gutter preference and quiet shadow. Split title bars are flat, lack site icons and rounded pane framing.
- New tab: large Graphene wordmark, 62pt search box, marketing sentence, and 520pt content width compete with the browser. Remove branding and marketing copy; use a compact centered search affordance and quiet recent-thread list.
- Command bar: current centered 600pt panel is appropriate for Arc-style layout. Top tabs wrongly uses the same floating position; anchor its existing functional results panel to the unified bar instead. No change to query, context, action or keyboard semantics.
- Top tabs toolbar: “Chat or search” placeholder, icon-only Ask button and colored tab strip differ from the brief. Use “Search or ask”, a labeled Chat control, neutral palette chrome, compact tabs and an inset rounded page.
- Chat: persistent messages, chips and provider status already exist. Header and empty-state copy dominate the panel; simplify and add real @ and / composer buttons wired to existing pickers. Preserve source search and unavailable-provider explanation.
- Settings: existing native sidebar/form structure is retained, not replaced by a custom clone. Live comparison outstanding.
- Context menus: native menus already used; no custom styling required. Live comparison outstanding.
- Appearance/motion: light/dark tokens and Reduce Motion branches exist. System appearance and Reduce Motion interaction verification outstanding. No system settings changed so far.

## Final verification and remaining work

Status: **partial visual pass, not near-match parity**. The final comparison was inspected with vision. It still shows obvious differences in toolbar architecture, sidebar grouping/density, selected-tab treatment and footer utilities. The same-size Arc/Dia/Graphene acceptance gate is not met. The reference montage is explicitly labeled and must not be presented as a normalized live-window comparison.

Implemented in this pass:

- Stronger space-colored Sidebar chrome, neutral Top tabs palette without rewriting saved space themes, translucent domain/selection pills.
- Full-width sidebar address container with Back/Forward moved to the window-control band. Wikipedia's domain is now readable.
- 13pt medium tab labels; 32pt rows with 2pt spacing; hidden empty Favorites/Pinned sections, revealed drop targets during a drag; four-column favorites retained.
- Clipped, horizontally scrolling space footer with inactive dots and active name, automatic selection visibility. Threads, Vault, Mail, Ask, Downloads, Board and Settings remain available.
- Compact 44pt new-tab search affordance, no wordmark/marketing copy, quiet recent threads.
- Neutral Top tabs, labeled Chat button, 6pt page gutter and rounded page. Top-tabs command panel is anchored near the unified bar rather than vertically centered; it is still a separate overlay, **not a true morphing address bar**.
- Chat's simpler header/empty state and @ and / buttons, with the slash picker preserving an existing draft. No fake model response or conversation was seeded.
- Rounded split frames with favicons and a quieter focus outline. Split interaction was not reverified.
- 80ms icon/tab/button hover fades and 120–160ms shell/palette transitions where changed. Existing Reduce Motion branches preserved. Space slide remains 180ms and was not motion-verified.

Real computer-use actions confirmed by subsequent captures:

- Cmd+T opened the Sidebar palette; text insertion worked. The first attempted layout search concatenated because Cmd+A did not select text; this caused a real test Google search, which remains in the disposable profile's recent threads. It is visible in the new-tab evidence, not fabricated content.
- A fresh palette search for the actual action name, **Switch layout**, followed by Return switched to Top tabs and back.
- Cmd+K opened and closed the real Chat panel. Its current-page chip, budget, composer and unavailable/ready status remain real UI; response generation was not tested.
- Cmd+, opened the native General Settings window. Appearance-row click failed first with `snapshot_id_required`, then with a no-op coordinate click. Stopped that step after two attempts.
- The slash button click was not confirmed after background and foreground attempts. No claim of button-input verification.
- The palette's **Home** action created the minimal new-tab page. Cmd+W closed that tab. Cmd+S collapsed and restored the Sidebar, and Cmd+4 selected the seeded Graphene pin.
- Shift+Cmd+L produced dark and light Sidebar captures. Webpage pixels were not artificially inverted.
- System appearance was read as dark, temporarily set light for a Dia capture, then restored to dark. AppleScript read-back returned **true**. No Arc/Dia tab, account or window geometry changes were made.

Remaining acceptance items and reasons:

- All three windows at 1280×820, all live reference regions, Arc/Dia palettes/context menus/Settings/Chat, and precise region-by-region near-matching: not completed. Arc had a password-manager prompt; mouse/AX targeting repeatedly failed in Graphene. Competitor interactions were left untouched instead of risking their signed-in tabs. The comparison therefore uses Arc's redacted historical still and Dia's live vertical layout, with original bounds.
- Hover captures: the exposed computer_use schema has no mouse-move/hover action. No JavaScript/debug substitute was counted as verification.
- Reduce Motion both ways, space slide, drag/drop, empty-section drag targets, split interaction and context menus: not desktop-verified. Settings clicks failed and no system accessibility preferences were changed.
- The Top-tabs unified bar is not a seamless Dia-style address expansion. The page/sidebar geometry and footer remain visibly Graphene-specific. More styling work is required; this report does not claim that driver failures alone explain all remaining visual differences.

Build and tests:

- `./scripts/build-app.sh` succeeded after each code batch; final bundle is `.build/Graphene.app`.
- Final `swift build` succeeded with no warnings. `swift test` passed **64 tests, 0 failures**, including three new palette/layout regression tests. These were added after the visual implementation, not a claimed strict TDD cycle. Full logs are alongside this report.
- `git diff --check` passed. No commit was made. No file under `docs/parity/ref/` was edited. Little Graphene was untouched.
- **16 PNG files** were decoded/verified and hashed in `screenshots.json`: baseline, Graphene light/dark main, Top tabs, two command panels, Chat, Settings, dark New Tab, collapsed Sidebar, Dia light/dark, and four explicitly labeled comparison collages. `make-comparisons.py` uses Pillow via `uv run --with pillow python` and retains only real screenshots/crops.

Cleanup:

- Final owned Graphene PID **18040** exited after computer_use Cmd+Q, verified with `ps` before the requested `pkill -f graphene-dev-profile` cleanup. Earlier sheet/Settings-blocked owned processes needed SIGTERM, as documented above.
- Final isolated session contains **8 tabs across 2 spaces**. The prior disposable profile backup was kept. Pre-existing Graphene processes were not targeted. Arc and Dia remain open and their tabs/windows were not changed. System appearance is restored.

Files changed by this pass: `Sources/Graphene/App/AppState.swift`; `Sources/Graphene/UI/{Sidebar,Theme,RootView,TopTabBar,ChatView,SplitView}.swift`; `Tests/GrapheneTests/VisualPaletteTests.swift`; `README.md`; this WP7 evidence directory. Existing changes from earlier packages were retained.
