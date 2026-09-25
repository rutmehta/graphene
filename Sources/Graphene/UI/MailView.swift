import SwiftUI
import WebKit

/// Mail — a first-class surface backed by your real Gmail (read-only). Shares the
/// shell, the reading sheet, and (soon) the vault, so a message is annotatable
/// with provenance like any web page. No sample data: connect to see your inbox.
struct MailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var mail: MailStore

    var body: some View {
        Group {
            if mail.isConnected {
                connected
            } else {
                ConnectGmail()
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
        .task { mail.bootstrap() }
    }

    private var connected: some View {
        let pal = app.pal
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Inbox").font(.system(size: 12.5, weight: .medium)).foregroundStyle(pal.ink)
                    let unread = mail.items.filter { $0.unread }.count
                    if unread > 0 {
                        Text("\(unread)").font(.system(size: 10, design: .monospaced)).foregroundStyle(pal.ink3)
                    }
                    Spacer()
                    if mail.isBusy { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    Button { mail.reload() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).foregroundStyle(pal.ink3)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 4).padding(.bottom, 12)

                if mail.items.isEmpty {
                    SurfaceState(symbol: mail.errorText == nil ? "envelope" : "exclamationmark.triangle", title: mail.isBusy ? "Loading inbox" : (mail.errorText == nil ? "No messages" : "Mail unavailable"), detail: mail.errorText ?? "Your inbox is read-only.", loading: mail.isBusy) {
                        if !mail.isBusy { Button("Refresh") { mail.reload() }.buttonStyle(.bordered) }
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(mail.items) { m in
                            MailRow(mail: m, on: m.id == mail.selected?.id) { mail.select(m.id) }
                        }
                    }
                }
            }
            .frame(width: 340)

            if let m = mail.selected {
                MailReading(mail: m)
            } else {
                RoundedRectangle(cornerRadius: 11).fill(pal.rdBg)
                    .overlay(Text("Select a message").font(.system(size: 13)).foregroundStyle(pal.rdInk3))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(pal.rdHair))
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
                Text(mail.isBusy ? "Waiting for Google…" : "Connect Gmail").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(mail.isBusy || !mail.isConfigured)
            .padding(.top, 4)

            Button("Open Gmail on the web") { app.openTab(url: URL(string: "https://mail.google.com")!, parent: nil, activate: true) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(app.pal.ink2)

            if !mail.isConfigured {
                Text("Gmail setup is required. Open Gmail on the web to use your inbox now.")
                    .font(.system(size: 11.5)).foregroundStyle(app.pal.ink3)
            }
            if let err = mail.errorText {
                Text(err).font(.system(size: 12)).foregroundStyle(app.pal.ink2)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
        }
        }
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
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Text(mail.initial).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(mail.color))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if mail.unread { Circle().fill(pal.accent).frame(width: 5, height: 5) }
                        Text(mail.from).font(.system(size: 12.5, weight: mail.unread ? .semibold : .medium)).foregroundStyle(pal.ink).lineLimit(1)
                    }
                    (Text(mail.subject).font(.system(size: 12)).foregroundStyle(pal.ink2)
                        + Text("  \(mail.preview)").font(.system(size: 12)).foregroundStyle(pal.ink3))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(mail.timeLabel).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(pal.ink3)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(on ? pal.active : (hovering ? pal.hover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? pal.hairline : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            VStack(alignment: .leading, spacing: 12) {
                Text(mail.subject).font(.system(size: 21, weight: .semibold)).foregroundStyle(pal.rdInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(mail.initial).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(mail.color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mail.from).font(.system(size: 13, weight: .medium)).foregroundStyle(pal.rdInk)
                        Text(mail.address).font(.system(size: 12)).foregroundStyle(pal.rdInk3)
                    }
                    Spacer()
                    Text(mail.timeLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(pal.rdInk3)
                }
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.rdHair).frame(height: 1) }

            body(pal)

            HStack(spacing: 9) {
                Text("Read-only").font(.system(size: 11.5)).foregroundStyle(pal.rdInk3)
                Spacer()
                Button {
                    let text = store.bodyCache[mail.id]?.text ?? mail.preview
                    app.vault.add(text: text.isEmpty ? mail.preview : String(text.prefix(16000)), note: "", url: sourceURL, title: mail.subject, context: "From \(mail.from)", spaceID: app.activeSpaceID, provenance: "mail", accountScope: store.accountAddress)
                    app.notify(app.vault.errorText == nil ? "Saved to Vault" : "Couldn’t save message")
                } label: { Label("Save message to Vault", systemImage: "bookmark") }
                .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(pal.rdInk2).disabled(store.accountAddress == nil)
                Button("Ask about this message") {
                    app.attachedSources = [KnowledgeSource(id: UUID(), title: mail.subject, url: sourceURL?.absoluteString ?? "", text: store.bodyCache[mail.id]?.text ?? mail.preview, kind: "Mail")]
                    app.sendToAsk("Summarize this message")
                }.buttonStyle(.plain).font(.system(size: 12)).disabled(store.accountAddress == nil)
            }
            .padding(.horizontal, 26).padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.rdBg))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.rdHair))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func body(_ pal: Palette) -> some View {
        if let email = store.bodyCache[mail.id] {
            if let html = email.html, !html.isEmpty {
                WebEmailView(html: html)
            } else {
                ScrollView {
                    Text(email.text.isEmpty ? mail.preview : email.text)
                        .font(.system(size: 13)).foregroundStyle(pal.rdInk).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26).padding(.vertical, 22)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading message…").font(.system(size: 12)).foregroundStyle(pal.rdInk3)
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
        let style = "<style>:root{color-scheme:light}body{font-family:-apple-system,system-ui,sans-serif;color:#1b1b20;margin:0;padding:22px 26px;font-size:15px;line-height:1.55;-webkit-text-size-adjust:100%}img{max-width:100%;height:auto}a{color:#645AA0}table{max-width:100%!important}</style>"
        if lower.contains("<head") {
            return body.replacingOccurrences(of: "<head", with: "\(style)<head", options: .caseInsensitive)
        }
        if lower.contains("<body") {
            return "\(style)\(body)"
        }
        return "<html><head><meta name='viewport' content='width=device-width'>\(style)</head><body>\(body)</body></html>"
    }
}
