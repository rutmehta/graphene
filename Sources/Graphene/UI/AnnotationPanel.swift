import SwiftUI

/// Your annotations, newest first — each keeps the page it came from. Provenance
/// is the point: click to reopen the source.
struct AnnotationPanel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    app.showAnnotations = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()

            if app.vault.annotations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No notes yet")
                        .font(.system(size: 14, weight: .medium))
                    Text("Select text on any page to highlight it and keep it — with its source.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(app.vault.annotations) { ann in
                            AnnotationCard(ann: ann)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
    }
}

private struct AnnotationCard: View {
    let ann: Annotation
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ann.text)
                .font(.system(size: 13))
                .lineLimit(4)
            if !ann.note.isEmpty {
                Text(ann.note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 9))
                Text(host)
                    .lineLimit(1)
                Spacer()
                Text(ann.created, style: .date)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0.03))
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = URL(string: ann.url) { app.openTab(url: url, parent: nil, activate: true) }
        }
    }

    private var host: String { URL(string: ann.url)?.host ?? ann.url }
}
