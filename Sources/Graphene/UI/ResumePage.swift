import SwiftUI

/// The Resume page's live counts (landing-and-tidy.md §2): the band's status line and the
/// four surface tiles. Pure, so the copy is testable.
struct ResumeSummary: Equatable {
    struct Tile: Equatable, Identifiable {
        let surface: Surface
        let name: String
        let glyph: String
        let detail: String
        var id: Surface { surface }
    }

    /// Tabs with a page in this space (a blank new tab does not count).
    var tabs = 0
    /// Threads in this space.
    var threads = 0
    /// Vault notes saved in this space.
    var notes = 0
    /// Board cards in this space.
    var cards = 0
    /// Gmail has an OAuth client configured.
    var mailConnected = false

    /// "3 threads", "1 note", "0 cards".
    static func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }

    /// "12 tabs · 3 threads · 5 notes · Tuesday 14:05" (weekday and time in the locale's clock).
    func status(now: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEjjmm")
        return [Self.count(tabs, "tab"), Self.count(threads, "thread"), Self.count(notes, "note"), formatter.string(from: now)]
            .joined(separator: " · ")
    }

    /// Threads, Vault, Board, Mail: the four Graphene surfaces, always shown.
    var tiles: [Tile] {
        [Tile(surface: .threads, name: "Threads", glyph: "point.3.connected.trianglepath.dotted", detail: Self.count(threads, "thread")),
         Tile(surface: .vault, name: "Vault", glyph: "tray.full", detail: Self.count(notes, "note")),
         Tile(surface: .board, name: "Board", glyph: "rectangle.3.group", detail: Self.count(cards, "card")),
         Tile(surface: .mail, name: "Mail", glyph: "envelope", detail: mailConnected ? "Read-only" : "Not connected")]
    }
}

/// What the Resume page shows beneath the band and tiles (graphene-identity.md §3.3,
/// landing-and-tidy.md §2). Pure, so the section rules are testable: Continue and Saved here
/// appear only with data, in a fixed order.
struct ResumeSections: Equatable {
    struct ContinueRow: Equatable, Identifiable {
        let id: UUID
        let title: String
        let host: String?
        let pageCount: Int
        let end: Date
        /// The thread's first page on `host`, so the row's favicon is looked up (and fetched) by
        /// that page's origin as the sidebar's is, not matched by host alone.
        var url: URL? = nil
    }
    struct SavedRow: Equatable, Identifiable {
        let id: UUID
        let quote: String
        let sourceTitle: String
        let url: URL
    }

    static let maxContinue = 3
    static let maxSaved = 4

    var continueRows: [ContinueRow] = []
    var savedRows: [SavedRow] = []
    var favoriteIDs: [UUID] = []

    /// Continue and Saved here are both empty: one line of copy sits under the surface tiles.
    var showsEmptyLine: Bool { continueRows.isEmpty && savedRows.isEmpty }
    static let emptyLine = "Open a page and Graphene will keep the thread. Select text and press ⌘D to save it."

    /// - threads: the space's threads (`app.currentThreads`); the newest three are shown.
    /// - notes: all Vault notes; only quotes from a page saved in `spaceID`, newest four.
    /// - favoriteIDs: the space's favorites, shown only while the sidebar is collapsed.
    static func build(threads: [KnowledgeGraph.Thread], notes: [Annotation], spaceID: UUID?,
                      favoriteIDs: [UUID] = [], sidebarCollapsed: Bool) -> ResumeSections {
        let continueRows = threads.filter { !$0.nodes.isEmpty }.sorted { $0.end > $1.end }.prefix(maxContinue).map {
            ContinueRow(id: $0.id, title: $0.title, host: $0.hosts.first, pageCount: $0.nodes.count, end: $0.end, url: firstPage($0))
        }
        let savedRows = notes
            .filter { $0.spaceID == spaceID && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.created > $1.created }
            .compactMap { note -> SavedRow? in
                guard let url = URL(string: note.url), url.scheme == "http" || url.scheme == "https" else { return nil }
                let quote = note.text.split(whereSeparator: \.isNewline).joined(separator: " ")
                return SavedRow(id: note.id, quote: quote, sourceTitle: note.title.isEmpty ? (url.host ?? note.url) : note.title, url: url)
            }
            .prefix(maxSaved)
        return ResumeSections(continueRows: Array(continueRows), savedRows: Array(savedRows),
                              favoriteIDs: sidebarCollapsed ? favoriteIDs : [])
    }

