import AppKit
import WebKit

/// Downloads outlive their originating tab and use the system save dialog.
@MainActor
final class BrowserDownload: NSObject, WKDownloadDelegate {
    private static var active: [ObjectIdentifier: BrowserDownload] = [:]
    private let download: WKDownload
    private var destination: URL?
    private var completion: () -> Void = {}
    private var store: DownloadStore?
    private var entryID: UUID?
    private var observation: NSKeyValueObservation?
    private var profileID: UUID?

    static func begin(_ download: WKDownload, store: DownloadStore?, profileID: UUID? = nil, completion: @escaping () -> Void = {}) {
        let handler = BrowserDownload(download)
        handler.store = store
        handler.profileID = profileID
        handler.completion = completion
        active[ObjectIdentifier(download)] = handler
        download.delegate = handler
    }
    private init(_ download: WKDownload) { self.download = download }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = store?.preferredDirectory?() ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            entryID = store?.begin(url, sourceURL: response.url, profileID: profileID)
            observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self, let id = self.entryID else { return }
                    self.store?.update(id, progress: fraction)
                }
            }
            completionHandler(url)
        } else {
            completionHandler(nil)
            complete()
            Self.active[ObjectIdentifier(download)] = nil
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        complete()
        if let entryID { store?.finish(entryID, error: nil) }
        Self.active[ObjectIdentifier(download)] = nil
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        complete()
        if let entryID { store?.finish(entryID, error: error.localizedDescription) }
        Self.active[ObjectIdentifier(download)] = nil
    }
    private func complete() { observation = nil; completion(); completion = {} }
}
