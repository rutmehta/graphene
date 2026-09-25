Wrote [report.md](/Users/rutmehta/Developer/graphene/docs/parity/shots/perf-2/report.md) with timing tables, screenshots, process readings, all three requested samples, and main-thread symbol extracts. **The audit is partial due to computer-use timeouts.**

Findings:

- **Idle CPU bug not reproduced:** interval readings were **0.0%**; **99.93%** of idle main-thread samples were waiting.
- **Page loading/reloading caused visible waits:** most tabs cleared progress roughly **0.5–1.5 seconds after their toolbar appeared**. Revisiting Wikipedia triggered a reload taking roughly **3.5–4 seconds**.
- **Graphene memory:** **96 MB** baseline, **109 MB** after visits, **105 MB** idle; sampled peak **519 MB**.
- **System contention:** WindowServer led interval readings at **82–83% CPU**. Graphene and WebContent were absent from the top eight. Screenshot overhead and other running apps prevent attribution to Graphene.
- The repeated ⌃Tab sample caught **SwiftUI/sidebar work**, with no main-thread `takeSnapshot`, `ThumbnailCache`, or `KnowledgeGraph` hotspot.

The exact held-Control gesture was unsupported by the tool. Space switching stopped after one successful switch followed by tool timeouts; sidebar scrolling and command-tab activation remain unmeasured. These limitations are explicit in the report.

Cleanup is complete: terminated only owned PID **67037**, removed `.build/Graphene-verify.app`, retained the profiles and evidence. **No commit.**

