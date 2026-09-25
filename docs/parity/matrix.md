# Graphene parity specification: Arc and Dia on macOS

Research cutoff: September 10, 2026, EDT. Repository: `/Users/rutmehta/Developer/graphene`, working tree on `master`, not just committed HEAD.

## WP9 update — September 11, 2026

The **Graphene now** feature-table column supersedes the original **Graphene today** column for current implementation status. The original comparison, source line numbers, gap sizes, priorities and proposed work packages below are preserved as a historical September 10 baseline, not a description of the current tree. Current entries consolidate WP1–WP8 implementation/evidence reports and WP9 checks; unless explicitly labelled WP9 observed/tested, they are carried-forward implementation status rather than fresh end-to-end verification. Competitor claims have not been re-researched.

WP9 is **not release-ready sign-off**. Debug/release builds are warning-free; 87 XCTest cases execute with one opt-in live-model skip and zero failures. The 0.3.0 bundle passes strict ad-hoc signature verification. Actual interaction coverage, a real benign-page AI refusal, stress measurements, desktop targeting failures and every outstanding gate are recorded in `shots/wp9/verification.md`. Little Graphene remains disabled and out of scope. `README.md` is the current usage/shortcut inventory.

## Historical status and evidence limits

This is an engineering gap specification with a partially completed local visual audit, NOT a claim of exhaustive locally verified parity. Desktop input approvals timed out for Arc's disposable-window shortcut, Graphene's New Tab button, and Graphene's quit shortcut. They were not retried or bypassed. Settings pages, menus, split interactions, and AI panels could therefore not be captured. The complete installed-app shortcut inventories also remain unverified. The tables below preserve those unknowns rather than inventing bindings or screenshots.

Installed versions read from application Info.plists: Arc **1.163.1**, Dia **1.47.2**. Arc's public September 10 release is **1.164.0**; Dia's September 10 issue is **1.49.0** in the rendered release-note index. No apps were updated. Consequently, September web functionality must not be assumed present in the installed versions or enabled for this user's account.[4][113]

Evidence labels:

- **Documented**: public first-party help or release notes, cited inline. Availability can depend on version, account, plan, or rollout. These are not hands-on performance measurements.
- **Observed**: actual resting-window screenshot or accessibility geometry from this session.
- **Source**: current Graphene source inspection, not proof that every code path works in the existing binary.
- **Unknown**: not established. This does not mean absent.
- Gap **none** means the narrowly stated behavior exists or is intentionally not a parity target; **small** means a bounded extension to an existing subsystem; **large** means missing architecture or a substantial workflow. Unknown parity is conservatively sized and flagged.
- **P0**: daily-driver correctness, privacy, recoverability, or essential shell interaction. **P1**: high-value parity after that foundation. **P2**: optional differentiation, ecosystem-scale work, or explicitly deferred mimicry. Priority is not a promise to implement everything.

### Captures and application state

Actual captures: `ref/arc-main.png` (private page and tab labels visibly redacted), `ref/dia-main.png` (public Dia release-note page), `ref/graphene-main.png` (isolated empty profile). Five derived crops: `arc-sidebar.png`, `arc-space-bar.png`, `dia-sidebar.png`, `graphene-sidebar.png`, `graphene-space-bar.png`. Footer crops are NOT captures of an expanded space switcher. `screenshots.json` records origins, dimensions, redaction rectangles, crop coordinates, and PNG hashes.

| Requested view | Arc | Dia | Graphene |
|---|---|---|---|
| Main window at rest | Captured, redacted | Captured | Captured |
| Sidebar / tab strip | Crop of main | Vertical-sidebar crop; horizontal mode not captured | Crop of main |
| Cmd+T / command bar | Blocked by input approval | Not attempted after input gate failures | Click to open blocked by input approval |
| Settings pages | Not captured | Not captured | Source-only menu inventory below |
| AI panel / Max | Not captured | Not captured | Ask source inspected, not captured |
| Split View | Not captured | Not captured; documented support | Not implemented in inspected source |
| Tab context menu | Not captured | Not captured | Source-only inventory |
| Space switcher | Visible footer only | No Arc-style Spaces established; profile switcher not captured | Visible footer only |
| Threads / Vault / Mail | Not applicable | Not equivalent native surfaces | Source inspected, not captured |

Arc and Dia were already running. No successful state-changing inputs were delivered to them, no account changes were made, and no tabs were closed. Arc's active page changed independently between read-only captures, so its final state cannot be claimed identical to the initial screenshot. The private content has not been transcribed into this report.

Graphene was launched exactly with `GRAPHENE_DATA_DIR=/tmp/graphene-parity-profile /Users/rutmehta/Developer/graphene/.build/Graphene.app/Contents/MacOS/Graphene`. Owned PID: **66950**, window ID **99392**. A pre-existing Graphene PID **14394** was left alone. The requested Cmd+Q approval timed out; PID 66950 was still running at the last check. Quit/cleanup is an outstanding acceptance item, not a completed step. No research was delegated or scheduled. The only background process launched was the explicitly requested GUI app.

## Executive assessment

Graphene already resembles the right class of product: a compact native sidebar, restrained tinted chrome, an inset page, a keyboard-first navigation palette, and a companion panel. The biggest gaps are behavior and completeness, not an entirely new visual identity. In particular, a pinned tab is currently a Boolean plus a tile, a Space is not a cookie-isolated profile, and Ask is a short-excerpt answer generator rather than Dia's multi-turn, tool-connected assistant.

Three corrections prevent a stale comparison:

1. Arc **Ask On Page was removed August 28, 2025**. Preserve it as historical context, not a current Arc requirement. Remaining documented Max tools are 5-second Previews, Tidy Tab Titles, Tidy Downloads, ChatGPT command-bar integration, Instant Links, and Tidy Tabs.[3][4]
2. Arc **Reader Mode was removed June 6, 2024**; Arc Notes were phased out in April 2024. Boost editing survives, but Boost sharing is deprecated. Do not recreate retired functionality just to check a parity box.[4][18][21]
3. Dia has advanced beyond its launch-era chat sidebar: pinned groups, meeting groups, tab cleanup, cross-device sync, proactive suggestions, live work groups, and connected-tool workflows. Some new AI experiences are gated behind Apps > New Chat and connected tools. Current plan documentation also separates free browsing from paid AI for new users, with existing-user transition exceptions.[108][119][121]

## Feature matrix

Graphene evidence references G1–G10 are defined immediately after this table. Unless explicitly marked otherwise, competitor entries are documented rather than locally exercised.

