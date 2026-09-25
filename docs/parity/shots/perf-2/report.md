# Graphene 60-tab interactive performance — run 2

Measured 2026-09-25, approximately 11:10–11:18 EDT; cleanup later after computer-use timeouts. **Partial interactive audit: A and C completed, B approximated, D stopped after one switch, E and command-tab activation not measured.** This does not establish that the owner's full complaint is fixed or reproduced in full.

## Setup and limits

- Checkout `509844561d233d94d605e81e8fd7d15ca79d4536`, initially clean. Built exactly with `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh` (debug build; compiler reported 0.17 s). No source changes or commits.
- Copied `/tmp/graphene-perf` to the previously absent `/tmp/graphene-perf-run-2`. Source fixture retained. 60 tabs: 20 each in Research, Personal and build; 7 pinned and 2 favorites in each. Fixture also contains three empty spaces, so six space dots appear.
- Launched `.build/Graphene-verify.app/Contents/MacOS/Graphene` with `GRAPHENE_DATA_DIR=/tmp/graphene-perf-run-2`, from a shell kept alive with `wait`. Owned PID **67037**, parent **67036**; launch **11:10:52.769 EDT**. Window ID **13233** obtained with `swift scripts/window-id.swift -p 67037`. Default 1280×820-point window, captured at 2560×1640 pixels (2×).
- macOS 26.1 (25B78), ARM64. Main process is `com.graphene.browser`, version 0.3.0 (3). Many other applications were running; no unrelated process was stopped.
- All UI actions used computer-use. Shell performed build, profile copy, process observation, screenshots, evidence processing and owned-process cleanup. No debug driver, debug environment flag, app-internal UI script or delegation.
- Twelve distinct allowed Today/pinned rows in Research were selected. The already loaded Graphene Wikipedia tab was the twelfth; it unexpectedly reloaded on revisit. No page-area actions were used. Stack Overflow's transient challenge resolved without interaction.
- Screenshot timestamps bracket acquisition, not hardware input delivery. The computer-use click call includes AX lookup/activation overhead; **request-to-clear is not pure app response latency**. A screenshot showing the new toolbar provides a second, later reference point. All load figures are approximate, normally about ±0.5 s plus capture duration. They measure toolbar progress disappearance, not all network activity or site interactivity.
- Visits: 360 screenshots at nominal 0.5 s cadence; actual median 0.500 s, range 0.396–0.603 s. Maximum capture duration 0.603 s. Control-Tab: 180 screenshots at nominal 0.25 s; actual median 0.250 s, range 0.192–0.466 s. Space captures: median 0.250 s, range 0.194–0.712 s.

## A. Twelve tab visits

`start` below is Unix epoch milliseconds from the computer-use runtime. `call` is click API wall time. `spacing` is between request starts (tool overhead prevented the requested approximately 3 s cadence). `clear` is request start to first conservatively clear toolbar frame; the preceding frame gives its lower bound. `visible remainder` is first new-URL screenshot to clear screenshot, excluding pre-display delay. Source frames and timestamps are in [visits/](visits/) and [timings.json](timings.json). Toolbar contact sheets are `visit-01-toolbar.png` through `visit-12-toolbar.png`; the extended GitHub strip is [here](visits-1790349157-contact.png).

