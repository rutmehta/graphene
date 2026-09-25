import SwiftUI
import CoreGraphics

/// Static textures (the chrome grain, the empty-state lattice) rasterised once per kind, pixel
/// size and scale into an alpha mask, and drawn as an image filled with their colour.
///
/// As `Canvas` views they redrew every time SwiftUI invalidated them: 2,400 rect fills for the
/// grain on each chrome update, including the space-switch cross-fade. The mask carries no
/// colour, so appearance and space changes (and their animation) reuse it; only a new size
/// renders again. A few sizes are kept, so a live window resize does not grow memory.
@MainActor
final class MaskRaster {
    static let shared = MaskRaster()

    struct Key: Hashable {
        var kind: String
        var width: Int
        var height: Int
        var scale: CGFloat
    }

    /// Sizes kept per process (most recent first).
    static let capacity = 6
    /// Larger areas (a very large Board canvas) are not rasterised; the caller draws directly.
    static let maxPixels = 4096 * 4096

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    /// Rasterisations performed, for tests.
    private(set) var renders = 0

    /// The mask for `kind` at `size` points and `scale`, drawing it with `draw` (in points,
    /// origin top-left, like `Canvas`) only when it is not cached. `nil` for an empty or
    /// oversized area.
    func image(kind: String, size: CGSize, scale: CGFloat, draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let scale = max(1, scale)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, width * height <= Self.maxPixels else { return nil }
        let key = Key(kind: kind, width: width, height: height, scale: scale)
        if let cached = images[key] {
            if order.first != key { order.removeAll { $0 == key }; order.insert(key, at: 0) }
            return cached
        }
        guard let context = Self.context(width: width, height: height) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        draw(context, size)
        guard let image = context.makeImage() else { return nil }
        renders += 1
        images[key] = image
        order.insert(key, at: 0)
        while order.count > Self.capacity { images[order.removeLast()] = nil }
        return image
    }

    /// An 8-bit alpha-only bitmap: a quarter of an RGBA one for a window-sized texture.
    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

/// Draws a cached `MaskRaster` mask filled with `color`, at the size it is offered.
struct RasterMaskFill: View {
    let kind: String
    let color: Color
    let draw: (CGContext, CGSize) -> Void
    /// Drawn instead when the area is too large to cache.
    var fallback: ((inout GraphicsContext, CGSize) -> Void)? = nil
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let mask = MaskRaster.shared.image(kind: kind, size: proxy.size, scale: scale, draw: draw) {
                Rectangle().fill(color)
                    .mask { Image(decorative: mask, scale: max(1, scale)).resizable().interpolation(.none) }
            } else if let fallback {
                Canvas { context, size in fallback(&context, size) }
            }
        }
    }
}
