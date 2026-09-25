import SwiftUI
import AppKit
import WebKit

/// Native Settings scene (arc-look.md §3.7): a 180pt page list, a `title` heading and
/// grouped `Form` pages in `body` type with `secondary` help text. Colour is limited to
/// the system materials, the palette's ink ramp and `accent`.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var mail: MailStore
    @State private var host = ""
    @State private var clearRange = 24.0
    @State private var cookies = false
    @State private var caches = true
    @State private var confirmClear = false
    @State private var status = ""
    @State private var searchTemplate = ""
    private let pages = ["General", "Appearance", "Spaces", "Sites", "Boosts", "Profiles", "Import", "Privacy", "Search", "AI", "Shortcuts", "Mail", "Advanced"]
    var body: some View {
        HStack(spacing: 0) {
            List(pages, id: \.self, selection: $app.settingsPage) { page in
                Button { app.settingsPage = page } label: {
                    Text(page).font(ShellType.body).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).tag(page)
                    .accessibilityIdentifier("settings.page.\(page)").accessibilityLabel(page).accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(app.settingsPage == page ? [.isSelected] : [])
            }.listStyle(.sidebar).frame(width: 180)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(app.settingsPage).font(ShellType.title).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
                page.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !status.isEmpty || app.settingsError != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if !status.isEmpty { SettingsHelp(status) }
                        if let error = app.settingsError { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger) }
                    }.padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 820, height: 620).font(ShellType.body).tint(app.pal.accent)
            .environment(\.colorScheme, app.pal.isDark ? .dark : .light)
            .preferredColorScheme(app.pal.isDark ? .dark : .light)
            .onDisappear { app.persist() }
            .onChange(of: app.mode) { _, _ in app.persist() }
            .onChange(of: app.searchEngine) { _, _ in app.persist() }
            .confirmationDialog("Clear website data?", isPresented: $confirmClear) {
                Button("Clear selected data", role: .destructive) { clearData() }
            } message: { Text("Cookies can sign you out. This does not delete Vault notes, Boards or Threads.") }
    }
    @ViewBuilder private var page: some View {
        switch app.settingsPage {
        case "General":
            Form {
                Section("Default browser") {
                    Text("Open web links in Graphene.")
                    Button("Make default browser…") { app.requestDefaultBrowser() }
                }
                Section("Tabs") {
                    Picker("Auto-archive inactive Today tabs", selection: $app.archiveHours) {
                        Text("12 hours").tag(12.0); Text("24 hours").tag(24.0); Text("7 days").tag(168.0); Text("Never").tag(0.0)
                    }
                    Picker("Discard background pages", selection: $app.discardMinutes) {
                        Text("30 minutes").tag(30.0); Text("1 hour").tag(60.0); Text("Never").tag(0.0)
                    }
                    Toggle("Start on a new tab (keep restored tabs)", isOn: Binding(get: { app.settings.startupBlank ?? false }, set: { app.settings.startupBlank = $0 }))
                }
                Section {
                    Text(app.settings.downloadsFolder ?? "Downloads").textSelection(.enabled)
                    Button("Choose downloads folder…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { app.settings.downloadsFolder = url.path }
                    }
                } header: { Text("Downloads") } footer: {
                    SettingsHelp("Downloads ask where to save each file, starting in your chosen folder. Pins and playing tabs are protected from automatic archiving.")
                }
            }
        case "Appearance":
            Form {
            Picker("Layout", selection: $app.layout) { ForEach(BrowserLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
                .accessibilityIdentifier("settings.appearance.layout").accessibilityLabel("Layout")
            Picker("Appearance", selection: $app.mode) {
                Text("System").tag(ThemeMode.automatic); Text("Light").tag(ThemeMode.light); Text("Dark").tag(ThemeMode.dark)
            }
            .accessibilityIdentifier("settings.appearance.mode").accessibilityLabel("Appearance")
            Toggle("Page frame gutter", isOn: $app.settings.pageGutter)
                .accessibilityIdentifier("settings.appearance.gutter").accessibilityLabel("Page frame gutter")
            Picker("Address bar", selection: $app.settings.addressPlacement) {
                Text("On page").tag(AddressPlacement.onPage); Text("In sidebar").tag(AddressPlacement.sidebar)
            }.accessibilityIdentifier("settings.appearance.address").accessibilityLabel("Address bar")
            Picker("Chat panel", selection: $app.settings.chatPanelMode) {
                Text("Floating").tag(ChatPanelMode.floating); Text("Docked").tag(ChatPanelMode.docked)
            }.accessibilityIdentifier("settings.appearance.chatPanel").accessibilityLabel("Chat panel")
            HStack { Text("Chat panel width"); Slider(value: $app.settings.askWidth, in: 360...560, step: 10).accessibilityIdentifier("settings.appearance.askWidth").accessibilityLabel("Chat panel width"); Text("\(Int(app.settings.askWidth)) pt") }
            Picker("Page font", selection: Binding(get: { app.settings.pageFont ?? .website }, set: { value in
                app.settings.pageFont = value
                for tab in app.tabs { (tab.loadedEngine as? WKWebEngine)?.refreshBoosts() }
            })) { ForEach(PageFont.allCases, id: \.self) { Text($0.title).tag($0) } }
                .accessibilityIdentifier("settings.appearance.font").accessibilityLabel("Page font")
            SettingsHelp("Page font changes article text, not browser chrome or code blocks. Choose Website default to restore site typography. Browser controls use the system font. Reduce Transparency and Reduce Motion follow macOS Accessibility settings.")
            }
        case "Spaces": RoutingSettingsView()
        case "Boosts": BoostSettings(store: app.boosts)
        case "Profiles": ProfileSettings()
        case "Import": ImportSettings()
        case "Sites":
            Form {
                Section {
                    if let error = app.sites.error { Text(error).foregroundStyle(app.pal.danger) }
                    SettingsHelp("Per-site zoom, permissions and blocking are available from the lock in the address toolbar. Settings are saved in sites.json.")
                }
                Section {
                    HStack {
                        TextField("example.com", text: $host).textFieldStyle(.roundedBorder)
                        Button("Exclude") { let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); if !value.isEmpty { app.excludedHosts.insert(value); app.persist(); host = "" } }.disabled(host.isEmpty)
                    }
                    ForEach(app.excludedHosts.sorted(), id: \.self) { value in
                        HStack { Text(value); Spacer(); Button("Allow capture") { app.excludedHosts.remove(value); app.persist() } }
                    }
                } header: { Text("Capture exclusions") } footer: {
                    SettingsHelp("Excluded sites remain browsable, but Graphene does not capture their history or text.")
                }
            }
        case "Privacy":
            Form {
                Section {
                    Toggle("Block ads & trackers", isOn: Binding(get: { app.settings.contentBlocking ?? true }, set: { value in
                        app.settings.contentBlocking = value
                        for tab in app.tabs { if let engine = tab.loadedEngine as? WKWebEngine { Task { await engine.applyBlocking(host: tab.url?.host ?? "") } } }
                    }))
                    SettingsHelp("Bundled EasyList-derived network rules. Site controls can override this setting. Reload pages after changing blocking; WebKit does not expose a blocked-request count.")
                }
                Section {
                    Toggle("Pause capture in this space", isOn: Binding(get: { app.pausedSpaces.contains(app.activeSpaceID) }, set: { if $0 { app.pausedSpaces.insert(app.activeSpaceID) } else { app.pausedSpaces.remove(app.activeSpaceID) }; app.persist() }))
                    SettingsHelp("Spaces assigned to the same profile share cookies. Private windows use an ephemeral store and do not save browsing knowledge. Cookie behavior follows WebKit’s built-in tracking prevention; Graphene does not send a Do Not Track header.")
                }
                Section("Clear website data") {
                    Picker("Modified within", selection: $clearRange) { Text("Past hour").tag(1.0); Text("Past day").tag(24.0); Text("Past week").tag(168.0); Text("All time").tag(0.0) }
                    Toggle("Cookies and website storage (signs you out)", isOn: $cookies)
                    Toggle("Caches", isOn: $caches)
                    Button("Clear selected data…") { confirmClear = true }.disabled(!cookies && !caches)
                }
            }
        case "Search":
            Form {
                Section {
                    Picker("Search engine", selection: $app.searchEngine) { ForEach(SearchEngine.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Toggle("Search suggestions", isOn: $app.searchSuggestions)
                    SettingsHelp("Suggestions send search text to your selected engine. URLs and tab mentions stay local.")
                }
                Section {
                    TextField("Custom search URL with %s", text: $searchTemplate).textFieldStyle(.roundedBorder).onAppear { searchTemplate = app.settings.customSearchURL ?? "" }
                    HStack {
                        Button("Use custom engine") {
                            guard Omnibox.resolve("test query", customSearchURL: searchTemplate) != nil else { status = "Use an http(s) URL containing %s."; return }
                            app.settings.customSearchURL = searchTemplate; status = "Custom search enabled. Suggestions are disabled for custom engines."
                        }
                        Button("Use selected built-in engine") { app.settings.customSearchURL = nil; searchTemplate = ""; status = "Using the selected built-in engine." }
                    }
                } header: { Text("Custom engine") } footer: {
                    SettingsHelp(app.settings.customSearchURL.map { "Active: \($0)" } ?? "Active: \(app.searchEngine.rawValue)")
                }
            }
        case "AI":
            AISettingsView(root: app.dataDirectory)
        case "Shortcuts": ShortcutSettingsView()
        case "Mail":
            Form {
                Section {
                    Label(mail.isConnected ? "Connected · read-only" : "Disconnected · read-only", systemImage: "envelope")
                    Text("Gmail is read-only. Graphene cannot send, archive or delete mail.")
                    if mail.isBusy { ProgressView("Connecting…") }
                    if let error = mail.errorText { Text(error).foregroundStyle(app.pal.danger) }
                    if mail.isConnected { Button("Disconnect Gmail") { mail.disconnect() } }
                    else { Button("Connect Gmail…") { mail.connect() }.disabled(!mail.isConfigured || mail.isBusy) }
                    if !mail.isConfigured { SettingsHelp("Gmail OAuth is not configured in this build. You can still open Gmail on the web.") }
                    Button("Open Gmail on the web") { app.openTab(url: URL(string: "https://mail.google.com")!, parent: nil, activate: true) }
                }
            }
        default:
            Form {
                Section("Data folder") {
                    Text(app.dataDirectory.path).textSelection(.enabled)
                    Button("Open in Finder") { NSWorkspace.shared.open(app.dataDirectory) }
                }
                Section {
                    HStack { Button("Export settings JSON…") { transferSettings(importing: false) }; Button("Import settings JSON…") { transferSettings(importing: true) } }
                } header: { Text("Settings file") } footer: {
                    SettingsHelp("Debug driver: \(ProcessInfo.processInfo.environment["GRAPHENE_DEBUG"] == "1" ? "enabled" : "disabled"). Launch with GRAPHENE_DEBUG=1 and write commands to cmd.txt inside the isolated data folder. It is never enabled by a webpage.")
                }
            }
        }
    }
    private func clearData() {
        guard let engine = app.activeTab?.engine as? WKWebEngine else { status = "Open a browser tab first."; return }
        let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache]
        var types: Set<String> = caches ? cacheTypes : []
        if cookies { types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes)) }
        let since = clearRange == 0 ? Date.distantPast : Date().addingTimeInterval(-clearRange * 3600)
        engine.webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: since) { status = "Selected website data cleared." }
    }
    private func transferSettings(importing: Bool) {
        do {
            if importing {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let imported = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
                app.importSettings(imported); status = "Settings imported. Existing spaces and tabs were kept."
            } else {
                let panel = NSSavePanel(); panel.nameFieldStringValue = "Graphene settings.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(app.exportedSettings).write(to: url, options: .atomic); status = "Settings exported."
            }
        } catch { status = error.localizedDescription }
    }
}

