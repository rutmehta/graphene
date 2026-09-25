# D6 Ask and shelf favicon re-verification

Run: 2026-09-25. Real isolated macOS app; public Wikipedia and Swift Forums only. No source edits, commits, stashes, debug driver, delegated work, or scripted in-app automation.

- HEAD: `78cd9443ec257124518dd03e26b0ae24e0d9c9c0`.
- Initial `git status --short`: clean. Final: only `?? docs/parity/shots/identity-ask/`.
- Built `.build/Graphene-verify.app` with the requested `GRAPHENE_APP_DIR` command.
- Owned PID: **23692**. Window ID: **10110**, obtained with `swift scripts/window-id.swift -p 23692`.
- Profile: `/tmp/graphene-identity-ask`, newly created and retained. Launch shell stayed alive with `& wait`.
- Default onboarding: Sidebar (Arc), Graphite selected; Start browsing. No default-browser change or import.
- Every evidence PNG below was captured with `screencapture -l 10110 -o -x`, checked with `sips`, and opened for visual inspection. All are **2560×1640 pixels**, corresponding to **1280×820 points at 2×**.

## Results

Checks 1 (Resume) and 2 (Branch) from the broader checklist were explicitly out of scope and were not tested. No verdict is assigned to them. Check 3 and the requested portion of check 4 are broken down below; a partial pass does not make check 3 an overall pass.

| Check | Status | Observed result | Evidence |
|---|---|---|---|
| 3a — empty Ask | PASS | Accent dot and “This page”; readable trimming notice; page source chip and skills above composer. | [ask-empty.png](ask-empty.png) |
| 3b — answer chips and sources line | PASS | Three inline chips numbered 1 and a sources line with 1, Wikipedia favicon, and page title. | [ask-answer.png](ask-answer.png) |
| 3c — clearly visible highlighted passage before click | FAIL (observed) | The initial answer capture does not clearly expose a tinted passage in the unobscured article. The infobox is almost entirely covered by Ask. AX reported its first row as “1 Graphene,” but that is not a substitute for visible passage evidence. | [ask-answer.png](ask-answer.png) |
| 3d — citation help | PASS | Recorded via AX: description “Source 1: Graphene - Wikipedia”; Help “Show in page”. Hover unavailable. | Recorded below; inline chips in ask-answer.png |
| 3e — active tint after clicking chip 1 | PASS | Opening word “Graphene” gets visibly darker lavender tint; inline chips and sources line also become tinted. The exposed bottom edge of the infobox also shows active tint. | [ask-click.png](ask-click.png) |
| 3f — scroll to mark | FAIL (blocked) | Target was already in the viewport and no scroll displacement was observed. Attempts to scroll away, both by coordinate and by web scroll-area AX target, failed with `windowNotFoundAtPosition`. Cannot claim navigation to an offscreen mark. | ask-click.png shows active target, **not proof of scrolling** |
| 3g — close removes marks | PASS | Panel closed; opening word and infobox return to their normal untinted appearance. No Ask marks visible in the captured viewport; infobox AX row returned to “Graphene” without the injected 1. | [ask-closed.png](ask-closed.png) |
| 4 — Swift shelf favicon | PASS | Triple-clicked requested paragraph, ⌘D, Save to Vault. Shelf chip displays actual orange Swift bird favicon, not a letter. | [shelf.png](shelf.png) |

**Overall: Ask is not fully verified. Shelf favicon passes.** The Peru/no-sources test, shelf reopening, two-chip layout, branch states, and other broad-checklist cases were not requested in this narrowed run and were not tested.

## Recorded text and measurements

Empty Ask notice: `Page text trimmed to 6,000 characters`

Grounding: `This page`. Composer: `Ask about this page…`.

Question: `What is graphene's tensile strength and who first isolated it?`

Answer verbatim, with `[1]` representing the rendered numbered chips:

```text
Source [1]: Graphene - Wikipedia
Tensile strength: 130 GPa [1]
First isolated: Andre Geim and Konstantin Novoselov [1]
```

