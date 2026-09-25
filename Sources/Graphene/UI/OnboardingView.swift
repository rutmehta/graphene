import SwiftUI

/// First-run sheet (arc-look.md §3.7): 540×420, `display` heading, `body` copy.
struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step = 0
    /// The three preset hues offered on the colour step.
    static let swatches: [SpaceColor] = [.iris, .tide, .moss]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Welcome to Graphene").font(ShellType.display)
                Spacer(); Text("\(step + 1) of 3").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
            }
            if step == 0 {
                Text("Choose how your tabs feel.").font(ShellType.body).foregroundStyle(app.pal.ink2)
                HStack(spacing: 16) {
                    ForEach(BrowserLayout.allCases, id: \.self) { layout in
                        Button { app.layout = layout } label: {
                            VStack(spacing: 10) {
                                ZStack(alignment: layout == .sidebar ? .leading : .top) {
                                    RoundedRectangle(cornerRadius: ShellLayout.pageRadius).fill(app.pal.rowHover)
                                    RoundedRectangle(cornerRadius: ShellLayout.rowRadius).fill(app.pal.elev).padding(layout == .sidebar ? .leading : .top, 38).padding(ShellLayout.windowGap)
                                    VStack(spacing: 5) { ForEach(0..<3) { _ in Capsule().fill(app.pal.ink3).frame(width: layout == .sidebar ? 18 : 40, height: 3) } }
                                        .padding(14)
                                }.frame(width: 222, height: 140)
                                    .overlay(RoundedRectangle(cornerRadius: ShellLayout.pageRadius).strokeBorder(app.layout == layout ? app.pal.accent : app.pal.hairline, lineWidth: app.layout == layout ? 2 : ShellLayout.hairline))
                                Text(layout.title).font(app.layout == layout ? ShellType.rowSelected : ShellType.row)
                            }
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.layout.\(layout.rawValue)").accessibilityLabel(layout.title).accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(app.layout == layout ? [.isSelected] : [])
                    }
                }
            } else if step == 1 {
                Text("Give your first space a color. The window takes on its gradient.").font(ShellType.body).foregroundStyle(app.pal.ink2)
                HStack(spacing: 16) {
                    ForEach(Self.swatches) { color in SpaceSwatch(color: color) }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("onboarding.color").accessibilityLabel("Space color")
            } else {
                Text("Your pages, notes and Boards stay on this Mac.").font(ShellType.title)
                Text("You can change layout, colors and shortcuts in Settings at any time, or import bookmarks from another browser. Passwords are not imported.")
                    .font(ShellType.body).foregroundStyle(app.pal.ink2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Button("Make Graphene the default browser…") { app.requestDefaultBrowser() }
                        .accessibilityIdentifier("onboarding.defaultBrowser").accessibilityLabel("Make Graphene the default browser").accessibilityAddTraits(.isButton)
                    Button("Open Settings") { finish(); app.settingsPresented = true }
                        .accessibilityIdentifier("onboarding.settings").accessibilityLabel("Open Settings").accessibilityAddTraits(.isButton)
                    Button("Import browser data…") { finish(); app.settingsPage = "Import"; app.settingsPresented = true }
                        .accessibilityIdentifier("onboarding.import").accessibilityLabel("Import browser data").accessibilityAddTraits(.isButton)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Skip setup") { finish() }
                    .accessibilityIdentifier("onboarding.skip").accessibilityLabel("Skip setup").accessibilityAddTraits(.isButton)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 }.accessibilityIdentifier("onboarding.back").accessibilityLabel("Back").accessibilityAddTraits(.isButton) }
                Button(step == 2 ? "Start browsing" : "Continue") { if step == 2 { finish() } else { step += 1 } }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.continue").accessibilityLabel(step == 2 ? "Start browsing" : "Continue").accessibilityAddTraits(.isButton)
            }
        }.font(ShellType.body).padding(28).frame(width: 540, height: 420)
            .foregroundStyle(app.pal.ink).background(app.pal.pageBg).tint(app.pal.accent)
            .interactiveDismissDisabled()
    }
    private func finish() { app.settings.onboardingComplete = true; app.onboardingPresented = false; app.persist() }
}

/// One live space swatch: the real chrome gradient (chromeTop → chromeBottom) the
/// preset produces in the current appearance, with a page card floating on it.
private struct SpaceSwatch: View {
    @EnvironmentObject var app: AppState
    let color: SpaceColor
    private var palette: Palette { Palette(mode: app.mode, space: color) }
    private var selected: Bool { app.activeSpace.theme == nil && app.activeSpace.color == color }
    var body: some View {
        Button { app.setColor(color) } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .trailing) {
                    palette.sidebarGradient
                    RoundedRectangle(cornerRadius: ShellLayout.rowRadius).fill(palette.pageBg)
                        .overlay(RoundedRectangle(cornerRadius: ShellLayout.rowRadius).strokeBorder(palette.pageBorder, lineWidth: ShellLayout.hairline))
                        .padding(.vertical, ShellLayout.windowGap).padding(.trailing, ShellLayout.windowGap).padding(.leading, 44)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3) { _ in Capsule().fill(palette.ink3).frame(width: 22, height: 3) }
                    }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: 148, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: ShellLayout.pageRadius))
                .overlay(RoundedRectangle(cornerRadius: ShellLayout.pageRadius).strokeBorder(selected ? app.pal.accent : app.pal.hairline, lineWidth: selected ? 2 : ShellLayout.hairline))
                Text(color.label).font(selected ? ShellType.rowSelected : ShellType.row)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.color.\(color.rawValue)").accessibilityLabel("\(color.label) space color")
            .accessibilityAddTraits(.isButton).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
