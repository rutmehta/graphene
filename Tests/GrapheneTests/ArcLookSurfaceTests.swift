import XCTest
import SwiftUI
import AppKit
@testable import Graphene

/// D5 (arc-look.md §3.7): Settings, onboarding, library surfaces and the reader draw only
/// from the shell tokens. The grep gate fails if a removed literal kind comes back.
@MainActor
final class ArcLookSurfaceTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Files swept in D5. `DownloadsView.swift` is gated from its popover body onward;
    /// the footer button above it belongs to the sidebar package.
    private static let files: [(path: String, fromMarker: String?)] = [
        ("Sources/Graphene/UI/SettingsView.swift", nil),
        ("Sources/Graphene/UI/AISettingsView.swift", nil),
        ("Sources/Graphene/UI/ImportSettings.swift", nil),
        ("Sources/Graphene/UI/ProfileSettings.swift", nil),
        ("Sources/Graphene/UI/BoostEditor.swift", nil),
        ("Sources/Graphene/UI/OnboardingView.swift", nil),
        ("Sources/Graphene/UI/LedgerView.swift", nil),
        ("Sources/Graphene/UI/ThreadSummaryView.swift", nil),
        ("Sources/Graphene/UI/VaultView.swift", nil),
        ("Sources/Graphene/UI/MailView.swift", nil),
        ("Sources/Graphene/UI/EaselView.swift", nil),
        ("Sources/Graphene/UI/ArchiveView.swift", nil),
        ("Sources/Graphene/UI/DownloadsView.swift", ".popover("),
        ("Sources/Graphene/UI/WritingHelpView.swift", nil),
        ("Sources/Graphene/Web/ReaderMode.swift", nil),
        ("Sources/Graphene/Mail/MailStore.swift", nil),
    ]

    /// Literal kinds replaced by tokens: font sizes, corner radii, colour opacity, raw
    /// white/red, hex colours, bare `.secondary`, `.headline`, and the retired aliases.
    private static let banned: [(name: String, pattern: String)] = [
        ("font size literal", #"\.font\(\.system\(size:"#),
        ("corner radius literal", #"cornerRadius:\s*[0-9]"#),
        ("opacity literal", #"\.opacity\("#),
        ("raw white", #"(Color)?\.white\b"#),
        ("raw red", #"(Color)?\.red\b"#),
        ("hex colour", #"Color\(hex:"#),
        ("system secondary style", #"[(\s,]\.secondary\b"#),
        ("headline font", #"\.headline\b"#),
        ("ground alias", #"pal\.ground\b"#),
        ("accentText alias", #"\.accentText\b"#),
    ]

    func testSweptFilesUseTokensOnly() throws {
        var failures: [String] = []
        for file in Self.files {
            let source = try String(contentsOf: Self.root.appendingPathComponent(file.path), encoding: .utf8)
            var lines = source.components(separatedBy: .newlines).enumerated().map { ($0.offset + 1, $0.element) }
            if let marker = file.fromMarker {
                let start = try XCTUnwrap(lines.firstIndex { $0.1.contains(marker) }, "\(file.path) lost its \(marker) marker")
                lines = Array(lines[start...])
            }
            for (number, line) in lines where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for rule in Self.banned where line.range(of: rule.pattern, options: .regularExpression) != nil {
                    failures.append("\(file.path):\(number): \(rule.name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Literals remain:\n" + failures.joined(separator: "\n"))
    }

    func testReaderUsesTheSharedPalette() throws {
        let reader = try String(contentsOf: Self.root.appendingPathComponent("Sources/Graphene/Web/ReaderMode.swift"), encoding: .utf8)
        XCTAssertNil(reader.range(of: #"Palette\("#, options: .regularExpression), "ReaderPage must read app.pal, not build its own Palette")
        XCTAssertTrue(reader.contains("let pal = app.pal") && reader.contains("pal.rdBg"))
    }

    func testLibrarySurfacesShareThePageToolbarBar() throws {
        for path in ["LedgerView", "VaultView", "MailView", "EaselView", "ArchiveView"] {
            let source = try String(contentsOf: Self.root.appendingPathComponent("Sources/Graphene/UI/\(path).swift"), encoding: .utf8)
            XCTAssertTrue(source.contains("LibraryBar(title:"), "\(path) must render the 32pt library bar")
        }
        let bar = try String(contentsOf: Self.root.appendingPathComponent("Sources/Graphene/UI/LedgerView.swift"), encoding: .utf8)
        XCTAssertTrue(bar.contains(".frame(height: ShellLayout.pageToolbarHeight)"))
        XCTAssertTrue(bar.contains("app.pal.pageBg"))
        XCTAssertEqual(ShellLayout.pageToolbarHeight, 32)
    }

    func testOnboardingSwatchesRenderThreeDistinctGradients() throws {
        XCTAssertEqual(OnboardingView.swatches.count, 3)
        for mode in [ThemeMode.dark, .light] {
            var tops: Set<[Int]> = []
            for color in OnboardingView.swatches {
                let palette = Palette(mode: mode, space: color)
                let top = try XCTUnwrap(NSColor(palette.chromeTop).usingColorSpace(.sRGB))
                let bottom = try XCTUnwrap(NSColor(palette.chromeBottom).usingColorSpace(.sRGB))
                XCTAssertNotEqual(top, bottom, "\(color) swatch must show a two-stop gradient")
                tops.insert([top.redComponent, top.greenComponent, top.blueComponent].map { Int(($0 * 255).rounded()) })
            }
            XCTAssertEqual(tops.count, 3, "The three preset hues must read as three different spaces in \(mode)")
        }
    }

    func testSemanticAndTileTokens() throws {
        let dark = Palette(mode: .dark, space: .iris), light = Palette(mode: .light, space: .iris)
        let danger = try XCTUnwrap(NSColor(dark.danger).usingColorSpace(.sRGB))
        XCTAssertEqual(danger.alphaComponent, 0.7, accuracy: 0.001)
        XCTAssertEqual(NSColor(dark.tileFill).usingColorSpace(.sRGB), NSColor(dark.fill).usingColorSpace(.sRGB))
        XCTAssertEqual(NSColor(light.tileFill).usingColorSpace(.sRGB), NSColor(light.rowHover).usingColorSpace(.sRGB),
                       "Light tiles fall back to rowHover so they stay visible on a white page")
    }
}
