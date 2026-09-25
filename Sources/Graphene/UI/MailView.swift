import SwiftUI
import WebKit

/// Mail — a first-class surface backed by your real Gmail (read-only). Shares the
/// shell and the vault, so a message is annotatable with provenance like any web page.
/// No sample data: connect to see your inbox.
struct MailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var mail: MailStore

    var body: some View {
        VStack(spacing: 0) {
            LibraryBar(title: "Mail", detail: unread > 0 ? "\(unread) unread" : nil, surface: .mail) {
                if mail.isConnected {
                    if mail.isBusy { ProgressView().controlSize(.small).frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize) }
                    LibraryBarButton("Refresh inbox", system: "arrow.clockwise") { mail.reload() }.disabled(mail.isBusy)
                } else {
                    Text("Read-only. Graphene never sends mail.").font(ShellType.caption).foregroundStyle(app.pal.ink3)
                        .lineLimit(1).padding(.trailing, ShellLayout.rowInsetLeading)
                }
                LibraryBarButton("Open Gmail on the web", system: "safari") { app.openTab(url: URL(string: "https://mail.google.com")!, parent: nil, activate: true) }
            }
            if mail.isConnected { connected } else { ConnectGmail() }
        }
        .foregroundStyle(app.pal.ink).background(app.pal.pageBg)
        .task { mail.bootstrap() }
    }

    private var unread: Int { mail.items.filter { $0.unread }.count }

    private var connected: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if mail.items.isEmpty {
                    SurfaceState(symbol: mail.errorText == nil ? "envelope" : "exclamationmark.triangle", title: mail.isBusy ? "Loading inbox" : (mail.errorText == nil ? "No messages" : "Mail unavailable"), detail: mail.errorText ?? "Your inbox is read-only.", loading: mail.isBusy) {
                        if !mail.isBusy { Button("Refresh") { mail.reload() }.buttonStyle(.bordered) }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(mail.conversations) { conversation in
                                ConversationRows(conversation: conversation, expanded: mail.expandedConversations.contains(conversation.id))
                            }
                        }.padding(ShellLayout.windowGap)
                    }
                }
            }
            .frame(width: 340)
            Rectangle().fill(app.pal.hairline).frame(width: ShellLayout.hairline)
            if let m = mail.selected {
                MailReading(mail: m)
            } else {
                Text("Select a message").font(ShellType.row).foregroundStyle(app.pal.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A conversation: its first message, then replies indented one step under it and joined by
/// the thread connector (the sidebar's `ProvenanceConnector` geometry at 44pt rows). Collapsed
/// conversations show the latest three replies behind an "N more" label.
private struct ConversationRows: View {
    let conversation: MailConversation
    let expanded: Bool
    @EnvironmentObject var app: AppState
    @EnvironmentObject var mail: MailStore

    var body: some View {
        let rows = conversation.rows(expanded: expanded)
        VStack(spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .message(let item, let reply):
                    MailRow(mail: item, reply: reply, on: item.id == mail.selected?.id) { mail.select(item.id) }
                case .more(let count):
                    toggle("\(count) more")
                case .fewer:
                    toggle("Show fewer")
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let connector = conversation.connector(expanded: expanded) {
                Path { path in
                    path.addRect(connector.vertical)
                    connector.ticks.forEach { path.addRect($0) }
                }
                .fill(app.pal.threadLine)
                .allowsHitTesting(false)
            }
        }
    }

    private func toggle(_ title: String) -> some View {
        Button { mail.toggleExpanded(conversation.id) } label: {
            Text(title).font(ShellType.label).monospacedDigit().foregroundStyle(app.pal.ink3)
                .padding(.leading, ShellLayout.rowInsetLeading + ShellLayout.threadIndent + ShellLayout.iconSlot + ShellLayout.iconGap)
                .frame(maxWidth: .infinity, minHeight: MailLayout.rowHeight, maxHeight: MailLayout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct ConnectGmail: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var mail: MailStore

    var body: some View {
        SurfaceState(symbol: "envelope", title: "Connect your inbox", detail: "Read-only Gmail alongside your research. Save useful messages to your Vault with a link to the original.", loading: mail.isBusy) {
            VStack(spacing: 12) {
                Button { mail.connect() } label: {
                    Text(mail.isBusy ? "Waiting for Google…" : "Connect Gmail").font(ShellType.rowSelected)
                }
                .buttonStyle(.bordered)
                .disabled(mail.isBusy || !mail.isConfigured)
                .padding(.top, 4)

                Button("Open Gmail on the web") { app.openTab(url: URL(string: "https://mail.google.com")!, parent: nil, activate: true) }
                    .buttonStyle(.plain).font(ShellType.secondary).foregroundStyle(app.pal.ink2)

                if !mail.isConfigured {
                    Text("Gmail setup is required. Open Gmail on the web to use your inbox now.")
                        .font(ShellType.secondary).foregroundStyle(app.pal.ink3)
                }
                if let err = mail.errorText {
                    Text(err).font(ShellType.secondary).foregroundStyle(app.pal.danger)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                }
            }
        }
    }
}

/// A two-line 44pt row: sender (`rowSelected` when unread) and subject, preview beneath, date
/// trailing. The icon slot holds the unread dot; there are no avatars.
private struct MailRow: View {
    let mail: MailItem
    var reply = false
    let on: Bool
    let tap: () -> Void
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        let pal = app.pal
        Button(action: tap) {
            HStack(spacing: ShellLayout.iconGap) {
                ZStack {
                    if mail.showsUnreadDot {
                        Circle().fill(pal.accent).frame(width: ShellLayout.statusDot, height: ShellLayout.statusDot).accessibilityLabel("Unread")
                    }
                }.frame(width: ShellLayout.iconSlot, height: ShellLayout.iconSlot)
                VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                    HStack(spacing: ShellLayout.iconGap) {
                        Text(mail.from).font(mail.unread ? ShellType.rowSelected : ShellType.row).foregroundStyle(pal.ink).lineLimit(1).layoutPriority(1)
                        Text(mail.subject).font(ShellType.row).foregroundStyle(pal.ink2).lineLimit(1)
                        Spacer(minLength: ShellLayout.iconGap)
                        Text(mail.timeLabel).font(ShellType.caption).monospacedDigit().foregroundStyle(pal.ink3)
                    }
                    Text(mail.preview).font(ShellType.secondary).foregroundStyle(pal.ink3).lineLimit(1)
                }
            }
            .padding(.leading, ShellLayout.rowInsetLeading + (reply ? ShellLayout.threadIndent : 0)).padding(.trailing, ShellLayout.rowInsetLeading)
            .frame(height: MailLayout.rowHeight)
            .background((on || hovering) ? pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The reading pane: a chrome-type header (from, to, date) above the message body, which is
/// page content and so renders on the reader sheet (`rdBg`, the reader's reading face). Links in
/// the body open as child tabs of the tab Mail sits over.
private struct MailReading: View {
    let mail: MailItem
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: MailStore
    private var sourceURL: URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/")!
        components.queryItems = store.accountAddress.map { [URLQueryItem(name: "authuser", value: $0)] }
        components.fragment = "inbox/\(mail.id)"
        return components.url
    }
    private var reader: ReaderOptions { app.settings.reader ?? ReaderOptions() }

    var body: some View {
        let pal = app.pal
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ShellLayout.rowInsetLeading) {
                Text(mail.subject).font(ShellType.title).foregroundStyle(pal.ink)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(alignment: .firstTextBaseline, spacing: ShellLayout.iconGap) {
                    VStack(alignment: .leading, spacing: ShellLayout.iconBackingInset) {
                        header("From", mail.from == mail.address ? mail.address : "\(mail.from) <\(mail.address)>")
                        if let to = store.accountAddress { header("To", to) }
                    }
                    Spacer()
                    Text(mail.timeLabel).font(ShellType.caption).monospacedDigit().foregroundStyle(pal.ink3)
                }
            }
            .padding(.horizontal, ShellLayout.newTabGap).padding(.top, ShellLayout.newTabGap).padding(.bottom, ShellLayout.sectionGap)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hairline).frame(height: ShellLayout.hairline) }

            body(pal).frame(maxWidth: .infinity, maxHeight: .infinity).background(pal.rdBg)
                .environment(\.openURL, OpenURLAction { url in app.openMailLink(url); return .handled })

            HStack(spacing: ShellLayout.rowInsetLeading) {
                Text("Read-only").font(ShellType.caption).foregroundStyle(pal.ink3)
                Spacer()
                Button {
                    let text = store.bodyCache[mail.id]?.text ?? mail.preview
                    app.vault.add(text: text.isEmpty ? mail.preview : String(text.prefix(16000)), note: "", url: sourceURL, title: mail.subject, context: "From \(mail.from)", spaceID: app.activeSpaceID, provenance: "mail", accountScope: store.accountAddress)
                    app.notify(app.vault.errorText == nil ? "Saved to Vault" : "Couldn’t save message")
                } label: { Label("Save message to Vault", systemImage: "bookmark") }
                .buttonStyle(.plain).font(ShellType.secondary).foregroundStyle(pal.ink2).disabled(store.accountAddress == nil)
                Button("Ask about this message") {
                    app.attachedSources = [KnowledgeSource(id: UUID(), title: mail.subject, url: sourceURL?.absoluteString ?? "", text: store.bodyCache[mail.id]?.text ?? mail.preview, kind: "Mail")]
                    app.sendToAsk("Summarize this message")
                }.buttonStyle(.plain).font(ShellType.secondary).foregroundStyle(pal.accent).disabled(store.accountAddress == nil)
            }
            .padding(.horizontal, ShellLayout.newTabGap).frame(height: ShellLayout.footerHeight)
            .overlay(alignment: .top) { Rectangle().fill(pal.hairline).frame(height: ShellLayout.hairline) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ShellLayout.iconGap) {
            Text(label).font(ShellType.label).foregroundStyle(app.pal.ink3)
            Text(value).font(ShellType.secondary).foregroundStyle(app.pal.ink2).lineLimit(1).textSelection(.enabled)
        }
    }

    /// The reader's face at the reader's size, outside the shell type scale (as `ReaderPage`).
    private var readingFace: Font { Font.system(size: reader.size, design: reader.serif ? .serif : .default) }

    @ViewBuilder
    private func body(_ pal: Palette) -> some View {
        if let email = store.bodyCache[mail.id] {
            if let html = email.html, !html.isEmpty {
                WebEmailView(html: html, style: MailSheetStyle(reader: reader, ink: pal.rdInk, link: pal.accent)) { app.openMailLink($0) }
            } else {
                ScrollView {
                    Text(MailLinks.attributed(email.text.isEmpty ? mail.preview : email.text))
                        .font(readingFace).foregroundStyle(pal.rdInk).lineSpacing(ShellType.rowLineSpacing).textSelection(.enabled).tint(pal.accent)
                        .frame(maxWidth: reader.width, alignment: .leading)
                        .padding(.horizontal, ShellLayout.newTabGap).padding(.vertical, ShellLayout.newTabGap)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: ShellLayout.rowInsetLeading) {
                ProgressView().controlSize(.small)
                Text("Loading message…").font(ShellType.secondary).foregroundStyle(pal.rdInk2)
            }
        }
    }
}

/// Plain-text message bodies with their web links made tappable.
enum MailLinks {
    static func attributed(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return value }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: value),
                  let upper = AttributedString.Index(range.upperBound, within: value) else { continue }
            value[lower..<upper].link = url
        }
        return value
    }
}

/// The reader sheet's CSS for an HTML message: the reading face and size, reading ink, accent links.
struct MailSheetStyle: Equatable {
    var serif: Bool
    var size: Double
    var width: Double
    var ink: String
    var link: String

    init(reader: ReaderOptions, ink: Color, link: Color) {
        serif = reader.serif; size = reader.size; width = reader.width
        self.ink = Self.css(ink); self.link = Self.css(link)
    }

    static func css(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "inherit" }
        let channel = { (v: CGFloat) in Int((v * 255).rounded()) }
        return "rgba(\(channel(c.redComponent)),\(channel(c.greenComponent)),\(channel(c.blueComponent)),\(c.alphaComponent))"
    }

    var css: String {
        let face = serif ? "'New York',ui-serif,Georgia,serif" : "-apple-system,system-ui,sans-serif"
        return "<style>:root{color-scheme:light}html,body{background:transparent}body{font-family:\(face);color:\(ink);margin:0 auto;padding:24px;max-width:\(Int(width))px;font-size:\(Int(size))px;line-height:1.45;-webkit-text-size-adjust:100%}img{max-width:100%;height:auto}a{color:\(link)}table{max-width:100%!important}</style>"
    }
}

/// Renders a full email's HTML body on the reader sheet (JS disabled). Link clicks and
/// new-window requests go to `onLink` instead of navigating the message.
private struct WebEmailView: NSViewRepresentable {
    let html: String
    let style: MailSheetStyle
    let onLink: (URL) -> Void

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: (String, MailSheetStyle)?
        var onLink: (URL) -> Void = { _ in }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                onLink(url)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { onLink(url) }
            return nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        if let loaded = context.coordinator.loaded, loaded.0 == html, loaded.1 == style { return }
        context.coordinator.loaded = (html, style)
        wv.loadHTMLString(wrapped(html), baseURL: nil)
    }

    private func wrapped(_ body: String) -> String {
        let lower = body.lowercased()
        let css = style.css
        if lower.contains("<head") {
            return body.replacingOccurrences(of: "<head", with: "\(css)<head", options: .caseInsensitive)
        }
        if lower.contains("<body") {
            return "\(css)\(body)"
        }
        return "<html><head><meta name='viewport' content='width=device-width'>\(css)</head><body>\(body)</body></html>"
    }
}