| Feature | Arc | Dia | Graphene today | Gap size (none/small/large) | Priority (P0/P1/P2) | Graphene now |
|---|---|---|---|---|---|---|
| Native desktop shell | Sidebar-first, inset page observed | Vertical sidebar and inset page observed; alternate topbar documented [113] | SwiftUI/AppKit shell, inset WKWebView [G1] | small | P0 | SwiftUI/AppKit shell retained; WP9 browsing/Threads/Print observed. |
| Vertical / horizontal tabs | Sidebar is core model [152] | Switchable sidebar/topbar, both hideable [113] | Vertical only; preserve as default [G1] | small | P2 | Both persisted layouts implemented (WP3/7c); horizontal interaction not reverified in WP9. |
| Sidebar resizing and collapse | Drag-to-collapse documented [4] | Resize, collapse, rubber-band at limits [62][149] | Toggle exists; stored width but no resize handle [G1][G2] | small | P0 | 200–360pt divider and collapsed edge-peek implemented; physical resize/peek gate open. |
| Arbitrary Spaces | Create, name, icon, theme, reorder context; each has pinned/unpinned sections [152] | Profiles plus tab groups, not a verified Arc Spaces clone [39][142] | Two predefined spaces, Research/Personal; no user create/delete/rename [G2] | large | P0 | CRUD, icons, reordering and folder/tab migration implemented; WP9 stress seed has four spaces. |
| Switching work context | Footer icons, sidebar swipe, Ctrl+number, command lookup [152] | Profile switcher; Ctrl+number documented [51][119] | Footer buttons only; last active tab per space in memory [G2] | small | P1 | Footer dots, Control-number and commands implemented; full gesture check open. |
| Profiles and login isolation | Separate cookies, history, authentication, favorites, extensions; profile can serve multiple Spaces [153] | Separate tabs, logins, AI; per-profile Memory controls [39][51] | All normal spaces share one static WKWebsiteDataStore [G3] | large | P0 | Named isolated WebKit stores and space assignments implemented; live cookie isolation not reverified. Knowledge library remains shared. |
| Per-space visual identity | Theme picker, icon, light/dark/automatic [152] | Profile colors; group colors/icons [43][142] | Five color presets, global light/dark, no automatic appearance [G1][G2] | small | P1 | Presets/custom hue/saturation/intensity/gradient/grain plus system/light/dark implemented. |
| Favorites distinct from pins | Up to 12 icon tiles; shared across Spaces within profile [27][153] | Pinned tray documented; identical Arc favorite tier not established [61] | Pins rendered as tiles, only within active space; no favorite tier [G1][G2] | large | P1 | Separate Favorites grid and pinned rows; Favorites remain space-scoped, not Arc profile-global. |
| Pinned-tab base URL | Pin preserves a resettable original destination; favicon or Reset Tab returns there [26] | Cmd+Return returns pinned tab to base URL [61] | Current URL + isPinned only; no base URL [G2][G3] | small | P0 | Persisted pinnedURL and Reset Tab implemented; full navigation/reset UI check open. |
| Close versus unpin | Pins are durable saved destinations distinct from ephemeral tabs [26] | Persistent pinned destinations; exact installed close semantics unverified [61] | Close removes even a pin; reopen restores pin only from in-memory stack [G2] | small | P0 | Separate close/unpin confirmation and durable archive restoration implemented. |
| Manual tab naming / icon | Rename, customized icons documented [3][4] | Double-click rename; emoji/icon override [44][49] | Title follows document; no override fields [G3] | small | P1 | Custom tab titles and contextual Rename implemented; arbitrary per-tab icon override not established. |
| Nested folders | Persistent pinned organization, hover-search preview; no auto-archive [151] | Collapsible groups with color/icon and hover preview, not proven nested folders [142] | Flat list and pin grid only [G1][G2] | large | P1 | Folder model and drag/drop organization implemented; full nesting/drag acceptance unverified. |
| Pinned groups | Pinned folders [151] | Pinned groups persist across profile windows; new groups auto-pin [141][145] | No group model [G2] | large | P1 | Pinned folders implemented, not Dia synced live groups. |
| Temporary tab lifecycle | Unpinned Today tabs; idle auto-archive, default 12 hours, cannot fully disable [150] | Stale-tab cleanup prompt, optional Clean-Up Daily, configurable age [114] | Open indefinitely; no last-active/archived tab model [G2] | large | P1 | 12h/24h/7d/Never auto-archive plus Tidy; protected-tab policy tested. |
| Archive / restore | Searchable archive, restore and clear; separate Little Arc filtering [13][150] | Overflow lists open/recently closed tabs/groups, chats/files, other devices [114] | Reopen stack capped at 20 and not persisted; graph history is not a tab archive [G2] | large | P0 | Searchable persisted archive, restore/delete and Undo implemented; capped at 2,000 on insertion. |
| Recently closed windows | Window behavior not tested; tab restore documented [1] | File-menu restore of a closed window with all tabs [145] | Shared AppState across WindowGroup; no window-session restoration model [G2] | large | P1 | Independent window selection/shared collections exist; restore-whole-closed-window remains absent. |
| Tab reorder / multi-select | Drag pin/unpin, Option-drag duplicate [26] | Drag group membership; multi-select context actions [142][149] | Vertical delta divided by 40, within same space/pin status only; no multi-select [G1][G2] | large | P0 | Drag/drop, keyboard reorder, Command/Shift selection and batch actions implemented; exhaustive physical check open. |
| Context menu richness | Duplicate, reset, move to, split, pin/favorite documented [10][26][27] | Actions show current customized shortcuts [113] | Regular: Pin, Copy link, Close. Pinned: Unpin, Close [G1] | small | P0 | Shared grouped menus for tabs/favorites, rename/reset/move/split/close and current shortcut hints; full menu check open. |
| Command bar navigation | URLs/search, named actions, extension invocation, spaces [24][152][155] | URLs/search/chat, skill invocation, new-document commands [49][55][119] | Search/open plus active-space tab/history matches, eight results; no command registry [G4] | large | P0 | Shared action registry, sections, cross-space tabs, history, notes, threads and Ask implemented. |
| Search engine selection | Configurable; Site Search keyword + Tab + query [156] | Configurable default, extension search shortcuts documented [44][54] | Google/DuckDuckGo only; no custom keyword engines [G4] | small | P1 | Built-in selection and custom %s search URL implemented; keyword engine shortcuts not established. |
| Cross-window tab search | Recent-tab switcher and command navigation [1][31] | Cmd+Shift+A searches all windows in current profile [44] | Palette restricted to active space [G4] | small | P1 | Palette searches shared cross-space tab collection; independent profile/window behavior needs full UI check. |
| Browser keyboard customization | Settings remapping, website-preference handling documented [1][37] | Settings remapping; non-US layouts fixed [47][60] | Fixed shortcuts; no conflict/remapping surface [G2] | large | P0 | Settings remapping/conflict checks and shared menu bindings implemented; live remapped-menu check open. |
| Little Arc | External links in a lightweight window, promote to a Space; default six-hour archive [13] | Equivalent detached external-link triage not established | No external URL event handling / mini browser in inspected App layer [G2] | large | P2 | Disabled, no menu/settings entry; explicitly out of scope for WP9. |
| Air Traffic Control | Contains/exact URL rules, default Space/most recent/Little Arc [24] | Arc-equivalent arbitrary routing rules not established | No routing policy or profile destination [G2] | large | P1 | Ordered enabled URL-glob routing to Spaces, external links and rule tester implemented. |
| Split View | Horizontal/vertical, persisted sidebar item; add directional split, separate, replace panel [10] | Split button/Open as Split; drag targets; remembered layouts [39][61][62] | One active WebContainer, Ask is not a second browser page [G1] | large | P1 | Two-to-four-pane persisted split model, focused pane and close controls implemented; drag gate open. |
| Split navigation context | Each split panel can change URL and focus independently [10] | Shift+Option-click opens in right side of split [51] | ActiveTabID global; must introduce focused pane without losing provenance [G2] | large | P1 | Per-window selection and focused split navigation implemented; regression tests cover persistence/close. |
| Peek | Cross-site links from pins/favorites open transient preview; promote to tab/split [11] | Group/site previews exist; equivalent interactive Peek not established [142] | Links navigate or open ordinary tabs [G3] | large | P1 | Transient preview and promotion implemented; full pinned-link interaction check open. |
| Favorite/site previews | Supported favorite sites can expose glanceable previews [12] | Calendar preview and live work previews [62][143] | No hover previews [G1] | large | P2 | Delayed bounded thumbnail cards implemented; service-specific live previews absent. |
| GitHub live work | Automatic GitHub Live Folders [25] | Pinned GitHub Live Groups, review/own PRs, merge cleanup, reauth and status previews [143][147] | No integration [G2] | large | P2 | Not implemented. |
| Meeting support | Live Calendar, meeting entry points [23] | Calendar previews, countdown/join reminders, auto-group related meeting links [44][62] | Gmail only; no meeting model [G9] | large | P2 | Not implemented; read-only Gmail is not meeting support. |
| Basic navigation / load state | Mature browser navigation; not benchmarked here [1][4] | Load cancel, crash/low-disk states documented [52][53][55] | Back/forward/reload/stop, swipe gestures, progress line, load error/retry [G1][G3] | small | P0 | URL navigation observed in WP9; back/forward/reload/stop and recovery implemented, full retest open. |
| New-tab links / popups | Browser tabs, Peek and split routing [10][11] | Browser tabs/groups/split destinations [46][51] | Cmd/middle click and target=_blank supported; configuration/opener fidelity not established [G3] | small | P0 | New-tab links and popup routing implemented; full opener/redirect compatibility remains unverified. |
| Multiwindow / webview ownership | Cross-window tab handoff documented [37] | Profiles/windows and restoration documented [44][145] | Shared singleton state and one engine view per tab; robust multiwindow ownership not implemented [G2][G3] | large | P0 | Per-window AppState over shared library with explicit WebView handoff; model tests pass. |
| Site controls / permissions | Site Control Center, PiP and Developer Mode; Chromium settings [14][17][153] | Permission identity improvements, ad/tracker controls [7][51] | Lock is scheme-based icon, not certificate inspector; no site-control center [G1][G3] | large | P0 | Host controls, certificate metadata and supported media/motion policy implemented; location/notifications disclosed as system-managed. |
| Private browsing | Incognito shortcut; extensions opt-in [1][155] | Dark incognito, excluded from Memory [52][145] | Debug profile is nonpersistent cookies but still records graph; no user private mode [G2][G3] | large | P0 | Nonpersistent windows and no browser-knowledge/session writes implemented and unit-tested; full private UI gate open. |
| Capture retention / forget site | Browser history/profile controls; no equivalent native knowledge store established [153] | Per-site Memory exclusions delete prior memories; per-profile/per-chat controls [51][52] | Automatic page-text capture, no exclusion list or forget-site UI [G3][G5] | large | P0 | Space pause, host exclusions and confirmed forget-site implemented; Vault notes retained. |
| Ad / tracker blocking | Extension ecosystem; current built-in default policy not verified [155] | Built-in blocker; legacy Manifest V2 unsupported from 1.17 [7][141] | No configured content-rule blocker in engine [G3] | large | P0 | Bundled bounded EasyList-derived WebKit rules, global toggle and exact-host overrides implemented; not full EasyList. |
| Password / passkey / autofill | Profile authentication and imports documented [153][154] | iCloud passkeys documented [61]; broad autofill not tested | WKWebView alone is not proof of full browser password-manager integration [G3] | large | P0 | Safari-equivalent Passwords integration not implemented; no password import. |
| Extensions | Chrome extensions, toolbar pins and command-bar invocation [155] | Modern Chromium extensions; per-profile extension sync [141][149] | Chrome extensions explicitly unsupported [G10] | large | P2 | Chrome extensions not implemented. |
| Browser import | Chrome, Safari, Firefox, Brave, Edge, Opera, Opera GX, Vivaldi; data varies [154] | Chrome pin import and account-bookmark import documented [49][124] | No import UI/model [G2] | large | P0 | Safari/Chrome bookmarks/history and Arc spaces/pins/favorites preview/import implemented; passwords and Arc Today excluded. Live import UI gate open. |
| Find in page | Cmd+F [1] | Cmd+F, redesigned Find UI [116] | WKFind, wrapping previous/next, no result count [G1][G3] | small | P0 | WP9 real Cmd+F/Cmd+G shows 1 of 2 then 2 of 2; exact main-document WebKit Range counts, frames excluded. |
| Page zoom / print / save | Zoom bindings documented [1]; full-page capture documented [19] | Printing support noted for popups [44]; other bindings require inventory | No explicit page zoom/print/save-page command plumbing in inspected engine/commands [G2][G3] | small | P0 | Host zoom and web-archive save implemented; WP9 native Print dialog observed and cancelled. |
| Downloads | Library/download location; Max renaming [3][28][32] | Download menu with prior downloads; safer notifications [51] | WKDownload + NSSavePanel + completion toast; no progress list, resume, cancel, history [G8] | large | P0 | Progress/history/popover and completion actions implemented; interrupted, not automatically resumed. Real download gate open. |
| Media playback controls | Mini audio controls in sidebar when leaving playing tab; muted tabs excluded [14] | PiP documented; exact standalone audio-controller feature unverified [108][124] | Webpage controls only; no browser-level playing/muted state [G3] | large | P1 | Audible HTML-media polling/Now playing implemented; Web Audio and iframe limits remain. |
| Picture-in-picture | Automatic on tab departure; manual; resize; site opt-out [14] | Video/Meet PiP, edge stash, Back to Tab [60][124][149] | WebKit/site-provided PiP may work; automatic shell PiP and controls absent [G3] | large | P1 | Real-user-activation page button implemented; floating PiP not verified; earlier WKWebView unsupported result retained. |
| Reader mode | Removed June 2024 [4] | Dedicated current reader mode not established; PDF context support is different [51] | Captured text in Threads, not in-page Reader Mode [G6] | small | P2 | Native text-only Reader, preferences, Vault save and Ask implemented; not Readability. |
| PDF/media understanding | PDF browser behavior not locally tested; no current Ask On Page [4] | PDF/image attachments and YouTube summaries [44][51][114] | DOM text capture omits canvas/iframe; not PDF/image/video comprehension [G3][G5] | large | P1 | No general PDF/image/video comprehension; DOM text only. |
| Boost visual editor | Colors, inversion, contrast, brightness, saturation, fonts, size, case, Zap, CSS/JS [21] | No first-party equivalent established | No user site-style editor [G3] | large | P2 | Per-host CSS/JS, font/scale/presets and persistent Zap selectors implemented; full editor/apply UI gate open. |
| Boost lifecycle/sharing | Per-domain, applies across profiles; disable/delete; sharing deprecated [21] | No equivalent established | None; do not implement retired sharing for parity | none | P2 | Save/disable/delete per-host Boosts implemented; no retired sharing feature. |
| Easels / visual capture | Whiteboard, draw/text/images, web captures, full-page capture, PNG export/share [19] | Reports/decks, not an established Easel canvas [39][108] | Threads map + Markdown Vault, no freeform canvas/capture export [G6][G7] | large | P2 | Space Boards with cards, geometry and Markdown export implemented; no Arc capture/drawing/PNG parity. Empty Board observed in WP9. |
| Native notes | Arc Notes phased out; New Note delegates to configured web service [16][18] | Writing drafts/chat, not Graphene's local Markdown Vault [51] | Own Markdown notes with edit/delete/source links [G7] | none | P0 | Vault grid/detail/edit/delete/provenance and Markdown files retained; WP9 Save sheet opened but saving not confirmed. |
| Space/folder/split sharing | Public URL snapshots; see constraints below [20] | Group URL copying documented; identical public sharing not verified [44] | Thread Markdown export only [G6] | small | P2 | Thread and Board Markdown export only; public shared snapshots absent. |
| Sync | Spaces/tabs sync; profile data does not per help [153] | E2EE/local-first sync, settings, tabs from other devices, extensions [127][148][149] | No sync [G10] | large | P2 | Not implemented. |
| Arc Max: 5-second Previews | Shift-hover link summaries; automatic hover on supported sites [3] | Chat/research context, not identical hover workflow | No link-summary preview [G5] | large | P2 | Shift-hover bounded cookie-free summaries implemented; full hover UI check open. |
| Arc Max: Tidy Tab Titles | AI shortens title when pinned, manual rename available [3] | Manual rename, automatic group naming/icon features [49][143] | No title override or AI renaming [G3] | small | P2 | Opt-in AI pin titles and manual rename implemented; live title-quality check open. |
| Arc Max: Tidy Downloads | Automatic filename rename, undo by clicking name [3] | Equivalent automatic download naming not established | Uses sanitized server filename [G8] | small | P2 | Opt-in suggestions with explicit confirmation and extension preservation implemented; live check open. |
| Arc Max: Instant Links | Shift+Return after command-bar query; can open multiple results/folder [3] | Search/chat routing, not verified identical action [119] | Search-engine URL only [G4] | large | P2 | Not implemented; Shift+Return opens a split instead. |
| Arc Max: Tidy Tabs | Broom groups Today tabs when more than six [3] | Grouping + stale cleanup [114][142] | No grouping/classification [G2] | large | P2 | Tidy archives stale Today tabs; not AI classification/grouping. |
| Arc Max: ChatGPT shortcut | Cmd+Option+G; logged-in ChatGPT profile required [3] | Native assistant rather than ChatGPT tab | On-device Ask; not a ChatGPT shortcut [G5] | none | P2 | No ChatGPT-specific shortcut; native configurable Chat retained. |
| Arc Max: Ask On Page | Removed August 2025 [4] | Core Chat feature [157] | This-page Ask source snapshot exists [G5] | none | P0 | Ask on Page retained despite Arc retirement; not current Arc parity. |
| Chat with current page | No current Max equivalent [4] | Cmd+E, context-aware help on page [157] | This-page scope, source capture, Use current tab refresh [G5] | small | P0 | Persistent Chat/context implemented; WP9 slash summary returned a refusal on example.org, unresolved model-quality failure. |
| Chat with multiple tabs / groups | No current comparable assistant documented [3][4] | Explicit tab attachments and @group attach all tabs [44][51] | Page/space/thread scopes; no arbitrary @tab picker [G5] | large | P1 | Explicit @tab/@all and removable chips implemented; full two-tab UI retest open. |
| @history and past chats | No comparable current assistant documented [3] | History includes chats/sites, automatic Memory search [51][60] | Lexical local source search; not persistent chat history [G5] | large | P1 | Local source retrieval and persistent per-space/profile chat history implemented; not Dia automatic history Memory parity. |
| Multi-turn chat persistence | No native equivalent established | Chats history, deletion, context/tool progress [43][146] | Each ask resets and creates a new LanguageModelSession; last question/answer only [G5] | large | P1 | Streaming, Stop/Regenerate/Copy and last-50 conversation storage implemented; WP9 refusal exchange persisted correctly. |
| Skills / reusable prompts | No Dia-style skill system; Max fixed feature toggles [3] | Editable team/user Skills, try/remix/gallery, slash or name invocation [50][51][55] | Two hardcoded suggestions; no reusable prompt model [G5] | large | P1 | Four editable slash skills in skills.json; WP9 /summarize invoked, but its answer failed quality. |
| Memory / personalization | No equivalent assistant memory established | Per-profile memory, per-chat disable, forget specific memory/site, ChatGPT import [51][52] | Provenance graph and notes are explicit evidence, not learned preferences [G5][G6] | large | P1 | Opt-in profile-scoped facts/settings/edit/delete implemented; no ChatGPT-memory import. |
| Writing help in text fields | No current Max writing editor documented [3] | Writing proposals/drafts documented [51][53]; exact current in-field replace UI NOT locally verified | No selection-to-rewrite/replace workflow [G3][G5] | large | P1 | Explicit preview/Replace/Insert below/Copy with field guards implemented; textarea/contenteditable full recheck open. |
| Reasoning / research | Instant Links is not a persistent researcher [3] | Read Links progress, deeper reasoning and skip control [50][54][62] | At most four excerpts, 1,400 characters each, 450 response tokens; no web research [G5] | large | P2 | No autonomous research. Apple source budget 6,000 chars/700 response tokens; remote context cap 24,000 chars. |
| AI source transparency | Max partner processing disclosure [3] | Attachment errors, citations, visible tool calls [54][62][146] | Source list and numeric citation prompt; no validation that generated references are correct [G5] | small | P0 | Source chips, trimming notices and validated numeric citation indices implemented; truth of generated claims not guaranteed. |
| AI model/offline behavior | Max sends data to partners [3] | Remote AI with fallback models documented [51] | Apple FoundationModels, availability/error UI, lexical search works without model [G5] | none | P0 | Apple plus opt-in OpenAI-compatible/Anthropic providers; lexical search independent. WP9 Apple refusal is a failed quality check, not provider success. |
| AI action on tabs | No generalized native agent established | @Tabs opens/closes tabs with action trace [61][146] | Ask cannot mutate tabs; citation buttons open sources [G5] | large | P2 | No generalized AI tab mutation/tool agent. |
| Voice | Not established for Max | Streaming transcription documented [146] | Standard OS dictation only, no app voice subsystem established [G5] | small | P2 | No app voice subsystem; standard OS dictation only. |
| Connected work tools | Calendar/GitHub browser integrations [23][25] | Slack, Granola, Notion, Linear; September Microsoft SharePoint/Teams tools [120][122][123] | Read-only Gmail only [G9] | large | P2 | Read-only Gmail only. WP9 local OAuth callback race/leak fixed and socket-tested, no live account connection. |
| Morning Brief / proactive work | No equivalent current feature established | New-tab suggestions, daily brief, reports/decks and meeting prep, rollout/plan-dependent [108][119][121] | Recent threads on new-tab page; no scheduled digest [G1][G10] | large | P2 | Recent Threads on New Tab; no scheduled digest or proactive work integrations. |
| Settings completeness | Native shell settings plus Chromium/profile/site settings [3][153][156] | Tabs/Profiles/Memory/Shortcuts/Apps/Sync and billing surfaces [108][121][148] | Small appearance/search/Vault menu only [G1] | large | P0 | 13 settings pages implemented; controls include routing/AI/import/shortcuts. Full persisted-control UI sweep incomplete. |
| Accessibility / keyboard focus | Exact compliance not audited | Shortcut/layout fixes and visible menu bindings documented [47][113] | Labels, Reduce Motion, native NSTextField; drag/multi-selection and surface keyboard audit outstanding [G1][G4] | small | P0 | Key controls have IDs/labels/traits; WP9 SOM index transport still rejects missing snapshot tokens. Full focus/Reduce Motion check open. |
| Memory/resource behavior | No benchmark taken; current releases mostly Chromium/security maintenance [4] | Cache cap, tab discarding and startup work documented, not measured here [49][62][145] | Every restored URL loads; one live engine per tab; no discard scheduler [G2][G3] | large | P0 | Lazy restore/discard and bounded caches implemented. WP9 60 tabs/four spaces: 1.82s window registration, 60 visits unchanged after >5m. Not interactive-readiness/discard proof; default discard is 30m. |
| Updates/distribution | Installed app + documented security releases [4] | Installed app + published updates [44][61] | README says ad-hoc local build, production signing/distribution future [G10] | large | P0 | 0.3.0 ad-hoc bundle and warning-free debug/release builds verified; production signing/notarization/updater absent. |

