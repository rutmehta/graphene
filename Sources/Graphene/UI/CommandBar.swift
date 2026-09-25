import SwiftUI
import AppKit

extension View {
    /// Pins the floating command bar's top edge at `commandTop × window height` (arc-look.md §3.4).
    /// The overlay that hosts the bar also holds a full-window click catcher, so the implicit
    /// stack around them is window-sized; without the top-aligned frame the card would be centred
    /// in the space below the padding and move whenever its height changes.
    func commandBarPlacement(window: CGSize) -> some View {
        frame(width: CommandBarLayout.width(window: window.width))
            .padding(.top, CommandBarLayout.top(window: window.height))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The same navigation surface opens a page, switches tabs, or brings back a source.
struct CommandBar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var integrated = false
    @State private var selectedIndex = 0
    @State private var askOverride: Bool?
    @State private var suggestions: [String] = []
    private var asking: Bool { !app.isPrivate && (askOverride ?? Omnibox.isQuestion(query)) }
    private var mention: String? {
        guard let index = query.lastIndex(of: "@") else { return nil }
        let suffix = String(query[query.index(after: index)...])
        return suffix.contains(" ") ? nil : suffix
    }
    private var completion: String? {
        guard !asking, mention == nil else { return nil }
        return Omnibox.completion(app.commandBarDraft, candidates: app.tabs.compactMap { $0.url?.absoluteString } + app.graph.nodeArray.sorted { $0.lastVisit > $1.lastVisit }.map(\.url))
    }

    private struct Result: Identifiable {
        enum Destination {
            case tab(UUID)
            case page(String)
            case input(String)
            case action(String), ask, attach(UUID), space(UUID), note(UUID), thread(UUID)
        }

        let id: String
        let title: String
        let detail: String
        let host: String?
        let symbol: String?
        let kind: String
        let destination: Destination
    }

    private var query: String {
        app.commandBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Result] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        func score(title: String, host: String, url: String) -> Int? {
            guard !terms.isEmpty else { return 0 }
            let title = title.lowercased()
            let host = host.lowercased()
            let url = url.lowercased()
            guard terms.allSatisfy({ title.contains($0) || host.contains($0) || url.contains($0) }) else { return nil }
            return terms.reduce(0) { total, term in
                total + (title.hasPrefix(term) ? 8 : title.contains(term) ? 4 : 0)
                    + (host.hasPrefix(term) ? 6 : host.contains(term) ? 3 : 0)
            }
        }

        var seen = Set<String>()
        var matches: [Result] = []
        if query == "Move Tab to Space ▸" {
            return app.spaces.filter { $0.id != app.activeTab?.spaceID }.map { space in
                Result(id: "space-\(space.id)", title: space.name, detail: "Move current tab", host: nil, symbol: "square.stack", kind: "Move Tab to Space", destination: .space(space.id))
            }
        }
        if let mention, !app.isPrivate {
            return app.spaces.flatMap { space in app.tabs.filter { $0.spaceID == space.id && !app.commandContextIDs.contains($0.id) && (mention.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(mention) || $0.url?.host?.localizedCaseInsensitiveContains(mention) == true) }.map { tab in
                Result(id: "attach-\(tab.id)", title: tab.displayTitle, detail: space.name, host: tab.url?.host, symbol: nil, kind: "Attach tab", destination: .attach(tab.id))
            } }
        }
        if query.isEmpty {
            for tab in CommandBarSuggestions.recentTabs(app.recentTabs, space: app.activeSpaceID, excluding: app.commandBarCreatesTab ? nil : app.activeTabID) {
                matches.append(Result(id: "tab-\(tab.id)", title: tab.displayTitle, detail: displayHost(tab.url?.host), host: tab.url?.host,
                                      symbol: nil, kind: "Tabs", destination: .tab(tab.id)))
            }
            for action in CommandBarSuggestions.actions(app.commandActions) {
                matches.append(Result(id: "action-\(action.id)", title: action.title, detail: "", host: nil, symbol: "command",
                                      kind: CommandBarSuggestions.section, destination: .action(action.id)))
            }
            return matches
        }
        if asking { matches.append(Result(id: "ask", title: "Ask Graphene: \(query)", detail: "Current page and attached tabs · On-device", host: nil, symbol: ShellGlyph.ask, kind: "Ask", destination: .ask)) }
        for action in app.commandActions where CommandMatch.matches(query, title: action.title) {
            matches.append(Result(id: "action-\(action.id)", title: action.title, detail: action.id == "archive-all" ? "Archive Today tabs; keep pins and favorites" : "", host: nil, symbol: "command", kind: "Commands", destination: .action(action.id)))
        }
        let tabs = app.tabs.compactMap { tab -> (Tab, URL, Int)? in
            guard let url = tab.url,
                  let rank = score(title: tab.displayTitle, host: url.host ?? "", url: url.absoluteString) else { return nil }
            return (tab, url, rank)
        }.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            if lhs.0.id == app.activeTabID { return false }
            if rhs.0.id == app.activeTabID { return true }
            return lhs.0.createdAt > rhs.0.createdAt
        }