    /// The web page of `thread`'s first host, for its row's favicon.
    static func firstPage(_ thread: KnowledgeGraph.Thread) -> URL? {
        thread.nodes.first { $0.host == thread.hosts.first }.flatMap { FaviconRequest(page: $0.url).url }
    }

    /// "6 pages · 2h ago".
    static func detail(pageCount: Int, end: Date, now: Date) -> String {
        "\(pageCount) \(pageCount == 1 ? "page" : "pages") · \(relative(end, now: now))"
    }

    /// A compact relative time: "just now", "5m ago", "2h ago", "3d ago", then the date.
    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

extension AppState {
    /// A key typed on the Resume page: printable characters without ⌘, ⌃ or ⌥ open the command
    /// bar in new-tab mode, starting with that text. Keys that arrive after that one but before
    /// the bar's field has focus (fast typing) are buffered in order, and the field inserts them
    /// after the first when it takes focus (`takeResumeKeys`). Returns whether the key was taken.
    @discardableResult
    func resumeTyped(_ characters: String, modifiers: EventModifiers = []) -> Bool {
        guard modifiers.isDisjoint(with: [.command, .control, .option]), let scalar = characters.unicodeScalars.first else { return false }
        if commandBarPresented {
            guard let buffer = resumeKeyBuffer else { return false }
            if scalar.value == 0x7F || scalar.value == 0x08 {
                if buffer.isEmpty { if !commandBarDraft.isEmpty { commandBarDraft.removeLast() } } else { resumeKeyBuffer = String(buffer.dropLast()) }
                return true
            }
            guard Self.resumePrintable(scalar) else { return false }
            resumeKeyBuffer = buffer + characters
            return true
        }
        guard Self.resumePrintable(scalar), !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        openCommandBar(newTab: true)
        commandBarDraft = characters
        resumeKeyBuffer = ""
        return true
    }
    /// Not a control character, nor an arrow or function key (those arrive as private-use scalars).
    private static func resumePrintable(_ scalar: Unicode.Scalar) -> Bool {
        !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
    }
    /// The command bar's field took focus: returns the keys buffered since the bar opened from the
    /// Resume page, in typing order, for the field to insert after the first; ends buffering.
    func takeResumeKeys() -> String {
        defer { resumeKeyBuffer = nil }
        return resumeKeyBuffer ?? ""
    }
}

/// The new-tab page: the space band (glyph, name, status, search), the four surface tiles,
/// then Continue, Saved here and (with the sidebar collapsed) the space's favorites.
struct ResumePage: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool

    private var favorites: [Tab] { app.visibleTabs.filter { $0.section == .favorites } }
    private var sections: ResumeSections {
        ResumeSections.build(threads: app.currentThreads, notes: app.vault.annotations, spaceID: app.activeSpaceID,
                             favoriteIDs: favorites.map(\.id), sidebarCollapsed: app.layout == .sidebar && app.sidebarCollapsed)
    }
    private var summary: ResumeSummary {
        ResumeSummary(tabs: app.visibleTabs.filter { $0.url != nil }.count,
                      threads: app.currentThreads.filter { !$0.nodes.isEmpty }.count,
                      notes: app.vault.notes(inSpace: app.activeSpaceID).count,
                      cards: app.boards.items(in: app.activeSpaceID).count,
                      mailConnected: GmailConfig.isConfigured)
    }

    var body: some View {
        let sections = sections, summary = summary
        ScrollView {
            VStack(spacing: 0) {
                band(summary)
                VStack(alignment: .leading, spacing: ShellLayout.newTabGap) {
                    surfacesRow(summary)
                    if sections.showsEmptyLine { emptyLine }
                    if !sections.continueRows.isEmpty { continueSection(sections.continueRows) }
                    if !sections.savedRows.isEmpty { savedSection(sections.savedRows) }
                    if !sections.favoriteIDs.isEmpty { favoritesSection(sections.favoriteIDs) }
                }
                .frame(maxWidth: ShellLayout.newTabColumnWidth)
                .padding(.horizontal, ShellLayout.newTabGap)
                .padding(.vertical, ShellLayout.newTabGap)
                .frame(maxWidth: .infinity)
            }
        }
        .background(app.pal.pageBg)
        // Typing goes straight to the command bar in new-tab mode, starting with the key pressed.
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { press in app.resumeTyped(press.characters, modifiers: press.modifiers) ? .handled : .ignored }
        .task { try? await Task.sleep(for: .milliseconds(100)); if !Task.isCancelled && !app.commandBarPresented { focused = true } }
        // "+ New Tab" may land on a Resume page already on screen: take the keyboard again.
        .onChange(of: app.resumeFocusRequest) { _, _ in if !app.commandBarPresented { focused = true } }
        .onChange(of: app.activeTabID) { _, _ in if !app.commandBarPresented { focused = true } }
    }

