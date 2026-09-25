import SwiftUI

/// Shared native empty/loading/error presentation for browser and library surfaces.
/// The empty Threads and Vault states draw the hex lattice in place of the symbol
/// (graphene-identity.md §3.6); every other state keeps its symbol.
struct SurfaceState<Actions: View>: View {
    @EnvironmentObject var app: AppState
    let symbol: String
    let title: String
    let detail: String
    var loading = false
    /// Draw the lattice instead of the symbol; `nil` decides from the surface (`showsLattice`).
    var lattice: Bool? = nil
    @ViewBuilder var actions: () -> Actions

    /// Width of the detail text and of the lattice band above it.
    static var contentWidth: CGFloat { ShellLayout.siteControlsWidth + 2 * ShellLayout.newTabGap }

    /// Only the empty Threads and Vault surfaces carry the lattice: not loading, and not
    /// an error (error states use an `exclamationmark` symbol).
    static func showsLattice(surface: Surface, symbol: String, loading: Bool) -> Bool {
        guard !loading, !symbol.hasPrefix("exclamationmark") else { return false }
        return surface == .threads || surface == .vault
    }

    private var drawsLattice: Bool {
        lattice ?? Self.showsLattice(surface: app.activeSurface, symbol: symbol, loading: loading)
    }

    var body: some View {
        VStack(spacing: ShellLayout.sectionGap) {
            if loading { ProgressView().controlSize(.regular).accessibilityLabel(title) }
            else if drawsLattice { Lattice().frame(width: Self.contentWidth, height: Lattice.bandHeight) }
            else { Image(systemName: symbol).font(ShellType.display.weight(.light)).foregroundStyle(app.pal.ink3) }
            Text(title).font(ShellType.display)
            Text(detail).font(ShellType.body).foregroundStyle(app.pal.ink2).multilineTextAlignment(.center)
                .lineSpacing(ShellType.rowLineSpacing).frame(maxWidth: Self.contentWidth)
            actions().padding(.top, ShellLayout.windowGap)
        }.foregroundStyle(app.pal.ink).padding(ShellLayout.peekInset).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
