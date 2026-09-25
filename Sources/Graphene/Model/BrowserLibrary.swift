import Combine
import Foundation

/// Shared collections; selection and presentation belong to each window's AppState.
@MainActor
final class BrowserLibrary: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var settings = Settings()
    @Published var profiles: [Profile] = []
    @Published var spaces = [SpaceInfo(id: UUID(), name: "Research", color: .tide), SpaceInfo(id: UUID(), name: "Personal", color: .iris)]
    @Published var folders: [TabFolder] = []
    @Published var archivedTabs: [AppState.SessionTab] = []
    @Published var splits: [TabSplit] = []
    @Published var excludedHosts: Set<String> = []
    @Published var pausedSpaces: Set<UUID> = []
    @Published var archiveHours: Double = 12
    @Published var discardMinutes: Double = 30
    @Published var littleEnabled = false
    @Published var layout: BrowserLayout = .sidebar
    @Published var searchSuggestions = true
    @Published var littlePinnedLinks = false
    var windows: [WeakBrowserState] = []
    var states: [AppState] { windows.compactMap(\.value) }
}

@MainActor
final class WeakBrowserState {
    weak var value: AppState?
    init(_ value: AppState) { self.value = value }
}