| # | Tab | start (epoch ms) | call s | spacing s | Clear interval s | visible remainder s | first / clear frame |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | github.com/swiftlang/swift | 1790349157765 | 5.498 | — | (6.162, 6.662] | 1.001 | 43 / 45 |
| 2 | developer.apple.com | 1790349175374 | 0.642 | 17.609 | (1.553, 2.053] | 1.503 | 68 / 71 |
| 3 | www.apple.com | 1790349182804 | 0.498 | 7.430 | (1.121, 1.623] | 1.003 | 83 / 85 |
| 4 | forums.swift.org | 1790349190168 | 0.464 | 7.364 | (1.258, 1.758] | 0.999 | 98 / 100 |
| 5 | en.wikipedia.org/wiki/Carbon | 1790349196590 | 0.577 | 6.422 | (0.833, 1.337] | 0.505 | 111 / 112 |
| 6 | stackoverflow.com | 1790349205718 | 2.382 | 9.128 | (4.206, 4.709] | 1.999 | 133 / 137 |
| 7 | go.dev | 1790349216246 | 0.554 | 10.528 | (0.677, 1.180] | 0.503 | 150 / 151 |
| 8 | nodejs.org | 1790349229528 | 0.484 | 13.282 | (0.399, 0.895] | 0.496 | 176 / 177 |
| 9 | www.python.org | 1790349236149 | 0.401 | 6.621 | (0.276, 0.777] | 0.501 | 189 / 190 |
| 10 | www.swift.org | 1790349243992 | 0.513 | 7.843 | (2.436, 2.936] | 2.503 | 205 / 210 |
| 11 | developer.mozilla.org | 1790349252736 | 0.469 | 8.744 | (0.689, 1.192] | 0.502 | 223 / 224 |
| 12 | en.wikipedia.org/wiki/Graphene (revisit) | 1790349259288 | 0.418 | 6.552 | (4.135, 4.640] | 4.000 | 236 / 244 |

The initial Stack Overflow toolbar was clear at +2.709 s, but a subsequent automatic navigation showed progress again; the table uses the later stable clear state at +4.709 s. The Wikipedia revisit's +4.640 s endpoint conservatively includes the final progress fade. It is **not** a warm-switch result despite having been loaded at launch.

GitHub's request took 5.498 s to return, with the old Wikipedia toolbar still visible at +5.162 s. GitHub appeared at +5.661 s and was clear at +6.662 s. The 5 s pre-display gap cannot be attributed to Graphene from these samples; computer-use/AX overhead is a confound. Other click calls were 0.401–0.642 s except Stack Overflow (2.382 s). There was no sample covering these two pre-display gaps.

## Baseline, after visits, and C. idle

The requested `top -l 1 -pid 67037 -stats pid,cpu,mem,threads` snapshots were recorded, but **every process in a first top sample showed 0.0% CPU**. Those values alone do not prove inactivity. Extra interval samples were captured for idle and system-load ranking.

| Stage | Main top CPU | Main memory | Threads | All WebContent count | Sum ps CPU | Sum RSS KiB | Sum RSS MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| Before launch | — | — | — | 5 | 0.0% | 115824 | 113.11 |
| Baseline, collection began at launch +30 s | 0.0% | 96M | 8 | 6 | 0.0% | 227824 | 222.48 |
| After 12 visits | 0.0% | 109M | 8 | 18 | 0.0% | 1083008 | 1057.62 |
| After untouched 60 s | 0.0% | 105M | 8 | 18 | 0.0% | 805904 | 787.02 |

WebContent totals include other apps: before launch, one macOS WebContent process and four simulator WebContent processes were already present. The count rose by 13 from prelaunch to after visits, but this is **not a per-tab ownership proof**. RSS and `top` physical memory use different accounting; do not add them as equivalent footprints.

Baseline command completed at launch timestamp +32.406 s. Idle interval began at epoch **1790349374.718703**, with a full 60 s without app input before `top`/`ps`. The entire collection through the 5 s sample ended at **1790349447.704648**. This was after visiting 12 tabs; exact simultaneous residency of those 12 pages was not inspected through app internals. The reload on revisit is a reason not to assume residency.

The extra `top -l 3 -s 1` idle readings were **0.0%, 0.0%, 0.0%**, memory **105M**, 8 threads. The requested >2% idle bug **was not reproduced**. Sample main-thread wait: **4,316/4,319 observations (99.93%)** at `mach_msg2_trap`; one sampled `AppState.pollMediaAndDiscard()` / `AppState.lruVictims(limit:)` path. Post-visit sample: **4,378/4,378** main-thread observations waiting. Peak main-process footprint recorded by sample was **518.8M**, versus 379.4M during the repeated-key sample and about 105M later.