        for (tab, url, _) in tabs.sorted(by: { lhs, rhs in
            (app.spaces.firstIndex { $0.id == lhs.0.spaceID } ?? 0) < (app.spaces.firstIndex { $0.id == rhs.0.spaceID } ?? 0)
        }) {
            seen.insert(KnowledgeGraph.canonicalURL(url.absoluteString))
            matches.append(Result(id: "tab-\(tab.id)", title: tab.displayTitle,
                                  detail: displayHost(url.host), host: url.host, symbol: nil,
                                  kind: "Tabs · " + (app.spaces.first { $0.id == tab.spaceID }?.name ?? "Space"),
                                  destination: .tab(tab.id)))
        }

        let history = app.graph.nodeArray.compactMap { node -> (GraphNode, Int)? in
            guard let rank = score(title: node.title, host: node.host, url: node.url) else { return nil }
            return (node, rank)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.lastVisit > rhs.0.lastVisit : lhs.1 > rhs.1
        }
        for (node, _) in history.prefix(8) {
            guard seen.insert(KnowledgeGraph.canonicalURL(node.url)).inserted else { continue }
            matches.append(Result(id: "page-\(node.id)", title: node.title.isEmpty ? displayHost(node.host) : node.title,
                                  detail: displayHost(node.host), host: node.host, symbol: nil,
                                  kind: "History", destination: .page(node.url)))
        }

