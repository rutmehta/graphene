import SwiftUI

/// Shared native empty/loading/error presentation for browser and library surfaces.
struct SurfaceState<Actions: View>: View {
    @EnvironmentObject var app: AppState
    let symbol: String
    let title: String
    let detail: String
    var loading = false
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 16) {
            if loading { ProgressView().controlSize(.regular).accessibilityLabel(title) }
            else { Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(app.pal.ink3) }
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(app.pal.ink2).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 360)
            actions().padding(.top, 6)
        }.foregroundStyle(app.pal.ink).padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
