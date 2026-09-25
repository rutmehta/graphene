import AppKit
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

    func applyBlocking(host: String) async {
        blockingGeneration += 1; let generation = blockingGeneration
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists(); blockingActive = false
        guard sites?.site(host).blocking ?? globalBlocking() else { notifyState(); return }
        do {
            if blocker == nil { blocker = try await ContentBlocker.compile() }
            guard generation == blockingGeneration else { return }
            if let blocker { controller.add(blocker); blockingActive = true }
            blockerError = nil
        } catch { blockerError = "Content blocker unavailable: \(error.localizedDescription)" }
        notifyState()
    }

    func setZoom(_ value: Double) {
        guard let host = currentURL?.host else { return }
        var site = sites?.site(host) ?? SitePreference()
        site.zoom = SiteSettings.zoom(value, factor: 1)
        do { try sites?.set(site, host: host); webView.pageZoom = site.zoom; notifyState() }
        catch { delegate?.engine(self, didFail: error) }
    }

    private var kvo: [NSKeyValueObservation] = []
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

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        guard SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            delegate?.engine(self, didFail: NSError(domain: "Graphene", code: NSURLErrorServerCertificateUntrusted, userInfo: [NSLocalizedDescriptionKey: "The certificate for \(challenge.protectionSpace.host) could not be verified. Graphene has not sent page data. Certificate overrides are unavailable because WebKit does not expose HSTS policy safely."]))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { delegate?.engine(self, didFail: error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { delegate?.engine(self, didFail: error) }

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
            Task { await applyBlocking(host: url.host ?? ""); decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow) }
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
            Task { await applyBlocking(host: navigationAction.request.url?.host ?? ""); decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow) }
        } else { decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame {
            Task { await applyBlocking(host: navigationResponse.response.url?.host ?? ""); decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download) }
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
        case "copy":
            delegate?.engine(self, didCopyText: body["text"] as? String ?? "", url: webView.url)
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
