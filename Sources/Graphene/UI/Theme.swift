import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Linear blend toward `other` by `t` (0…1) in sRGB — our stand-in for CSS color-mix.
    func mixed(with other: Color, by t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = CGFloat(max(0, min(1, t)))
        return Color(.sRGB,
                     red: Double(a.redComponent + (b.redComponent - a.redComponent) * t),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * t),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * t),
                     opacity: 1)
    }
}

// MARK: - design knobs (user-controlled, Arc-style)

enum ThemeMode: String, Codable, CaseIterable { case light, dark, automatic }

/// Layout tokens, in points. `docs/design/arc-look.md` §2.1 is the source of truth.
enum ShellLayout {
    // Window and page card
    static let windowGap: CGFloat = 8
    static let windowOutline: CGFloat = 1
    static let pageRadius: CGFloat = 10
    static let pageToolbarHeight: CGFloat = 32
    static let minimumPageWidth: CGFloat = 480
    // Sidebar
    static let sidebarDefault: CGFloat = 224
    static let sidebarRange: ClosedRange<CGFloat> = 180...360
    static let collapseThreshold: CGFloat = 160
    static let trafficBandHeight: CGFloat = 44
    /// Traffic lights sit centred at y = 22, first centre at x = 20, 20pt apart.
    static let trafficLightCenterY: CGFloat = 22
    static let trafficLightLeading: CGFloat = 20
    static let trafficLightSpacing: CGFloat = 20
    /// Clearance from the window's left edge kept free for the traffic lights.
    static let trafficReserve: CGFloat = 84
    static func favoriteColumns(width contentWidth: CGFloat) -> Int { contentWidth >= 300 ? 4 : 3 }
    static let favoriteGap: CGFloat = 10
    static let favoriteHeight: CGFloat = 44
    static let favoriteRadius: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let rowPitch: CGFloat = 40
    static let rowRadius: CGFloat = 8
    static let rowInsetLeading: CGFloat = 8
    static let iconSize: CGFloat = 16
    static let favoriteIconSize: CGFloat = 20
    static let controlSize: CGFloat = 28
    static let footerHeight: CGFloat = 36
    static let sectionGap: CGFloat = 12
    static let hairline: CGFloat = 1
    // Sidebar details (arc-look.md §3.3)
    /// Favicon/glyph slot at a row's leading edge, and the gap to the title.
    static let iconSlot: CGFloat = 20
    /// A favicon drawn on a contrast backing sits this far inside it.
    static let iconBackingInset: CGFloat = 2
    /// Corner radius of the favicon contrast backing.
    static let iconBackingRadius: CGFloat = 4
    static let iconGap: CGFloat = 8
    static let spaceLabelHeight: CGFloat = 24
    /// Hit target of a row's close glyph and the space label's `…`.
    static let closeTarget: CGFloat = 24
    static let folderIndent: CGFloat = 20
    /// Provenance rows in Today (graphene-identity.md §2): per-depth indent of a child row,
    /// x of the connector hairline from the parent row's leading edge, and the deepest indent.
    static let threadIndent: CGFloat = 20
    static let threadLineInset: CGFloat = 17
    /// A connector tick's run from the vertical's x to the child's icon slot edge
    /// (`threadLineInset + threadTick == threadIndent + rowInsetLeading`), so it enters the favicon column.
    static let threadTick: CGFloat = 11
    static let threadMaxDepth = 3
    /// Thread map (graphene-language.md §4, §5.2): a node's favicon slot (favicon 16 in a 20
    /// slot), the column pitch per depth, and the row pitch (the sidebar's `rowPitch`).
    static let threadNodeSize: CGFloat = 20
    static let threadColumn: CGFloat = 180
    static let threadRowPitch: CGFloat = 40
    /// Threads surface: the thread list column, and the selected thread's one-line header strip
    /// (title, counts, Continue browsing) under the library bar.
    static let threadListWidth: CGFloat = 260
    static let threadHeaderHeight: CGFloat = 44
    /// Reset-tab dot on a pinned favicon and footer space dots.
    static let statusDot: CGFloat = 6
    static let spaceDotPitch: CGFloat = 14
    static let sidebarAddressHeight: CGFloat = 28
    /// Invisible resize strip at the sidebar's trailing edge.
    static let resizeStrip: CGFloat = 8
    /// Horizontal travel of the sidebar's space-switch slide.
    static let spaceSlide: CGFloat = 24
    /// Sidebar content inset: `windowGap` leading and trailing.
    static func sidebarContentWidth(_ sidebarWidth: CGFloat) -> CGFloat { sidebarWidth - 2 * windowGap }
    static func favoriteTileWidth(contentWidth: CGFloat) -> CGFloat {
        let columns = CGFloat(favoriteColumns(width: contentWidth))
        return (contentWidth - (columns - 1) * favoriteGap) / columns
    }
    /// Small inline key-hint chips ("esc", "⌘T").
    static let chipRadius: CGFloat = 4
    // Vault shelf (graphene-identity.md §3.5)
    /// The shelf row above the sidebar footer.
    static let shelfHeight: CGFloat = 44
    /// A shelf chip's width at most; chips are 32 tall.
    static let shelfChipWidth: CGFloat = 96
    static let shelfChipRadius: CGFloat = 8
    // Top-tabs layout strip
    static let topTabHeight: CGFloat = 40
    // Command bar
    static let commandWidth: CGFloat = 640
    static let commandRadius: CGFloat = 16
    static let commandInputHeight: CGFloat = 56
    static let commandRowHeight: CGFloat = 44
    /// Fraction of the window height from the top to the command bar's top edge.
    static let commandTop: CGFloat = 0.18
    /// Total horizontal clearance kept around the command bar: width is `min(commandWidth, window − commandMargin)`.
    static let commandMargin: CGFloat = 80
    /// Leading inset of the input row's glyph.
    static let commandInset: CGFloat = 20
    static let commandSectionHeight: CGFloat = 24
    /// Horizontal inset of result rows, and the list's top and bottom padding.
    static let commandListPadding: CGFloat = 8
    /// Rows shown before the result list scrolls.
    static let commandMaxRows = 8
    // Popovers and panels
    static let popoverRadius: CGFloat = 12
    /// Board cards (graphene-language.md §4): the popover radius.
    static let boardCardRadius: CGFloat = popoverRadius
    static let chatWidth: CGFloat = 420
    static let chatWidthRange: ClosedRange<CGFloat> = 360...560
    /// Peek card: at most this wide, inset from the page card on every side.
    static let peekMaxWidth: CGFloat = 900
    static let peekInset: CGFloat = 40
    /// Little Arc's floating panel.
    static let littleArcSize = CGSize(width: 760, height: 560)
    static let chatHeaderHeight: CGFloat = 44
    /// Context chips in the chat panel.
    static let chipHeight: CGFloat = 24
    static let composerMinHeight: CGFloat = 40
    // Toast, tab switcher, site controls
    static let toastMaxWidth: CGFloat = 420
    static let toastHeight: CGFloat = 40
    /// Distance from the page card's bottom edge.
    static let toastInset: CGFloat = 24
    static let thumbnailSize = CGSize(width: 96, height: 60)
    static let siteControlsWidth: CGFloat = 320
    // Resume page and lattice (graphene-identity.md §2, graphene-language.md §4)
    /// Content column of the new-tab (Resume) page.
    static let newTabColumnWidth: CGFloat = 560
    /// Vertical gap between Resume page sections.
    static let newTabGap: CGFloat = 24
    /// The Resume page's space band, full card width, and its bottom fade into `pageBg`
    /// (landing-and-tidy.md §2).
    static let newTabBandHeight: CGFloat = 160
    static let newTabBandFade: CGFloat = 24
    /// The search row in the band, right-aligned to the column.
    static let newTabSearchWidth: CGFloat = 260
    /// A surface tile (Threads, Vault, Board, Mail): two favorite tiles tall.
    static let surfaceTileHeight: CGFloat = favoriteHeight * 2
    /// Width of one hex cell of the empty-state lattice.
    static let latticeCell: CGFloat = 28
    /// Padding of the in-page citation mark, in CSS px.
    static let markInset: CGFloat = 1
    // Annotations (graphene-language.md §5.3)
    /// The selection bar in the page.
    static let annotationBarHeight: CGFloat = 36
    /// The in-page note editor and note card, and their gap to the selection and the margin.
    static let annotationCardWidth: CGFloat = 320
    static let annotationGap: CGFloat = 8
    /// The quote rule's inset from the top and bottom of its quote.
    static let quoteRuleInset: CGFloat = 2
    /// The favicon on a Vault row's provenance line.
    static let provenanceIconSize: CGFloat = 12
    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(sidebarRange.upperBound, max(sidebarRange.lowerBound, width))
    }
}

