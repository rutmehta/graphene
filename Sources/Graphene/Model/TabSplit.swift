import Foundation

struct TabSplit: Codable, Identifiable, Equatable {
    var id = UUID()
    var tabIDs: [UUID]
    var vertical = false
    var fractions: [Double] = [0.5, 0.5, 0.5]
}

extension AppState {
    var activeSplit: TabSplit? { splits.first { $0.tabIDs.contains(activeTabID ?? UUID()) } }
    var splitTabs: [Tab] { (activeSplit?.tabIDs ?? []).compactMap { id in tabs.first { $0.id == id } } }

    func openSplit(_ id: UUID, vertical: Bool = false) {
        guard let active = activeTabID, active != id, let tab = tabs.first(where: { $0.id == id }), tab.spaceID == activeSpaceID else { return }
        if let index = splits.firstIndex(where: { $0.tabIDs.contains(active) }) {
            guard splits[index].tabIDs.count < 4, !splits[index].tabIDs.contains(id), !splits.contains(where: { $0.tabIDs.contains(id) }) else { return }
            splits[index].tabIDs.append(id)
        } else {
            guard !splits.contains(where: { $0.tabIDs.contains(id) }) else { return }
            splits.append(TabSplit(tabIDs: [active, id], vertical: vertical))
        }
        activate(id); persist()
    }
    func splitNextTab(vertical: Bool) {
        if let next = visibleTabs.first(where: { candidate in candidate.id != activeTabID && !splitTabs.contains(where: { $0.id == candidate.id }) }) {
            openSplit(next.id, vertical: vertical)
        }
    }
    func separateSplit() {
        guard let id = activeSplit?.id else { return }
        splits.removeAll { $0.id == id }; persist()
    }
    func setSplitFraction(_ id: UUID, index: Int, fraction: Double) {
        guard let i = splits.firstIndex(where: { $0.id == id }), splits[i].fractions.indices.contains(index) else { return }
        splits[i].fractions[index] = min(0.8, max(0.2, fraction)); persist()
    }
}