### Graphene source evidence map

Additional parity details that should not be flattened into a checkbox:

- Arc shared Spaces/Folders/Splits are snapshots at link creation, not live collaborative documents. A new share is required for updates. The help page says a shared link cannot be self-service deleted or sharing undone, and authenticated content still requires the recipient's own access. Do not copy that irreversibility into Graphene. Arc also documents Share Quote links from selected webpage text.[20]
- Arc's GitHub live folder supports filters such as Created by Me, Drafts and repositories, but its documentation excludes self-hosted/custom-domain GitHub Enterprise. Its Calendar countdown/join affordance requires Google Calendar in Favorites. These are service-specific integrations, not generic semantics of every pinned tab.[23][25]
- Dia documents iPhone-to-Mac tab Handoff, confirmation-dialog loop protection, selectable/copyable dialog text, and bookmark menus that grow up to 600px. Graphene's synchronous `NSAlert.runModal()` handlers have no per-origin dialog-loop guard in inspected source. Add that to WP3 rather than calling native alerts complete browser parity.[43]
- Dia's source-level product quality bar includes avoiding flashes on tab close, protecting the last ten recent tabs from proactive discard, prewarming favicons, and avoiding chat-panel flicker across tab switches. These are vendor-documented improvements, not performance results measured here.[49][64]
- In-field writing is a specific unresolved audit item. The documented Write/proposal behavior supports describing writing assistance, but not claiming a universal floating bubble or reliable replacement in every rich editor. Verify selected plain text, textarea, contenteditable, Gmail and Google Docs separately; password/payment fields must be excluded. Graphene should start with explicit draft preview and undoable insertion, not arbitrary page mutation.[51][53]

