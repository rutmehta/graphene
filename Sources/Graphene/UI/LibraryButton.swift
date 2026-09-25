import SwiftUI

/// Native destinations remain one click away without occupying the tab list.
struct LibraryButton: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        SidebarGlyphButton("Library", system: "books.vertical", identifier: "sidebar.library") { app.libraryPresented.toggle() }
            .popover(isPresented: $app.libraryPresented) { LibraryMenu { app.libraryPresented = false } }
    }
}

/// The page toolbar's Library glyph (arc-look.md §3.2): the same popover, anchored to the toolbar.
struct ToolbarLibraryButton: View {
    @EnvironmentObject var app: AppState
    @State private var presented = false
    static let title = "Library"
    static let glyph = "books.vertical"
    var body: some View {
        ToolbarGlyphButton(title: Self.title, system: Self.glyph, on: presented, identifier: "toolbar.library") { presented.toggle() }
            .popover(isPresented: $presented, arrowEdge: .bottom) { LibraryMenu { presented = false } }
    }
}

/// The Library popover's list: Archived tabs, Web, the four library surfaces, Downloads.
struct LibraryMenu: View {
    @EnvironmentObject var app: AppState
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Library").font(ShellType.label).foregroundStyle(app.pal.ink3).padding(ShellLayout.rowInsetLeading)
            entry("Archived tabs", symbol: "archivebox", hint: "⇧⌘A") { app.archivePresented.toggle() }
            entry("Web", symbol: "globe", hint: "⌘⌥1") { app.show(.web) }
            entry("Threads", symbol: "point.3.connected.trianglepath.dotted", hint: "⌘⌥2") { app.show(.threads) }
            entry("Mail", symbol: "envelope", hint: "⌘⌥3") { app.show(.mail) }
            entry("Vault", symbol: "tray", hint: "⌘⌥4") { app.show(.vault) }
            entry("Board", symbol: "square.grid.2x2", hint: "⌘⌥5") { app.show(.board) }.disabled(app.isPrivate)
            Divider().overlay(app.pal.hairline)
            entry("Downloads", symbol: "arrow.down.circle") { app.downloadsPresented = true }
        }.padding(ShellLayout.rowInsetLeading).frame(width: 248).foregroundStyle(app.pal.ink).background(app.pal.elev)
    }
    private func entry(_ title: String, symbol: String, hint: String = "", action: @escaping () -> Void) -> some View {
        Button { close(); action() } label: {
            HStack(spacing: ShellLayout.iconGap) {
                Image(systemName: symbol).frame(width: ShellLayout.iconSlot); Text(title); Spacer(); Text(hint).font(ShellType.label).foregroundStyle(app.pal.ink3)
            }.font(ShellType.row).padding(.horizontal, ShellLayout.rowInsetLeading).frame(maxWidth: .infinity).frame(height: ShellLayout.controlSize)
                .contentShape(Rectangle())
        }.buttonStyle(ShellButtonStyle()).accessibilityIdentifier("library.\(title)")
            .accessibilityLabel(title).accessibilityAddTraits(.isButton)
    }
}
