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
            LibraryBar(title: "Mail", detail: unread > 0 ? "\(unread) unread" : nil) {
                if mail.isConnected {
                    if mail.isBusy { ProgressView().controlSize(.small).frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize) }
                    LibraryBarButton("Refresh inbox", system: "arrow.clockwise") { mail.reload() }.disabled(mail.isBusy)
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
                            ForEach(mail.items) { m in
                                MailRow(mail: m, on: m.id == mail.selected?.id) { mail.select(m.id) }
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

/// Sender initial on a `tileFill` disc; colour stays with favicons and the space gradient.
private struct SenderMark: View {
    @EnvironmentObject var app: AppState
    let initial: String
    let size: CGFloat
    var body: some View {
        Text(initial).font(size > ShellLayout.controlSize ? ShellType.rowSelected : ShellType.label).foregroundStyle(app.pal.ink2)
            .frame(width: size, height: size).background(app.pal.tileFill, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct MailRow: View {
    let mail: MailItem
    let on: Bool
    let tap: () -> Void
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        let pal = app.pal
        Button(action: tap) {
            HStack(alignment: .top, spacing: ShellLayout.rowInsetLeading) {
                SenderMark(initial: mail.initial, size: ShellLayout.iconSize + 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if mail.unread { Circle().fill(pal.accent).frame(width: 6, height: 6).accessibilityLabel("Unread") }
                        Text(mail.from).font(mail.unread ? ShellType.rowSelected : ShellType.row).foregroundStyle(pal.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(mail.timeLabel).font(ShellType.caption).monospacedDigit().foregroundStyle(pal.ink3)
                    }
                    (Text(mail.subject).foregroundStyle(pal.ink2) + Text("  \(mail.preview)").foregroundStyle(pal.ink3))
                        .font(ShellType.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, ShellLayout.rowInsetLeading).padding(.vertical, 10)
            .background((on || hovering) ? pal.rowHover : .clear, in: RoundedRectangle(cornerRadius: ShellLayout.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

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

    var body: some View {
        let pal = app.pal
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(mail.subject).font(ShellType.title).foregroundStyle(pal.ink)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(spacing: ShellLayout.rowInsetLeading) {
                    SenderMark(initial: mail.initial, size: ShellLayout.controlSize + 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mail.from).font(ShellType.rowSelected).foregroundStyle(pal.ink)
                        Text(mail.address).font(ShellType.secondary).foregroundStyle(pal.ink3)
                    }
                    Spacer()
                    Text(mail.timeLabel).font(ShellType.caption).monospacedDigit().foregroundStyle(pal.ink3)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hairline).frame(height: ShellLayout.hairline) }

            body(pal)

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
            .padding(.horizontal, 24).frame(height: ShellLayout.footerHeight)
            .overlay(alignment: .top) { Rectangle().fill(pal.hairline).frame(height: ShellLayout.hairline) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func body(_ pal: Palette) -> some View {
        if let email = store.bodyCache[mail.id] {
            if let html = email.html, !html.isEmpty {
                // Message HTML is authored for a light page, so it keeps the reading sheet behind it.
                WebEmailView(html: html).background(pal.rdBg)
            } else {
                ScrollView {
                    Text(email.text.isEmpty ? mail.preview : email.text)
                        .font(ShellType.row).foregroundStyle(pal.ink).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24).padding(.vertical, 20)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading message…").font(ShellType.secondary).foregroundStyle(pal.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Renders a full email's HTML body in a lightweight web view (JS disabled).
private struct WebEmailView: NSViewRepresentable {
    let html: String
    final class Coordinator { var loadedHTML: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        wv.loadHTMLString(wrapped(html), baseURL: nil)
    }

    private func wrapped(_ body: String) -> String {
        let lower = body.lowercased()
        let style = "<style>:root{color-scheme:light}body{font-family:-apple-system,system-ui,sans-serif;color:#1b1b20;margin:0;padding:20px 24px;font-size:13px;line-height:1.5;-webkit-text-size-adjust:100%}img{max-width:100%;height:auto}a{color:#645AA0}table{max-width:100%!important}</style>"
        if lower.contains("<head") {
            return body.replacingOccurrences(of: "<head", with: "\(style)<head", options: .caseInsensitive)
        }
        if lower.contains("<body") {
            return "\(style)\(body)"
        }
        return "<html><head><meta name='viewport' content='width=device-width'>\(style)</head><body>\(body)</body></html>"
    }
}
