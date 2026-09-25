import SwiftUI
import AppKit

struct SpaceEditor: View {
    @EnvironmentObject var app: AppState
    private var theme: SpaceTheme {
        if let theme = app.activeSpace.theme { return theme }
        let color = NSColor(app.activeSpace.color.c1).usingColorSpace(.deviceRGB) ?? .systemBlue
        return SpaceTheme(hue: color.hueComponent, saturation: color.saturationComponent)
    }
    private func binding<Value>(_ key: WritableKeyPath<SpaceTheme, Value>) -> Binding<Value> {
        Binding(get: { theme[keyPath: key] }, set: { value in var copy = theme; copy[keyPath: key] = value; app.updateSpaceTheme(copy) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Space").font(.system(size: 13, weight: .semibold))
                Spacer()
                IconButton("Done", system: "checkmark") { app.spaceEditorPresented = false }
            }
            TextField("Space name", text: Binding(get: { app.activeSpace.name }, set: { app.renameSpace(app.activeSpaceID, name: $0) }))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                ForEach(["circle.hexagongrid.fill", "leaf", "book", "briefcase", "globe", "star", "moon"], id: \.self) { icon in
                    Button { app.updateSpaceTheme(theme, icon: icon) } label: { Image(systemName: icon).frame(width: 24, height: 26) }
                        .buttonStyle(ShellButtonStyle(selected: app.activeSpace.icon == icon)).help(icon)
                        .accessibilityIdentifier("space.icon.\(icon)").accessibilityLabel(icon).accessibilityAddTraits(.isButton)
                }
            }
            TextField("SF Symbol name or emoji", text: Binding(get: { app.activeSpace.icon ?? "" }, set: { app.updateSpaceTheme(theme, icon: $0) }))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                ForEach(SpaceColor.allCases) { color in
                    Button { app.setColor(color) } label: {
                        Circle().fill(color.c1).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(app.pal.ink.opacity(app.activeSpace.color == color && app.activeSpace.theme == nil ? 0.7 : 0.1), lineWidth: 2))
                    }.buttonStyle(.plain).help(color.label)
                        .accessibilityIdentifier("space.color.\(color.rawValue)").accessibilityLabel(color.label).accessibilityAddTraits(.isButton)
                }
                Spacer()
            }
            // Two-dimensional hue/saturation plane. Sliders below offer keyboard equivalents.
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 0.7, brightness: 0.8) }, startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [app.pal.elev.opacity(0.85), app.pal.elev.opacity(0)], startPoint: .top, endPoint: .bottom)
                    Circle().strokeBorder(app.pal.ink, lineWidth: 2).background(Circle().fill(app.pal.elev.opacity(0.5)))
                        .frame(width: 12, height: 12).offset(x: theme.hue * (geometry.size.width - 12), y: theme.saturation * (geometry.size.height - 12))
                }.clipShape(RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        var copy = theme
                        copy.hue = min(1, max(0, value.location.x / geometry.size.width))
                        copy.saturation = min(1, max(0, value.location.y / geometry.size.height))
                        app.updateSpaceTheme(copy)
                    })
            }.frame(height: 90).accessibilityLabel("Hue and saturation; use sliders below for keyboard adjustment")
            labeledSlider("Hue", value: binding(\.hue), range: 0...1)
            labeledSlider("Saturation", value: binding(\.saturation), range: 0...1)
            labeledSlider("Intensity", value: binding(\.intensity), range: 0...0.65)
            Toggle("Gradient", isOn: binding(\.gradient))
            Toggle("Subtle grain", isOn: binding(\.grain))
            Picker("Appearance", selection: Binding(get: { app.mode }, set: { app.mode = $0; app.persist() })) {
                ForEach(ThemeMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
        }.font(.system(size: 12)).foregroundStyle(app.pal.ink)
            .padding(18).frame(width: 290).background(app.pal.sidebarBg)
            .environment(\.colorScheme, app.pal.isDark ? .dark : .light)
    }
    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(title).frame(width: 64, alignment: .leading); Slider(value: value, in: range).accessibilityLabel(title).accessibilityIdentifier("space.slider.\(title)") }
    }
}
