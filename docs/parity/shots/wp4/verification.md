# WP4 implementation and verification

Status: substantial implementation, not complete Dia/Arc Max acceptance.

## Build

Swift 6.2.4, Swift 5 language mode. Final `swift build` succeeded, `swift test` passed 61 tests with 0 failures, `./scripts/build-app.sh` succeeded, and `codesign --verify --deep --strict .build/Graphene.app` returned 0. Final build/test/bundle logs are beside this file; no warning lines were present. Logs were printed using Python's last-30-lines slicing because the terminal tool forbids tail. No commit was made.

## Isolation and input

Used GRAPHENE_DATA_DIR=/tmp/graphene-dev-profile/wp4. The parent development directory already contained imported browsing state, so a fresh child profile avoided exposing or attaching it. No real-profile browser state was changed. Owned Graphene PIDs were 58180, 60395 and 72184. The fixture server was PID 62406, bound only to 127.0.0.1:18764. All four were verified stopped at completion. Cmd+Q was attempted through computer_use; one restart exited with Cmd+Q, other cleanup required terminating the exact owned PID after failed/ambiguous tool input. The requested pkill -f graphene-dev-profile cleanup was also issued. Existing unrelated Graphene instances were left alone.

Onboarding's Skip button failed twice before coordinate scaling was understood, so onboarding-complete was seeded in the fresh profile settings while the app was stopped. No feature actions were driven through DebugDriver. Actual page navigation, Cmd+K, typing/submission, mentions, writing-help actions and Settings were exercised with computer_use.

Tool limitations: element-index clicks were rejected because the wrapper omitted snapshot tokens. Pixel fallback worked using window-relative screenshot coordinates, despite tool summaries incorrectly recommending global AX coordinates. Convert each AX center by subtracting window origin, then scale by screenshot width/window width. After a restart, focus_app reported an ended session twice; capture/key/pixel input continued to work. No System Events, osascript or screencapture was used.

## Evidence

1. 01-on-device-response.png: original prompt produced a refusal on Example Domain.
2. 02-slash-skill.png: /summarize picker and explicit current-tab context.
3. 03-two-tab-mentions.png: Example Domain and writing fixture attached via two picker selections; budget visible.
4. 04-writing-affordance.png: focused textarea with floating writing button.
5. 05-textarea-replaced.png: real model draft inserted after explicit Replace. The fixture AX counter subsequently showed input=4, change=2, confirming both event types. The model added an unwanted introduction to its otherwise corrected sentence; it was not fabricated or silently rewritten for the screenshot.
6. 06-contenteditable-affordance.png: Gmail-style nested contenteditable separately focused, floating button shown. Its native preview was also opened; replacement/undo in that editor was not completed.
7. 07-on-device-answer-fixed.png: corrected prompt answered what Example Domain is for, using the actual page text. This supersedes the initial refusal for that question.
8. 08-ai-settings.png: provider status, personal context off, tidy toggles off, editable skill controls.

On-device diagnosis: a minimal FoundationModels probe answered the public question with ordinary reference instructions but refused when told broadly that sources were untrusted data. The prompt now explicitly distinguishes untrusted commands from usable evidence, retaining source-instruction isolation and no tools. Example Domain subsequently answered correctly in the app. The writing-fixture summarization still refused; model output quality is not guaranteed. Ollama was not running at localhost:11434; no remote provider or credentials were configured.

Chats were read back from the isolated chats.json with user/assistant turn history. Store tests separately verify retention of 50 chats, metadata round-trips, request JSON shapes, budget splitting, numeric citations, fenced Markdown, skill and memory parsing, question routing, cross-profile graph collisions, private tabs, and late-generation cancellation. The malicious source string remains user data in an encoded request with a separate system instruction and no tools. A reusable prompt-injection fixture is included under Tests/GrapheneTests/Fixtures; the current request test uses an inline injection rather than loading that file.

## Implemented surfaces