Raw evidence: [baseline top](top-baseline.txt), [after-visits top](top-after-visits.txt), [idle top](top-idle.txt), [idle interval top](top-idle-interval.txt), and the corresponding `ps-*.txt` files.

## B. Control-Tab and adjacent-tab keys

The public computer-use API provides `pressKey(chord)`, with no documented independent modifier-down/up calls. Consequently the exact **hold Control → Tab three times → release** experiment was not possible with the required interaction mechanism. No workaround input injector was used. **Switcher appearance latency and release-to-third-target latency are N/A**, not zero.

| Trial | Raw wall timestamps / duration | Observed outcome |
|---|---|---|
| Eight separate Ctrl+Tab chords | epoch 1790349295492–1790349296638 ms; 1.146 s | Screenshots show Wikipedia → MDN → Wikipedia. First MDN frame +0.278 s from first request; previous frame +0.029 s still Wikipedia. No persistent switcher caught. |
| Forty separate Ctrl+Tab chords | epoch 1790349322148–1790349325853 ms; 3.705 s | Repeated visible Wikipedia/MDN toggles; ended on Wikipedia. First MDN screenshot +0.120 s. Cannot verify all 40 transitions at 4 fps. |
| Cmd+Option+Right/Left, alternating, ten total | epoch 1790349360919–1790349361304 ms; 0.385 s | Started and ended on Apple Developer, the expected net position. Per-key API times: 16, 4, 3, 3, 276, 22, 11, 5, 22, 23 ms. Individual delivered transitions/dropped presses unverified; equal left/right counts could mask drops. |

The Ctrl+Tab capture interval does not cover the later arrow-key burst. No per-arrow visual latency claim is made. The API's 276 ms call is an input-call outlier, not a proven app stall.

First attempt at `sample-ctrl-tab.txt` completed before the first input burst; it is retained honestly as [sample-ctrl-tab-pre-input.txt](sample-ctrl-tab-pre-input.txt). The replacement [sample-ctrl-tab.txt](sample-ctrl-tab.txt) began **11:15:17.913 EDT**, for requested 5 s. The second input burst began **11:15:22.148**, so only roughly the final **0.765 s** of the requested sample window overlapped input. It is a mixed resting/interactive sample, not five full seconds of keyboard stress.

Contact sheets: [first burst](ctrl-tab-1790349295-contact.png), [second burst](ctrl-tab-1790349322-contact.png). At 0.25 s cadence short-lived overlays and fast toggles can be missed. No dropped-key conclusion is justified.

## D. Space switching, E. sidebar scrolling, and activation

| Requested measurement | Result |
|---|---|
| Ten space changes with Ctrl+1/2/3 | Only Ctrl+2 attempted. Research → Personal is visible between screenshot epochs 1790349460.949 and 1790349461.203 (254 ms capture separation). Input timestamp was lost when the tool timed out; this is a visual transition bracket, not input-to-switch latency. |
| Sidebar animation | Captures show old content then new Personal content; no intermediate slide is resolved. Animation is unverified at 0.25 s cadence. Source has a slide/fade transition, which is not live proof. |
| Scroll over 20-tab list | Not performed: computer-use failed before this step. Neither “does not scroll” nor stutter was confirmed. AX selection of lower rows brought them into view during A, but that does not test two-finger scrolling. |
| Command-tab activation | Not measured before tool failure. No claim about activation speed. |

The Personal space automatically selected its existing BBC tab. No page-area interaction occurred there. The combined key/state computer-use call timed out after **120.058 s**, a follow-up state request timed out after **30.028 s** and reset the kernel, and reconnect for cleanup timed out after **120.296 s**. The literal URL-policy refusal from the earlier run was **not** returned this time; the failure was tool timeouts. Do not label these durations Graphene stalls. Screenshot [space-transition.png](space-transition.png) proves that the space change actually occurred despite the failed tool response. Per the task's stop-and-report fallback, the remaining measurements are marked missing rather than routed through another UI driver.

## F. System load