/// Settings help and status text: `secondary` type in `ink3`.
struct SettingsHelp: View {
    @EnvironmentObject var app: AppState
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(ShellType.secondary).foregroundStyle(app.pal.ink3).fixedSize(horizontal: false, vertical: true)
    }
}

/// A modal sheet presented from Settings: `title` heading, `body` controls.
struct SettingsSheet<Content: View>: View {
    @EnvironmentObject var app: AppState
    let title: String
    let width: CGFloat
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(ShellType.title)
            content()
        }.font(ShellType.body).padding(24).frame(width: width).tint(app.pal.accent)
    }
}

struct RoutingSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var pattern = ""
    @State private var destination: UUID?
    @State private var testURL = ""
    var body: some View {
        Form {
            Section("Spaces") {
                ForEach(app.spaces) { space in
                    HStack {
                        SpaceGlyph(icon: space.icon)
                        TextField("Space name", text: Binding(get: { app.spaces.first { $0.id == space.id }?.name ?? space.name }, set: { app.renameSpace(space.id, name: $0) }))
                        Button("Theme…") { app.selectSpace(space.id); app.spaceEditorPresented = true }
                        Button { if let index = app.spaces.firstIndex(where: { $0.id == space.id }), index > 0 { app.moveSpace(space.id, before: app.spaces[index - 1].id) } } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move \(space.name) up")
                    }
                }
                Button("New Space") { app.createSpace() }
            }
            Section {
                ForEach(app.settings.routingRules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(get: { app.settings.routingRules.first { $0.id == rule.id }?.enabled ?? false }, set: { value in var rules = app.settings.routingRules; if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i].enabled = value }; app.settings.routingRules = rules })).labelsHidden()
                        Text(rule.pattern).lineLimit(2)
                        Spacer()
                        Text(app.spaces.first { $0.id == rule.spaceID }?.name ?? "Missing space").foregroundStyle(app.pal.ink3)
                        Button { app.settings.routingRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete routing rule")
                    }
                }
                TextField("https://example.com/*", text: $pattern).textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Open in", selection: $destination) { ForEach(app.spaces) { Text($0.name).tag(Optional($0.id)) } }
                    Button("Add Rule") { if let destination { app.settings.routingRules.append(RoutingRule(pattern: pattern, spaceID: destination)); pattern = "" } }.disabled(pattern.isEmpty || destination == nil)
                }
                TextField("Test a URL without opening it", text: $testURL).textFieldStyle(.roundedBorder)
                if let url = URL(string: testURL), !testURL.isEmpty {
                    let rule = app.settings.routingRules.first { rule in rule.matches(url) && app.spaces.contains { $0.id == rule.spaceID } }
                    SettingsHelp(rule.flatMap { rule in app.spaces.first { $0.id == rule.spaceID }?.name }.map { "Routes to \($0)" } ?? "No rule matches")
                }
            } header: { Text("Routing · Air Traffic Control") } footer: {
                SettingsHelp("First matching rule wins. Match the whole URL with * (any text) and ? (one character). Routed links switch to the destination space.")
            }
        }.onAppear { destination = app.activeSpaceID }
            .sheet(isPresented: $app.spaceEditorPresented) { SpaceEditor().environmentObject(app) }
    }
}

