import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    private var groups: [(Date, [AppState.SessionTab])] {
        let entries = app.archivedTabs.filter { query.isEmpty || "\($0.customTitle ?? $0.title ?? "") \($0.url ?? "")".localizedCaseInsensitiveContains(query) }
        return Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.archivedAt ?? .distantPast) }
            .sorted { $0.key > $1.key }.map { ($0.key, $0.value.reversed()) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Archived tabs").font(.system(size: 13, weight: .semibold))
                Spacer()
                IconButton("Close archive", system: "xmark") { app.archivePresented = false }
            }
            TextField("Search archive", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty { Text("No archived tabs").foregroundStyle(app.pal.ink3) }
                    ForEach(groups, id: \.0) { day, entries in
                        Text(day, format: .dateTime.month().day().year()).font(.system(size: 11, weight: .medium)).foregroundStyle(app.pal.ink3)
                        ForEach(entries, id: \.archiveID) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.customTitle ?? entry.title ?? entry.url ?? "Tab").lineLimit(1)
                                Text(entry.url ?? "").font(.system(size: 10)).foregroundStyle(app.pal.ink3).lineLimit(1)
                                HStack {
                                    Button("Restore") { if let id = entry.archiveID { app.restoreArchive(id) } }
                                    Spacer()
                                    Button("Delete", role: .destructive) { if let id = entry.archiveID { app.deleteArchive(id) } }
                                }.buttonStyle(.plain).foregroundStyle(app.pal.accentText)
                            }.padding(8).background(app.pal.hover, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.font(.system(size: 12))
            }
        }.padding(12)
    }
}
