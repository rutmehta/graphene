import SwiftUI

/// The history graph — the signature surface. Pages are nodes; edges are the
/// chronological path plus the search that led there. A cooled force layout
/// spreads the graph on open, then rests; pan/zoom and click to reopen.
struct GraphView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var pos: [UUID: CGPoint] = [:]
    @State private var vel: [UUID: CGVector] = [:]
    @State private var temperature = 1.0
    @State private var timer: Timer?

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var startPan: CGSize = .zero
    @State private var startZoom: CGFloat = 1
    @State private var hover: GraphNode?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let nodes = app.graph.nodeArray
            let edges = app.graph.edges
            let fit = Fit(positions: pos, nodes: nodes, size: geo.size, zoom: zoom, pan: pan)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(nsColor: .textBackgroundColor))
                RadialGradient(colors: [Theme.accent.opacity(0.05), .clear],
                               center: .center, startRadius: 0, endRadius: geo.size.height * 0.7)
                    .allowsHitTesting(false)

                Canvas { ctx, _ in draw(ctx, nodes: nodes, edges: edges, fit: fit) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { v in pan = CGSize(width: startPan.width + v.translation.width,
                                                           height: startPan.height + v.translation.height) }
                            .onEnded { _ in startPan = pan }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { v in zoom = max(0.35, min(3.5, startZoom * v.magnification)) }
                            .onEnded { _ in startZoom = zoom }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): hover = fit.nearest(to: pt, nodes: nodes); hoverPoint = pt
                        case .ended: hover = nil
                        }
                    }
                    .onTapGesture { pt in
                        if let n = fit.nearest(to: pt, nodes: nodes), let url = URL(string: n.url) {
                            app.openTab(url: url, parent: nil, activate: true)
                            app.showGraph = false
                        }
                    }

                header
                if let h = hover {
                    tooltip(for: h)
                        .position(x: min(max(hoverPoint.x, 150), geo.size.width - 150), y: hoverPoint.y - 46)
                        .allowsHitTesting(false)
                }
                if nodes.isEmpty { emptyState.frame(width: geo.size.width, height: geo.size.height) }
            }
            .onAppear { startSimulation(nodes: nodes, edges: edges) }
            .onDisappear { timer?.invalidate(); persist() }
        }
    }

    // MARK: drawing

    private func draw(_ ctx: GraphicsContext, nodes: [GraphNode], edges: [GraphEdge], fit: Fit) {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        // edges
        for e in edges {
            guard let a = byID[e.from], let b = byID[e.to] else { continue }
            let p1 = fit.screen(a), p2 = fit.screen(b)
            var path = Path()
            path.move(to: p1)
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 - 18)
            path.addQuadCurve(to: p2, control: mid)
            if e.kind == .query {
                ctx.stroke(path, with: .color(Theme.accent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1, 5]))
            } else {
                ctx.stroke(path, with: .color(.primary.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        // nodes
        for n in nodes {
            let p = fit.screen(n)
            let isNote = n.annotationCount > 0
            let isSearch = n.query != nil
            let r: CGFloat = 5 + min(7, CGFloat(n.visitCount) * 1.6)
            let base: Color = isNote ? Theme.accent : .primary
            // soft glow
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 6, y: p.y - r - 6, width: r * 2 + 12, height: r * 2 + 12)),
                     with: .radialGradient(Gradient(colors: [base.opacity(isNote ? 0.22 : 0.12), .clear]),
                                           center: p, startRadius: 0, endRadius: r + 6))
            // body
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(isNote ? Theme.accent : .primary.opacity(0.62)))
            // inner highlight for depth
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.7, width: r, height: r)),
                     with: .color(.white.opacity(0.18)))
            if isSearch && !isNote {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 2.5, y: p.y - r - 2.5, width: r * 2 + 5, height: r * 2 + 5)),
                           with: .color(Theme.accent.opacity(0.8)), lineWidth: 1.5)
            }
            // label
            if zoom > 0.55 {
                let name = n.title.count > 34 ? String(n.title.prefix(33)) + "…" : n.title
                var t = ctx
                t.addFilter(.shadow(color: .black.opacity(0.55), radius: 3, y: 1))
                t.draw(Text(name).font(.system(size: 11, weight: .medium)).foregroundColor(.primary.opacity(0.9)),
                       at: CGPoint(x: p.x, y: p.y + r + 9), anchor: .top)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("History graph").font(.system(size: 13, weight: .semibold))
            Text("\(app.graph.nodeArray.count) pages · \(app.graph.edges.count) links")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { app.showGraph = false } label: {
                Text("Done").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline(scheme)).frame(height: 1) }
    }

    private func tooltip(for n: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(n.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(n.host).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            if let q = n.query {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 9))
                    Text(q).lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline(scheme)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text("Your history graph is empty").font(.system(size: 15, weight: .medium))
            Text("Browse a few pages — they'll appear here as a navigable graph.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    // MARK: force simulation (cooled, then rests — no idle CPU)

    private func startSimulation(nodes: [GraphNode], edges: [GraphEdge]) {
        guard nodes.count <= 500 else { seedStatic(nodes); return }
        var p: [UUID: CGPoint] = [:]
        for n in nodes { p[n.id] = CGPoint(x: n.x, y: n.y) }
        pos = p
        vel = [:]
        temperature = 1.0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            MainActor.assumeIsolated {
                step(nodes: nodes, edges: edges)
                if temperature < 0.02 { t.invalidate(); persist() }
            }
        }
    }

    private func seedStatic(_ nodes: [GraphNode]) {
        var p: [UUID: CGPoint] = [:]
        for n in nodes { p[n.id] = CGPoint(x: n.x, y: n.y) }
        pos = p
    }

    private func step(nodes: [GraphNode], edges: [GraphEdge]) {
        let ids = nodes.map(\.id)
        var force: [UUID: CGVector] = [:]
        for id in ids { force[id] = .zero }

        // repulsion (O(n²) — fine at this scale)
        for i in 0..<ids.count {
            let a = ids[i]; guard let pa = pos[a] else { continue }
            for j in (i + 1)..<ids.count {
                let b = ids[j]; guard let pb = pos[b] else { continue }
                var dx = pa.x - pb.x, dy = pa.y - pb.y
                var d2 = dx * dx + dy * dy
                if d2 < 0.01 { dx = .random(in: -1...1); dy = .random(in: -1...1); d2 = 1 }
                let d = d2.squareRoot()
                let rep = 9000 / d2
                let fx = dx / d * rep, fy = dy / d * rep
                force[a]? += CGVector(dx: fx, dy: fy)
                force[b]? += CGVector(dx: -fx, dy: -fy)
            }
        }
        // springs along edges
        for e in edges {
            guard let pa = pos[e.from], let pb = pos[e.to] else { continue }
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let d = max(1, (dx * dx + dy * dy).squareRoot())
            let f = (d - 120) * 0.03
            let fx = dx / d * f, fy = dy / d * f
            force[e.from]? += CGVector(dx: fx, dy: fy)
            force[e.to]? += CGVector(dx: -fx, dy: -fy)
        }
        // gentle centering
        for id in ids {
            guard let p = pos[id] else { continue }
            force[id]? += CGVector(dx: -p.x * 0.012, dy: -p.y * 0.012)
        }
        // integrate
        for id in ids {
            var v = vel[id] ?? .zero
            let f = force[id] ?? .zero
            v.dx = (v.dx + f.dx) * 0.82
            v.dy = (v.dy + f.dy) * 0.82
            vel[id] = v
            if var p = pos[id] {
                p.x += v.dx * temperature
                p.y += v.dy * temperature
                pos[id] = p
            }
        }
        temperature *= 0.965
    }

    private func persist() {
        var out: [UUID: (Double, Double)] = [:]
        for (id, p) in pos { out[id] = (Double(p.x), Double(p.y)) }
        app.graph.updatePositions(out)
    }
}