/// SF Symbols with one meaning across the shell.
enum ShellGlyph {
    /// Ask / chat, wherever it appears: the page toolbar, the library bars, the command bar,
    /// the top-tabs toolbar.
    static let ask = "sparkle"
}

/// The shell's type scale (arc-look.md §2.2): system face, default design, nothing above 22.
enum ShellType {
    static let label = Font.system(size: labelSize, weight: .semibold)
    /// `label`'s point size, for the in-page annotation UI (CSS px).
    static let labelSize: CGFloat = 11
    static let caption = Font.system(size: 11, weight: .regular)
    static let secondary = Font.system(size: 12, weight: .regular)
    static let row = Font.system(size: rowSize, weight: .regular)
    static let rowSelected = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13, weight: .regular)
    static let title = Font.system(size: 15, weight: .semibold)
    static let input = Font.system(size: inputSize, weight: .regular)
    static let display = Font.system(size: 22, weight: .semibold)
    /// The space glyph in the Resume page's band.
    static let bandGlyph = Font.system(size: 24, weight: .regular)
    /// A surface tile's glyph on the Resume page.
    static let surfaceGlyph = Font.system(size: 20, weight: .regular)
    /// Toolbar and footer glyphs.
    static let glyph = Font.system(size: 15, weight: .medium)
    /// Close glyphs and space glyphs.
    static let glyphSmall = Font.system(size: 12, weight: .regular)
    /// Folder chevrons and inline status badges.
    static let glyphMini = Font.system(size: 10, weight: .regular)
    /// Code blocks in chat answers.
    static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// Page text quoted in chrome at small size (graphene-language.md §3): snippets, shelf chips.
    /// Chat body line height as a multiple of the font size.
    static let rowLineHeight: CGFloat = 1.45
    /// Extra leading that turns `row` into `rowLineHeight`.
    static var rowLineSpacing: CGFloat { rowSize * (rowLineHeight - 1) }
    /// Point sizes for AppKit text fields that take an `NSFont` (the command bar input).
    static let rowSize: CGFloat = 13
    static let inputSize: CGFloat = 18
    /// Text quoted from a page, anywhere in chrome: the system serif (New York) at 13/1.45.
    static let quote = Font.system(size: quoteSize, weight: .regular, design: .serif)
    /// Snippets and chips quoting a page: the system serif at 12.
    static let quoteSmall = Font.system(size: quoteSmallSize, weight: .regular, design: .serif)
    static let quoteSize: CGFloat = 13
    static let quoteSmallSize: CGFloat = 12
    /// `quote` line height as a multiple of the font size.
    static let quoteLineHeight: CGFloat = 1.45
    /// Extra leading that turns `quote` into `quoteLineHeight`.
    static var quoteLineSpacing: CGFloat { lineSpacing(size: quoteSize, lineHeight: quoteLineHeight) }
    /// The `lineSpacing` that sets text of `size` at `lineHeight` × size.
    static func lineSpacing(size: CGFloat, lineHeight: CGFloat) -> CGFloat { size * (lineHeight - 1) }
}