- **G1 Shell:** `Sources/Graphene/UI/RootView.swift:4–174` (layout, sidebar, surfaces), `:195–272` (settings and tab menus), `:276–357` (toolbar/page/loading), `:362–409` (new tab); `UI/Theme.swift:82–105`; `UI/WindowAccessor.swift:15–22`.
- **G2 State/commands:** `App/AppState.swift:14–20` (width/spaces), `:66–75` (space switch), `:154–224` (tab lifecycle), `:299–372` (session); `App/GrapheneApp.swift:10–20,39–70` (shared window state and shortcuts).
- **G3 Web/tab model:** `Model/Tab.swift:16–39`; `Web/WKWebEngine.swift:16–43` (shared store), `:92–101` (capture), `:130–176` (links, downloads, dialogs, uploads). These establish missing explicit shell APIs, not that WebKit cannot render a feature.
- **G4 Palette:** `UI/CommandBar.swift:29–89` (matching/ranking/scope), `:94–164` (geometry), `:235–335` (native focus/input); `Model/Omnibox.swift`.
- **G5 Ask:** `UI/KnowledgeSearchView.swift:14–59,84–98,112–160,267–334`; `Intelligence/KnowledgeAssistant.swift:23–86`. Captured page context is deliberately stable until refreshed. Notes in knowledge scope are filtered by graph URL membership, so a Mail-only Vault item can be missing from Ask.
- **G6 Threads:** `Model/KnowledgeGraph.swift`; `UI/LedgerView.swift:4–51,56–120,159–214`. Provenance visits and a graph survive closing browsing tabs; a visual tab group must not replace this data model.
- **G7 Vault:** `UI/VaultView.swift:4–109`; `Store/Vault.swift`; `Store/Paths.swift:19–31`. Standalone note files and editing are already real capabilities.
- **G8 Downloads:** `Web/BrowserDownload.swift:6–36`. Handler survives tab close, but resume data is ignored on failure and no progress registry is exposed to UI.
- **G9 Mail:** `UI/MailView.swift:7–20,65–103,169–179`; `Mail/MailStore.swift`, `Mail/GmailClient.swift`. No credentials, tokens, or actual messages were read during this audit.
- **G10 Product boundaries:** `README.md:16–24,26–41,51–71`. Important discrepancy: README says favicons are local initials only, but current `UI/Favicon.swift:4–63` implements same-origin `/favicon.ico` fetching for live tabs with a bounded response and in-memory cache. Treat source as authority for the current tree. The empty binary capture does not establish populated-favicon behavior.

## UI and polish

### Measurement methodology

Use AppKit points/AX native units for implementation, not the tool's resized PNG dimensions. Tool screenshots include shadow margins and were not normalized to a common window size. Ratios were calculated from visible window bounds and AX width, not from the tool's generic scale hint (which includes desktop offsets). Inputs and calculations are in `measurements.json`. Arc's geometry tree was from the initial resting capture; its redacted PNG is a later resting capture at apparently unchanged bounds, so the conversion is approximate. Do not turn these estimates into an unsupported pixel-perfect claim.

| Property | Arc observed/estimated | Dia observed/estimated | Graphene source/observed |
|---|---|---|---|
| Screenshot file size | 1568×983 px | 1568×1340 px | 1568×1037 px |
| Native window bounds | Initial AX 2056×1289 | AX 1163×994 | AX 1007×666; configured default 1280×820, minimum 940×620 |
| Sidebar | AX tab region 228 units; image estimate about 229 | AX tab region 192; image estimate about 191 | Source width 224; page left edge about 230 including six-point inset |
| Toolbar | About 33 points from 24 image pixels | About 41 points from 52 image pixels | Exact 36 points; observed about 36 |
| Page corner radius | Estimate 8–12 points | Estimate 10–14 points | Exact 12 points; observed about 12 |
| Tab row height/pitch | AX 40 high, consecutive rows 41 apart | AX about 39 high; overlapping new-tab/active bounds preclude a rigorous inter-row gap | Exact minimum 36 high + 4 gap = 40 pitch |
| Tab text | Visual estimate 13–14 pt, regular/medium; exact font/weight unavailable | Visual estimate 13–14 pt, active medium; exact font/weight unavailable | Exact system 13 pt, regular inactive / medium active |
| Leading icon | Recognizable site favicons; grid favorite icons | Site favicon on active tab, icon/color customization documented | Source normal favicon 16 pt in 18-pt slot; pins 22 pt; origin fetch with monogram fallback |
| Row padding | Compact inset icon then title; no exact token extraction | Active row inset from sidebar with rounded selection | 10-pt leading padding, 10-pt icon/text gap; close target 26×30 |
| Traffic lights | Initial AX x offsets 12/35/58, y16; 16-unit bounds | AX x offsets 17/40/63, y19; 16-unit bounds | AX x offsets 8/31/54, y8; 16-unit bounds |
| Window chrome | No separate visible title text; traffic lights in sidebar band | Same; browser navigation starts in page frame | `.hiddenTitleBar`, fullSizeContentView, transparent titlebar; background dragging explicitly disabled |
| Selected tab | Light/translucent selection; selected favorite outline visible | Dark inset selected row with diffuse halo in captured inactive dark window | Light elevated row, 8-pt radius; close visible when hovered or selected |
| Hover | Not exercised; do not infer timing from still image | Not exercised; do not infer timing from still image | Source `.onHover`, 5% black/6% white wash; no observed animation timing |
| Space color | Subtle dark indigo-to-purple chrome in this setup | Dark neutral/purple vertical chrome; webpage's decorative gradient is NOT browser chrome | Flat tinted sidebar background, not a rendered gradient; theme defines gradient but RootView uses sidebarBg |
| Icons | Monochrome outline shell icons + colorful site glyphs | Monochrome outline icons + purple chat bubble + site glyphs | SF Symbols with 12-pt medium toolbar icons, 26×26 targets; app surface tiles use 17-pt medium icons |
| Command bar | Not captured or measured | Not captured or measured | Source max 600 wide, radius16, 19-pt input, 13/11 title/detail, eight results |
| Ask panel | Max settings not captured | Chat panel not captured | Source width min(350, window width×0.36), 8-point gap, radius12; not runtime measured |

