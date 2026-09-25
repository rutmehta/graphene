import Foundation

enum ChatPanelMode: String, Codable, CaseIterable { case floating, docked }

/// Optional storage keeps settings written by earlier versions readable.
struct Settings: Codable, Equatable {
    var ai: AISettings?
    var customSearchURL: String?
    var downloadsFolder: String?
    var startupBlank: Bool?
    var compactSidebar: Bool?
    var layout: BrowserLayout?
    var appearance: ThemeMode?
    var searchEngine: SearchEngine?
    var suggestions: Bool?
    var archiveHours: Double?
    var discardMinutes: Double?
    var spaces: [SpaceInfo]?
    var excludedHosts: Set<String>?
    var contentBlocking: Bool?
    var reader: ReaderOptions?
    var pageFont: PageFont?
    private var gutter: Bool?
    private var panelWidth: Double?
    private var panelMode: ChatPanelMode?
    var chatPanelMode: ChatPanelMode { get { panelMode ?? .floating } set { panelMode = newValue } }
    private var completed: Bool?
    private var routes: [RoutingRule]?
    private var shortcuts: [String: CommandShortcut]?
    var shortcutOverrides: [String: CommandShortcut] { get { shortcuts ?? [:] } set { shortcuts = newValue } }
    var routingRules: [RoutingRule] { get { routes ?? [] } set { routes = newValue } }
    var pageGutter: Bool { get { gutter ?? true } set { gutter = newValue } }
    var askWidth: Double { get { min(560, max(360, panelWidth ?? 420)) } set { panelWidth = min(560, max(360, newValue)) } }
    var onboardingComplete: Bool { get { completed ?? false } set { completed = newValue } }
}
