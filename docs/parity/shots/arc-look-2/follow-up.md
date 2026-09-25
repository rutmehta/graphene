# Follow-up to the second verification run (September 25, 2026)

Fixed on master after this run:

- **The rule across the top band at y=32.** Cause found with an env-gated view-tree dump (`GRAPHENE_DUMP_WINDOW=1`): SwiftUI treats the hidden titlebar as a 32pt safe area, and the `WindowOutline` overlay respected it, so its top stroke landed at y=32 across the sidebar (the page card covered it on the right). `WindowOutline` and `ChromeBackground` now ignore the safe area. Verified by pixel-scanning a fresh window-only capture of the seeded profile: no edge at y=32; the only remaining edge at y=44 is the favorites tile top. The titlebar separator setting was not the cause.
- **Letter placeholder favicons** now use a neutral fill and secondary ink instead of a hashed hue.
- **Grain** reduced to 2% in both schemes.

Not a defect, recorded so nobody chases it again: the dark sidebar samples in `pixel-samples.txt` (23,16,49) come from a Display P3 screenshot converted to sRGB, which lifts dark values by roughly 7 to 11 per channel. The palette value in-process is (16,12,38) for `chromeTop`, within 2 of the spec's (14,13,38). The Arc reference PNG was captured by a different tool at a different scale, so its (10,11,39) is not comparable pixel-for-pixel. Acceptance item 2 should be judged in-process (the `VisualPaletteTests` assertion) or with both captures taken through the same pipeline.

Still unverified after two runs, because Codex's desktop computer-use API has no pointer-only move or held-key capture: Today row hover, the hairline "Clear" reveal, sidebar edge peek, the ⌃Tab switcher, and every mid-animation frame. The peek trigger rule and toast timing are covered by unit tests only.