Sources line: `[1] [Wikipedia favicon] Graphene - Wikipedia`.

All three inline citation controls exposed the same AX description, `Source 1: Graphene - Wikipedia`, and Help, `Show in page`. No pointer-only move API exists, so no hover capture was attempted or substituted.

Selected and saved quote, as observed in the Save sheet and AX selection:

```text
The Swift Forums are governed by the Swift Code of Conduct
```

Shelf visible fragment: `Swift Foru…`, in serif type. Leading control is a tray glyph with AX label `Vault`. Shelf chip AX description retains the complete quote and Help is `Opens the source page`.

| Measurement | Observed |
|---|---|
| Window | 2560×1640 px / 1280×820 pt; all five PNGs |
| Sidebar | AX reports 224 pt |
| Swift favicon colored bounds | x=72…95, y=1512…1535 px in shelf.png: **24×24 px / 12×12 pt** |
| Shelf chip | Approximately 192×64 px / 96×32 pt from visual bounds; approximate, not an AX size |
| Active opening-word tint | At PNG pixel (500,638): answer `(255,255,255)`, clicked `(198,202,224)`, closed `(255,255,255)` in device RGB |

Pixel colors and the favicon bounding box were measured from the saved PNG files with AppKit. A first attempt using Python Pillow failed because Pillow is unavailable; it was not installed.

## What looked wrong / limits

- Ask overlays the right side of the page and almost completely conceals the infobox where AX indicates a numbered mark. The initial answer screenshot does not meet a clear visible-highlight acceptance bar.
- Chip 1 visibly activates the generic opening word “Graphene,” rather than exposing the strength or isolation claim in the unobscured page. This is weak citation targeting even though active tint works.
- No newly injected matching superscript is clearly visible in the unobscured passage. Wikipedia's native reference `[1]` next to the pronunciation is not counted as Graphene's citation marker.
- Scroll attempts failed with `windowNotFoundAtPosition((794.0, 590.0))` and `windowNotFoundAtPosition((1217.0, 741.0))`. No substitute scroll capture was supplied.
- ⌘T/type/Return after closing Ask did not navigate. Clicking the sidebar New Tab and location controls did, and that was used for Swift Forums.
- The selection's floating “Save to Graphene / Add note / Save” bar remains visible after saving to Vault. The shelf itself is present with the correct icon.
- No hover, held-modifier click, or coordinate drag states were attempted. They are unsupported/known-broken in this API.
- No crash or hang was observed. `app.log` is empty; this does not prove absence of all system-console errors.

## Build and tests

Both commands exited 0. `swift test`: **205 executed, 3 skipped, 0 failures**. These tests do not establish the blocked visual behaviors.

Build tail:

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.14s)
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app: replacing existing signature
/Users/rutmehta/Developer/graphene/.build/Graphene-verify.app
```

Test tail:

```text
Test Suite 'WorkspaceSettingsTests' passed at 2026-09-25 05:55:25.451.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.278 (0.278) seconds
Test Suite 'GraphenePackageTests.xctest' passed at 2026-09-25 05:55:25.451.
	 Executed 205 tests, with 3 tests skipped and 0 failures (0 unexpected) in 6.087 (6.103) seconds
Test Suite 'All tests' passed at 2026-09-25 05:55:25.451.
	 Executed 205 tests, with 3 tests skipped and 0 failures (0 unexpected) in 6.087 (6.104) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

## Cleanup

Quit through this app's Graphene → Quit Graphene menu using computer use. The owned launch shell completed with exit 0, confirming PID 23692 ended. Deleted only `.build/Graphene-verify.app`; verified the bundle no longer exists. The initial shell deletion command was rejected by command policy; the explicitly authorized exact-path bundle deletion was completed with Python filesystem operations. No installed Graphene bundle was touched, no other Graphene process was quit, and no profile or evidence was deleted. Temporary profile retained at `/tmp/graphene-identity-ask`.
