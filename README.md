# Graphene

A native macOS browser built to be the hub of knowledge work — not a portal you tab away from.

Graphene starts from three problems with how browsers treat the work you do inside them:

- **History is a dead list.** It never tells you *why* you went somewhere or what search started the thread. Graphene records your browsing as a **navigable graph** — pages are nodes, connected by how you actually moved (opened-from) and the search that led you there.
- **Notes lose their source.** Highlight something, switch to a notes app, and the provenance is gone. In Graphene you **annotate in place**, and every note keeps the page it came from.
- **AI is stuck in one tab.** Context you hand a chatbot doesn't travel. Graphene's direction is an AI layer that reasons over your *thread of thought and your own knowledge*, not a single page. Early concept explorations live in [`docs/ai-concepts`](docs/).

Descended from the Mangrove / Graphene hackathon project; rebuilt native.

## Status

Phase 1 foundation, working:

- Real browsing on WKWebView — tabs, back/forward/reload, omnibox (URL or search), session restore.
- The knowledge graph: navigations become nodes with chronological "opened-from" edges and the search query that led there; page text and title captured for each. Persisted as one JSON file.
- An interactive graph view of your history (pan/zoom, hover, click to reopen).
- Annotate any page — select text to highlight and keep it, with its source URL and surrounding context, saved to a markdown vault.
- Arc-style sidebar, one default space.

Deliberately deferred: semantic grouping of the graph, the cross-tab AI layer + daily update, Arc-style Spaces, a Chromium/CEF engine backend (see below), Chrome extensions.

## Design

- **Native macOS, Swift + SwiftUI**, AppKit only where it earns its place (the web-view host, the graph canvas). Follows the system light/dark appearance.
- **WKWebView behind a `WebEngine` protocol.** WKWebView ships a real, native-feeling browser today; the protocol boundary means a Chromium/CEF backend can replace it later without touching tabs, the graph, the UI, or annotations. (WKWebView's limits — some sign-in flows, no Chrome extensions — are exactly what that later backend is for.)
- **Local-first.** No database, no cloud. The graph is one JSON file; annotations and daily digests are plain markdown in `~/GrapheneVault`, each carrying its source.

## Architecture

```
Web/     WebEngine        protocol — the Chromium-swappable boundary
         WKWebEngine      WKWebView: nav capture, SPA pushState hook, window.open → new tab, JS bridge
         WebContainer     hosts the active tab's long-lived web view (others keep running)
Model/   Tab, Space       per-tab state; themed contexts
         KnowledgeGraph   nodes + chronological/query edges; JSON persistence
         Omnibox          URL-vs-search resolution; captures the query as the "why"
Store/   Vault            annotations + daily digests as markdown, with provenance
         Paths            one folder you own
UI/      RootView         sidebar · toolbar · web content
         GraphView        the history graph (Canvas)
         AnnotationPanel  your notes, newest first
App/     GrapheneApp      @main + activation
         AppState         the BrowserCoordinator: routes navigation into the graph
```

## Run

```bash
swift build
swift run Graphene
```

Requires the Swift 6.2 toolchain (Xcode 26). `swift run` is the dev loop; an `.app` bundling step (for `http://` support via ATS and stable cookie storage) comes next — until then some plain-HTTP sites and sign-in flows are limited by WKWebView.

## Vault

Everything Graphene remembers is on your disk:

- `~/GrapheneVault/annotations/YYYY-MM-DD.md` — your highlights and notes, with sources.
- `~/GrapheneVault/daily/` — daily digests (Phase 2).
- `~/Library/Application Support/Graphene/graph.json` — the knowledge graph.