- Optional Apple, OpenAI-compatible and Anthropic provider registry; SSE, cancellation, ephemeral sessions, redirect rejection, HTTPS except loopback, Keychain API keys and explicit first remote-selection explanation.
- Multi-turn chat, history popover, new/stop/regenerate/copy, basic block Markdown, validated numeric links, local source search, @tab/@all, context chips and budget notices.
- Readable content/selection/author/date/headings extraction and WebEngine API. Forms/editors are excluded from ordinary page capture.
- Editable slash skills and opt-in profile-scoped personal memory stores/settings.
- Native writing preview and explicit apply/copy, origin/stale-field guards, password/payment exclusion, input/change events, simple-editor undo via insertText.
- Shift-hover preview implementation with bounded cookie-free target fetch and 100-entry memory cache; opt-in tidy pinned title and confirmed download rename; Ask on Page shortcut; cached thread summary and Vault context.

## Remaining acceptance and limitations

- Remote SSE endpoints, first-use consent interaction, Keychain UI, memory extraction/edit lifecycle, tidy-title automation and download rename confirmation were not exercised live. Request encoding is tested without network.
- Shift-hover was not verified. The exposed computer_use schema has no mouse-move/hover or held-key lifecycle action. No driver-seeded preview was substituted for a real hover.
- Rich-editor Replace/Insert/Copy/undo, Gmail itself, Google Docs, password/payment exclusion and text-input replacement need further desktop verification. Only the textarea Replace and both editor affordances were observed. Complex rich editors can reject synthetic input or lose formatting; Copy is the fallback.
- Thread-summary generation/cache UI, Vault chat handoff, skill CRUD, past-chat deletion and full keyboard-only picker navigation need further desktop verification.
- The final small privacy guard, cancellation injection seam and post-insert status-label correction were built/tested after the last GUI run; the final bundled binary was not relaunched after those changes.
- Chat scope remains stable until refresh/new chat, not silently recaptured on every active-tab change. Basic Markdown preserves list lines rather than providing a full CommonMark layout engine. On-device history is bounded separately from its 6,000-character source budget.
- Legacy shared graph text is conservatively excluded if any visit belongs to another profile or lacks explicit space provenance. Account-only Mail sources without space provenance fail closed for AI, while Mail browsing and Vault saving remain available.
- The old source-search view is retained privately as legacy code; the visible panel uses ChatView. Existing note-to-composer drag/drop handling is still in that legacy view and has not been ported to ChatView.
- Skills/memory settings can hold stale in-memory lists across simultaneous windows; concurrent edit reconciliation is not implemented.
- Readability is heuristic, not Mozilla Readability. Link previews reject literal local addresses and redirects but do not implement a complete DNS-rebinding defense or authenticated target reading.

## Files touched for WP4

Intelligence: KnowledgeAssistant.swift, LanguageModelProvider.swift, ChatSession.swift, PageContext.swift, Skills.swift, MemoryStore.swift, AITidy.swift.
UI: KnowledgeSearchView.swift, ChatView.swift, ChatMarkdown.swift, AISettingsView.swift, SettingsView.swift, WritingHelpView.swift, ThreadSummaryView.swift, LedgerView.swift.
Integration: App/AppState.swift, Model/Settings.swift, Model/Commands.swift, Model/KnowledgeGraph.swift, Mail/Keychain.swift, Web/WebEngine.swift, Web/WKWebEngine.swift, Web/BrowserDownload.swift, Store/DownloadStore.swift, Resources/annotate.js.
Other: README.md, scripts/build-app.sh, Tests/GrapheneTests/IntelligenceTests.swift, Tests/GrapheneTests/Fixtures/prompt-injection.txt, this evidence directory.

Reference images under docs/parity/ref were not changed. Dia and Graphene captures were inspected with the vision tool. The new chat retains quiet palette-driven light surfaces, hairlines and native controls; no chat-panel clipping was observed. Central fixture-page clipping was ordinary scrollable webpage content, not a chat layout change. No Little Graphene work was performed.
