import Foundation
import Combine

func jsLiteral(_ text: String) -> String {
    String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
}
struct Boost: Codable, Identifiable, Equatable {
    var id: String { host }
    var host: String
    var enabled = true
    var css = ""
    var javascript = ""
    var font = "Default"
    var scale: Double = 1
    var preset = "Default"
    var selectors: [String] = []
    var renderedCSS: String {
        guard enabled else { return "" }
        var result = css + "\n"
        if font != "Default" { result += "body, body * { font-family: \(font == "Serif" ? "Georgia, serif" : "system-ui, sans-serif") !important; }\n" }
        if scale != 1 { result += "body { zoom: \(min(2, max(0.5, scale))); }\n" }
        switch preset {
        case "Dim": result += "html { color-scheme: dark; filter: brightness(.8); }\n"
        case "Sepia": result += "html { filter: sepia(.65); }\n"
        case "Contrast": result += "html { filter: contrast(1.4); }\n"
        default: break
        }
        result += selectors.map { "\($0) { display: none !important; }" }.joined(separator: "\n")
        return result
    }
    var styleScript: String {
        """
        (() => { if(location.hostname.toLowerCase() !== \(jsLiteral(host))) return;
          const apply = () => { let s = document.getElementById('graphene-boost-style');
            if (!s) { s = document.createElement('style'); s.id = 'graphene-boost-style'; (document.head || document.documentElement).appendChild(s); }
            s.textContent = \(jsLiteral(renderedCSS)); };
          if(document.documentElement) apply(); else document.addEventListener('DOMContentLoaded', apply, {once:true});
        })();
        """
    }
    var codeScript: String {
        enabled ? "if(location.hostname.toLowerCase() === \(jsLiteral(host))) { (() => {\n\(javascript)\n})(); }" : ""
    }
}

final class Boosts: ObservableObject {
    @Published private(set) var items: [Boost] = []
    @Published private(set) var error: String?
    private let directory: URL
    private let persistent: Bool
    init(directory: URL, persistent: Bool = true) {
        self.directory = directory; self.persistent = persistent
        guard persistent else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                items.append(try JSONDecoder().decode(Boost.self, from: Data(contentsOf: file)))
            }
        } catch { self.error = "Boosts couldn’t be read: \(error.localizedDescription)" }
    }
    func boost(_ host: String) -> Boost { items.first { $0.host == host.lowercased() } ?? Boost(host: host.lowercased()) }
    func save(_ boost: Boost) throws {
        guard error == nil else { throw CocoaError(.fileReadCorruptFile) }
        guard !boost.host.isEmpty, boost.host.allSatisfy({ $0.isLetter || $0.isNumber || ".-:".contains($0) }) else { throw CocoaError(.fileWriteInvalidFileName) }
        if persistent { try JSONEncoder().encode(boost).write(to: directory.appendingPathComponent(boost.host + ".json"), options: .atomic) }
        items.removeAll { $0.host == boost.host }; items.append(boost)
    }
}
