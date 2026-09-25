import SwiftUI
import AppKit

extension AppState {
    var sidebarOrderedTabs: [Tab] {
        var result = visibleTabs.filter { $0.section == .favorites }
        for section in [TabSection.pinned, .today] {
            for folder in folders where folder.spaceID == activeSpaceID && folder.section == section && !folder.collapsed {
                result += visibleTabs.filter { $0.folderID == folder.id }
            }
            result += visibleTabs.filter { $0.section == section && $0.folderID == nil }
        }
        return result
    }
    func selectSidebarTab(_ id: UUID, extend: Bool, toggle: Bool) {
        let rows = sidebarOrderedTabs
        if extend, let anchor = selectionAnchor, let a = rows.firstIndex(where: { $0.id == anchor }), let b = rows.firstIndex(where: { $0.id == id }) {
            selectedTabIDs = Set(rows[min(a, b)...max(a, b)].map(\.id))
        } else if toggle {
            if !selectedTabIDs.insert(id).inserted { selectedTabIDs.remove(id) }
            selectionAnchor = id
        } else { selectedTabIDs = [id]; selectionAnchor = id; activate(id) }
    }
    func sidebarClick(_ tab: Tab, reset: Bool = false) {
        let modifiers = NSEvent.modifierFlags
        if reset && !modifiers.contains(.command) && !modifiers.contains(.shift) { resetPinnedTab(tab) }
        else { selectSidebarTab(tab.id, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command)) }
    }
}

struct BatchTabMenu: View {
    @EnvironmentObject var app: AppState
    private var tabs: [Tab] { app.visibleTabs.filter { app.selectedTabIDs.contains($0.id) } }
    var body: some View {
        if tabs.count > 1 {
            Menu("Selected tabs (\(tabs.count))") {
                Button("Close selected") { for tab in tabs { app.closeTab(tab.id) }; app.selectedTabIDs = [] }
                Button("Pin selected") { for tab in tabs { app.placeTab(tab.id, section: .pinned) } }
                Menu("Move to space") {
                    ForEach(app.spaces) { space in
                        Button(space.name) { for tab in tabs { app.placeTab(tab.id, section: tab.section, spaceID: space.id) }; app.selectedTabIDs = [] }
                    }
                }
                Menu("Add to folder") {
                    Button("New folder") {
                        let id = app.createFolder(section: .pinned)
                        for tab in tabs { app.placeTab(tab.id, section: .pinned, folderID: id) }
                    }
                    ForEach(app.folders.filter { $0.spaceID == app.activeSpaceID }) { folder in
                        Button(folder.name) { for tab in tabs { app.placeTab(tab.id, section: folder.section, folderID: folder.id) } }
                    }
                }
            }
            Divider()
        }
    }
}
