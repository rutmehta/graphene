Saved the [verification report](docs/parity/shots/identity-fixes/report.md) and captures. **D6 is not a clean pass.**

- **Passed:** both Resume entries, ⌘T command bar, branch tree and menu collapse/expand, 11-point connector tick, Ask grounding notice, and shelf presentation/navigation. Shelf chips measure **87 points**, with **12-point favicons**.
- **Failed:** typing `swift` in one action retained only `s`; paced typing worked. Ask citations reported **“Passage not found on this page”** and did not highlight or scroll. The Peru question repeated the graphene answer with citations—no “No sources” line.
- **Other limits:** expand shortcut attempt did nothing, though the menu worked. Hover chevron was blocked by the API. Mark removal could not be verified because Ask never created marks.

Build passed; **196 tests, one skipped, zero failures**. PID **1055** exited, and `.build/Graphene-verify.app` was removed. The installed app was untouched.

