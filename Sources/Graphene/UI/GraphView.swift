import SwiftUI

/// The history graph: pages as nodes, chronological + query edges. Draws the
/// persisted layout with pan/zoom; click a node to reopen it. (A cooled force
/// relaxation is a later refinement — positions are seeded near their parent.)
struct GraphView: View {
    @EnvironmentObject var app: AppState
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var hover: GraphNode?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let nodes = app.graph.nodeArray
            let edges = app.graph.edges
            let layout = Layout(nodes: nodes, size: geo.size, zoom: zoom, pan: pan)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                Canvas { ctx, _ in
                    let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
                    for e in edges {
                        guard let a = byID[e.from], let b = byID[e.to] else { continue }
                        let p1 = layout.point(a), p2 = layout.point(b)
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        let isQuery = e.kind == .query
                        ctx.stroke(path, with: .color(.primary.opacity(isQuery ? 0.28 : 0.14)),
                                   style: StrokeStyle(lineWidth: 1, dash: isQuery ? [4, 4] : []))
                    }
                    for n in nodes {
                        let p = layout.point(n)
                        let isNote = n.annotationCount > 0
                        let isSearch = n.query != nil
                        let r: CGFloat = 5 + min(6, CGFloat(n.visitCount) * 1.4)
                        // fill
                        let fill = Color.primary.opacity(0.5)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(fill))
                        // annotation ring in the one accent
                        if isNote {
                            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: r * 2 + 4, height: r * 2 + 4)),
                                       with: .color(Theme.accent), lineWidth: 1.5)
                        }
                        if isSearch {
                            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                       with: .color(Theme.accent), lineWidth: 1.5)
                        }
                        if zoom > 0.7 {
                            let text = Text(n.title).font(.system(size: 10)).foregroundColor(.secondary)
                            ctx.draw(text, at: CGPoint(x: p.x, y: p.y + r + 9), anchor: .top)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in pan = CGSize(width: startPan.width + v.translation.width,
                                                       height: startPan.height + v.translation.height) }
                        .onEnded { _ in startPan = pan }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in zoom = max(0.3, min(3, startZoom * v.magnification)) }
                        .onEnded { _ in startZoom = zoom }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt):
                        hover = layout.nearest(to: pt, in: nodes)
                        hoverPoint = pt
                    case .ended: hover = nil
                    }
                }
                .onTapGesture { pt in
                    if let n = layout.nearest(to: pt, in: nodes), let url = URL(string: n.url) {
                        app.openTab(url: url, parent: nil, activate: true)
                        app.showGraph = false
                    }
                }

                header
                if let h = hover { tooltip(for: h).position(x: min(hoverPoint.x + 130, geo.size.width - 130), y: hoverPoint.y - 8) }
                if nodes.isEmpty { emptyState.frame(width: geo.size.width, height: geo.size.height) }
            }
        }
    }

    @State private var startPan: CGSize = .zero
    @State private var startZoom: CGFloat = 1

    private var header: some View {
        HStack {
            Text("History graph")
                .font(.system(size: 13, weight: .medium))
            Text("\(app.graph.nodeArray.count) pages")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { app.showGraph = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func tooltip(for n: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(n.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(n.host).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            if let q = n.query {
                Text("searched: \(q)").font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1)
            }
        }
        .padding(9)
        .frame(maxWidth: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Your history graph is empty")
                .font(.system(size: 15, weight: .medium))
            Text("Browse a few pages and they'll appear here as a navigable graph.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

/// Fits persisted node positions into the view with pan/zoom, and hit-tests.
private struct Layout {
    let size: CGSize
    let zoom: CGFloat
    let pan: CGSize
    let minX: Double, minY: Double, spanX: Double, spanY: Double

    init(nodes: [GraphNode], size: CGSize, zoom: CGFloat, pan: CGSize) {
        self.size = size; self.zoom = zoom; self.pan = pan
        let xs = nodes.map(\.x), ys = nodes.map(\.y)
        minX = xs.min() ?? 0; minY = ys.min() ?? 0
        spanX = max(1, (xs.max() ?? 1) - minX)
        spanY = max(1, (ys.max() ?? 1) - minY)
    }

    func point(_ n: GraphNode) -> CGPoint {
        let pad: CGFloat = 80
        let w = size.width - pad * 2, h = size.height - pad * 2
        let nx = spanX == 0 ? 0.5 : (n.x - minX) / spanX
        let ny = spanY == 0 ? 0.5 : (n.y - minY) / spanY
        let base = CGPoint(x: pad + CGFloat(nx) * w, y: pad + CGFloat(ny) * h)
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: (base.x - cx) * zoom + cx + pan.width,
                       y: (base.y - cy) * zoom + cy + pan.height)
    }

    func nearest(to pt: CGPoint, in nodes: [GraphNode]) -> GraphNode? {
        var best: GraphNode?; var bestD = 20.0
        for n in nodes {
            let p = point(n)
            let d = Double(hypot(p.x - pt.x, p.y - pt.y))
            if d < bestD { bestD = d; best = n }
        }
        return best
    }
}
