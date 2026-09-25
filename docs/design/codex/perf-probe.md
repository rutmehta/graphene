# Task: measure Graphene's interactive slowness on a many-tab profile

You are Codex running on macOS with the computer-use tool. Use it for every interaction with the app; use the shell for builds, `top`, `sample`, `ps` and `screencapture`. Do the work synchronously; do not delegate, schedule or ask. Never use `GRAPHENE_DEBUG`, the `cmd.txt` debug driver, or scripted UI automation inside the app. Public pages only.

## Goal
The owner reports: "very slow, slow to command-tab to, slow for the websites to load in the profile that has a lot of tabs / a lot of pinned tabs, and it's slowing down the entire computer." Reproduce on a 60-tab profile, measure where the time goes, and write `docs/parity/shots/perf/report.md` with numbers and `sample` evidence. Do not commit.

## Build and launch
1. `GRAPHENE_APP_DIR=$PWD/.build/Graphene-verify.app ./scripts/build-app.sh`. Never touch `~/Applications/Graphene.app`; never quit a Graphene process you did not start.
2. Copy the prepared profile: `rm -rf /tmp/graphene-perf-run && cp -R /tmp/graphene-perf /tmp/graphene-perf-run` (it contains a 60-tab session across 3 spaces: 7 pinned and 2 favorites per space). Launch from a shell kept alive with `wait`: `GRAPHENE_DATA_DIR=/tmp/graphene-perf-run .build/Graphene-verify.app/Contents/MacOS/Graphene`. Record the PID. Window 1280×820; window id via `swift scripts/window-id.swift -p <PID>`.

## Measurements (record everything in the report)
Baseline: 30 s after launch, `top -l 1 -pid <PID> -stats pid,cpu,mem,threads`, and `ps -Ao pid,pcpu,rss,comm | grep WebKit.WebContent` (count, total CPU, total RSS; note that other apps' WebContent processes are included, so also record the count before launch).

A. **Visiting tabs.** Click 12 different Today/pinned tabs in the first space, about 3 s apart. After each click record the wall-clock time until the page's toolbar progress bar disappears (use screenshots at 0.5 s intervals if the tool cannot observe otherwise; approximate is fine, say so). After the 12th, repeat the `top`/`ps` measurements, and run `sample <PID> 5 -file docs/parity/shots/perf/sample-after-visits.txt`.

B. **⌃Tab.** Hold Control and press Tab three times, release. Record how long the switcher takes to appear after the first Tab (screenshot cadence 0.25 s) and how long the switch to the target tab takes after release. Run `sample <PID> 5 -file docs/parity/shots/perf/sample-ctrl-tab.txt` **while** pressing ⌃Tab repeatedly (start `sample` in the background first). Also do ⌘⌥→ / ⌘⌥← ten times quickly and note any lag or dropped presses.

C. **Idle after use.** Leave the app untouched for 60 s with 12 loaded tabs, then `top`/`ps` again and `sample <PID> 5 -file docs/parity/shots/perf/sample-idle.txt`. Note the main process CPU: anything above 2% idle is a bug.

D. **Space switching.** Switch between the three spaces with ⌃1/⌃2/⌃3 ten times; record any lag, and whether the sidebar visibly animates.

E. **Sidebar scroll.** Two-finger scroll over the tab list in a space with 20 tabs; report whether the list scrolls at all (the owner says it does not), and whether it stutters.

F. **System load.** During A and B, capture `top -l 1 -o cpu -n 8` once each and record which processes are on top (Graphene, WebContent, WindowServer, other).

## Report
For each `sample` file, extract the top 15 main-thread frames belonging to `com.graphene.browser` (the `Sort by top of stack` section and the call graph under `DispatchQueue_1: com.apple.main-thread`), and name the Swift symbols involved (SwiftUI body evaluations, `Sidebar`, `ThumbnailCache`, `takeSnapshot`, `TabLifecycle`, `Favicon`, `KnowledgeGraph`, `WKWebEngine`, `cite`, etc.). Table of every timing above with the raw numbers. A blunt "what is slow and why, ordered by cost" list. Cleanup: quit your PID, delete `.build/Graphene-verify.app`; leave `/tmp/graphene-perf-run`.
