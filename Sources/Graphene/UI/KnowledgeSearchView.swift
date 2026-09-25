import SwiftUI

/// Captured page context stays put while the user follows links and citations.
struct KnowledgeSearchView: View {
    var scopedNodes: [GraphNode]? = nil
    var threadTitle: String? = nil
    var embedded = false
    var body: some View { ChatView(scopedNodes: scopedNodes, threadTitle: threadTitle, embedded: embedded) }
}
