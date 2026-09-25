Completed the short run. [Report and evidence](docs/parity/shots/identity-ask/report.md) are saved.

- **PASS:** empty Ask grounding and trimming notice; numbered answer chips and sources line; darker tint after clicking chip 1; visible marks removed on close.
- **FAIL (observed):** the initial answer capture does not clearly show a highlighted passage—the Ask panel obscures almost all of the infobox.
- **FAIL (blocked):** scroll-to-mark behavior. Both scrolling attempts returned `windowNotFoundAtPosition`; the click capture proves active tint, not scrolling.
- **PASS:** the Swift shelf chip shows the actual orange Swift bird favicon.

All five PNGs were checked with `sips` and viewed: **2560×1640**, or **1280×820 at 2×**. Build passed; tests reported **205 executed, 3 skipped, 0 failures**.

Owned PID **23692** was quit, and `.build/Graphene-verify.app` was removed. The isolated profile and evidence remain. No source changes or commits.