/// Fits world positions into the viewport with pan/zoom, and hit-tests.
private struct Fit {
    let positions: [UUID: CGPoint]
    let size: CGSize
    let zoom: CGFloat
    let pan: CGSize
    let minX: CGFloat, minY: CGFloat, spanX: CGFloat, spanY: CGFloat
    let byID: [UUID: CGPoint]

    init(positions: [UUID: CGPoint], nodes: [GraphNode], size: CGSize, zoom: CGFloat, pan: CGSize) {
        self.positions = positions
        self.size = size; self.zoom = zoom; self.pan = pan
        self.byID = positions
        let xs = positions.values.map(\.x), ys = positions.values.map(\.y)
        minX = xs.min() ?? -1; minY = ys.min() ?? -1
        spanX = Swift.max(1, (xs.max() ?? 1) - minX)
        spanY = Swift.max(1, (ys.max() ?? 1) - minY)
    }

    func screen(_ n: GraphNode) -> CGPoint { screen(byID[n.id] ?? .zero) }

    func screen(_ world: CGPoint) -> CGPoint {
        let pad: CGFloat = 90
        let topPad: CGFloat = 70
        let w = size.width - pad * 2, h = size.height - topPad - pad
        let nx = (world.x - minX) / spanX
        let ny = (world.y - minY) / spanY
        let base = CGPoint(x: pad + nx * w, y: topPad + ny * h)
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: (base.x - cx) * zoom + cx + pan.width,
                       y: (base.y - cy) * zoom + cy + pan.height)
    }

    func nearest(to pt: CGPoint, nodes: [GraphNode]) -> GraphNode? {
        var best: GraphNode?; var bestD = 22.0
        for n in nodes {
            let p = screen(n)
            let d = Double(hypot(p.x - pt.x, p.y - pt.y))
            if d < bestD { bestD = d; best = n }
        }
        return best
    }
}

private extension CGVector {
    static func += (l: inout CGVector, r: CGVector) { l.dx += r.dx; l.dy += r.dy }
}
