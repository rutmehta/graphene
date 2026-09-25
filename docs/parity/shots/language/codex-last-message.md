Verification finished. The [report](docs/parity/shots/language/report.md) contains the per-check PASS / FAIL (observed) / FAIL (blocked) table, measurements, language-rule inventory, logs, and cleanup details. **This is not a design-language sign-off.**

Main findings:

- **Threads:** correct ancestry, accent path, 180pt column pitch, 40pt row pitch, and 6pt note dots. Latin is clipped by the summary pane; clicking a node exits the map.
- **Annotations/Vault:** marks, floating actions, note saving, list typography, provenance, grouping, and opening saved passages worked.
- **Ask:** claim chips and the 2004 sentence mark worked. The panel still obscures part of the cited sentence; the tensile row’s exact highlight bounds remain unverified.
- **Board:** page cards and their faint connector worked; deleting Graphene removed its connector. **Vault → Add to Board rendered a page card instead of a quote card.** Adding a note overlapped Carbon.
- **Mail:** exact read-only line and disconnected fallback passed. Connected views were blocked by missing OAuth.
- **Language:** extra divider hairlines remain across surfaces.

Saved **22 screenshots**, each checked with `sips` and visually inspected. Hover, exact sentence selection, and card movement limitations are explicitly documented without misleading replacement captures.

Build passed. Tests: **244 executed, 3 skipped, 0 failures**. Owned PID **40754** exited cleanly; `.build/Graphene-verify.app` was deleted. Existing installed app and tracked files were untouched.

