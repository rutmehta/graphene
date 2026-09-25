import SwiftUI

/// Archived tabs. The sidebar hosts it on the chrome plane, so its 32pt bar keeps the
/// library bar geometry without painting `pageBg`.
struct ArchiveView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    private var groups: [(Date, [AppState.SessionTab])] {
        let entries = app.archivedTabs.filter { query.isEmpty || "\($0.customTitle ?? $0.title ?? "") \($0.url ?? "")".localizedCaseInsensitiveContains(query) }
        return Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.archivedAt ?? .distantPast) }
            .sorted { $0.key > $1.key }.map { ($0.key, $0.value.reversed()) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryBar(title: "Archive", onCard: false) {
                LibraryBarButton("Close archive", system: "xmark") { app.archivePresented = false }
            }
            FilterField(placeholder: "Search archive", text: $query).padding(.vertical, ShellLayout.windowGap)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty {
                        Text("No archived tabs").font(ShellType.row).foregroundStyle(app.pal.ink3).padding(.horizontal, ShellLayout.rowInsetLeading).padding(.vertical, ShellLayout.sectionGap)
                    }
                    ForEach(groups, id: \.0) { day, entries in
                        Text(day, format: .dateTime.month().day().year()).font(ShellType.label).foregroundStyle(app.pal.ink2)
                            .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.top, ShellLayout.sectionGap).padding(.bottom, 4)
                        ForEach(entries, id: \.archiveID) { entry in ArchiveRow(entry: entry) }
                    }
                }
            }
        }.foregroundStyle(app.pal.ink)
    }
}

/// An archived tab: `row` title, `caption` URL, restore and delete glyphs in `ink3`.
private struct ArchiveRow: View {
    let entry: AppState.SessionTab
    @EnvironmentObject var app: AppState
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.customTitle ?? entry.title ?? entry.url ?? "Tab").font(ShellType.row).foregroundStyle(app.pal.ink).lineLimit(1)
                Text(entry.url ?? "").font(ShellType.caption).foregroundStyle(app.pal.ink3).lineLimit(1)
            }
            Spacer(minLength: 4)
            LibraryBarButton("Restore", system: "arrow.uturn.backward") { if let id = entry.archiveID { app.restoreArchive(id) } }
            LibraryBarButton("Delete", system: "trash") { if let id = entry.archiveID { app.deleteArchive(id) } }
        }
        .padding(.leading, ShellLayout.rowInsetLeading).padding(.trailing, 4).padding(.vertical, 4)
        .background(hovering ? app.pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}
