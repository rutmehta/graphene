import Foundation

enum PageFont: String, Codable, CaseIterable {
    case website, system, serif, monospaced
    var title: String { switch self { case .website: return "Website default"; case .system: return "System sans"; case .serif: return "Serif"; case .monospaced: return "Monospaced" } }
    var css: String {
        let family: String
        switch self { case .website: return ""; case .system: family = "system-ui"; case .serif: family = "ui-serif, Georgia, serif"; case .monospaced: family = "ui-monospace, monospace" }
        return "body, p, li, h1, h2, h3, h4, h5, h6, blockquote { font-family: \(family) !important; }"
    }
    var script: String {
        """
        (() => { const apply = () => { let style = document.getElementById('graphene-page-font'); if (!style) { style = document.createElement('style'); style.id = 'graphene-page-font'; (document.head || document.documentElement).append(style); } style.textContent = \(jsLiteral(css)); }; if (document.documentElement) apply(); else document.addEventListener('DOMContentLoaded', apply, {once:true}); })();
        """
    }
}
