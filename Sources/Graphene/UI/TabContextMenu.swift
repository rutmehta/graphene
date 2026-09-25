import SwiftUI

/// Both tab layouts expose the same actions and native menu groups.
struct TabContextMenu: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tab: Tab
    var rename: () -> Void
    var body: some View {
        // One action table per evaluation, not one per item (see `CommandMenuTable`).
        let actions = CommandMenuTable(app.allCommandActions)
        command("pin", actions, tab.isPinned ? "Unpin" : "Pin") { app.pin(tab) }
        command("favorite", actions, tab.isFavorite ? "Remove from Favorites" : "Add to Favorites") { app.placeTab(tab.id, section: tab.isFavorite ? .today : .favorites) }
        if tab.isPinned { Button("Reset to Pinned Page") { app.resetPinnedTab(tab) } }
        command("rename", actions, "Rename…", run: rename)
        Button("Duplicate") { app.duplicateTab(tab) }
        Divider()
        Menu("Move to") {
            Menu("Space") {
                ForEach(app.spaces) { space in Button(space.name) { app.placeTab(tab.id, section: tab.section, spaceID: space.id) } }
            }
            Menu("Folder") {
                Button("None") { app.placeTab(tab.id, section: tab.section) }
                ForEach(app.folders.filter { $0.spaceID == tab.spaceID && $0.section == tab.section }) { folder in
                    Button(folder.name) { app.placeTab(tab.id, section: tab.section, folderID: folder.id) }
                }
            }
            Button("New Window") { BrowserWindows.open(sharing: app, moving: tab.id) }
        }
        Button("Open in split view") { app.openSplit(tab.id) }.disabled(tab.id == app.activeTabID)
        command("separate", actions, "Separate split") { app.separateSplit() }.disabled(app.activeSplit == nil)
        Divider()
        command("copy-url", actions, "Copy Link") { copyLink(tab.url) }.disabled(tab.url == nil)
        Button("Show in Thread") { app.selectedThreadID = tab.currentThreadID; app.show(.threads) }.disabled(tab.currentThreadID == nil)
        command("peek", actions, "Peek") { if let url = tab.url { app.showPeek(url) } }.disabled(tab.url == nil)
        BatchTabMenu()
        Divider()
        command("close-tab", actions, tab.isPinned ? "Close" : "Archive Tab") { app.requestCloseTab(tab.id) }
        // Provenance rows (graphene-identity.md §3.1): only Today rows in a branch gain these.
        if !app.branchChildren(of: tab.id).isEmpty { Button("Close branch") { app.closeBranch(tab.id) } }
        if app.branchParent(of: tab.id) != nil { Button("Detach from parent") { app.detachFromParent(tab.id) } }
        Button("Archive Other Tabs") { for other in app.visibleTabs where other.id != tab.id && !other.isPinned { app.closeTab(other.id) } }
        Button("Archive Tabs Below") {
            let rows = app.visibleTabs
            if let index = rows.firstIndex(where: { $0.id == tab.id }) {
                for other in rows.dropFirst(index + 1) where !other.isPinned { app.closeTab(other.id) }
            }
        }
    }
    @ViewBuilder private func command(_ id: String, _ actions: CommandMenuTable, _ title: String, run: @escaping () -> Void) -> some View {
        // Only the main command menu registers accelerators. SwiftUI can keep
        // contextual shortcuts alive after dismissal, targeting an unrelated tab.
        let hint = actions[id]?.hint ?? ""
        Button(hint.isEmpty ? title : title + "    " + hint, action: run)
    }
}
