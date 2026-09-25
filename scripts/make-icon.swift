import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        NSColor(srgbRed: 0.26, green: 0.34, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill()
        let path = NSBezierPath()
        let points: [NSPoint] = [.init(x: 512, y: 790), .init(x: 750, y: 650), .init(x: 750, y: 374), .init(x: 512, y: 234), .init(x: 274, y: 374), .init(x: 274, y: 650)]
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.close()
        path.lineWidth = 46; path.lineJoinStyle = .round
        NSColor(srgbRed: 0.94, green: 0.96, blue: 0.91, alpha: 1).setStroke()
        path.stroke()
        let branch = NSBezierPath(); branch.move(to: points[2]); branch.line(to: .init(x: 512, y: 512)); branch.line(to: points[4]); branch.move(to: .init(x: 512, y: 512)); branch.line(to: points[0]); branch.lineWidth = 29; branch.stroke()
        NSColor(srgbRed: 0.94, green: 0.96, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 469, y: 469, width: 86, height: 86)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
