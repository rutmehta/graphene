import SwiftUI

struct CommandShortcut: Codable, Equatable {
    var key: String
    var command = true
    var option = false
    var control = false
    var shift = false
    var modifiers: EventModifiers {
        var value: EventModifiers = []
        if command { value.insert(.command) }; if option { value.insert(.option) }
        if control { value.insert(.control) }; if shift { value.insert(.shift) }
        return value
    }
    var hint: String { key.isEmpty ? "" : (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased() }
    init(key: String, command: Bool = true, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key.lowercased(); self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    init(action: BrowserAction) {
        key = action.key.map { String($0.character) } ?? ""
        command = action.modifiers.contains(.command); option = action.modifiers.contains(.option)
        control = action.modifiers.contains(.control); shift = action.modifiers.contains(.shift)
    }
}

extension AppState {
    func remapCommand(_ id: String, to shortcut: CommandShortcut) -> String? {
        guard allCommandActions.contains(where: { $0.id == id }) else { return "Unknown command." }
        if !shortcut.key.isEmpty {
            guard shortcut.key.count == 1, shortcut.command || shortcut.control || shortcut.option else { return "Choose one key with Command, Control or Option." }
            if shortcut.command && !shortcut.option && !shortcut.control && ["c", "x", "v", "a", "z", "q", "h", "m"].contains(shortcut.key) { return "Reserved for standard macOS editing or window commands." }
            if let other = allCommandActions.first(where: { $0.id != id && CommandShortcut(action: $0) == shortcut }) { return "Conflicts with \(other.title)." }
        }
        settings.shortcutOverrides[id] = shortcut
        return nil
    }
}
