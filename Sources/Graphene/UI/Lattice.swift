import SwiftUI

/// Geometry of the empty-state hex lattice (graphene-identity.md §3.6): pointy-top
/// hexagons `cell` wide, odd rows shifted half a cell, tiled to cover a rectangle.
enum LatticeGeometry {
    /// The lattice is opaque down to this fraction of its height, then fades to clear.
    static let fadeStart: Double = 2.0 / 3.0

    /// Circumradius of a hexagon `cell` wide (flat-to-flat).
    static func radius(cell: CGFloat) -> CGFloat { cell / 3.0.squareRoot() }
    /// Vertical distance between row centres.
    static func rowPitch(cell: CGFloat) -> CGFloat { radius(cell: cell) * 1.5 }

    /// Centres of every hexagon that touches `size`, row by row.
    static func centers(in size: CGSize, cell: CGFloat) -> [CGPoint] {
        guard cell > 0, size.width > 0, size.height > 0 else { return [] }
        let r = radius(cell: cell), pitch = rowPitch(cell: cell)
        let rows = Int((size.height + r) / pitch) + 1
        let columns = Int(size.width / cell) + 2
        var points: [CGPoint] = []
        points.reserveCapacity(rows * columns)
        for row in 0..<rows {
            let offset = row.isMultiple(of: 2) ? 0 : cell / 2
            for column in 0..<columns {
                points.append(CGPoint(x: CGFloat(column) * cell + offset, y: CGFloat(row) * pitch))
            }
        }
        return points
    }

    /// The six vertices of the hexagon around `center`, clockwise from the top.
    static func vertices(center: CGPoint, cell: CGFloat) -> [CGPoint] {
        let r = radius(cell: cell)
        return (0..<6).map { index in
            let angle = (Double(index) * 60 - 90) * .pi / 180
            return CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
        }
    }

    /// One path for the whole lattice, so shared edges are stroked once (no doubled alpha).
    static func path(in size: CGSize, cell: CGFloat) -> Path {
        var path = Path()
        for center in centers(in: size, cell: cell) {
            let points = vertices(center: center, cell: cell)
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }
}

/// The hex lattice for the three empty states (new tab, Threads, Vault). 1pt `lattice`
/// strokes on `latticeCell` cells, fading out over the bottom third. Reduce Transparency
/// removes it entirely.
struct Lattice: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Height of the lattice band an empty state draws above its line of text.
    static let bandHeight: CGFloat = ShellLayout.latticeCell * 5

    var body: some View {
        if !reduceTransparency {
            Canvas { context, size in
                context.stroke(LatticeGeometry.path(in: size, cell: ShellLayout.latticeCell),
                               with: .color(app.pal.lattice), lineWidth: ShellLayout.hairline)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: LatticeGeometry.fadeStart),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