The inactive-window captures soften controls and text. Do not measure contrast accessibility from inactive chrome alone. Neither exact proprietary font family nor spring constants can be established from screenshots.

**Arc visual language:** a quiet, personalized container around the web, with a compact horizontal navigation band and a strong three-level sidebar grammar: favorite tiles, durable pinned work, disposable Today tabs. Small dividers and indentation do organizational work. The page is the dominant luminous plane inside colored chrome. The footer is navigation infrastructure, not a second dashboard.

**Dia visual language:** less Arc-specific structure upfront, with a pinned tray, collapsible groups and either vertical or horizontal tabs; Chat is prominent in the upper-right page toolbar. The observed dark sidebar is restrained. Documented newer polish includes larger, clearer sidebar labels, updated tab-switcher colors/shadows, site-color-responsive top band, sidebar rubber-banding, drag haptics, and a subtle new-tab profile-color shimmer.[61][148][149] These animations were NOT observed live. The shimmer is separately documented in 1.15.0.[43]

**Graphene visual language:** light blue-gray chrome, inset near-white page, small SF Symbol controls, conspicuous top tiles for Threads/Vault/Mail, and a second Ask launcher at the bottom. The hierarchy is readable but the native app tiles consume premium tab space. The flat tint is not the multi-stop gradient promised by an unused theme helper. The live window has tighter traffic-light offsets than the competitors. Mail also uses serif headings while Threads/Vault use system sans, creating a source-level consistency question that requires populated captures.

### Specific shell changes to implement

- Introduce shared layout tokens rather than scattering 8/9/10/11/12/13/14/16 radii. Keep page radius12, row radius8, popover radius12, command panel radius16, toolbar36, row pitch40 as the starting system. These are Graphene design decisions, not claims of Arc's exact tokens.
- Add a real resize divider: default sidebar224, user range200–320, collapse threshold176, keyboard resize accessibility actions. Extend the current hard cap260 deliberately. Remember width per window and preserve page scroll positions while resizing.
- Preserve 13-pt tab labels and medium active weight. Use single-line truncation with full-title tooltip and independently accessible title, audio state, and close action. Do not let the close glyph shrink the title only on hover.
- Reduce top surface-tile visual weight: optional compact 32–36-point-high labeled launcher row, same Cmd+1–4 destinations. Do not hide the native features in a settings menu. Preserve a comfortable hit target even if visible glyphs shrink.
- Give favorites and pinned work distinct sections. Favorites use compact icon tiles with tooltip; pins remain titled rows/folders with base-URL reset. A generic Boolean tile should not impersonate both semantics.
- Add a subtle per-space gradient behind the sidebar only, with contrast-safe neutral overlays. Do not tint webpage pixels or invert them when switching Graphene appearance. Add automatic system appearance and Reduce Transparency fallback.
- Standardize traffic-light reserved area and drag regions. Target an approximately 16-point top/leading inset after testing AppKit hit regions, not manual button reparenting without fullscreen tests. Current window background cannot drag; expose a tested draggable blank toolbar region that never intercepts tabs or text input.
- Add hover/pressed/focus/selected/disabled states to all actionable rows and surface launchers. Current selected tab needs the selected accessibility trait; custom gesture rows need keyboard selection and reorder. Keep focus ring visible against tinted backgrounds.
- Use native tracked drag/drop with insertion indicators, auto-scroll, folder hover-expand, cross-space destinations, keyboard equivalents, and cancel/undo. Replace distance/40 index math before adding folders or variable-height rows.
- Maintain the existing Reduced Motion branches. Initial target durations: current sidebar180ms, Ask200ms, palette120ms. Test real observed smoothness and interruption; do not cite these as measured Arc/Dia durations.
- Upgrade favicon discovery to page-declared icons and same-origin safe fallback, with redirect policy, size limits, bounded cache, retries and invalidation. Do not introduce a third-party history-leaking favicon service. Dia's published cache cap is evidence that a favicon cache can become a startup problem, not a benchmark for Graphene.[145]
- Improve command results with explicit sections (Tabs, Sources, Commands), actionable verbs, shortcut hints, full URL on focus, and stable result selection. Keep no-network local lookup as a fast first response. Do not send every keystroke or local source title to a search provider.
- A 940-point window with sidebar+Ask can leave the actual page uncomfortably narrow. Set an explicit minimum web-pane width (proposed 480), collapse an optional pane or allow overlay Ask instead of silently squeezing it. Preserve draft, scope and citation context across that transition.
- Align Threads/Vault/Mail empty, loading, error, offline and permission states with the same shell components. A disconnected Mail screen must remain useful and clearly read-only. Ask's unavailable model state must not disable source search.

### Settings surfaces and exact remaining capture checklist

These are documented routes, not screenshots of the installed settings hierarchy.

| App | Documented/current source surface | Content to inventory without changing values |
|---|---|---|
| Arc | General; native Settings | Account/sync controls, startup/browser options and Little Arc archive settings; exact page grouping may differ [4][13] |
| Arc | Profiles | Profile data, archive cadence, default search/new documents; some advanced settings live at `arc://settings` [16][150][153] |
| Arc | Links | Peek toggle, Little Arc behavior, Air Traffic Control route panel [11][24] |
| Arc | Shortcuts | All action rows, current/default bindings and website preference behavior [1][37] |
| Arc | Max | Six remaining documented features, per-feature opt-in and privacy information; no Ask On Page [3][4] |
| Arc | Site Control Center | Permissions, extensions/pins, PiP, Developer Mode, Boosts; advanced Chromium settings [14][17][21] |
| Dia | Tabs | Sidebar/topbar, group behavior, meeting grouping, Tab Cleanup [46][114] |
| Dia | Profiles | Profile default, identity, data separation and color [46][51] |
| Dia | Personalization / Memory | Instructions, per-profile memory, exclusions, per-chat override; source terminology evolves [51][52] |
| Dia | Privacy / security | Ad/tracker blocking, content-data sharing controls and AI privacy [7][39] |
| Dia | Shortcuts | Full installed binding list; customized shortcuts reflected in context menus [113] |
| Dia | Sync / Account | Sources differ: 1.26 names Settings > Sync, 1.29 names Settings > Account. Record actual installed route without enabling it [127][149] |
| Dia | Apps | Connected tools and New Chat rollout toggle; never enable during reference capture [120][121] |
| Dia | Usage / Billing | Plan/usage controls documented; do not capture payment/account details. Record headings only [108] |
| Graphene | Gear/sliders menu | Light/dark, Space color, Search engine, Open Vault in Finder; no native Settings scene [G1][G2] |

For a completed local audit, each app needs an owned public-data window, saved window/selection/layout state, and a confirmed input-approval path. Capture every settings page by its actual heading (`arc-settings-general.png`, etc.), not by assuming this inventory is exhaustive. Capture tab menu, command bar, empty AI panel, split created only from owned test tabs, profile/space selector. Do not populate AI context with existing tabs, grant permissions, update apps, change account settings, or invoke destructive shortcuts to test them.

## Keyboard shortcuts: side-by-side reference and Graphene mapping

**Completeness boundary:** the first table contains every macOS row in Arc's published common-shortcuts table, plus separately documented features. Dia's own release notes say its full list is in Settings > Shortcuts; that page could not be opened. Thus this is a complete transcription of Arc's public common list and a best-evidenced Dia comparison, NOT a fabricated complete installed Dia shortcut table.[1][113] Unknown bindings are explicit. macOS text-editing and website shortcuts are context-dependent and must be checked separately.

Notation: ⌘ Command, ⌥ Option, ⌃ Control, ⇧ Shift. **C** means conventional macOS/browser binding proposed for verification, not a Dia-specific verified binding. **Menu only** means intentionally no new default keyboard shortcut. **Keep** means preserve README's mapping.

