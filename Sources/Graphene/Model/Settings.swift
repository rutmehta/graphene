import Foundation

enum ChatPanelMode: String, Codable, CaseIterable { case floating, docked }
enum AddressPlacement: String, Codable, CaseIterable { case onPage, sidebar }

/// Optional storage keeps settings written by earlier versions readable.
struct Settings: Codable, Equatable {
    var ai: AISettings?
    var customSearchURL: String?
    var downloadsFolder: String?
    var startupBlank: Bool?
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
    private var address: AddressPlacement?
    var addressPlacement: AddressPlacement { get { address ?? .onPage } set { address = newValue } }
    private var completed: Bool?
    private var routes: [RoutingRule]?
    private var shortcuts: [String: CommandShortcut]?
    var shortcutOverrides: [String: CommandShortcut] { get { shortcuts ?? [:] } set { shortcuts = newValue } }
    var routingRules: [RoutingRule] { get { routes ?? [] } set { routes = newValue } }
    var pageGutter: Bool { get { gutter ?? true } set { gutter = newValue } }
    var askWidth: Double { get { Self.clampedAskWidth(panelWidth ?? Double(ShellLayout.chatWidth)) } set { panelWidth = Self.clampedAskWidth(newValue) } }
    private static func clampedAskWidth(_ width: Double) -> Double {
        min(Double(ShellLayout.chatWidthRange.upperBound), max(Double(ShellLayout.chatWidthRange.lowerBound), width))
    }
    var onboardingComplete: Bool { get { completed ?? false } set { completed = newValue } }
}