    /// The space band: the space's chrome gradient over `pageBg` with the lattice as texture,
    /// fading into the page at its bottom edge. Glyph, name and status left; search right.
    private func band(_ summary: ResumeSummary) -> some View {
        ZStack {
            LinearGradient(colors: [app.pal.bandTop, app.pal.bandBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Lattice()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: [app.pal.bandFade, app.pal.pageBg], startPoint: .top, endPoint: .bottom)
                    .frame(height: ShellLayout.newTabBandFade)
            }.allowsHitTesting(false)
            HStack(spacing: ShellLayout.sectionGap) {
                VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                    HStack(spacing: ShellLayout.iconGap) {
                        bandGlyph
                        Text(app.activeSpace.name).font(ShellType.display).foregroundStyle(app.pal.ink).lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(summary.status(now: context.date)).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("newTab.space")
                Spacer(minLength: ShellLayout.sectionGap)
                searchRow.frame(maxWidth: ShellLayout.newTabSearchWidth)
            }
            .frame(maxWidth: ShellLayout.newTabColumnWidth)
            .padding(.horizontal, ShellLayout.newTabGap)
        }
        .frame(height: ShellLayout.newTabBandHeight)
        .frame(maxWidth: .infinity)
        .background(app.pal.pageBg)
    }

    /// The space's emoji or SF Symbol at 24pt, resolved as the sidebar's `SpaceGlyph` does.
    private var bandGlyph: some View {
        let icon = app.activeSpace.icon
        return Group {
            if let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil { Text(String(icon.prefix(2))) }
            else { Image(systemName: icon ?? "circle.hexagongrid.fill") }
        }.font(ShellType.bandGlyph).foregroundStyle(app.pal.ink2).accessibilityHidden(true)
    }

    private var searchRow: some View {
        Button { app.openCommandBar(newTab: true) } label: {
            HStack(spacing: ShellLayout.sectionGap) {
                Image(systemName: "magnifyingglass").font(ShellType.glyph)
                Text(app.layout == .topTabs ? "Search or ask" : "Search or enter a URL").font(ShellType.row).lineLimit(1)
                Spacer(minLength: 0)
                Text("⌘T").font(ShellType.label).padding(.horizontal, ShellLayout.rowInsetLeading / 2).padding(.vertical, PageToolbarGeometry.controlGap)
                    .background(app.pal.rowHover, in: RoundedRectangle(cornerRadius: ShellLayout.chipRadius))
            }.foregroundStyle(app.pal.ink3).padding(.horizontal, ShellLayout.sectionGap).frame(height: ShellLayout.commandRowHeight)
                .background(app.pal.fill, in: RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("newTab.search")
            .accessibilityLabel("Search or enter a URL").accessibilityAddTraits(.isButton)
    }

    /// Threads, Vault, Board and Mail as four equal tiles with live counts.
    private func surfacesRow(_ summary: ResumeSummary) -> some View {
        HStack(spacing: ShellLayout.favoriteGap) {
            ForEach(summary.tiles) { tile in ResumeSurfaceTile(tile: tile) }
        }
    }

    private var emptyLine: some View {
        Text(ResumeSections.emptyLine).font(ShellType.secondary).foregroundStyle(app.pal.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("newTab.empty")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(ShellType.label).foregroundStyle(app.pal.ink3)
    }

    private func continueSection(_ rows: [ResumeSections.ContinueRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("Continue")
                Spacer()
                Button("All threads") { app.show(.threads) }.font(ShellType.caption).foregroundStyle(app.pal.ink3).buttonStyle(.plain)
                    .accessibilityIdentifier("newTab.allThreads").accessibilityLabel("All threads").accessibilityAddTraits(.isButton)
            }.padding(.bottom, ShellLayout.rowInsetLeading)
            ForEach(rows) { row in ResumeContinueRow(row: row) }
        }
    }

    private func savedSection(_ rows: [ResumeSections.SavedRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Saved here").padding(.bottom, ShellLayout.rowInsetLeading)
            ForEach(rows) { row in ResumeSavedRow(row: row) }
        }
    }

    private func favoritesSection(_ ids: [UUID]) -> some View {
        let tiles = ids.compactMap { id in favorites.first { $0.id == id } }
        let minimum = ShellLayout.favoriteTileWidth(contentWidth: ShellLayout.sidebarContentWidth(ShellLayout.sidebarDefault))
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Pinned in this space").padding(.bottom, ShellLayout.rowInsetLeading)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: ShellLayout.favoriteGap)], spacing: ShellLayout.favoriteGap) {
                ForEach(tiles) { tab in ResumeFavoriteTile(tab: tab) }
            }
        }
    }
}

/// A surface tile: 20pt glyph, the surface's name and its live count. Mail without an OAuth
/// client opens Settings → Mail instead of the Mail view.
private struct ResumeSurfaceTile: View {
    @EnvironmentObject var app: AppState
    let tile: ResumeSummary.Tile
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                Image(systemName: tile.glyph).font(ShellType.surfaceGlyph).foregroundStyle(app.pal.ink2)
                Spacer(minLength: 0)
                Text(tile.name).font(ShellType.row).foregroundStyle(app.pal.ink).lineLimit(1)
                Text(tile.detail).font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
            }
            .padding(ShellLayout.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ShellLayout.surfaceTileHeight)
            .background(hovering ? app.pal.tileFillHover : app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.favoriteRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.hover.animation) { hovering = inside } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(tile.detail)").accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityIdentifier(tile.surface == .threads ? "newTab.threads" : "newTab.surface.\(tile.surface.rawValue)")
    }
    private func open() {
        if tile.surface == .mail && !GmailConfig.isConfigured {
            app.settingsPage = "Mail"; app.settingsPresented = true
        } else {
            app.show(tile.surface)
        }
    }
}