The exact requested `top -l 1 -o cpu -n 8` was captured once in A and once in B. Both snapshots reported all eight entries at 0.0%, so their order is not a usable load ranking: mlhostd (98353, 98248), Chrome helpers (97595, 97565, 97563, 97559), logd_helper (97288), SearchIndexer (97285). See [A raw](top-system-A.txt) and [B raw](top-system-B.txt).

Additional second interval samples provide a meaningful ranking:

| Rank | A process | CPU | B process | CPU |
|---:|---|---:|---|---:|
| 1 | WindowServer | 83.4% | WindowServer | 82.3% |
| 2 | kernel_task | 61.3% | PerfPowerService | 70.6% |
| 3 | node | 40.9% | kernel_task | 54.1% |
| 4 | PerfPowerService | 36.4% | Hermes Helper (renderer) | 35.0% |
| 5 | Hermes Helper (renderer) | 31.1% | systemstatusd | 26.7% |
| 6 | mediaanalysisd | 26.0% | Hermes Helper | 23.6% |
| 7 | Hermes Helper | 17.8% | ControlCenter | 15.0% |
| 8 | Grok Bot Helper | 16.9% | node | 13.7% |

Graphene and WebContent were absent from both interval top-eight lists. A was captured during the visit pass, between initial tab actions. B was captured during preparation for the first key burst, **not verified concurrent with delivered keys**. This is a limitation of cross-tool start timing. Screenshot capture itself contributes compositor work; WindowServer CPU cannot be attributed solely to Graphene.

Whole-system physical memory was **45G used / 2053M unused** at baseline, and **47G used / 147M unused** after visits, with **15G compressed** and **16G wired**. After-visits load average was **15.00 / 11.39 / 9.95**, CPU **55.0% idle**. The environment was already heavily loaded at baseline (load **11.17 / 9.73 / 9.21**). These are substantial confounders for “slowing the entire computer”; no before/after attribution to this app is established.

## What is slow and why, ordered by measured cost

1. **Page loading/reloading is the largest observed app-visible wait.** The previously loaded Wikipedia page required roughly **3.5–4.0 s after its target toolbar appeared** to clear the progress bar; Swift roughly **2.5 s**, Stack Overflow roughly **2 s** after first showing its target URL (with an automatic challenge/navigation). Most other visible-target-to-clear intervals were **0.5–1.5 s**. These are end-to-end WKWebView/navigation waits, not a CPU profile of server/network work. Exact network versus WebContent versus app cost is unresolved.
2. **Input/observation tooling introduces large pre-display delays.** GitHub had about **5.2–5.7 s** before its toolbar replaced Wikipedia; Stack Overflow about **2.2–2.7 s**. These align with long AX click calls, and are not covered by a simultaneous process sample. They cannot be called Graphene main-thread stalls. The later 120 s tool timeouts are also not app timings.
3. **System/compositor contention is real but not attributable to Graphene.** WindowServer led interval CPU readings (~82–83%) while the machine had very little unused RAM and many active apps. Screenshot overhead contributes. Graphene's measured main-process footprint was modest after settling, although peak was 518.8M and WebContent aggregate RSS grew by about 944.5 MiB over prelaunch before settling to 787.0 MiB total.
4. **Repeated switching does cause SwiftUI work, but this run does not show a dominant expensive Graphene symbol.** In the mixed Ctrl+Tab sample, **3,758/4,274 main-thread observations (87.93%)** end in `mach_msg2_trap`. Run-loop observer branches account for 492 inclusive observations (~11.5%); `SidebarTab.body`, `Sidebar.body`, layout and `Favicon.body` appear. Inclusive symbols overlap and cannot be added as separate costs. The sample's brief overlap with input limits interpretation.
5. **Sustained main-process idle CPU is not reproduced.** Interval readings are 0.0%; 99.93% of idle main-thread samples are in a kernel wait. No evidence here supports blaming idle thumbnail snapshots, KnowledgeGraph or citation work.

