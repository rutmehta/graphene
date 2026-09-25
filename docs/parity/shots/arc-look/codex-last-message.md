Wrote the [verification report](docs/parity/shots/arc-look/report.md). **The rebuild is not accepted; verification remains incomplete.**

The confirmed failure is the **command bar’s vertical position**: empty ⌘T, the URL-prefilled bar, and the `swift` query appeared at different heights. URL selection worked, but acceptance item 4 fails.

Other findings:

- Split view worked through the context menu; the requested shortcut produced no visible change.
- Folder collapse/expand, space switching, and floating chat worked.
- Build log contained no warnings. Tests passed: **125 executed, one skipped, zero failures**.
- `master` advanced externally from `2b11f27` to `a5b8b9f` during the run, so the bundle and later tests do not validate one fixed revision.

**The capture suite was blocked.** Only [settings-general.png](docs/parity/shots/arc-look/settings-general.png) was saved and visually validated, at 1640×1304. Other capture attempts targeted unrelated content and were moved to Trash. The report explicitly marks missing measurements, hover checks, and animation evidence as unverified.

Cleanup is verified: both isolated app PIDs exited, `.build/Graphene-verify.app` was removed, the requested profile remains, and Reduce Motion is back **off**. No commit was made.

