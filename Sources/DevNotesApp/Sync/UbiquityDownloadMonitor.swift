import Foundation

/// Actively pulls iCloud Drive changes down instead of waiting for the system to materialise
/// them. The `DirectoryWatcher` only sees files *after* the iCloud daemon has downloaded them
/// locally — on a quiet Mac that can lag a remote edit by minutes. This monitor runs an
/// `NSMetadataQuery` over the app's ubiquity Documents scope, so it learns about remote changes
/// as soon as the metadata lands, then calls `startDownloadingUbiquitousItem` for every note
/// that isn't fully downloaded — turning sync from passive to eager.
///
/// It complements (not replaces) `DirectoryWatcher`: the query triggers the download, the
/// directory watcher notices the downloaded file landing and refreshes the UI. `onChange` also
/// fires from here so list metadata (names, dates) updates even before content arrives.
@MainActor
final class UbiquityDownloadMonitor {
    private let query = NSMetadataQuery()
    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []

    /// - Parameter onChange: invoked on the main queue whenever the ubiquity scope reports a
    ///   change (initial gather or live update).
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard observers.isEmpty else { return }
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)

        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        for name in names {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                // The observer queue is `.main`, so this closure is already on the main actor.
                MainActor.assumeIsolated { self?.handleQueryChange() }
            })
        }
        query.start()
    }

    func stop() {
        query.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    /// Kicks off downloads for every result that isn't current, then notifies.
    private func handleQueryChange() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        for case let item as NSMetadataItem in query.results {
            guard
                let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                let status = item.value(
                    forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
                ) as? String,
                status != NSMetadataUbiquitousItemDownloadingStatusCurrent
            else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        onChange()
    }

    // No deinit teardown: the owner (`AppModel`) keeps this monitor for the app's lifetime and
    // calls `stop()` explicitly if it ever needs to; a MainActor-isolated deinit can't touch
    // `observers` under Swift 6 isolation rules.
}
