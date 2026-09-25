import SwiftUI
import WebKit
import Security

struct SiteControlsButton: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: PageToolbarGeometry.controlGap) {
            if tab.articleDetected {
                ToolbarGlyphButton(title: "Reader", system: "doc.plaintext", identifier: "toolbar.reader") { app.commandActions.first { $0.id == "reader" }?.run() }
            }
            // The page's favicon is the site-controls button (arc-look.md §3.2).
            Button { app.siteControlsTabID = tab.id } label: {
                Favicon(host: tab.url?.host, size: ShellLayout.iconSize, url: tab.url)
                    .frame(width: ShellLayout.controlSize, height: ShellLayout.controlSize).contentShape(Rectangle())
            }.buttonStyle(ShellButtonStyle())
                .disabled(tab.url?.host == nil)
                .help(tab.url?.scheme == "https" && tab.loadError == nil ? "Site controls: secure connection" : "Site controls: connection not secure")
                .accessibilityLabel("Site controls").accessibilityIdentifier("toolbar.siteControls").accessibilityAddTraits(.isButton)
                .popover(isPresented: Binding(get: { app.siteControlsTabID == tab.id }, set: { if !$0 { app.siteControlsTabID = nil } })) { SiteControlsPopover(tab: tab) }
        }
    }
}
struct SiteControlsPopover: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tab: Tab
    @State private var site = SitePreference()
    @State private var status = ""
    private var host: String { tab.url?.host?.lowercased() ?? "" }
    private var engine: WKWebEngine? { tab.engine as? WKWebEngine }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(host).font(ShellType.title).lineLimit(1).truncationMode(.middle)
            DisclosureGroup(tab.url?.scheme == "https" && tab.loadError == nil ? "Secure connection" : "Connection not secure") {
                Text(engine?.certificateSummary ?? "No certificate available. HTTP connections are not encrypted.").font(ShellType.secondary).foregroundStyle(app.pal.ink2).textSelection(.enabled)
            }
            HStack {
                Text("Zoom"); Spacer()
                Button("−") { zoom(site.zoom / 1.1) }; Text("\(Int(site.zoom * 100))%").monospacedDigit().frame(width: 44)
                Button("+") { zoom(site.zoom * 1.1) }; Button("Reset") { zoom(1) }
            }
            Slider(value: Binding(get: { site.zoom }, set: { zoom($0) }), in: 0.25...3, step: 0.05)
            Toggle("Block ads & trackers", isOn: Binding(get: { site.blocking ?? app.settings.contentBlocking ?? true }, set: { site.blocking = $0; save(); Task { await engine?.applyBlocking(host: host) } }))
            HStack { Text(engine?.blockingActive == true ? "Blocking on" : "Blocking off"); Spacer(); Button("Use global setting") { site.blocking = nil; save(); Task { await engine?.applyBlocking(host: host) } } }.font(ShellType.secondary).foregroundStyle(app.pal.ink3)
            if let error = engine?.blockerError { Text(error).font(ShellType.secondary).foregroundStyle(app.pal.ink2) }
            Divider()
            permission("Camera", key: \.camera)
            permission("Microphone", key: \.microphone)
            permission("Motion", key: \.motion)
            Text("Location and notifications: managed by WebKit/macOS. No public per-site delegate is available in this macOS WKWebView.").font(ShellType.secondary).foregroundStyle(app.pal.ink3)
            Divider()
            Button("Boosts ▸") { app.boostHost = host; dismiss() }
            Button("Zap an element…") { engine?.startZap(); app.notify("Click an element to hide it. Escape cancels."); dismiss() }
            Button("Clear data for this site…") { app.clearCurrentSiteData() }
            if let url = tab.url { Button("Open in default browser") { app.openInSystemBrowser(url) } }
            if !status.isEmpty { Text(status).font(ShellType.secondary).foregroundStyle(app.pal.ink2) }
        }.padding(ShellLayout.windowGap * 2).frame(width: ShellLayout.siteControlsWidth).font(ShellType.body).foregroundStyle(app.pal.ink).background(app.pal.elev)
            .onAppear { site = app.sites.site(host) }
            .onReceive(app.sites.$entries) { _ in site = app.sites.site(host) }
    }
    static let width: CGFloat = 320
    private func permission(_ title: String, key: WritableKeyPath<SitePreference, SitePermission>) -> some View {
        Picker(title, selection: Binding(get: { site[keyPath: key] }, set: { site[keyPath: key] = $0; save() })) {
            ForEach(SitePermission.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }
    private func save() { do { try app.sites.set(site, host: host) } catch { status = error.localizedDescription } }
    private func zoom(_ value: Double) { site.zoom = SiteSettings.zoom(value, factor: 1); engine?.setZoom(site.zoom) }
}

extension WKWebEngine {
    var certificateSummary: String? {
        guard let trust = webView.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else { return nil }
        let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown subject"
        let keys = [kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray
        let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any] ?? [:]
        func describe(_ key: CFString) -> String {
            guard let property = values[key as String] as? [String: Any], let value = property[kSecPropertyKeyValue as String] else { return "Not supplied" }
            if let number = value as? Double { return Date(timeIntervalSinceReferenceDate: number).formatted(date: .abbreviated, time: .omitted) }
            if let rows = value as? [[String: Any]] { return rows.compactMap { $0[kSecPropertyKeyValue as String] as? String }.joined(separator: ", ") }
            return String(describing: value)
        }
        return "\(subject)\nIssuer: \(describe(kSecOIDX509V1IssuerName))\nValid from: \(describe(kSecOIDX509V1ValidityNotBefore))\nValid until: \(describe(kSecOIDX509V1ValidityNotAfter))"
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let site = sites?.site(origin.host) ?? SitePreference()
        let values: [SitePermission] = type == .camera ? [site.camera] : type == .microphone ? [site.microphone] : [site.camera, site.microphone]
        decisionHandler(values.contains(.block) ? .deny : values.allSatisfy { $0 == .allow } ? .grant : .prompt)
    }
    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let value = sites?.site(origin.host).motion ?? .ask
        decisionHandler(value == .block ? .deny : value == .allow ? .grant : .prompt)
    }
}
