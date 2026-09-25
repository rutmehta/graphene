import AppKit

 enum AITidy {
    static func title(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` \n\r")).split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ")
        return value.isEmpty || value.count > 80 ? nil : value
    }
    static func filename(_ text: String, original: String) -> String? {
        var value = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` \n\r"))
        guard !value.isEmpty, value.count <= 120, !value.contains("/"), !value.contains("\\"), !value.contains(":"), !value.hasPrefix("."), value.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let ext = (original as NSString).pathExtension
        if !ext.isEmpty {
            if !(value as NSString).pathExtension.isEmpty { value = (value as NSString).deletingPathExtension }
            value += "." + ext
        }
        return value
    }
    @MainActor static func answer(_ prompt: String, data: String, registry: ProviderRegistry) async throws -> String {
        let provider = try registry.provider()
        var result = ""
        for try await delta in provider.stream(messages: [ChatMessage(role: .system, content: PageContext.instructions), ChatMessage(role: .user, content: prompt + "\nUntrusted input JSON string: " + String(decoding: try JSONEncoder().encode(String(data.prefix(1000))), as: UTF8.self))]) {
            result += delta; if result.count > 500 { break }
        }
        return result
    }
}
extension AppState {
    func tidyTitle(_ tab: Tab) {
        guard settings.ai?.tidyTitles == true, aiTabAllowed(tab), tab.customTitle == nil, let url = tab.url, !tab.isLoading, providerRegistry.unavailableReason == nil else { return }
        let key = tab.profileID.uuidString + ":" + url.absoluteString
        guard settings.ai?.tidiedURLs?.contains(key) != true else { return }
        var options = settings.ai ?? AISettings(); var tried = options.tidiedURLs ?? []; tried.insert(key); options.tidiedURLs = tried; settings.ai = options
        let registry = providerRegistry
        Task { [weak self, weak tab] in
            do {
                let result = try await AITidy.answer("Return only a short 1–3 word title for this pinned tab.", data: tab?.title ?? "", registry: registry)
                guard let self, let tab, self.aiTabAllowed(tab), self.settings.ai?.tidyTitles == true, tab.url == url, tab.isPinned, tab.customTitle == nil, let title = AITidy.title(result) else { return }
                self.renameTab(tab, name: title)
            } catch { self?.notify("Couldn’t tidy tab title: \(error.localizedDescription)") }
        }
    }
    /// Tidy Today with "Tidy pinned tab titles" on and a model available: each new folder gets a
    /// 1–3 word name from its tabs' titles, replacing the heuristic unless the folder was renamed
    /// or removed meanwhile. Titles of tabs the AI may not read are left out.
    func nameTidyFolders(_ folders: [(id: UUID, group: TidyPlan.Group)]) {
        guard settings.ai?.tidyTitles == true, !isPrivate, providerRegistry.unavailableReason == nil else { return }
        let registry = providerRegistry
        for (id, group) in folders {
            let titles = group.tabIDs.compactMap { tabID in tabs.first { $0.id == tabID && aiTabAllowed($0) }?.displayTitle }
            guard !titles.isEmpty else { continue }
            Task { [weak self] in
                guard let result = try? await AITidy.answer("Return only a short 1–3 word name for a folder holding these browser tabs.", data: titles.joined(separator: "\n"), registry: registry),
                      let self, self.settings.ai?.tidyTitles == true, let name = AITidy.title(result),
                      self.folders.contains(where: { $0.id == id && $0.name == group.name }) else { return }
                self.updateFolder(id, name: name)
            }
        }
    }
    func tidyDownload(_ entry: DownloadEntry) {
        guard !isPrivate, settings.ai?.tidyDownloads == true, entry.profileID == (activeSpace.profileID ?? Profile.defaultID), let source = entry.sourceURL, let host = source.host?.lowercased(), !excludedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }), providerRegistry.unavailableReason == nil else { return }
        let registry = providerRegistry
        Task {
            do {
                let result = try await AITidy.answer("Suggest one descriptive filename stem based only on this original name. Return only the name, no path or explanation.", data: entry.destination.lastPathComponent, registry: registry)
                guard settings.ai?.tidyDownloads == true, providerRegistry.namespace == registry.namespace,
                      let name = AITidy.filename(result, original: entry.destination.lastPathComponent), name != entry.destination.lastPathComponent,
                      let window = NSApp.keyWindow else { return }
                let alert = NSAlert(); alert.messageText = "Rename finished download?"
                alert.informativeText = "\(entry.destination.lastPathComponent) → \(name)\nThe extension stays unchanged. File contents were not sent to the model."
                alert.addButton(withTitle: "Keep original"); alert.addButton(withTitle: "Rename")
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard response == .alertSecondButtonReturn else { return }
                    Task { @MainActor in
                        do { try self?.downloads.rename(entry.id, to: name); self?.notify("Download renamed") }
                        catch { self?.notify("Couldn’t rename: \(error.localizedDescription)") }
                    }
                }
            } catch { notify("Couldn’t suggest download name: \(error.localizedDescription)") }
        }
    }
}
