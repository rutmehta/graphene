The computer-use session was forcibly stopped during the ninth tab visit with: **“Computer Use is not allowed on the current browser URL.”** The tool requires ending the session, so I could not complete the measurements or write `report.md`.

Completed before the block:

- Built `.build/Graphene-verify.app` and launched the copied profile at `/tmp/graphene-perf-run`.
- Recorded owned PID **97847**, window ID **11092**, and a **1280×820-point** window.
- Captured the 30-second baseline, pre-launch process inventory, eight tab visits, screenshots at a requested 0.5-second cadence, and system-load captures during A.
- Saved available evidence under [docs/parity/shots/perf](/Users/rutmehta/Developer/graphene/docs/parity/shots/perf).

The baseline showed Graphene at **112 MB and 13 threads**, with substantial whole-system load: **47 GB used, 16 GB compressed, load average 16.70**. The single `top` capture reported **0.0% CPU**, which is insufficient to establish idle CPU behavior.

**Incomplete:** remaining visits, B–E, all three `sample` captures, timing analysis, report, and cleanup. **PID 97847 may still be running, and the verification app remains on disk.** No commits were made; the existing Graphene installation and processes were left untouched.