/// A grounded space color: two gradient stops + a readable accent. Not neon.
/// Declaration order is the picker order; raw values are what profiles store, so
/// reordering or adding cases never changes how saved spaces decode.
enum SpaceColor: String, Codable, CaseIterable, Identifiable {
    case graphite, iris, tide, moss, clay, slate
    /// The preset a new space (and a fresh profile's first space) starts with
    /// (graphene-identity.md §3.2). Saved spaces keep their own colour.
    static let defaultPreset: SpaceColor = .graphite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .graphite: return "Graphite"
        case .clay: return "Clay"; case .moss: return "Moss"; case .tide: return "Tide"
        case .iris: return "Iris"; case .slate: return "Slate"
        }
    }
    var c1: Color {
        switch self {
        case .graphite: return Color(hex: "868AA4")
        case .clay: return Color(hex: "C08361"); case .moss: return Color(hex: "7E9564")
        case .tide: return Color(hex: "5C87A2"); case .iris: return Color(hex: "8B80C6")
        case .slate: return Color(hex: "9A9486")
        }
    }
    var c2: Color {
        switch self {
        case .graphite: return Color(hex: "3E404D")
        case .clay: return Color(hex: "93402F"); case .moss: return Color(hex: "41603C")
        case .tide: return Color(hex: "2E4A63"); case .iris: return Color(hex: "4E4880")
        case .slate: return Color(hex: "565149")
        }
    }
    var accent: Color {
        switch self {
        case .graphite: return Color(hex: "545A81")
        case .clay: return Color(hex: "9C4536"); case .moss: return Color(hex: "4F7145")
        case .tide: return Color(hex: "3E6C8C"); case .iris: return Color(hex: "645AA0")
        case .slate: return Color(hex: "6C665D")
        }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Chrome saturation for the preset. The swatch colours are muted (s ≈ 0.13–0.5), which
    /// left the flooded gradient nearly flat; presets drive the chrome at s ≥ 0.6, like the
    /// Arc calibration capture (arc-look.md §2.3); Slate stays at 0 as the neutral grey preset.
    /// Graphite (hue 232°) sits at 0.12, so s′ = 0.56: a graphite neutral rather than a colour
    /// (graphene-identity.md §3.2). Custom themes keep their own saturation.
    var presetSaturation: Double {
        switch self {
        case .graphite: return 0.12
        case .clay: return 0.68; case .moss: return 0.62; case .tide: return 0.66
        case .iris: return 0.64; case .slate: return 0
        }
    }
    /// The preset as a hue and saturation: the swatch's hue with `presetSaturation`.
    var theme: SpaceTheme {
        let color = NSColor(c1).usingColorSpace(.sRGB) ?? .systemBlue
        return SpaceTheme(hue: Double(color.hueComponent), saturation: presetSaturation)
    }
}

