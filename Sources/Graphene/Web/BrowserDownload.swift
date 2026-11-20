import AppKit
import WebKit

/// Downloads outlive their originating tab and use the system save dialog.
@MainActor
final class BrowserDownload: NSObject, WKDownloadDelegate {
    private static var active: [ObjectIdentifier: BrowserDownload] = [:]
    /// Resume data WebKit returned for a failed or cancelled download, by history entry, kept for
    /// this launch only. The website data store goes with it so a resumed request keeps the
    /// original profile's cookies.
    private static var resumable: [UUID: (data: Data, dataStore: WKWebsiteDataStore, store: DownloadStore?, profileID: UUID?)] = [:]
    private let download: WKDownload
    private var destination: URL?
    private var completion: () -> Void = {}
    private var store: DownloadStore?
    private var entryID: UUID?
    private var observation: NSKeyValueObservation?
    private var profileID: UUID?
    private var dataStore: WKWebsiteDataStore?
    /// The off-screen web view a resumed download runs in; nothing else retains it.
    private var host: WKWebView?
    private var cancelled = false
    private var ended = false

    static func begin(_ download: WKDownload, store: DownloadStore?, profileID: UUID? = nil, completion: @escaping () -> Void = {}) {
        let handler = BrowserDownload(download)
        handler.store = store
        handler.profileID = profileID
        handler.completion = completion
        handler.dataStore = download.webView?.configuration.websiteDataStore
        active[ObjectIdentifier(download)] = handler
        download.delegate = handler
    }
    private init(_ download: WKDownload) { self.download = download }

    static func isActive(_ entryID: UUID) -> Bool { active.values.contains { $0.entryID == entryID } }
    static func canResume(_ entryID: UUID) -> Bool { resumable[entryID] != nil && !isActive(entryID) }

    /// Stops a running download, keeping WebKit's resume data so it can be picked up again.
    static func cancel(_ entryID: UUID) {
        guard let handler = active.values.first(where: { $0.entryID == entryID }), !handler.cancelled else { return }
        handler.cancelled = true
        handler.download.cancel { data in
            Task { @MainActor in handler.end(error: nil, resumeData: data) }
        }
    }

    /// Picks a failed or cancelled download up where it stopped, writing to the same file.
    static func resume(_ entryID: UUID) {
        guard let saved = resumable[entryID], !isActive(entryID) else { return }
        resumable[entryID] = nil
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = saved.dataStore
        let host = WKWebView(frame: .zero, configuration: configuration)
        saved.store?.resume(entryID)
        host.resumeDownload(fromResumeData: saved.data) { download in
            let handler = BrowserDownload(download)
            handler.store = saved.store
            handler.profileID = saved.profileID
            handler.dataStore = saved.dataStore
            handler.host = host
            handler.entryID = entryID
            handler.destination = saved.store?.entries.first(where: { $0.id == entryID })?.destination
            handler.observeProgress()
            active[ObjectIdentifier(download)] = handler
            download.delegate = handler
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // A resumed download already has its file.
        if entryID != nil, let destination { completionHandler(destination); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = store?.preferredDirectory?() ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            entryID = store?.begin(url, sourceURL: response.url, profileID: profileID)
            observeProgress()
            completionHandler(url)
        } else {
            completionHandler(nil)
            complete()
            Self.active[ObjectIdentifier(download)] = nil
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard !ended else { return }
        ended = true
        complete()
        if let entryID { store?.finish(entryID, error: nil) }
        Self.active[ObjectIdentifier(download)] = nil
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        end(error: error, resumeData: resumeData)
    }

    /// Cancellation and failure can both report back; the first one records the outcome and the
    /// second only adds resume data the first lacked.
    private func end(error: Error?, resumeData: Data?) {
        if let entryID, let resumeData, let dataStore, Self.resumable[entryID] == nil {
            Self.resumable[entryID] = (resumeData, dataStore, store, profileID)
        }
        guard !ended else { return }
        ended = true
        complete()
        if let entryID { store?.finish(entryID, error: cancelled ? "Cancelled" : error?.localizedDescription ?? "Download failed") }
        Self.active[ObjectIdentifier(download)] = nil
    }
    private func observeProgress() {
        observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, let id = self.entryID else { return }
                self.store?.update(id, progress: fraction)
            }
        }
    }
    private func complete() {
        observation = nil; completion(); completion = {}
        // Let WebKit finish delivering this callback before the resumed download's web view goes.
        if let host { self.host = nil; DispatchQueue.main.async { _ = host } }
    }
}
