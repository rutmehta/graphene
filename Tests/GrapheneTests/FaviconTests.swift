import XCTest
import AppKit
import SwiftUI
@testable import Graphene

/// Icon discovery order and the contrast backing for icons that vanish on the chrome.
@MainActor
final class FaviconTests: XCTestCase {
    private func solid(_ color: NSColor, side: Int = 32) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: side, height: side).fill(); image.unlockFocus()
        return image
    }

    func testSolidIconsClassifyByLuminance() {
        XCTAssertEqual(FaviconStore.tone(of: solid(.black)), .dark)
        XCTAssertEqual(FaviconStore.tone(of: solid(.white)), .light)
        XCTAssertEqual(FaviconStore.tone(of: solid(NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))), .other, "Colourful icons stand on either chrome")
        XCTAssertEqual(FaviconStore.tone(of: solid(NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1))), .other, "Light grey needs no backing")
        XCTAssertEqual(FaviconStore.tone(of: solid(.clear)), .other, "An empty icon is not classified")
    }

    func testToneThresholds() {
        XCTAssertEqual(FaviconTone.darkLuminance, 0.35)
        XCTAssertEqual(FaviconTone.classify(meanLuminance: 0.34, meanChroma: 0.05), .dark)
        XCTAssertEqual(FaviconTone.classify(meanLuminance: 0.36, meanChroma: 0.05), .other)
        XCTAssertEqual(FaviconTone.classify(meanLuminance: 0.1, meanChroma: 0.5), .other)
        XCTAssertEqual(FaviconTone.classify(meanLuminance: 0.95, meanChroma: 0.05), .light)
    }

    func testBackingOnlyWhereTheIconWouldVanish() throws {
        let dark = Palette(mode: .dark, space: .iris), light = Palette(mode: .light, space: .iris)
        let backing = try XCTUnwrap(dark.iconBacking(for: .dark))
        let white = try XCTUnwrap(NSColor(backing).usingColorSpace(.sRGB))
        XCTAssertEqual(white.alphaComponent, 0.85, accuracy: 0.001)
        XCTAssertEqual(white.redComponent, 1, accuracy: 0.001)
        XCTAssertNil(dark.iconBacking(for: .light))
        XCTAssertNil(dark.iconBacking(for: .other))
        XCTAssertNotNil(light.iconBacking(for: .light))
        XCTAssertNil(light.iconBacking(for: .dark))
        // On a light page card in dark appearance a black icon needs nothing.
        XCTAssertNil(dark.page(dark: false).iconBacking(for: .dark))
        XCTAssertEqual(ShellLayout.iconBackingInset, 2)
    }

    func testDeclaredIconsRankBeforeTheFallback() {
        let page = URL(string: "https://forums.swift.org/t/some-topic/123")!
        // forums.swift.org declares both icons on its CDN; its /favicon.ico answers 204.
        let links = FaviconDiscovery.links(from: [
            ["href": "https://global.discourse-cdn.com/swift/touch_180x180.png", "rel": "apple-touch-icon", "type": "image/png", "sizes": ""],
            ["href": "https://global.discourse-cdn.com/swift/icon_32x32.ico", "rel": "icon", "type": "image/vnd.microsoft.icon", "sizes": ""],
        ])
        XCTAssertEqual(FaviconDiscovery.candidates(links, page: page).map(\.absoluteString), [
            "https://global.discourse-cdn.com/swift/icon_32x32.ico",
            "https://global.discourse-cdn.com/swift/touch_180x180.png",
        ])
    }

    func testCandidateOrderWithinRel() {
        let page = URL(string: "https://example.org/")!
        let links = [
            FaviconLink(href: "/16.png", rel: "icon", sizes: "16x16", type: "image/png"),
            FaviconLink(href: "/mask.svg", rel: "mask-icon", type: "image/svg+xml"),
            FaviconLink(href: "/any.png", rel: "shortcut icon"),
            FaviconLink(href: "/96.png", rel: "icon", sizes: "96x96", type: "image/png"),
            FaviconLink(href: "/32.png", rel: "icon", sizes: "32x32", type: "image/png"),
            FaviconLink(href: "/vector.svg", rel: "icon", type: "image/svg+xml"),
            FaviconLink(href: "/32.png", rel: "icon", sizes: "32x32", type: "image/png"),
            FaviconLink(href: "/font.woff", rel: "icon", type: "font/woff"),
            FaviconLink(href: "http://example.org/insecure.png", rel: "icon"),
        ]
        XCTAssertEqual(FaviconDiscovery.candidates(links, page: page).map(\.path), ["/vector.svg", "/32.png", "/96.png", "/any.png"],
                       "SVG, then ≥ 32px ascending, then unsized; mask icons, other types, downgrades and duplicates drop; capped at four")
        XCTAssertEqual(FaviconDiscovery.maxCandidates, 4)
        XCTAssertTrue(FaviconDiscovery.links(from: "not a list").isEmpty)
        XCTAssertTrue(FaviconDiscovery.links(from: [["rel": "icon"]]).isEmpty, "A link without href is ignored")
    }

    func testDecodesSVGAndRejectsJunk() throws {
        let svg = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32"/></svg>"##.utf8)
        XCTAssertNotNil(FaviconStore.decode(svg))
        XCTAssertNil(FaviconStore.decode(Data("<html>not an icon</html>".utf8)))
        let tiff = try XCTUnwrap(solid(.white).tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        XCTAssertNotNil(FaviconStore.decode(png))
    }
}
