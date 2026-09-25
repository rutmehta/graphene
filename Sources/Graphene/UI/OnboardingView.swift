import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Welcome to Graphene").font(ShellType.display)
                Spacer(); Text("\(step + 1) of 3").foregroundStyle(app.pal.ink3)
            }
            if step == 0 {
                Text("Choose how your tabs feel.").font(ShellType.title)
                HStack(spacing: 18) {
                    ForEach(BrowserLayout.allCases, id: \.self) { layout in
                        Button { app.layout = layout } label: {
                            VStack(spacing: 12) {
                                ZStack(alignment: layout == .sidebar ? .leading : .top) {
                                    RoundedRectangle(cornerRadius: ShellLayout.pageRadius).fill(app.pal.hover)
                                    RoundedRectangle(cornerRadius: ShellLayout.rowRadius).fill(app.pal.elev).padding(layout == .sidebar ? .leading : .top, 38).padding(8)
                                    VStack(spacing: 5) { ForEach(0..<3) { _ in Capsule().fill(app.pal.ink3).frame(width: layout == .sidebar ? 18 : 40, height: 3) } }
                                        .padding(14)
                                }.frame(width: 210, height: 140)
                                    .overlay(RoundedRectangle(cornerRadius: ShellLayout.pageRadius).strokeBorder(app.layout == layout ? app.pal.accentText : app.pal.hairline, lineWidth: 2))
                                Text(layout.title).font(ShellType.rowSelected)
                            }
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.layout.\(layout.rawValue)").accessibilityLabel(layout.title).accessibilityAddTraits(.isButton)
                    }
                }
            } else if step == 1 {
                Text("Give your first space a color.").font(ShellType.title)
                Picker("Space color", selection: Binding(get: { app.activeSpace.color }, set: { app.setColor($0) })) {
                    ForEach(SpaceColor.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                    .accessibilityIdentifier("onboarding.color").accessibilityLabel("Space color")
                RoundedRectangle(cornerRadius: ShellLayout.popoverRadius).fill(app.pal.sidebarBg).frame(height: 140)
                    .overlay(Text(app.activeSpace.name).font(ShellType.title))
            } else {
                Text("Your pages, notes and Boards stay on this Mac.").font(ShellType.title)
                Text("You can change layout, colors and shortcuts in Settings at any time, or import bookmarks from another browser. Passwords are not imported.").foregroundStyle(app.pal.ink3)
                Button("Make Graphene the default browser…") { app.requestDefaultBrowser() }
                    .accessibilityIdentifier("onboarding.defaultBrowser").accessibilityLabel("Make Graphene the default browser").accessibilityAddTraits(.isButton)
                Button("Open Settings") { finish(); app.settingsPresented = true }
                    .accessibilityIdentifier("onboarding.settings").accessibilityLabel("Open Settings").accessibilityAddTraits(.isButton)
                Button("Import browser data…") { finish(); app.settingsPage = "Import"; app.settingsPresented = true }
                    .accessibilityIdentifier("onboarding.import").accessibilityLabel("Import browser data").accessibilityAddTraits(.isButton)
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
        }.padding(28).frame(width: 540, height: 410).foregroundStyle(app.pal.ink).background(app.pal.ground).tint(app.pal.accentText)
            .interactiveDismissDisabled()
    }
    private func finish() { app.settings.onboardingComplete = true; app.onboardingPresented = false; app.persist() }
}
