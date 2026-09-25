import AppKit
import SwiftUI
import WebKit

/// WKWebView-backed WebEngine. One instance per tab; the view persists across
/// tab switches (the container just swaps which hostView is on screen).
@MainActor
final class WKWebEngine: NSObject, WebEngine, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    weak var delegate: WebEngineDelegate?
    var linkHandler: ((URL, NSEvent.ModifierFlags) -> Bool)?
    private(set) var formDirty = false
    private(set) var activeDownloads = 0
    let isPrivate: Bool
    let aiProfileID: UUID
    var capturePermitted: () -> Bool = { true }
    /// The Vault notes with a quote saved from a page, marked in it after every load.
    var savedNotes: (URL) -> [Annotation] = { _ in [] }
    weak var aiOwner: AppState?
    var aiPopover: NSPopover?
    private var dialogs = DialogGuard()
    var downloads: DownloadStore?
    var sites: SiteSettings?
    var boosts: Boosts?
    private var zapHost: String?
    private(set) var articleDetected = false
    private(set) var signInBlocked = false
    private var externalDecisions: [String: Bool] = [:]
    /// The server trust WebKit handed us in the last server-trust challenge, read-only.
    private(set) var challengeTrust: (host: String, trust: SecTrust)?
    private static let pipScript: String = {
        guard let url = Bundle.module.url(forResource: "pip", withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    func refreshBoosts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let font = aiOwner?.settings.pageFont ?? .website
        controller.addUserScript(WKUserScript(source: font.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.evaluateJavaScript(font.script, completionHandler: nil)
        controller.addUserScript(WKUserScript(source: Self.pipScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.navHookScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.iconScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if !isPrivate { controller.addUserScript(WKUserScript(source: Self.annotateScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)) }
        for boost in boosts?.items ?? [] {
            controller.addUserScript(WKUserScript(source: boost.styleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            if !boost.codeScript.isEmpty { controller.addUserScript(WKUserScript(source: boost.codeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)) }
        }
        if let host = currentURL?.host, let boost = boosts?.boost(host) { webView.evaluateJavaScript(boost.styleScript, completionHandler: nil) }
    }
    func startZap() {
        guard let host = currentURL?.host, let url = Bundle.main.url(forResource: "zap", withExtension: "js") ?? Bundle.module.url(forResource: "zap", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { return }
        zapHost = host
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    var globalBlocking: () -> Bool = { true }
    private(set) var blockingActive = false
    private(set) var blockerError: String?
    private var blocker: WKContentRuleList?
    private var blockingGeneration = 0

    /// The compiled rule list, shared by every engine so only the first navigation in the process compiles.
    private static var sharedBlocker: WKContentRuleList?

    func applyBlocking(host: String) async {
        if applyBlockingIfReady(host: host) { return }
        blockingGeneration += 1; let generation = blockingGeneration
        do {
            let compiled = try await ContentBlocker.compile()
            Self.sharedBlocker = compiled; blocker = compiled
            guard generation == blockingGeneration else { return }
            webView.configuration.userContentController.add(compiled); blockingActive = true
            blockerError = nil
        } catch { blockerError = "Content blocker unavailable: \(error.localizedDescription)" }
        notifyState()
    }

    /// Applies the blocking policy without suspending when no compile is needed (blocking off, or the
    /// list already compiled). Returns false when the caller must await `applyBlocking`. Deciding a
    /// navigation synchronously matters: an awaited policy decision that WebKit supersedes (a redirect,
    /// a second load) is logged as an ignored policy listener with a full backtrace.
    @discardableResult
    func applyBlockingIfReady(host: String) -> Bool {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists(); blockingActive = false
        guard sites?.site(host).blocking ?? globalBlocking() else { blockingGeneration += 1; notifyState(); return true }
        if blocker == nil { blocker = Self.sharedBlocker }
        guard let blocker else { return false }
        blockingGeneration += 1
        controller.add(blocker); blockingActive = true; blockerError = nil
        notifyState(); return true
    }

    func setZoom(_ value: Double) {
        guard let host = currentURL?.host else { return }
        var site = sites?.site(host) ?? SitePreference()
        site.zoom = SiteSettings.zoom(value, factor: 1)
        do { try sites?.set(site, host: host); webView.pageZoom = site.zoom; notifyState() }
        catch { delegate?.engine(self, didFail: error) }
    }

    private var kvo: [NSKeyValueObservation] = []
    /// The last reported page darkness; citation marks take the matching scheme's accent.
    private var pageIsDark: Bool?
    private var lastRecordedURL: URL?

    // Stable profile identifiers isolate cookies, including separate development namespaces.
    init(configuration: WKWebViewConfiguration? = nil, privateMode: Bool = false, profileID: UUID = Profile.defaultID) {
        isPrivate = privateMode
        aiProfileID = profileID
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.websiteDataStore = privateMode ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: Profile.storeID(profileID, namespace: ProcessInfo.processInfo.environment["GRAPHENE_DATA_DIR"]))
            // Present as Safari so sites (and sign-in flows) don't gate an unknown UA.
            config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(source: Self.pipScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: Self.navHookScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: Self.iconScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            if !privateMode && !Self.annotateScript.isEmpty {
                controller.addUserScript(WKUserScript(source: Self.annotateScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
            config.userContentController = controller
        }

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        config.userContentController.add(WeakScriptHandler(self), name: "graphene")
        config.userContentController.add(WeakScriptHandler(self), name: "graphene.writing")

        observe()
    }

    private func observe() {
        // WKWebView KVO fires on the main thread, so assuming main-actor isolation is safe.
        let notify: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.notifyState() } }
        kvo = [
            webView.observe(\.title) { _, _ in notify() },
            webView.observe(\.url) { _, _ in notify() },
            webView.observe(\.canGoBack) { _, _ in notify() },
            webView.observe(\.canGoForward) { _, _ in notify() },
            webView.observe(\.estimatedProgress) { _, _ in notify() },
            webView.observe(\.isLoading) { _, _ in notify() },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in MainActor.assumeIsolated { self?.reportPageDarkness() } },
            webView.observe(\.themeColor) { [weak self] _, _ in MainActor.assumeIsolated { self?.reportPageDarkness() } },
        ]
    }

    /// The page's own colour: its `theme-color` when declared, else the colour WebKit
    /// paints under the page (the document background by default).
    private func reportPageDarkness() {
        guard let dark = Palette.pageIsDark(webView.themeColor) ?? Palette.pageIsDark(webView.underPageBackgroundColor) else { return }
        let changed = pageIsDark != dark
        pageIsDark = dark
        if changed { Task { await applyAnnotationTheme() } }
        delegate?.engine(self, didChangePageDarkness: dark)
    }

    private func notifyState() { delegate?.engineDidChangeState(self) }

    // MARK: WebEngine

    var hostView: NSView { webView }
    var currentURL: URL? { webView.url }
    var pageTitle: String? { webView.title }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    var isLoading: Bool { webView.isLoading }
    var estimatedProgress: Double { webView.estimatedProgress }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    func evaluateJavaScript(_ js: String) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { value, _ in cont.resume(returning: value) }
        }
    }

    func find(_ text: String, backwards: Bool) async -> Bool {
        let config = WKFindConfiguration()
        config.backwards = backwards; config.wraps = true; config.caseSensitive = false
        return await withCheckedContinuation { continuation in
            webView.find(text, configuration: config) { continuation.resume(returning: $0.matchFound) }
        }
    }

    // MARK: in-page citations (Resources/cite.js)

    func highlight(passages: [CitedPassage]) async -> [String] {
        let eligible = passages.filter { !$0.normalized.isEmpty }
        guard !isPrivate, !eligible.isEmpty, !Self.citeScript.isEmpty else { return [] }
        let items: [[String: Any]] = eligible.map { passage in
            var item: [String: Any] = ["id": passage.id, "text": passage.text]
            if let index = passage.index { item["index"] = index }
            if Annotation.noteID(markID: passage.id) != nil { item["kind"] = "note" }
            return item
        }
        let palette = aiOwner?.pal.page(dark: pageIsDark) ?? Palette(mode: pageIsDark == true ? .dark : .light, space: .slate)
        let found = await callCite("return window.__grapheneCite.highlight(passages, style);", install: true,
                                   arguments: ["passages": items, "style": Self.citeStyle(palette)])
        return (found as? [Any])?.compactMap { $0 as? String } ?? []
    }

    func setActiveHighlight(_ id: String?) async {
        guard !isPrivate else { return }
        await callCite("if (window.__grapheneCite) window.__grapheneCite.setActive(id);", arguments: ["id": id ?? NSNull()])
    }

    func scrollToHighlight(_ id: String) async {
        guard !isPrivate else { return }
        await callCite("if (window.__grapheneCite) window.__grapheneCite.scrollTo(id);", arguments: ["id": id])
    }

    func highlightRect(id: String) async -> CGRect? {
        guard !isPrivate else { return nil }
        // Reads the mark's box only; cite.js is not involved. CSS pixels are scaled to the host
        // view's points by the viewport's width, which absorbs page zoom.
        let value = await callCite("""
            const mark = Array.from(document.querySelectorAll('mark[data-graphene-cite]')).find(m => m.getAttribute('data-graphene-cite') === id);
            if (!mark) return null;
            const r = mark.getBoundingClientRect();
            return [r.left, r.top, r.width, r.height, window.innerWidth];
            """, arguments: ["id": id])
        guard let numbers = (value as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }), numbers.count == 5, numbers[4] > 0 else { return nil }
        let scale = webView.bounds.width / numbers[4]
        return CGRect(x: numbers[0] * scale, y: numbers[1] * scale, width: numbers[2] * scale, height: numbers[3] * scale)
    }

    func clearHighlights() async {
        guard !isPrivate else { return }
        await callCite("if (window.__grapheneCite) window.__grapheneCite.clear();", arguments: [:])
    }

    /// Runs `call` as a function body in the page world, first installing cite.js when asked.
    @discardableResult
    private func callCite(_ call: String, install: Bool = false, arguments: [String: Any]) async -> Any? {
        let body = (install ? Self.citeScript + "\n" : "") + call
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    /// The CSS colours and inset `cite.js` styles its marks with, from `palette`.
    static func citeStyle(_ palette: Palette) -> [String: Any] {
        ["highlight": cssColor(palette.highlight), "highlightActive": cssColor(palette.highlightActive),
         "accent": cssColor(palette.accent), "inset": Double(ShellLayout.markInset)]
    }

    /// A colour as a CSS `rgba()` in sRGB.
    static func cssColor(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func channel(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        let alpha = (Double(c.alphaComponent) * 1000).rounded() / 1000
        return "rgba(\(channel(c.redComponent)),\(channel(c.greenComponent)),\(channel(c.blueComponent)),\(alpha))"
    }

    /// Citation marks, loaded from Resources/cite.js.
    static let citeScript: String = {
        guard let url = Bundle.main.url(forResource: "cite", withExtension: "js") ?? Bundle.module.url(forResource: "cite", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return src
    }()

    // MARK: saved notes (Resources/annotate.js, graphene-language.md §5.3)

    /// Late-rendering pages get a few more tries before a saved quote counts as missing.
    static let noteMarkAttempts = 3
    static let noteMarkRetry: Duration = .milliseconds(700)

    /// Sends annotate.js the page-scheme tokens and the page's saved notes, then marks each
    /// note's quote with cite.js as `note:<uuid>`, kind "note". Returns the mark ids found.
    @discardableResult
    func markSavedNotes() async -> [String] {
        guard !isPrivate, let url = currentURL else { return [] }
        let notes = savedNotes(url)
        await applyAnnotationTheme()
        let list: [[String: Any]] = notes.map { ["id": $0.markID, "quote": $0.text, "note": $0.note] }
        await callAnnotate("if (window.__grapheneAnnotateNotes) window.__grapheneAnnotateNotes(notes);", arguments: ["notes": list])
        guard currentURL == url else { return [] }
        return await highlight(passages: notes.compactMap(\.passage))
    }

    /// Marks the saved notes after a load, retrying while quotes of a late-rendering page are missing.
    private func markSavedNotesAfterLoad(_ url: URL?) async {
        for attempt in 0..<Self.noteMarkAttempts {
            guard currentURL == url, let url, !isLoading else { return }
            let wanted = savedNotes(url).compactMap(\.passage).count
            if await markSavedNotes().count >= wanted { return }
            if attempt + 1 < Self.noteMarkAttempts { try? await Task.sleep(for: Self.noteMarkRetry) }
        }
    }

    /// Saves the page's live selection as a note (⌘D). False when nothing is selected.
    func saveSelection() async -> Bool {
        guard !isPrivate else { return false }
        return await evaluateJavaScript("window.__grapheneAnnotateSave ? window.__grapheneAnnotateSave() : false") as? Bool ?? false
    }

    /// The selection bar, editor, margin dot and note card take the page's scheme.
    private func applyAnnotationTheme() async {
        guard !isPrivate else { return }
        let palette = aiOwner?.pal.page(dark: pageIsDark) ?? Palette(mode: pageIsDark == true ? .dark : .light, space: .graphite)
        await callAnnotate("if (window.__grapheneAnnotateTheme) window.__grapheneAnnotateTheme(style);", arguments: ["style": Self.annotationStyle(palette)])
    }

    private func callAnnotate(_ body: String, arguments: [String: Any]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { _ in continuation.resume() }
        }
    }

    /// The tokens annotate.js draws with, from the page-scheme `palette`: CSS colours, and
    /// sizes in CSS px.
    static func annotationStyle(_ palette: Palette) -> [String: Any] {
        [
            "elev": cssColor(palette.elev), "hairline": cssColor(palette.hairline), "ink": cssColor(palette.ink),
            "ink2": cssColor(palette.ink2), "ink3": cssColor(palette.ink3), "accent": cssColor(palette.accent),
            "elevFill": cssColor(palette.elevFill), "quoteRule": cssColor(palette.quoteRule),
            "shadow": cssColor(palette.pageShadow), "shadowRadius": Double(palette.pageShadowRadius), "shadowY": Double(palette.pageShadowY),
            "highlightActive": cssColor(palette.highlightActive),
            "radius": Double(ShellLayout.popoverRadius), "rowRadius": Double(ShellLayout.rowRadius),
            "barHeight": Double(ShellLayout.annotationBarHeight), "cardWidth": Double(ShellLayout.annotationCardWidth),
            "gap": Double(ShellLayout.annotationGap), "dot": Double(ShellLayout.statusDot),
            "labelSize": Double(ShellType.labelSize), "rowSize": Double(ShellType.rowSize), "bodySize": Double(ShellType.rowSize),
            "quoteSize": Double(ShellType.quoteSize), "quoteLineHeight": Double(ShellType.quoteLineHeight),
        ]
    }

    func captureSnapshotText() async -> String {
        guard !isPrivate, capturePermitted() else { return "" }
        return await captureReadableContent().text
    }
    func captureReadableContent() async -> ReadableContent {
        guard !isPrivate, capturePermitted() else { return ReadableContent() }
        let url = currentURL
        let value = await evaluateJavaScript("window.__grapheneReadable ? window.__grapheneReadable() : null")
        guard !isPrivate, capturePermitted(), currentURL == url else { return ReadableContent() }
        if let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value), let content = try? JSONDecoder().decode(ReadableContent.self, from: data) { return content }
        let text = (await evaluateJavaScript(ReaderMode.extractor)) as? String ?? ""
        guard capturePermitted(), currentURL == url else { return ReadableContent() }
        return ReadableContent(title: pageTitle ?? "", text: text)
    }

    // MARK: WKNavigationDelegate
    // Record on *finish*, not commit, so redirect/OAuth bounce pages don't
    // each become their own graph node.

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        zapHost = nil
        articleDetected = false; signInBlocked = false
        formDirty = false
        delegate?.engineDidStartNavigation(self, url: webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        webView.pageZoom = sites?.site(webView.url?.host ?? "").zoom ?? 1
        delegate?.engineDidCommit(self, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recordIfNew(webView.url, title: webView.title)
        delegate?.engineDidChangeState(self)
        reportPageDarkness()
        let url = webView.url
        Task { await markSavedNotesAfterLoad(url) }
        Task {
            let detected = await evaluateJavaScript("!!document.querySelector('article, main') && (document.querySelector('article, main').innerText || '').length > 600") as? Bool ?? false
            let rejected = await evaluateJavaScript("(document.body.innerText || '').includes('This browser or app may not be secure')") as? Bool ?? false
            guard currentURL == url else { return }
            articleDetected = detected; signInBlocked = rejected; notifyState()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.engine(self, didFail: NSError(domain: "Graphene", code: 1, userInfo: [NSLocalizedDescriptionKey: "This page crashed — Reload to continue."]))
    }

    /// WebKit evaluates server trust itself — with its own policies, revocation settings and
    /// network fetches of missing intermediates — so Graphene never pre-evaluates or overrides it.
    /// The trust is only kept (read-only) for the Site Controls certificate summary.
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            challengeTrust = (challenge.protectionSpace.host, trust)
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { delegate?.engine(self, didFail: Self.presentable(error, host: currentURL?.host)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { delegate?.engine(self, didFail: Self.presentable(error, host: currentURL?.host)) }

    /// The URL errors WebKit reports when it rejects a server certificate. Graphene fails closed:
    /// there is no bypass, only the page's "Try again".
    nonisolated static let certificateErrorCodes: Set<Int> = [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                                                  NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid]

    /// A certificate failure as a clear, user-facing error; every other error is returned unchanged.
    nonisolated static func presentable(_ error: Error, host fallbackHost: String? = nil) -> Error {
        let nsError = error as NSError
        // A TLS failure that carries the peer's trust (e.g. a certificate issued for another host)
        // is a certificate rejection too, whatever code the network layer chose.
        let rejectedTrust = nsError.code == NSURLErrorSecureConnectionFailed && nsError.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil
        guard nsError.domain == NSURLErrorDomain, certificateErrorCodes.contains(nsError.code) || rejectedTrust else { return error }
        let failing = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        let host = failing?.host ?? fallbackHost ?? "This site"
        var info = nsError.userInfo
        info[NSLocalizedDescriptionKey] = "\(host)'s certificate isn't trusted, so Graphene didn't load the page."
        info[NSUnderlyingErrorKey] = nsError
        return NSError(domain: NSURLErrorDomain, code: nsError.code, userInfo: info)
    }

    private func recordIfNew(_ url: URL?, title: String?) {
        guard let url, url.scheme == "http" || url.scheme == "https" else { return }
        lastRecordedURL = url
        delegate?.engineDidFinish(self, url: url, title: title)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(), !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
            decisionHandler(.cancel)
            guard navigationAction.navigationType == .linkActivated, let destination = NSWorkspace.shared.urlForApplication(toOpen: url) else { return }
            if let allowed = externalDecisions[scheme] { if allowed { NSWorkspace.shared.open(url) }; return }
            let alert = NSAlert(); alert.messageText = "Open in \(destination.deletingPathExtension().lastPathComponent)?"
            alert.informativeText = "\(currentURL?.host ?? "This page") wants to open a \(scheme) link in another app."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Open")
            alert.showsSuppressionButton = true; alert.suppressionButton?.title = "Remember for this tab until closed"
            let allowed = alert.runModal() == .alertSecondButtonReturn
            if alert.suppressionButton?.state == .on { externalDecisions[scheme] = allowed }
            if allowed { NSWorkspace.shared.open(url) }; return
        }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme ?? ""), navigationAction.navigationType != .linkActivated {
            let policy: WKNavigationActionPolicy = navigationAction.shouldPerformDownload ? .download : .allow
            if applyBlockingIfReady(host: url.host ?? "") { decisionHandler(policy) }
            else { Task { await applyBlocking(host: url.host ?? ""); decisionHandler(policy) } }
            return
        }
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           linkHandler?(url, navigationAction.modifierFlags) == true { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2,
           let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") {
            delegate?.engine(self, requestNewTabFor: url, activate: navigationAction.modifierFlags.contains(.shift))
            decisionHandler(.cancel)
        } else if navigationAction.targetFrame?.isMainFrame == true {
            let host = navigationAction.request.url?.host ?? ""
            let policy: WKNavigationActionPolicy = navigationAction.shouldPerformDownload ? .download : .allow
            if applyBlockingIfReady(host: host) { decisionHandler(policy) }
            else { Task { await applyBlocking(host: host); decisionHandler(policy) } }
        } else { decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame {
            let host = navigationResponse.response.url?.host ?? ""
            let policy: WKNavigationResponsePolicy = navigationResponse.canShowMIMEType ? .allow : .download
            if applyBlockingIfReady(host: host) { decisionHandler(policy) }
            else { Task { await applyBlocking(host: host); decisionHandler(policy) } }
        } else { decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { beginDownload(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { beginDownload(download) }
    private func beginDownload(_ download: WKDownload) {
        activeDownloads += 1
        BrowserDownload.begin(download, store: downloads, profileID: capturePermitted() && !isPrivate ? aiProfileID : nil) { [weak self] in self?.activeDownloads -= 1 }
    }

    // MARK: WKUIDelegate — window.open / target=_blank become new tabs (graph "opened-from" edge)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "http" || url.scheme == "https" {
            delegate?.engine(self, requestNewTabFor: url, activate: true)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let alert = siteAlert(message, frame: frame) else { completionHandler(); return }
        alert.addButton(withTitle: "OK")
        _ = runSiteAlert(alert); completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let alert = siteAlert(message, frame: frame) else { completionHandler(false); return }
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        completionHandler(runSiteAlert(alert) == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let alert = siteAlert(prompt, frame: frame) else { completionHandler(nil); return }
        let field = NSTextField(string: defaultText ?? ""); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 164))
        if let message = alert.accessoryView { message.setFrameOrigin(NSPoint(x: 0, y: 36)); content.addSubview(message) }
        content.addSubview(field); alert.accessoryView = content
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        completionHandler(runSiteAlert(alert) == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    private func siteAlert(_ message: String, frame: WKFrameInfo) -> NSAlert? {
        let origin = frame.securityOrigin
        let label = "\(origin.protocol)://\(origin.host)\(origin.port == 0 ? "" : ":\(origin.port)")"
        guard !dialogs.suppressed.contains(label) else { return nil }
        let alert = NSAlert(); alert.messageText = label
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 128))
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true; text.string = message
        text.font = .systemFont(ofSize: 13); text.drawsBackground = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        alert.accessoryView = scroll
        alert.showsSuppressionButton = dialogs.record(label, at: Date())
        alert.suppressionButton?.title = "Suppress dialogs from this site"
        return alert
    }
    private func runSiteAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { dialogs.suppressed.insert(alert.messageText) }
        return response
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    // MARK: WKScriptMessageHandler — SPA nav hook + annotation + copy

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "writing", "preview":
            guard !isPrivate, capturePermitted(), let app = aiOwner,
                  app.activeTab?.loadedEngine === self, app.activeTab.map(app.aiTabAllowed) == true else { return }
            showAI(body, app: app)
        case "zap":
            guard let host = zapHost, host == currentURL?.host,
                  let selector = body["selector"] as? String, !selector.isEmpty, selector.count < 2000,
                  !selector.contains("{"), !selector.contains("}"), let boosts else { return }
            zapHost = nil
            var boost = boosts.boost(host); boost.enabled = true
            if !boost.selectors.contains(selector) { boost.selectors.append(selector) }
            do { try boosts.save(boost); refreshBoosts() }
            catch { delegate?.engine(self, didFail: error) }
        case "dirty": formDirty = true
        case "icon":
            if !isPrivate, let page = webView.url {
                let declared = FaviconDiscovery.candidates(FaviconDiscovery.links(from: body["icons"]), page: page)
                Task { await FaviconStore.shared.fetch(page, declared: declared) }
            }
        case "navigate":
            // Client-side (pushState/replaceState/popstate) navigation — no delegate fires for these.
            if let s = body["url"] as? String, let url = URL(string: s), url == webView.url,
               KnowledgeGraph.canonicalURL(s) != lastRecordedURL.map({ KnowledgeGraph.canonicalURL($0.absoluteString) }) {
                recordIfNew(url, title: webView.title)
            }
        case "annotation":
            let ann = CapturedAnnotation(
                text: body["text"] as? String ?? "", note: body["note"] as? String ?? "",
                url: webView.url, title: webView.title ?? "", context: body["context"] as? String ?? "")
            delegate?.engine(self, didCaptureAnnotation: ann)
        case "ask":
            guard !isPrivate, capturePermitted(), let app = aiOwner, let tab = app.activeTab, tab.loadedEngine === self, app.aiTabAllowed(tab),
                  let text = body["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 8000 else { return }
            app.askAboutSelection(text, in: tab)
        case "noteEdit", "noteOpen":
            // Only a note saved from this page, whose mark the page shows, can be changed from it.
            guard !isPrivate, let app = aiOwner, let markID = body["id"] as? String, let id = Annotation.noteID(markID: markID),
                  let note = app.vault.annotations.first(where: { $0.id == id }), let page = currentURL,
                  KnowledgeGraph.canonicalURL(note.url) == KnowledgeGraph.canonicalURL(page.absoluteString) else { return }
            if kind == "noteOpen" { app.openNoteInVault(id) }
            else if let text = body["note"] as? String, text.count <= 20_000 { app.updateNote(note, text: text) }
        case "copy":
            delegate?.engine(self, didCopyText: body["text"] as? String ?? "", url: webView.url)
        case "citeHover":
            guard !isPrivate else { return }
            delegate?.engine(self, didHoverHighlight: body["id"] as? String)
        default: break
        }
    }

    private static let iconScript = """
    (() => {
      let last = '';
      const publish = () => {
        const icons = Array.from(document.querySelectorAll('link[rel~="icon"], link[rel~="apple-touch-icon"], link[rel~="apple-touch-icon-precomposed"]'))
          .filter(link => link.href)
          .map(link => ({href: link.href, rel: link.rel || '', sizes: link.getAttribute('sizes') || '', type: link.type || ''}));
        const signature = JSON.stringify(icons);
        if (signature !== last) {
          last = signature;
          window.webkit.messageHandlers.graphene.postMessage({kind:'icon', icons});
        }
      };
      publish();
      if (document.head) new MutationObserver(publish).observe(document.head, {childList:true, subtree:true, attributes:true, attributeFilter:['href','rel']});
    })();
    """

    /// Hooks the History API so single-page-app navigations reach the graph.
    private static let navHookScript = """
    (() => {
      const post = () => { try { window.webkit.messageHandlers.graphene.postMessage({kind:'navigate', url: location.href}); } catch(e){} };
      const dirty = () => window.webkit.messageHandlers.graphene.postMessage({kind:'dirty'});
      document.addEventListener('input', dirty, true);
      const add = window.addEventListener;
      window.addEventListener = function(type, ...args) { if (type === 'beforeunload') dirty(); return add.call(this, type, ...args); };
      setInterval(() => { if (window.onbeforeunload) dirty(); }, 1000);
      const wrap = (name) => { const orig = history[name]; history[name] = function(){ const r = orig.apply(this, arguments); setTimeout(post, 0); return r; }; };
      wrap('pushState'); wrap('replaceState');
      window.addEventListener('popstate', () => setTimeout(post, 0));
    })();
    """

    /// Annotation UI, loaded from Resources/annotate.js.
    static let annotateScript: String = {
        guard let url = Bundle.main.url(forResource: "annotate", withExtension: "js") ?? Bundle.module.url(forResource: "annotate", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return src
    }()

    deinit { kvo.forEach { $0.invalidate() } }
}

/// WKUserContentController retains handlers; the proxy keeps closed tabs releasable.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