/// How a favicon reads against the chrome, from its alpha-weighted mean colour.
enum FaviconTone: Equatable {
    /// A near-black, near-grey mark (GitHub): vanishes on dark chrome.
    case dark
    /// A near-white, near-grey mark: vanishes on light chrome.
    case light
    /// Anything with enough colour or mid-tone to stand on either chrome.
    case other

    /// Mean relative luminance below this, with low colourfulness, is a dark icon.
    static let darkLuminance = 0.35
    /// Mean relative luminance above this, with low colourfulness, is a light icon.
    static let lightLuminance = 0.8
    /// Mean sRGB chroma (max − min channel) at or above this counts as colourful.
    static let maxChroma = 0.2
    /// Icons whose visible pixels cover less than this fraction are not classified.
    static let minimumCoverage = 0.02

    static func classify(meanLuminance: Double, meanChroma: Double) -> FaviconTone {
        guard meanChroma < maxChroma else { return .other }
        if meanLuminance < darkLuminance { return .dark }
        if meanLuminance > lightLuminance { return .light }
        return .other
    }
}

/// One of the browser's first-class surfaces (the app tiles in the sidebar).
enum Surface: String, CaseIterable { case web, threads, mail, vault, board }


/// The resolved color system for the current (mode, space), per arc-look.md §2.3.
/// Recomputed cheaply from AppState's published knobs, so any view that reads it
/// updates on change. The window is flooded with the space's two-stop chrome
/// gradient; every fill on top of it is translucent ink, and colour otherwise
/// comes only from `accent`.
struct Palette {
    let mode: ThemeMode
    let space: SpaceColor
    var theme: SpaceTheme? = nil
    var neutralChrome = false
    var isDark: Bool {
        mode == .dark || (mode == .automatic && NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    // MARK: space input

    /// Hue and saturation (0…1) of the space: its custom theme, else the preset's.
    private var spaceHS: (hue: Double, saturation: Double) {
        let theme = theme ?? space.theme
        return (min(1, max(0, theme.hue)), min(1, max(0, theme.saturation)))
    }
    /// `s′ = 0.5 + 0.5·s`, so a tinted space never turns grey; a neutral space (s = 0)
    /// and the top-tabs layout (`neutralChrome`) get `s′ = 0`.
    var chromeSaturation: Double {
        let s = spaceHS.saturation
        return neutralChrome || s <= 0 ? 0 : 0.5 + 0.5 * s
    }
    private static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> Color {
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        return Color(hue: wrapped < 0 ? wrapped + 1 : wrapped, saturation: min(1, max(0, saturation)), brightness: brightness)
    }

    // MARK: chrome plane

    /// Dark coefficients are calibrated to the Arc capture (#0E0D26 → #200A26 at h = 243°, s = 0.6).
    /// Light stops carry the space visibly (landing-and-tidy.md §3): graphite light is a cool grey-blue.
    var chromeTop: Color {
        isDark ? Self.hsb(spaceHS.hue, 0.82 * chromeSaturation, 0.15)
               : Self.hsb(spaceHS.hue, 0.30 * chromeSaturation, 0.93)
    }
    var chromeBottom: Color {
        isDark ? Self.hsb(spaceHS.hue + 44.0 / 360, 0.92 * chromeSaturation, 0.15)
               : Self.hsb(spaceHS.hue + 25.0 / 360, 0.34 * chromeSaturation, 0.90)
    }
    var grainOpacity: Double { 0.02 }
    var chromeGrain: Color { (isDark ? Color.white : Color.black).opacity(grainOpacity) }

    // MARK: ink and translucent fills

    var ink: Color { isDark ? .white : Color(hex: "1B1B22") }
    var ink2: Color { ink.opacity(isDark ? 0.72 : 0.75) }
    var ink3: Color { ink.opacity(isDark ? 0.48 : 0.50) }
    /// Disabled glyphs and labels.
    var inkDisabled: Color { ink.opacity(0.25) }
    var fill: Color { Color.white.opacity(isDark ? 0.09 : 0.55) }
    var fillHover: Color { Color.white.opacity(isDark ? 0.14 : 0.60) }
    var fillSelected: Color { Color.white.opacity(isDark ? 0.22 : 0.85) }
    var fillSelectedStroke: Color { isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.08) }
    var rowHover: Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04) }
    var rowSelected: Color { Color.white.opacity(isDark ? 0.12 : 0.60) }
    /// `fill` for tiles that sit on the page card (Vault grid, mail avatars). On light chrome
    /// `fill` is translucent white, which vanishes on a white `pageBg`, so it falls back to `rowHover`.
    var tileFill: Color { isDark ? fill : rowHover }
    /// `tileFill` hovered: `fillHover` in dark; in light a deeper ink wash, since white vanishes on `pageBg`.
    var tileFillHover: Color { isDark ? fillHover : Color.black.opacity(0.07) }
    var hairline: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    /// The provenance connector under Today rows, and the one on the selected tab's branch.
    var threadLine: Color { ink.opacity(isDark ? 0.18 : 0.24) }
    var threadLineActive: Color { accent.opacity(0.60) }
    /// `fill` for chips, bubbles and fields on an `elev` surface: light `fill` is white, which vanishes on a white card.
    var elevFill: Color { isDark ? fill : rowHover }
    /// The provenance connector hairline (graphene-identity.md §2).
    /// The 1pt rule beside a quote block: the thread, drawn vertically.
    var quoteRule: Color { threadLine }
    /// Empty-state hex lattice strokes.
    var lattice: Color { ink.opacity(0.04) }
    /// The Resume page's space band (landing-and-tidy.md §2): the chrome stops over `pageBg`,
    /// at 55% in light and 70% in dark, so a new tab carries its space.
    var bandOpacity: Double { isDark ? 0.70 : 0.55 }
    var bandTop: Color { chromeTop.opacity(bandOpacity) }
    var bandBottom: Color { chromeBottom.opacity(bandOpacity) }
    /// The band's bottom fade: `pageBg` from clear to opaque.
    var bandFade: Color { pageBg.opacity(0) }
    /// In-page citation highlight (injected as CSS).
    var highlight: Color { accent.opacity(0.22) }
    /// Hovered or selected in-page citation.
    var highlightActive: Color { accent.opacity(0.38) }    /// A practically invisible fill that still receives hover and drops.
    var hitTarget: Color { Color.black.opacity(0.001) }

    // MARK: page card and elevated surfaces

    /// Native surfaces on the card follow the chrome's scheme; web content paints its own background.
    var pageBg: Color { isDark ? Color(hex: "1E1E22") : .white }
    var pageBorder: Color { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08) }
    var pageShadow: Color { Color.black.opacity(isDark ? 0.35 : 0.10) }
    var pageShadowRadius: CGFloat { isDark ? 12 : 10 }
    var pageShadowY: CGFloat { isDark ? 2 : 1 }
    var windowOutline: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06) }
    var elev: Color { isDark ? Color(hex: "26262C") : .white }
    /// The collapsed sidebar peeking over the page card.
    var sidebarPeekBg: Color { elev.opacity(0.96) }
    var scrim: Color { Color.black.opacity(isDark ? 0.30 : 0.13) }
    /// Dimming over the page card behind the command bar.
    var commandScrim: Color { Color.black.opacity(isDark ? 0.20 : 0.10) }
    /// The command bar's deep shadow (same in both schemes).
    var commandShadow: Color { Color.black.opacity(0.30) }
    var commandShadowRadius: CGFloat { 32 }
    var commandShadowY: CGFloat { 12 }
    /// The light dimming behind the top-tabs integrated command bar.
    var scrimSubtle: Color { Color.black.opacity(isDark ? 0.075 : 0.035) }

    var accent: Color {
        isDark ? Self.hsb(spaceHS.hue, 0.45, 0.85) : Self.hsb(spaceHS.hue, 0.55, 0.62)
    }
    /// The focused split pane's border.
    var focusBorder: Color { accent.opacity(0.6) }
    /// Semantic system red at 70%, only for destructive and error state (§2.3), never decoration.
    var danger: Color { Color.red.opacity(0.7) }

    // MARK: aliases kept for existing views

    var sidebarBg: Color { chromeTop }
    var chromeBg: Color { chromeTop }
    var ground: Color { pageBg }
    var selection: Color { rowSelected }
    var hover: Color { rowHover }
    var active: Color { fillHover }
    var shadow: Color { pageShadow }
    var accentText: Color { accent }
    var accentSoft: Color { accent.opacity(0.15) }
    var sidebarGradient: LinearGradient {
        LinearGradient(colors: [chromeTop, chromeBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func luminance(_ color: Color) -> Double { luminance(NSColor(color)) }
    /// WCAG relative luminance of an sRGB colour (0 black … 1 white).
    static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? .black
        func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v / 12.92) : pow(Double((v + 0.055) / 1.055), 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    // MARK: favicon contrast

    /// Backing behind a dark favicon on dark chrome.
    var iconBacking: Color { Color.white.opacity(0.85) }
    /// Backing behind a very light favicon on light chrome.
    var iconBackingOnLight: Color { Color.black.opacity(0.72) }
    /// The backing a favicon of `tone` needs on this palette's chrome, if any.
    func iconBacking(for tone: FaviconTone) -> Color? {
        switch tone {
        case .dark: return isDark ? iconBacking : nil
        case .light: return isDark ? nil : iconBackingOnLight
        case .other: return nil
        }
    }

    // MARK: page-following card

    /// A page whose background luminance is below this reads as dark; the card and its
    /// toolbar then use the dark page tokens even under a light appearance, and vice versa.
    static let darkPageLuminance = 0.4
    /// Colours more transparent than this say nothing about the page and are ignored.
    static let pageColorMinimumAlpha: CGFloat = 0.5
    /// Whether a page's background (`themeColor`, else `underPageBackgroundColor`) is dark;
    /// `nil` when there is no usable colour yet.
    static func pageIsDark(_ color: NSColor?) -> Bool? {
        guard let color = color?.usingColorSpace(.sRGB), color.alphaComponent >= pageColorMinimumAlpha else { return nil }
        return luminance(color) < darkPageLuminance
    }
    /// The palette for native chrome drawn on a web page card: the dark or light scheme
    /// matching the page, keeping the space. `nil` (no report yet) follows the appearance.
    func page(dark: Bool?) -> Palette {
        guard let dark else { return self }
        return Palette(mode: dark ? .dark : .light, space: space, theme: theme, neutralChrome: neutralChrome)
    }
    /// The page card fill: white over light pages, #1E1E22 over dark ones.
    func pageBg(dark: Bool?) -> Color { page(dark: dark).pageBg }
    /// Toolbar glyphs on the page card.
    func pageToolbarInk(dark: Bool?) -> Color { page(dark: dark).ink3 }
    /// The host in the toolbar's address run.
    func pageToolbarInkStrong(dark: Bool?) -> Color { page(dark: dark).ink2 }
    /// WCAG contrast of `ink` against the chrome's top stop.
    var inkContrast: Double {
        let a = Self.luminance(ink), b = Self.luminance(chromeTop)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // reading tokens — a clean, cool near-white sheet (a web page doesn't invert)
    var rdBg: Color   { Color(hex: "FCFCFD") }
    var rdInk: Color  { Color(hex: "252933") }
    var rdInk2: Color { Color(hex: "626875") }
    var rdInk3: Color { Color(hex: "727987") }
    var rdHair: Color { Color(hex: "E8ECF2") }
}