| Action | Arc macOS | Dia macOS | Recommended Graphene mapping |
|---|---|---|---|
| New tab / palette | ⌘T [1] | ⌘T [113] | Keep ⌘T |
| New window | ⌘N [1] | ⌘N (C) | ⌘N, only after independent window ownership |
| New incognito window | ⇧⌘N [1] | ⇧⌘N (C); incognito documented [145] | ⇧⌘N after true private mode |
| Close current tab/window | ⌘W [1] | ⌘W (C) | Keep ⌘W, make pin semantics explicit |
| Open Little Arc | ⌥⌘N [1][13] | Unknown/not established equivalent | Menu only initially |
| Reopen closed tab | ⇧⌘T [1] | ⇧⌘T (C) | Keep ⇧⌘T, persist restore stack |
| Pin/unpin tab | ⌘D [1] | Unknown; do not assume ⌘D pin versus bookmark | ⌃⌘P proposed, user-remappable; ⌘D remains Vault; avoid macOS Dock toggle ⌥⌘D |
| Copy current URL | ⇧⌘C [1] | ⇧⌘C [113] | ⇧⌘C |
| Copy URL as Markdown | ⌥⇧⌘C [1] | Unknown | ⌥⇧⌘C |
| Edit current location | ⌘L [1] | ⌘L (C) | Keep ⌘L |
| Show/hide sidebar/tab strip | ⌘S [1] | ⌘S [113] | Keep ⌘S; never reassign to Save Page |
| Clear unpinned / close all | ⇧⌘K clears unpinned [1] | ⇧⌘K described as close all [113]; pin exclusion unverified | Menu-only “Archive unpinned tabs” + undo, no destructive default |
| Select tab by number | ⌘1, ⌘2, ⌘3… [1] | Unknown exact range/order; ⌘number is conventional, not verified | ⌥⌘1–9 if enabled; preserve ⌘1–4 surfaces |
| Select Space/Profile by number | ⌃1, ⌃2, ⌃3… for Spaces [1] | ⌃1, ⌃2, ⌃3… for profiles [119] | Menu/palette initially; OS Mission Control can own ⌃number |
| Recent-tab switcher | ⌃Tab [1] | ⌃Tab / ⇧⌃Tab [113][148] | ⌃Tab / ⇧⌃Tab for MRU, distinct from sequential tabs |
| Sequential tabs | ⌥⌘↑ / ⌥⌘↓ [1] | Exact sequential/MRU distinction not fully verified | Keep ⇧⌘[ / ⇧⌘] |
| Previous/next Space | ⌥⌘← / ⌥⌘→ [1] | Unknown | ⌥⌘← / ⌥⌘→; make remappable for website collisions |
| Forward | ⌘→ or ⌘] [1] | ⌘] (C) | Keep ⌘]; leave text-editing ⌘→ to focused field |
| Back | ⌘← or ⌘[ [1] | ⌘[ (C) | Keep ⌘[; leave text-editing ⌘← to focused field |
| Add Split View | ⌃⇧+ in common table [1]; split article says ⌘⇧+ [10], conflict unresolved locally | Option-click + button documented [54]; keyboard binding unknown | Menu/palette Add Right Split first, no conflicting + shortcut |
| Close Split View | ⌃⇧− [1] | Unknown | Menu-only Separate All / Close Pane |
| Focus split N | ⌃⇧1, ⌃⇧2… [1] | Unknown | ⌃⇧1–3 after OS/keyboard testing |
| History | ⌘Y [1] | ⌘Y (C) | ⌘Y opens browser History, not Threads |
| Zoom in | ⌘+ [1] | ⌘+ (C) | ⌘+ and ⌘= aliases |
| Zoom out | ⌘− [1] | ⌘− (C) | ⌘− |
| Reset page zoom | ⌘0 [1] | ⌘0 (C) | ⌘0 |
| Reload | ⌘R [1] | ⌘R (C) | Keep ⌘R |
| Find in page | ⌘F [1] | ⌘F [116] | Keep ⌘F |
| Settings | ⌘, [3] | ⌘, (C) | ⌘, opens real Settings scene |
| Cycle/open extensions | ⌘E [155] | Unknown | Menu only; no claim of Chrome extension support |
| Open/focus AI Chat | Current Arc equivalent absent; ⌘E is extensions [4][155] | ⌘E [157] | Keep ⌘K; optional user alias ⌘E, not default |
| New AI conversation | No current equivalent | ⇧⌘E reported elsewhere, not verified in first-party inventory | Menu/button only until persistent conversations exist |
| Global tab search | Current exact binding beyond command bar unverified | ⇧⌘A [44] | ⇧⌘A for all tabs within profile, explicit Space labels |
| Toggle topbar/sidebar | Not an equivalent mode switch | ⇧⌘S [113] | Menu only; vertical stays default |
| New tab inside group | No same documented binding | ⌥⌘T [46][124] | ⌥⌘T after group model exists |
| Reset pinned destination | Click icon or “Reset Tab” [26] | ⌘Return [61] | Menu-only Reset Pinned Tab to avoid editor submission collisions |
| Open link in right split | Not specified in cited Arc page | ⇧⌥click [51] | ⇧⌥click after split routing exists |
| Open new-tab split | Drag / command actions [10] | ⌥click + button [54] | Same modifier action on +; accessible menu equivalent |
| Promote Peek/Little Arc to main | ⌘O [11][13] | No equivalent established | Context-specific ⌘O only if transient preview added |
| Promote Little Arc to chosen Space | ⌥⌘O [13] | No equivalent established | Menu-only Choose Space |
| Open current tab in Little Arc | ⌥⌘click tab [13] | No equivalent established | No default initially |
| Duplicate a tab | ⌥drag tab [26] | Context menu; exact shortcut unknown | Context-menu Duplicate; optional ⌥drag |
| New Easel | ⌃⇧E [19] | No equivalent established | No mapping, preserve Threads/Vault instead |
| Full page capture | ⌘T → “Capture Full Page” [19] | Unknown | Palette “Capture Full Page” if implemented |
| Capture selection to Easel | ⌘T → “Capture” [19] | Unknown | Palette “Capture Selection”, not ⌘D replacement |
| System screenshot selection | ⇧⌘4 (macOS) [19] | System shortcut, not Dia-specific | Leave to macOS |
| AI link summary | ⇧hover, sometimes hover alone [3] | Unknown equivalent | No default initially |
| Instant Links | ⇧Return after palette search [3] | Not same as AI chat routing | No default network-opening action |
| Ask ChatGPT | ⌥⌘G [3] | Native Chat uses ⌘E [157] | No mapping; on-device Ask remains ⌘K |
| Site Search | Keyword, Tab, query, Return [156] | Extension search shortcuts supported; exact trigger inventory unknown [44] | Same sequence with explicit engine chip |
| Skill invocation | No Dia-style equivalent | /skill or skill name + Return [55] | Slash command inside Ask composer only |
| Attach context | No equivalent current chat | @tab, @history; @group [44][51] | @ picker inside Ask composer only |
| Command-bar Chat/Search routing | No exact equivalent | Published modifier glyphs ⌃⌘ / ⇧⌘ lack terminal key in prose [119] | Do not invent missing Return/T binding; explicit selectable actions |
| Developer tools | Developer Mode commands; exact binding not confirmed [17] | F12 documented [43] | Menu-only Web Inspector, enable safely per build/site |
| Stop loading / dismiss transient UI | Escape behavior depends on focused website; release notes discuss preference [37] | X load-stop documented [55]; Escape mapping not verified | Escape: palette → preview → find; page receives it otherwise |
| Find next / previous | Not in published common table | Unknown (⌘G / ⇧⌘G conventional) | ⌘G / ⇧⌘G only with find context |
| Print page | Exact binding not checked | Print support documented; ⌘P conventional [44] | ⌘P |
| Save webpage to file | Exact binding not checked; ⌘S already sidebar | Exact binding not checked; ⌘S already tabs | Menu-only Save Page As, not ⌘S |
| Downloads list | Exact binding not checked | Exact binding not checked | Menu/palette “Downloads” |
| Reading mode | Removed [4] | Unknown | Menu-only if implemented |
| Web / Threads / Mail / Vault | No equivalent native surfaces | No equivalent native surfaces | Keep ⌘1 / ⌘2 / ⌘3 / ⌘4 |
| Save page/selection to Vault | Arc ⌘D pins [1] | Not equivalent to local Vault | Keep ⌘D |
| Light/dark | Exact binding not checked | Exact binding not checked | Keep ⇧⌘L |
| Undo / redo | Native/web context, not app inventory verified | Native/web context, not app inventory verified | Preserve ⌘Z / ⇧⌘Z for first responder; tab actions only when applicable |
| Cut/copy/paste/select all | Native/web context | Native/web context | Preserve ⌘X/⌘C/⌘V/⌘A; never global-intercept |
| Quit / hide / minimize / fullscreen | Standard macOS context; installed bindings not audited | Same | Preserve standard OS behavior; actual Cmd+Q execution blocked in audit |

The Add Split View discrepancy is a real first-party documentation conflict, not permission to silently choose one as Arc's verified default. Likewise, a third-party cheat sheet found in search called Dia ⇧⌘A “AI sidebar” and ⇧⌘S “Summarize”; both conflict with first-party release notes and are excluded.[44][113]

Shortcut acceptance: enumerate all menu and Settings bindings in the installed apps, including unassigned actions and modifier aliases; compare against this table, record user customizations separately, and test US/non-US layouts, focused web text fields, native note editors, palette, Ask, and fullscreen. Keep README's existing bindings unchanged. Custom shortcut settings must show conflict ownership (macOS, Graphene, website) and reset-to-default.

## Graphene-native features to preserve

### Threads: provenance, not just tab organization

Keep the recorded visit graph, originating-page edges, branching/revisits, space scoping, captured text and Markdown export. A folder/group says “these tabs belong together”; a thread says “this is how I got here.” Preserve both concepts. Expose Threads in the compact sidebar launcher and ⌘2, a current-thread breadcrumb on the page, and a context-menu “Show in Thread.” A split or Peek promotion must retain the parent visit. Auto-archiving must remove live tabs, not knowledge. Show list first with a map toggle, searchable sources, resume browsing and Ask this thread. No graph deletion as a side effect of close/cleanup. [G2][G6]

### Vault: durable explicit saves

Keep Markdown files, selected text, source URL, note editor and explicit delete confirmation. ⌘D remains save-to-Vault, not pin. Surface a saved indicator on the page and a quick note composer without stealing the current tab. Vault should distinguish all-notes versus current-space filtering, because current Vault is global but Ask filters by graph URL membership. Introduce explicit note scope/provenance so Mail saves are retrievable without inventing a browsing visit. Reuse the same list/detail typography and empty/error state as Threads. Do not treat an Easel replacement as prerequisite to useful note-taking. [G5][G7][G9]

### Ask: grounded local companion

Keep on-device-by-default answers, model availability honesty, searchable sources independent of AI, and context that does not silently change when following a citation. Preserve ⌘K and the three scopes, then add explicit removable @tab/@thread/@note chips, persistent conversation records, and a visible context budget. The present implementation feeds four source prefixes and starts a fresh model session for each question; do not market that as full-tab memory or multi-turn reasoning. Validate cited source numbers before rendering clickable citations. New Skills should be user-visible templates with declared input scope, not hidden instructions that alter data access. A remote model is a separate opt-in product decision, not a prerequisite for shell quality. [G5]

### Mail: useful read-only integration, not an email-client detour

Keep ⌘3, read-only disclosure, Gmail web fallback and Save message to Vault. The shell should show a clear connected/disconnected/loading/error state and never imply send/archive/delete capabilities that do not exist. Unify serif-versus-sans heading treatment intentionally. Add explicit source type and account scope to saved messages so Ask can cite them without cross-profile leakage. Do not connect Gmail or view personal messages merely to obtain screenshots. New connected-tool automation remains P2 and requires separate permissions, previews and execution evidence. [G9]

## Proposed implementation order

These are future work packages. **No source or test changes were made for this specification.** Paths labeled “new” are proposed files, not existing symbols. Other paths below exist in the inspected tree. Names under `Sources/Graphene/` are relative to that directory. Test paths are proposed future work only.

### WP1 — Privacy, persistence and window ownership (P0)

Likely files: `App/AppState.swift`, `App/GrapheneApp.swift`, `Model/Tab.swift`, `Model/KnowledgeGraph.swift`, `Store/Paths.swift`, `Store/Vault.swift`, `Web/WKWebEngine.swift`; new `Model/BrowserProfile.swift`, `Store/SessionStore.swift`, `Store/CapturePolicy.swift`.

Separate persisted profile/space/tab identities from per-window focus/surface/pane state. Add capture-policy allow/deny/pause and forget-site workflows before expanding AI. User private windows must write neither cookies nor graph/text/history/chat records. Session schema versions, atomic migrations and backups must preserve existing graph and notes. Restore metadata immediately, lazily restore webviews; never record restoration as a new navigation. Handle corrupt storage visibly and preserve originals.

Acceptance: two profiles keep cookies and captured knowledge separate; private browsing leaves no persisted content; two windows cannot attach one WKWebView simultaneously; restart retains open and closed-tab state and pinned base URLs; no migration loses notes. Test regular, isolated-development and private modes independently.

### WP2 — Cohesive shell and complete command system (P0)

Likely files: `UI/RootView.swift`, `UI/Theme.swift`, `UI/WindowAccessor.swift`, `UI/CommandBar.swift`, `UI/Favicon.swift`, `Model/Omnibox.swift`, `App/GrapheneApp.swift`; new `Model/BrowserCommand.swift`, `UI/SettingsView.swift`.

Centralize geometry/style tokens; add resize divider and safe drag regions; preserve surface launchers and existing shortcuts. Introduce stable command IDs used by palette, menus and settings. Add history/site search/tab search sections, location identity and conflict-aware shortcut settings. Implement native Settings with General, Tabs/Spaces, Profiles, Privacy, Search, Ask, Mail and Shortcuts; no decorative dead toggles.

Acceptance: all README shortcuts still work from webpage, text field, Ask and note editor; Escape restores prior focus without clearing drafts; keyboard-only traversal has visible focus; minimum-size window remains usable; light/dark/automatic, Reduced Motion/Transparency, inactive and fullscreen states have reference captures.

### WP3 — Complete browser basics and site trust controls (P0)

Likely files: `Web/WebEngine.swift`, `Web/WKWebEngine.swift`, `Web/WebContainer.swift`, `Web/BrowserDownload.swift`, `Model/Tab.swift`, `UI/RootView.swift`; new `UI/SiteControlsView.swift`, `UI/DownloadsView.swift`, `Store/DownloadStore.swift`.

Add explicit per-site permission management and secure-origin display, page zoom, print, load/renderer-failure recovery, progress/cancel/retry/download history, and safe external scheme handling. Evaluate passkey/autofill and WKWebView compatibility with actual supported APIs rather than promising Chromium compatibility. Introduce supported WebKit content rules for blocking with per-site exceptions. Preserve upload panels and JavaScript dialogs with origin labeling.

Acceptance: redirect/OAuth fixture, SPA navigation, popups, upload, PDF download, canceled download, failed/resumed download, certificate failure, camera/microphone denial, local development origin, back/forward state and renderer termination cases produce clear UI and no extra thread visits. Unsupported embedded sign-in gets an explicit open-in-system-browser escape hatch.

### WP4 — Durable tabs, Spaces and migration (P0 → P1)

Depends on WP1/2. Likely files: `App/AppState.swift`, `Model/Tab.swift`, `UI/RootView.swift`, `UI/CommandBar.swift`; new `Model/TabCollection.swift`, `Store/TabArchive.swift`, `Store/BrowserImport.swift`, `UI/ImportView.swift`.

Add space CRUD/reorder, labeled pins with base destinations, distinct favorite tiles, groups/folders, multi-select, duplicate, move-to and keyboard reorder. Persist close/archive metadata and offer opt-in cleanup with exclusions for pins, audio, downloads, forms and recently active tabs. Start import with browser bookmark HTML and supported exported metadata, preview destinations/duplicates, and report unsupported data. Do not silently import passwords or promise Chrome extension import into WebKit.

Acceptance: pin navigation/reset and unpin are separate actions; 100-tab sidebar stays navigable; cancel drag restores original order; archive/undo/restart preserves thread links; imports are idempotent and do not silently collapse spaces or delete originals. Ctrl+Tab uses MRU while existing sequential shortcuts remain sequential.

### WP5 — Split browsing, Peek and routing (P1)

Depends on window ownership and tab collections. Likely files: `UI/RootView.swift`, `App/AppState.swift`, `Web/WebContainer.swift`, `Web/WKWebEngine.swift`, `Model/Tab.swift`; new `Model/PaneLayout.swift`, `UI/SplitBrowserView.swift`, `UI/PeekView.swift`, `Model/LinkRouter.swift`.

Implement two-pane side-by-side first, then vertical/three-pane only if minimum widths allow. Persist pane identity/ratio and focused pane independently from visible tab collection. Add drag-to-split, replace pane, separate, close one pane, focus keys and Ask-on-focused-pane. Peek must be dismissible without disturbing parent page state, and promotion must preserve provenance. Add inspectable external-link destination rules with test mode. Little Arc-like standalone windows can remain later P2.

Acceptance: navigation/find/reload/zoom/Ask apply to the focused pane; closing one pane never closes another user's tab; sources retain parent edges; restore keeps layout without duplicate visits; Escape dismisses only the highest-priority transient UI. Routing rules expose exact/host/contains semantics and never silently mix profiles.

### WP6 — Grounded persistent Ask and writing workflows (P1)

Likely files: `Intelligence/KnowledgeAssistant.swift`, `UI/KnowledgeSearchView.swift`, `Model/KnowledgeGraph.swift`, `Store/Vault.swift`, `Web/WKWebEngine.swift`; new `Intelligence/ConversationStore.swift`, `Intelligence/SkillStore.swift`, `UI/ContextPicker.swift`.

Persist conversations/scopes; add explicit @ context chips and reusable Skills with inspectable input/output policies. Make retrieval include intentionally scoped Vault/Mail sources, rank excerpts around query matches, expose truncation and model budget, validate numeric citations, and retain lexical mode when AI unavailable. Writing assistance must offer a draft preview and explicit replace/insert, with undo and correct input/change events. Do not silently modify arbitrary rich editors or send page content remotely.

Acceptance: following source links cannot change the answer's evidence; missing/unreadable tabs are named; canceled generation cannot overwrite a newer answer; private/excluded/profile-other sources are impossible to attach by accident; prompt-injection fixtures do not alter scope or trigger side effects. Clearly distinguish reply history from preference memory. Remote connectors/model choice need separate architecture approval.

### WP7 — Media and everyday recovery polish (P1)

Likely files: `Web/WebEngine.swift`, `Web/WKWebEngine.swift`, `Model/Tab.swift`, `UI/RootView.swift`, `Web/BrowserDownload.swift`; new `UI/MediaControlsView.swift`, `Web/MediaSessionController.swift`.

Expose playing/muted state, tab mute and compact media controls; evaluate supported PiP APIs, per-site behavior and return-to-tab ownership. Prevent unload of playing, recording, downloading or form-dirty tabs. Preserve system media key behavior. Add bounded favicon caching and background restoration/discard policies with observable diagnostics.

Acceptance: audio never unexpectedly duplicates during window/split transitions; tab mute status is accessible; PiP survives ordinary navigation where supported and returns to correct window; unsupported meeting PiP is disclosed, not simulated. Measure memory, startup, warm tab switch and resize traces using repeatable public fixtures, not a subjective “feels fast.”

### WP8 — Native knowledge surfaces, release quality and optional expansion (P0 release gate / P2 expansion)

Likely files: `UI/LedgerView.swift`, `UI/VaultView.swift`, `UI/MailView.swift`, `Mail/MailStore.swift`, `Model/KnowledgeGraph.swift`, `Store/Vault.swift`, `UI/Theme.swift`; existing `scripts/build-app.sh` for later packaging work; proposed test files under `Tests/`.

Unify list/detail states and searchable provenance across Threads/Vault/Mail. Add current-thread/source breadcrumbs without cluttering the page. Keep Mail explicitly read-only. Finish accessibility, migration and UI regression coverage, then sign/notarize/update distribution before marketing a daily-driver browser. Optional subsequent projects: end-to-end-encrypted sync, live groups/calendar, local daily digest, safe per-site CSS customization, screenshots and visual collections. Chrome extensions and cloud-connected autonomous work are not small polish tasks and require separate decisions.

Acceptance: meaningful populated and empty screenshots for every native surface; keyboard-only read/save/reopen/export workflows; export references real sources; missing model/network/account states remain usable; protected fixtures prove profile isolation and no source-loss regressions. Capture same-size light/dark Arc/Dia/Graphene reference windows only after input approvals are available.

## Verification and outstanding acceptance items

The accompanying `verification.json` records hash comparison of every file under Sources/ and Tests/ against the pre-write baseline, PNG decoding, output counts, and markdown/table checks. This audit did not run the product test suite or rebuild Graphene because it made no product changes; runtime behavior beyond resting-window launch is not certified.

Outstanding: all interactive screenshots in the capture table, full installed shortcut inventories, live hover/animation/drag observations, populated Graphene native-surface captures, and quitting the owned Graphene process. Unknown competitor capabilities must not become “absent” simply because they were not found in public docs. This document is ready to guide architecture and prioritization, but not a completed pixel-parity sign-off.

## Sources

[1] https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts — Keyboard Shortcuts – Arc Help Center
[3] https://resources.arc.net/hc/en-us/articles/19335160678679-Arc-Max-Boost-Your-Browsing-with-AI — Arc Max: Boost Your Browsing with AI – Arc Help Center
[4] https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes — Arc for macOS - 2024 - 2026 Release Notes – Arc Help Center
[7] https://www.diabrowser.com/security — Dia Browser | Security
[10] https://resources.arc.net/hc/en-us/articles/19335393146775-Split-View-View-Multiple-Tabs-at-Once — Split View: View Multiple Tabs at Once – Arc Help Center
[11] https://resources.arc.net/hc/en-us/articles/19335302900887-Peek-Preview-Sites-From-Pinned-Tabs — Peek: Preview Sites From Pinned Tabs – Arc Help Center
[12] https://resources.arc.net/hc/en-us/articles/19335284431639-Previews-Glance-Top-Sites — Previews: Glance Top Sites – Arc Help Center
[13] https://resources.arc.net/hc/en-us/articles/19235387524503-Little-Arc-Quick-Lookups-Instant-Triaging — Little Arc: Quick Lookups & Instant Triaging – Arc Help Center
[14] https://resources.arc.net/hc/en-us/articles/19234766331799-Mini-Player-Watch-or-Listen-as-you-Browse — Mini Player: Watch or Listen as you Browse – Arc Help Center
[16] https://resources.arc.net/hc/en-us/articles/22557798824855-Customize-Default-Notes-App — Customize Default Notes App – Arc Help Center
[17] https://resources.arc.net/hc/en-us/articles/20468488031511-Developer-Mode-Instant-Dev-Tools — Developer Mode: Instant Dev Tools – Arc Help Center
[18] https://resources.arc.net/hc/en-us/articles/19233788518039-Phasing-Out-Arc-Notes — Phasing Out Arc Notes – Arc Help Center
[19] https://resources.arc.net/hc/en-us/articles/19231142050071-Easels-Capture-Create — Easels: Capture & Create – Arc Help Center
[20] https://resources.arc.net/hc/en-us/articles/19228534606743-Share-Spaces-Folders-Splits-with-Anyone — Share Spaces, Folders & Splits with Anyone – Arc Help Center
[21] https://resources.arc.net/hc/en-us/articles/19212718608151-Boosts-Customize-Any-Website — Boosts: Customize Any Website – Arc Help Center
[23] https://resources.arc.net/hc/en-us/articles/24158102740631-Live-Calendars — Live Calendars – Arc Help Center
[24] https://resources.arc.net/hc/en-us/articles/22932014625431-Air-Traffic-Control-Automate-Your-Link-Routing — Air Traffic Control: Automate Your Link Routing – Arc Help Center
[25] https://resources.arc.net/hc/en-us/articles/22731612065815-Automatic-GitHub-Live-Folders — Automatic GitHub Live Folders – Arc Help Center
[26] https://resources.arc.net/hc/en-us/articles/19231060187159-Pinned-Tabs-Tabs-you-want-to-stick-around — Pinned Tabs: Tabs you want to stick around – Arc Help Center
[27] https://resources.arc.net/hc/en-us/articles/19230755904151-Favorites-Top-Tabs-Across-Every-Space — Favorites: Top Tabs Across Every Space – Arc Help Center
[28] https://resources.arc.net/hc/en-us/articles/19230634389911-Library-A-home-for-your-downloads-archived-tabs-easels-and-more — Library: A home for your downloads, archived tabs, easels and more. – Arc Help Center
[31] https://resources.arc.net/hc/en-us/articles/25619402657303-How-Do-You-Switch-Between-Tabs-Quickly-on-Arc-Desktop — How Do You Switch Between Tabs Quickly on Arc Desktop? – Arc Help Center
[32] https://resources.arc.net/hc/en-us/articles/25614213458711-How-Do-You-Change-Your-Download-Location-in-Arc-for-Desktop — How Do You Change Your Download Location in Arc for Desktop? – Arc Help Center
[37] https://resources.arc.net/hc/en-us/articles/20498377604887-Arc-for-macOS-2023-Release-Notes — Arc for macOS - 2023 Release Notes – Arc Help Center
[39] https://diabrowser.com — Dia | A browser you won't dread opening
[43] https://diabrowser.com/changelog/1-15-0 — Dia Browser | Update 1.15.0
[44] https://diabrowser.com/changelog/1-14-0 — Dia Browser | Update 1.14.0
[46] https://diabrowser.com/changelog/1-16-0 — Dia Browser | Update 1.16.0
[47] https://diabrowser.com/changelog/1-10-1 — Dia Browser | Update 1.10.1
[49] https://diabrowser.com/changelog/1-8-0 — Dia Browser | Update 1.8.0
[50] https://diabrowser.com/changelog/0-43-0 — Dia Browser | Update 0.43.0
[51] https://diabrowser.com/changelog/0-44-0 — Dia Browser | Update 0.44.0
[52] https://diabrowser.com/changelog/0-45-0 — Dia Browser | Update 0.45.0
[53] https://diabrowser.com/changelog/0-46-0 — Dia Browser | Update 0.46.0
[54] https://diabrowser.com/changelog/0-47-0 — Dia Browser | Update 0.47.0
[55] https://diabrowser.com/changelog/0-48-0 — Dia Browser | Update 0.48.0
[60] https://diabrowser.com/changelog/1-3-1 — Dia Browser | Update 1.3.1
[61] https://diabrowser.com/changelog/1-4-0 — Dia Browser | Update 1.4.0
[62] https://diabrowser.com/changelog/1-5-0 — Dia Browser | Update 1.5.0
[64] https://diabrowser.com/changelog/1-13-1 — Dia Browser | Update 1.13.1
[108] https://diabrowser.com/plans — Dia Browser | Plans
[113] https://www.diabrowser.com/release-notes/1-21-0-before-you-reach-for-it
[114] https://www.diabrowser.com/release-notes/1-30-0-keeping-tabs-tidy
[116] https://www.diabrowser.com/release-notes/1-5-0-meet-me-in-dia
[119] https://www.diabrowser.com/release-notes/1-22-0-dont-think
[120] https://www.diabrowser.com/release-notes/granola
[121] https://www.diabrowser.com/release-notes/1-37-0-morning-brief
[122] https://www.diabrowser.com/release-notes/Tools
[123] https://www.diabrowser.com/release-notes/Notion
[124] https://www.diabrowser.com/release-notes/1-36-0-pip-stash
[127] https://www.diabrowser.com/release-notes/1-26-0-sync-is-here
[141] https://www.diabrowser.com/release-notes/1-16-0-organization-that-grows
[142] https://www.diabrowser.com/release-notes/1-9-0-tab-groups
[143] https://www.diabrowser.com/release-notes/1-31-0-pr-hover
[145] https://www.diabrowser.com/release-notes/1-18-1-your-setup-your-way
[146] https://www.diabrowser.com/release-notes/1-6-0-conversations-context-chat
[147] https://www.diabrowser.com/release-notes/1-17-0-github-live-tab-groups
[148] https://www.diabrowser.com/release-notes/1-28-0-look-closer
[149] https://www.diabrowser.com/release-notes/1-29-0-sync-unpinned-tabs
[150] https://resources.arc.net/hc/en-us/articles/19228855311127-Auto-Archive-Clean-as-you-go
[151] https://resources.arc.net/hc/en-us/articles/19228419623447-Folders-Stash-Similar-Tabs-Together
[152] https://resources.arc.net/hc/en-us/articles/19228064149143-Spaces-Distinct-Browsing-Areas
[153] https://resources.arc.net/hc/en-us/articles/19227964556183-Profiles-Separate-Work-Personal-Browsing
[154] https://resources.arc.net/hc/en-us/articles/19335089616791-Import-Bookmarks-Logins-History-Extensions-from-Your-Previous-Browser
[155] https://resources.arc.net/hc/en-us/articles/19434259167767-Extensions-in-Arc-How-to-Import-Add-Open
[156] https://resources.arc.net/hc/en-us/articles/20855018192791-Site-Search-Directly-Search-any-Website
[157] https://www.diabrowser.com/getting-started
