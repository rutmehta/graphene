import SwiftUI

/// Renders one thread of thought as a chronological timeline-tree: time flows
/// left→right, branches (opened-from) fork into lanes, pages are favicon nodes.
/// This is the honest shape of browsing — a git-graph of your train of thought,
/// not a physics blob.
struct ThreadTimeline: View {
    let thread: KnowledgeGraph.Thread
    let edges: [GraphEdge]
    var laneHeight: CGFloat = 62
    var compact = false
    var onOpen: (URL) -> Void

    @State private var hover: UUID?

    private var layout: Layout { Layout(thread: thread, edges: edges) }

    var body: some View {
        let lay = layout
        GeometryReader { geo in
            let pts = points(in: geo.size, layout: lay)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawEdges(ctx, points: pts) }
                ForEach(thread.nodes) { node in
                    if let p = pts[node.id] {
                        NodeChip(node: node,
                                 hovered: hover == node.id,
                                 compact: compact,
                                 onHover: { hover = $0 ? node.id : (hover == node.id ? nil : hover) },
                                 onOpen: { if let u = URL(string: node.url) { onOpen(u) } })
                            .position(p)
                    }
                }
            }
        }
        .frame(height: CGFloat(max(1, lay.laneCount)) * laneHeight + 8)
    }

    private func points(in size: CGSize, layout lay: Layout) -> [UUID: CGPoint] {
        let padX: CGFloat = 34
        let w = size.width - padX * 2
        let denom = CGFloat(max(1, lay.colCount - 1))
        var out: [UUID: CGPoint] = [:]
        for n in thread.nodes {
            guard let cl = lay.place[n.id] else { continue }
            let x = lay.colCount == 1 ? size.width / 2 : padX + CGFloat(cl.col) / denom * w
            let y = CGFloat(cl.lane) * laneHeight + laneHeight / 2 + 4
            out[n.id] = CGPoint(x: x, y: y)
        }
        return out
    }

    private func drawEdges(_ ctx: GraphicsContext, points: [UUID: CGPoint]) {
        let ids = Set(thread.nodes.map(\.id))
        for e in edges where ids.contains(e.from) && ids.contains(e.to) {
            guard let a = points[e.from], let b = points[e.to] else { continue }
            var path = Path()
            path.move(to: a)
            // smooth S-curve between columns
            let dx = (b.x - a.x) * 0.5
            path.addCurve(to: b, control1: CGPoint(x: a.x + dx, y: a.y), control2: CGPoint(x: b.x - dx, y: b.y))
            if e.kind == .query {
                ctx.stroke(path, with: .color(Theme.accent.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            } else {
                ctx.stroke(path, with: .color(.primary.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    /// Column = chronological index; lane = branch (first child continues the
    /// parent's lane, later children fork to a new lane).
    struct Layout {
        var place: [UUID: (col: Int, lane: Int)] = [:]
        var colCount = 0
        var laneCount = 1

        init(thread: KnowledgeGraph.Thread, edges: [GraphEdge]) {
            let ordered = thread.nodes  // already chronological
            colCount = ordered.count
            let ids = Set(ordered.map(\.id))
            let col = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })

            // parent = source of an incoming edge within the thread (nearest earlier page)
            var parent: [UUID: UUID] = [:]
            for e in edges where ids.contains(e.from) && ids.contains(e.to) {
                guard let cf = col[e.from], let ct = col[e.to], cf < ct else { continue }
                if let existing = parent[e.to], let ce = col[existing], ce >= cf { continue }
                parent[e.to] = e.from
            }
            var firstChild: [UUID: UUID] = [:]
            for n in ordered {
                if let p = parent[n.id], firstChild[p] == nil { firstChild[p] = n.id }
            }

            var next = 0
            var lane: [UUID: Int] = [:]
            for n in ordered {
                if let p = parent[n.id] {
                    if firstChild[p] == n.id, let pl = lane[p] { lane[n.id] = pl }
                    else { lane[n.id] = next; next += 1 }
                } else {
                    lane[n.id] = next; next += 1
                }
            }
            laneCount = max(1, next)
            for n in ordered { place[n.id] = (col[n.id] ?? 0, lane[n.id] ?? 0) }
        }
    }
}

private struct NodeChip: View {
    let node: GraphNode
    let hovered: Bool
    let compact: Bool
    let onHover: (Bool) -> Void
    let onOpen: () -> Void

    private var size: CGFloat { compact ? 26 : 30 }

    var body: some View {
        let host = URL(string: node.url)?.host
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(
                    node.annotationCount > 0 ? Theme.accent : Color.primary.opacity(hovered ? 0.35 : 0.14),
                    lineWidth: node.annotationCount > 0 ? 1.6 : 1))
                .shadow(color: .black.opacity(hovered ? 0.28 : 0.16), radius: hovered ? 7 : 3, y: 1)
            FaviconImg(host: host, size: size * 0.55)
            if node.query != nil {
                Circle().strokeBorder(Theme.accent.opacity(0.85), lineWidth: 1.5)
                    .frame(width: size + 6, height: size + 6)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(hovered ? 1.12 : 1)
        .overlay(alignment: .top) {
            if hovered {
                Text(node.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
                    .fixedSize()
                    .offset(y: -(size / 2) - 16)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.14), value: hovered)
        .onHover(perform: onHover)
        .onTapGesture(perform: onOpen)
    }
}

/// A favicon image without a placeholder frame (used inside chips).
struct FaviconImg: View {
    let host: String?
    var size: CGFloat = 16
    var body: some View {
        AsyncImage(url: host.flatMap { URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\($0)") }) { phase in
            if case .success(let img) = phase {
                img.resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe").resizable().fontWeight(.light).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