A plausible explanation for reload-on-return is tab discard under memory pressure: current `TabLifecycle.swift` caps background tabs, halves the cap on warning, discards them on critical pressure, and delays thumbnails 800 ms. This is **source-based inference only**: no memory-pressure event log was collected. `ThumbnailCache`, `takeSnapshot`, `KnowledgeGraph`, `WKWebEngine` and `cite` did not occur in the captured main-thread sample paths. `Favicon.body` did, once; idle media polling/LRU evaluation did, once. A thumbnail scheduling closure appears on another thread in the key sample, not as a main-thread snapshot hotspot.

## Main-thread symbol extracts

The binary-image map identifies `(in Graphene)` as `com.graphene.browser`. Below are the top 15 distinct app-image symbols by inclusive sampled frame count, restricted to the main-thread call graph. The keyboard sample labels the same main thread `DispatchQueue_<multiple>` rather than `DispatchQueue_1`; it was not discarded for that naming difference. The global “Sort by top of stack” section aggregates **all threads**, so it is reproduced separately and not misrepresented as main-thread-only. There are **no Graphene-image entries in those collapsed global top-of-stack sections** (threshold ≥5). Trivial entry frames are included for completeness; they describe stack ancestry, not computation cost. Fewer than 15 symbols exist in the quiet samples.

## sample-after-visits.txt

Main-thread header: `4378 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4378 | `Graphene_main` | 26 |
| 4378 | `static GrapheneApp.$main()` | 27 |

2 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        13134
        __workq_kernreturn  (in libsystem_kernel.dylib)        13133
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4378
        __psynch_cvwait  (in libsystem_kernel.dylib)        4373
```

## sample-ctrl-tab-pre-input.txt

Main-thread header: `4426 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4426 | `Graphene_main` | 26 |
| 4426 | `static GrapheneApp.$main()` | 27 |
| 1 | `thunk for @escaping @callee_guaranteed @Sendable (@guaranteed NSTimer) -> ()` | 52 |
| 1 | `closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 53 |
| 1 | `static MainActor.assumeIsolated<A>(_:file:line:)` | 54 |
| 1 | `closure #1 in static MainActor.assumeIsolated<A>(_:file:line:)` | 55 |
| 1 | `partial apply for thunk for @callee_guaranteed () -> (@out A, @error @owned Error)` | 56 |
| 1 | `thunk for @callee_guaranteed () -> (@out A, @error @owned Error)` | 57 |
| 1 | `partial apply for closure #1 in closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 58 |
| 1 | `closure #1 in closure #5 in AppState.init(directory:clock:sharing:privateMode:)` | 59 |
| 1 | `AppState.archiveInactiveTabs()` | 60 |
| 1 | `AppState.archiveInactiveTabs(in:)` | 61 |
| 1 | `AppState.archiveHours.getter` | 62 |
| 1 | `BrowserLibrary.archiveHours.getter` | 63 |

14 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        13278
        __workq_kernreturn  (in libsystem_kernel.dylib)        8851
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4426
        __psynch_cvwait  (in libsystem_kernel.dylib)        4422
```

## sample-ctrl-tab.txt

Main-thread header: `4274 Thread_8992773: Main Thread   DispatchQueue_<multiple>`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4274 | `Graphene_main` | 26 |
| 4274 | `static GrapheneApp.$main()` | 27 |
| 9 | `protocol witness for View.body.getter in conformance SidebarTab` | 1163 |
| 9 | `SidebarTab.body.getter` | 1164 |
| 5 | `closure #1 in SidebarTab.body.getter` | 1166 |
| 5 | `SidebarTab.rowContent.getter` | 1167 |
| 4 | `closure #1 in SidebarTab.rowContent.getter` | 1171 |
| 4 | `protocol witness for View.body.getter in conformance Sidebar` | 1239 |
| 4 | `Sidebar.body.getter` | 1240 |
| 4 | `closure #1 in Sidebar.body.getter` | 1244 |
| 4 | `closure #3 in closure #1 in Sidebar.body.getter` | 1248 |
| 4 | `ScrollView.init(_:content:)` | 1249 |
| 4 | `closure #1 in closure #3 in closure #1 in Sidebar.body.getter` | 1251 |
| 4 | `protocol witness for Layout.explicitAlignment(of:in:proposal:subviews:cache:) in conformance ShellContentLayout` | 2169 |
| 4 | `protocol witness for Layout.placeSubviews(in:proposal:subviews:cache:) in conformance ShellContentLayout` | 2176 |

