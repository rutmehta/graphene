import Foundation
import CoreGraphics

/// Where a tab dragged in the sidebar lands (arc-look.md §3.3, graphene-identity.md §3.1).
/// Every sidebar drop destination resolves to one of these and `AppState.sidebarDrop`
/// applies it, so the drag gestures and their tests share one code path.
enum SidebarDropTarget: Equatable {
    /// The favorites grid, or its empty drop band while a tab is dragged.
    case favorites
    /// The space label, the pinned section's header.
    case pinned
    /// The hairline above Today.
    case today
    /// A row or favorite tile: the dragged tab joins its section and folder, before or after it.
    case row(UUID, after: Bool)
    /// A Today row's icon slot: the dragged tab becomes its newest child.
    case branch(UUID)
    /// A row held under the pointer for half a second: both tabs go into one folder.
    case group(UUID)
    /// A folder row.
    case folder(UUID)
    /// A space dot: a tab moves to that space; a dragged space is reordered before it.
    case space(UUID)
}

/// Which half of a drop target the pointer is in: the trailing half (below a row's middle,
/// right of a tile's middle) drops after it.
enum SidebarDropPlacement {
    static func after(location: CGPoint, size: CGSize, horizontal: Bool) -> Bool {
        horizontal ? location.x > size.width / 2 : location.y > size.height / 2
    }
}

/// The direction of a space switch: 1 toward the next space, -1 toward the previous one.
enum SpaceTravel {
    /// A relative step (swipe, next or previous space) keeps its sign even when it wraps
    /// around the ends; a direct pick follows the spaces' order. `nil` when nothing moves.
    static func direction(from: Int?, to: Int?, delta: Int?) -> Int? {
        if let delta, delta != 0 { return delta > 0 ? 1 : -1 }
        guard let from, let to, from != to else { return nil }
        return to > from ? 1 : -1
    }
}

extension AppState {
    func beginSidebarDrag(_ id: UUID) { if sidebarDragTabID != id { sidebarDragTabID = id } }
    func endSidebarDrag() { if sidebarDragTabID != nil { sidebarDragTabID = nil } }

    /// Applies a sidebar drop of `payload` ("tab:<id>" or "space:<id>") on `target`.
    /// Returns whether the model changed.
    @discardableResult
    func sidebarDrop(_ payload: String, on target: SidebarDropTarget) -> Bool {
        defer { endSidebarDrag() }
        if case .space(let spaceID) = target, let moved = payloadID(payload, prefix: "space:") {
            guard moved != spaceID else { return false }
            moveSpace(moved, before: spaceID); return true
        }
        guard let id = payloadID(payload, prefix: "tab:"), let tab = tabs.first(where: { $0.id == id }) else { return false }
        switch target {
        case .favorites:
            placeTab(id, section: .favorites, spaceID: activeSpaceID)
        case .pinned:
            placeTab(id, section: .pinned, spaceID: activeSpaceID)
        case .today:
            placeTab(id, section: .today, spaceID: activeSpaceID)
        case .row(let targetID, let after):
            guard targetID != id, let target = tabs.first(where: { $0.id == targetID }) else { return false }
            placeTab(id, section: target.section, folderID: target.folderID, spaceID: target.spaceID)
            return reorderTab(id, beside: targetID, after: after)
        case .branch(let parentID):
            adoptTab(id, under: parentID)
            return tab.parentTabID == parentID
        case .group(let targetID):
            guard targetID != id, let target = tabs.first(where: { $0.id == targetID }), target.spaceID == activeSpaceID else { return false }
            let section = target.section == .favorites ? TabSection.pinned : target.section
            let folder = target.folderID ?? createFolder(section: section)
            placeTab(targetID, section: section, folderID: folder)
            placeTab(id, section: section, folderID: folder, spaceID: activeSpaceID)
        case .folder(let folderID):
            guard let folder = folders.first(where: { $0.id == folderID }) else { return false }
            placeTab(id, section: folder.section, folderID: folder.id, spaceID: folder.spaceID)
        case .space(let spaceID):
            placeTab(id, section: tab.section, spaceID: spaceID)
        }
        return true
    }

    /// Moves `id` directly before or after `targetID` in the same space and section. A
    /// reordered child leaves its branch and becomes a root at the drop position.
    @discardableResult
    func reorderTab(_ id: UUID, beside targetID: UUID, after: Bool) -> Bool {
        guard id != targetID, let source = tabs.firstIndex(where: { $0.id == id }),
              let target = tabs.first(where: { $0.id == targetID }),
              tabs[source].spaceID == target.spaceID, tabs[source].section == target.section else { return false }
        let tab = tabs.remove(at: source)
        guard let index = tabs.firstIndex(where: { $0.id == targetID }) else { tabs.insert(tab, at: source); return false }
        tabs.insert(tab, at: after ? index + 1 : index)
        tab.parentTabID = nil
        objectWillChange.send(); persistSoon()
        return true
    }

    /// A split pane's close glyph: a pinned tab leaves the split and stays in the sidebar;
    /// any other tab closes as ⌘W closes it.
    func closePane(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.isPinned, let index = splits.firstIndex(where: { $0.tabIDs.contains(id) }) else { requestCloseTab(id); return }
        let sibling = splits[index].tabIDs.first { $0 != id }
        splits[index].tabIDs.removeAll { $0 == id }
        splits.removeAll { $0.tabIDs.count < 2 }
        if activeTabID == id, let sibling { activate(sibling) }
        persistSoon()
    }
}