struct ShortcutSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var editing: String?
    @State private var draft = CommandShortcut(key: "")
    @State private var error = ""
    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Copy as Markdown") {
                        let text = "| Command | Shortcut |\n| --- | --- |\n" + app.allCommandActions.map { "| \($0.title) | \($0.hint) |" }.joined(separator: "\n")
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    }
                    Button("Reset to defaults") { app.settings.shortcutOverrides = [:] }
                }
                SettingsHelp("macOS may own Control-number shortcuts. Websites can also intercept keys. Standard system editing shortcuts stay reserved.")
            }
            ForEach(["File", "Find", "View & Settings", "Spaces", "Tabs & History", "Knowledge"], id: \.self) { group in
                Section(group) {
                    ForEach(app.allCommandActions.filter { $0.group == group }) { action in
                        HStack {
                            Text(action.title); Spacer()
                            Button(action.hint.isEmpty ? "Unassigned" : action.hint) { editing = action.id; draft = CommandShortcut(action: action); error = "" }
                        }
                    }
                }
            }
        }.sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            SettingsSheet(title: "Change shortcut", width: 400) {
                TextField("Key (empty to unassign)", text: $draft.key)
                HStack { Toggle("⌘", isOn: $draft.command); Toggle("⌥", isOn: $draft.option); Toggle("⌃", isOn: $draft.control); Toggle("⇧", isOn: $draft.shift) }
                if !error.isEmpty { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.danger) }
                HStack { Button("Cancel") { editing = nil }; Spacer(); Button("Save") { if let id = editing { draft.key = draft.key.lowercased(); if let issue = app.remapCommand(id, to: draft) { error = issue } else { editing = nil } } } }
            }
        }
    }
}

extension AppState {
    func requestDefaultBrowser() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.notify(error.localizedDescription); return }
                NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https") { error in
                    Task { @MainActor in self.notify(error?.localizedDescription ?? "Default browser updated") }
                }
            }
        }
    }
}