        for note in app.vault.annotations.filter({ query.isEmpty || ($0.title + " " + $0.text + " " + $0.note).localizedCaseInsensitiveContains(query) }).prefix(5) {
            matches.append(Result(id: "note-\(note.id)", title: note.title, detail: note.note.isEmpty ? note.text : note.note, host: nil, symbol: "bookmark", kind: "Vault notes", destination: .note(note.id)))
        }
        for thread in app.graph.threads(spaceID: nil).filter({ query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }).prefix(5) {
            matches.append(Result(id: "thread-\(thread.id)", title: "Resume thread \(thread.title)", detail: "\(thread.nodes.count) pages", host: nil, symbol: "point.3.connected.trianglepath.dotted", kind: "Threads", destination: .thread(thread.id)))
        }
        if !query.isEmpty {
            let url = Omnibox.asURL(query)
            let engine = app.searchEngine == .google ? "Google" : "DuckDuckGo"
            let action = Result(id: "input", title: url == nil ? "Search \(engine) for “\(query)”" : query,
                                detail: url == nil ? "Search the web" : "Open website",
                                host: nil, symbol: url == nil ? "magnifyingglass" : "arrow.up.right",
                                kind: "Search", destination: .input(query))
            // A typed address should navigate verbatim; a page name should first
            // offer the matching tab or source the user already has.
            if url != nil || matches.isEmpty { matches.insert(action, at: 0) }
            else { matches.append(action) }
            for suggestion in suggestions where suggestion != query {
                matches.append(Result(id: "suggest-\(suggestion)", title: suggestion, detail: "Search suggestion", host: nil, symbol: "magnifyingglass", kind: "Search", destination: .input(suggestion)))
            }
        }
        return matches
    }

    private var cornerRadius: CGFloat { integrated ? ShellLayout.rowRadius : ShellLayout.commandRadius }

    var body: some View {
        let rows = results
        let sections = rows.map(\.kind)
        let labels = CommandBarLayout.sectionStarts(sections)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: asking ? ShellGlyph.ask : "magnifyingglass")
                    .font(integrated ? ShellType.row : ShellType.input)
                    .foregroundStyle(app.pal.ink3)
                    .accessibilityHidden(true)
                CommandInput(text: $app.commandBarDraft,
                             focusRequest: app.commandBarFocusRequest,
                             selectAllOnFocus: !app.commandBarCreatesTab,
                             placeholder: asking ? "Ask about this page…" : "Search or enter URL…",
                             color: NSColor(app.pal.ink),
                             placeholderColor: NSColor(app.pal.ink3),
                             fontSize: integrated ? ShellType.rowSize : ShellType.inputSize,
                             onMove: moveSelection,
                             onSubmit: submitSelection,
                             onCancel: { app.dismissCommandBar() }, completion: completion,
                             onToggle: toggleMode,
                             onFocused: { app.takeResumeKeys() })
                    .id(app.commandBarCreatesTab)
                    .frame(maxWidth: .infinity)
                    .frame(height: integrated ? 28 : 30)
                    .accessibilityIdentifier("commandBarInput")
            }
            .padding(.horizontal, integrated ? ShellLayout.commandListPadding + ShellLayout.rowInsetLeading : ShellLayout.commandInset)
            .frame(height: integrated ? ShellLayout.pageToolbarHeight : ShellLayout.commandInputHeight)
            .accessibilityAction(named: asking ? "Switch to Search" : "Switch to Ask", toggleMode)

            Rectangle().fill(app.pal.hairline).frame(height: ShellLayout.hairline)

            if !app.commandContextIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ShellLayout.commandListPadding / 2) {
                        ForEach(app.commandContextIDs, id: \.self) { id in
                            Button { app.commandContextIDs.removeAll { $0 == id } } label: {
                                Label(app.tabs.first { $0.id == id }?.displayTitle ?? "Closed tab", systemImage: "xmark")
                                    .font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(1)
                                    .padding(.horizontal, ShellLayout.rowInsetLeading).frame(height: ShellLayout.chipHeight)
                                    .background(app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("command.removeContext.\(id)").accessibilityLabel("Remove attached tab").accessibilityAddTraits(.isButton)
                        }
                    }.padding(.horizontal, ShellLayout.commandInset).padding(.top, ShellLayout.commandListPadding)
                }
            }

            if rows.isEmpty {
                Text("Your open tabs and recent pages will appear here.")
                    .font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ShellLayout.commandInset)
                    .frame(height: ShellLayout.commandRowHeight + 2 * ShellLayout.commandListPadding)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                                if labels.contains(index) {
                                    Text(result.kind).font(ShellType.label).foregroundStyle(app.pal.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, ShellLayout.commandInset)
                                        .frame(height: ShellLayout.commandSectionHeight)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                resultRow(result, selected: index == selectedIndex).id(result.id)
                                    .onTapGesture { activate(result) }
                                    .onHover { inside in if inside { selectedIndex = index } }
                            }
                        }
                        .padding(.top, labels.contains(0) ? 0 : ShellLayout.commandListPadding)
                        .padding(.bottom, ShellLayout.commandListPadding)
                        .id(rows.map(\.id))
                    }.frame(height: CommandBarLayout.listHeight(sections)).scrollIndicators(.automatic)
                        .onChange(of: selectedIndex) { _, index in
                            if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                        }
                }
            }
        }
        .frame(maxWidth: integrated ? .infinity : ShellLayout.commandWidth)
        .background(app.pal.elev, in: RoundedRectangle(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(app.pal.hairline, lineWidth: ShellLayout.hairline))
        .shadow(color: integrated ? .clear : app.pal.commandShadow, radius: app.pal.commandShadowRadius, x: 0, y: app.pal.commandShadowY)
        .onChange(of: app.commandBarDraft) { selectedIndex = 0 }
        .task(id: "\(query)|\(app.searchEngine.rawValue)|\(app.searchSuggestions)|\(asking)") {
            suggestions = []
            guard app.searchSuggestions, app.settings.customSearchURL == nil, !app.isPrivate, !asking, mention == nil, !query.isEmpty,
                  Omnibox.asURL(query) == nil, !app.commandActions.contains(where: { CommandMatch.matches(query, title: $0.title) }) else { return }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let values = try await SearchSuggestions.fetch(query, engine: app.searchEngine)
                try Task.checkCancellation(); suggestions = values
            } catch { /* Local results remain available when suggestions fail. */ }
        }
        .onExitCommand { app.dismissCommandBar() }
        .accessibilityIdentifier("commandBar")
    }

    /// `Tab` flips between Search and Ask; there is no visible pill.
    private func toggleMode() {
        guard !app.isPrivate else { return }
        askOverride = !asking
    }

    private func resultRow(_ result: Result, selected: Bool) -> some View {
        HStack(spacing: ShellLayout.rowInsetLeading) {
            Group {
                if let symbol = result.symbol {
                    Image(systemName: symbol).font(ShellType.row).foregroundStyle(app.pal.ink3)
                } else {
                    Favicon(host: result.host, size: ShellLayout.iconSize)
                }
            }.frame(width: ShellLayout.iconSlot)
            Text(result.title).font(ShellType.row)
                .foregroundStyle(app.pal.ink).lineLimit(1).layoutPriority(1)
            if !result.detail.isEmpty {
                Text(result.detail).font(ShellType.secondary)
                    .foregroundStyle(app.pal.ink3).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: ShellLayout.rowInsetLeading)
            let hint = rowHint(result, selected: selected)
            if !hint.isEmpty {
                Text(hint).font(ShellType.label).foregroundStyle(app.pal.ink3).fixedSize()
            }
        }
        .padding(.horizontal, ShellLayout.rowInsetLeading + ShellLayout.rowInsetLeading / 2)
        .frame(height: ShellLayout.commandRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
        .animation(Motion.hover.reduced(reduceMotion), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
        .padding(.horizontal, ShellLayout.commandListPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("command.result.\(result.id)")
        .accessibilityLabel(result.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(result) }
    }

    private func displayHost(_ host: String?) -> String {
        guard let host, !host.isEmpty else { return "Page" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    private func submitSelection() {
        let rows = results
        guard rows.indices.contains(selectedIndex) else {
            if !query.isEmpty { app.commitCommandBar(query) }
            return
        }
        activate(rows[selectedIndex])
    }

    private func activate(_ result: Result) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        func open(_ input: String) {
            if flags.contains(.shift), let origin = app.activeTabID, (app.activeSplit?.tabIDs.count ?? 1) < 4 {
                let tab = app.newTab(activate: false); app.submit(input, on: tab)
                app.activate(origin); app.openSplit(tab.id); app.commandBarPresented = false
            } else { if flags.contains(.command) { app.commandBarCreatesTab = true }; app.commitCommandBar(input) }
        }
        switch result.destination {
        case .tab(let id):
            if !flags.intersection([.command, .shift]).isEmpty, let url = app.tabs.first(where: { $0.id == id })?.url { open(url.absoluteString) }
            else { app.completeCommandBarSwitch(id) }
        case .page(let url), .input(let url):
            open(url)
        case .action(let id):
            app.commandBarPresented = false
            // Chosen from the bar itself, New Tab opens the Resume page rather than the bar again.
            if id == "new-tab" { app.openResumeTab(); return }
            app.commandAction(id)?.run()
        case .ask: app.sendToAsk(query)
        case .attach(let id):
            app.commandContextIDs.append(id)
            if let index = app.commandBarDraft.lastIndex(of: "@") { app.commandBarDraft = String(app.commandBarDraft[..<index]) }
            askOverride = true; app.commandBarFocusRequest += 1
        case .space(let id):
            if let tab = app.activeTab { app.placeTab(tab.id, section: tab.section, spaceID: id) }
            app.dismissCommandBar()
        case .note(let id):
            app.vaultSelectionID = id; app.commandBarPresented = false; app.show(.vault)
        case .thread(let id):
            if let thread = app.graph.threads(spaceID: nil).first(where: { $0.id == id }) { app.resumeThread(thread) }
            app.commandBarPresented = false
        }
    }

    /// Tabs name their verb, actions show their registered shortcut, and the
    /// selected row shows the key that opens it.
    private func rowHint(_ result: Result, selected: Bool) -> String {
        switch result.destination {
        case .tab: return "Switch to Tab"
        case .action(let id):
            let hint = app.commandAction(id)?.hint ?? ""
            return hint.isEmpty && selected ? "↩" : hint
        default: return selected ? "↩" : ""
        }
    }
}

/// Native field editing keeps URL selection and the command keys consistent
/// with macOS without installing an app-wide event monitor.
private struct CommandInput: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let selectAllOnFocus: Bool
    let placeholder: String
    let color: NSColor
    let placeholderColor: NSColor
    let fontSize: CGFloat
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var completion: String?
    var onToggle: () -> Void
    /// Called when the field takes focus; returns text typed before it could (Resume page burst typing).
    var onFocused: () -> String = { "" }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.delegate = context.coordinator
        field.contentType = .URL
        field.isAutomaticTextCompletionEnabled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Search or enter URL")
        field.setAccessibilityIdentifier("commandBarInput")
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.textColor = color
        field.completionSuffix = completion.map { String($0.dropFirst(text.count)) } ?? ""
        field.needsDisplay = true
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: NSFont.systemFont(ofSize: fontSize)]
        )
        field.onFocused = onFocused
        field.requestFocus(focusRequest, selectAll: selectAllOnFocus)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandInput
        init(_ parent: CommandInput) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.insertTab(_:)):
                parent.onToggle()
            case #selector(NSResponder.moveRight(_:)):
                guard Omnibox.acceptsCompletion(parent.text, selection: textView.selectedRange()),
                      let completion = parent.completion else { return false }
                textView.string = completion
                textView.setSelectedRange(NSRange(location: (completion as NSString).length, length: 0))
                parent.text = completion
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}

