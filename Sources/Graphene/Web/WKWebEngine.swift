import AppKit
import WebKit

/// WKWebView-backed WebEngine. One instance per tab; the view persists across
/// tab switches (the container just swaps which hostView is on screen).
@MainActor
final class WKWebEngine: NSObject, WebEngine, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    weak var delegate: WebEngineDelegate?

    private var kvo: [NSKeyValueObservation] = []
    private var lastRecordedURL: URL?

    // A single stable data store keeps cookies/logins across launches without a
    // bundle identifier (which an unbundled `swift run` binary lacks).
    private static let dataStore: WKWebsiteDataStore =
        WKWebsiteDataStore(forIdentifier: UUID(uuidString: "8E7C21A0-3B2E-4C9D-9F10-000000000001")!)

    init(configuration: WKWebViewConfiguration? = nil) {
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.websiteDataStore = Self.dataStore
            // Present as Safari so sites (and sign-in flows) don't gate an unknown UA.
            config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(source: Self.navHookScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            if !Self.annotateScript.isEmpty {
                controller.addUserScript(WKUserScript(source: Self.annotateScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
            config.userContentController = controller
        }

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        config.userContentController.add(self, name: "graphene")

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
        ]
    }

    private func notifyState() { delegate?.engineDidChangeState(self) }

    // MARK: WebEngine

    var hostView: NSView { webView }
    var currentURL: URL? { webView.url }
    var pageTitle: String? { webView.title }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
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

    func captureSnapshotText() async -> String {
        let js = """
        (() => { const c = document.body ? document.body.cloneNode(true) : null;
          if (!c) return '';
          c.querySelectorAll('script,style,noscript,svg,canvas,nav,footer,header,aside,iframe,form').forEach(n => n.remove());
          return (c.innerText || '').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 60000); })()
        """
        return (await evaluateJavaScript(js)) as? String ?? ""
    }

    // MARK: WKNavigationDelegate
    // Record on *finish*, not commit, so redirect/OAuth bounce pages don't
    // each become their own graph node.

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        delegate?.engineDidStartNavigation(self, url: webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        delegate?.engineDidCommit(self, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recordIfNew(webView.url, title: webView.title)
        delegate?.engineDidChangeState(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { notifyState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { notifyState() }

    private func recordIfNew(_ url: URL?, title: String?) {
        guard let url, url.scheme == "http" || url.scheme == "https" else { return }
        if url != lastRecordedURL {
            lastRecordedURL = url
            delegate?.engineDidFinish(self, url: url, title: title)
        }
    }

    // MARK: WKUIDelegate — window.open / target=_blank become new tabs (graph "opened-from" edge)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "http" || url.scheme == "https" {
            delegate?.engine(self, requestNewTabFor: url, activate: true)
        }
        return nil
    }

    // MARK: WKScriptMessageHandler — SPA nav hook + annotation + copy

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "navigate":
            // Client-side (pushState/replaceState/popstate) navigation — no delegate fires for these.
            if let s = body["url"] as? String, let url = URL(string: s) { recordIfNew(url, title: webView.title) }
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

    /// Hooks the History API so single-page-app navigations reach the graph.
    private static let navHookScript = """
    (() => {
      const post = () => { try { window.webkit.messageHandlers.graphene.postMessage({kind:'navigate', url: location.href}); } catch(e){} };
      const wrap = (name) => { const orig = history[name]; history[name] = function(){ const r = orig.apply(this, arguments); setTimeout(post, 0); return r; }; };
      wrap('pushState'); wrap('replaceState');
      window.addEventListener('popstate', () => setTimeout(post, 0));
    })();
    """

    /// Annotation UI, loaded from Resources/annotate.js.
    static let annotateScript: String = {
        guard let url = Bundle.module.url(forResource: "annotate", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return src
    }()

    deinit { kvo.forEach { $0.invalidate() } }
}
