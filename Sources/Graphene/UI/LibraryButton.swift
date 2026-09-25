import SwiftUI

/// Native destinations remain one click away without occupying the tab list.
struct LibraryButton: View {
    @EnvironmentObject var app: AppState
    @State private var presented = false
    var body: some View {
        IconButton("Library", system: "archivebox") { presented.toggle() }
            .popover(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library").font(.system(size: 13, weight: .semibold)).padding(8)
                    entry("Archived tabs", symbol: "archivebox", hint: "⇧⌘A") { app.archivePresented.toggle() }
                    entry("Web", symbol: "globe", hint: "⌘⌥1") { app.show(.web) }
                    entry("Threads", symbol: "point.3.connected.trianglepath.dotted", hint: "⌘⌥2") { app.show(.threads) }
                    entry("Mail", symbol: "envelope", hint: "⌘⌥3") { app.show(.mail) }
                    entry("Vault", symbol: "tray", hint: "⌘⌥4") { app.show(.vault) }
                    entry("Board", symbol: "square.grid.2x2", hint: "⌘⌥5") { app.show(.board) }.disabled(app.isPrivate)
                    Divider().overlay(app.pal.hairline)
                    entry("Downloads", symbol: "arrow.down.circle") { app.downloadsPresented = true }
                }.padding(8).frame(width: 248).foregroundStyle(app.pal.ink).background(app.pal.elev)
            }
    }
    private func entry(_ title: String, symbol: String, hint: String = "", action: @escaping () -> Void) -> some View {
        Button { presented = false; action() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18); Text(title); Spacer(); Text(hint).foregroundStyle(app.pal.ink3)
            }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 30)
        }.buttonStyle(ShellButtonStyle()).accessibilityIdentifier("library.\(title)")
            .accessibilityLabel(title).accessibilityAddTraits(.isButton)
    }
}