98 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
__workq_kernreturn  (in libsystem_kernel.dylib)        12813
        mach_msg2_trap  (in libsystem_kernel.dylib)        12307
        __psynch_cvwait  (in libsystem_kernel.dylib)        5712
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4274
        pas_thread_local_cache_for_all  (in JavaScriptCore)        14
        AG::Graph::UpdateStack::update()  (in AttributeGraph)        11
        swift_release  (in libswiftCore.dylib)        11
        <deduplicated_symbol>  (in SwiftUICore)        10
        stop_allocator  (in JavaScriptCore)        10
        AG::Graph::propagate_dirty(AG::AttributeID)  (in AttributeGraph)        8
        swift::MetadataCacheKey::operator==(swift::MetadataCacheKey const&) const  (in libswiftCore.dylib)        8
        scavenger_thread_main  (in JavaScriptCore)        7
        swift_retain  (in libswiftCore.dylib)        7
        AG::Subgraph::update(unsigned int)  (in AttributeGraph)        5
        start_wqthread  (in libsystem_pthread.dylib)        5
        swift_bridgeObjectRetain  (in libswiftCore.dylib)        5
```

## sample-idle.txt

Main-thread header: `4319 Thread_8992773   DispatchQueue_1: com.apple.main-thread  (serial)`. Counts below are inclusive frame occurrences summed across call-tree branches, not additive CPU percentages.

| Samples | Graphene symbol | Raw line |
|---:|---|---:|
| 4318 | `Graphene_main` | 26 |
| 4318 | `static GrapheneApp.$main()` | 27 |
| 1 | `partial apply for thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | 81 |
| 1 | `thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | 82 |
| 1 | `partial apply for closure #1 in closure #4 in AppState.init(directory:clock:sharing:privateMode:)` | 83 |
| 1 | `closure #1 in closure #4 in AppState.init(directory:clock:sharing:privateMode:)` | 84 |
| 1 | `AppState.pollMediaAndDiscard()` | 85 |
| 1 | `AppState.lruVictims(limit:)` | 86 |
| 1 | `getEnumTagSinglePayload for TabLifecycle.Resident` | 89 |
| 1 | `???` | 90 |

10 distinct Graphene symbols in this main-thread call graph; fewer than 15 are listed when fewer exist.

Top-of-stack section (all threads; cannot be relabeled main-thread-only):
```text
mach_msg2_trap  (in libsystem_kernel.dylib)        12954
        __workq_kernreturn  (in libsystem_kernel.dylib)        8634
        __psynch_cvwait  (in libsystem_kernel.dylib)        4610
        semaphore_wait_trap  (in libsystem_kernel.dylib)        4319
```

## Cleanup and evidence integrity

Computer-use could not reconnect for a normal UI quit. As an explicit cleanup fallback, verified PID 67037 still referred to `.build/Graphene-verify.app/Contents/MacOS/Graphene`, sent **SIGTERM only to that owned PID**, verified it absent with `ps`, then removed `.build/Graphene-verify.app`. This is a process-cleanup exception to the otherwise computer-use-only app interaction rule. No other Graphene process was terminated; `~/Applications/Graphene.app` was untouched. `/tmp/graphene-perf`, `/tmp/graphene-perf-run`, and `/tmp/graphene-perf-run-2` remain. [Cleanup record](cleanup.txt).

All raw screenshots, timestamp logs, samples, extraction scripts and derived contact sheets remain in this directory. No commit was made. The report intentionally leaves held-modifier latency, dropped-key reliability, ten-switch space timing, sidebar scroll/stutter and command-tab activation unresolved.