private final class CommandTextField: NSTextField {
    var completionSuffix = ""
    /// Draws the inline completion's remainder the way selected text looks, as Arc does.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !completionSuffix.isEmpty, let font else { return }
        let x = (stringValue as NSString).size(withAttributes: [.font: font]).width + 2
        guard x < bounds.width else { return }
        let size = (completionSuffix as NSString).size(withAttributes: [.font: font])
        let highlight = NSRect(x: x, y: (bounds.height - size.height) / 2, width: min(size.width, bounds.width - x), height: size.height)
        NSColor.selectedTextBackgroundColor.setFill()
        highlight.fill()
        (completionSuffix as NSString).draw(in: NSRect(x: x, y: 1, width: bounds.width - x, height: bounds.height),
                                            withAttributes: [.font: font, .foregroundColor: textColor ?? NSColor.labelColor])
    }
    private var focusRequest = 0
    private var handledFocusRequest: Int?
    private var selectAllOnFocus = false
    var onFocused: (() -> String)?

    func requestFocus(_ request: Int, selectAll: Bool) {
        focusRequest = request
        selectAllOnFocus = selectAll
        focusIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    private func focusIfNeeded() {
        guard window != nil, handledFocusRequest != focusRequest else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window,
                  self.handledFocusRequest != self.focusRequest,
                  window.makeFirstResponder(self),
                  let editor = self.currentEditor() as? NSTextView else { return }
            self.handledFocusRequest = self.focusRequest
            // Keys typed before the field existed go after the text already in it, in order.
            let buffered = self.onFocused?() ?? ""
            if !buffered.isEmpty {
                let end = (editor.string as NSString).length
                editor.insertText(buffered, replacementRange: NSRange(location: end, length: 0))
            }
            if self.selectAllOnFocus && buffered.isEmpty {
                editor.selectAll(nil)
            } else {
                editor.setSelectedRange(NSRange(location: (self.stringValue as NSString).length, length: 0))
            }
        }
    }
}