/// A "Continue" row: the map node treatment (favicon, title) plus the page count and age.
private struct ResumeContinueRow: View {
    @EnvironmentObject var app: AppState
    let row: ResumeSections.ContinueRow
    @State private var hovering = false
    var body: some View {
        Button { if let thread = app.currentThreads.first(where: { $0.id == row.id }) { app.openThread(thread) } } label: {
            HStack(spacing: ShellLayout.iconGap) {
                Favicon(host: row.host, size: ShellLayout.iconSize, url: row.url).frame(width: ShellLayout.iconSlot)
                Text(row.title).font(ShellType.row).foregroundStyle(app.pal.ink).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(ResumeSections.detail(pageCount: row.pageCount, end: row.end, now: context.date))
                        .font(ShellType.secondary).foregroundStyle(app.pal.ink3).lineLimit(1)
                }.fixedSize()
                Spacer(minLength: ShellLayout.iconGap)
                if hovering { Text("Resume").font(ShellType.label).foregroundStyle(app.pal.ink3) }
            }
            .padding(.horizontal, ShellLayout.rowInsetLeading)
            .frame(height: ShellLayout.rowHeight)
            .background(hovering ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.hover.animation) { hovering = inside } }
        .accessibilityIdentifier("newTab.thread.\(row.id)").accessibilityLabel(row.title).accessibilityAddTraits(.isButton)
    }
}

/// A "Saved here" row: the Vault quote treatment in `quoteSmall` with the left rule.
private struct ResumeSavedRow: View {
    @EnvironmentObject var app: AppState
    let row: ResumeSections.SavedRow
    @State private var hovering = false
    var body: some View {
        Button { app.openSource(url: row.url, passage: row.quote) } label: {
            HStack(alignment: .top, spacing: ShellLayout.iconGap) {
                Rectangle().fill(app.pal.quoteRule).frame(width: ShellLayout.hairline)
                VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                    Text(row.quote).font(ShellType.quoteSmall).foregroundStyle(app.pal.ink2).lineLimit(1)
                    Text(row.sourceTitle).font(ShellType.secondary).foregroundStyle(app.pal.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.vertical, PageToolbarGeometry.controlGap)
            .frame(minHeight: ShellLayout.rowHeight)
            .background(hovering ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.hover.animation) { hovering = inside } }
        .accessibilityIdentifier("newTab.note.\(row.id)").accessibilityLabel("\(row.quote), \(row.sourceTitle)").accessibilityAddTraits(.isButton)
    }
}

/// A favorite tile, shown on the Resume page while the sidebar is collapsed.
private struct ResumeFavoriteTile: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    @State private var hovering = false
    var body: some View {
        Button { app.activate(tab.id) } label: {
            Favicon(host: tab.url?.host, size: ShellLayout.favoriteIconSize, url: tab.url)
                .frame(maxWidth: .infinity).frame(height: ShellLayout.favoriteHeight)
                .background(hovering ? app.pal.rowHover : app.pal.tileFill, in: RoundedRectangle(cornerRadius: ShellLayout.favoriteRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.displayTitle)
        .accessibilityIdentifier("newTab.favorite.\(tab.id)").accessibilityLabel(tab.displayTitle).accessibilityAddTraits(.isButton)
    }
}
