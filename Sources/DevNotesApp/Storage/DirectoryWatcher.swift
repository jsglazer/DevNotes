import Foundation

/// Watches a directory for changes using a GCD file-system-object source, so external edits to
/// the notes folder — an iCloud download landing, or a save from another device replacing a file —
/// are noticed promptly instead of only when the user next switches notes.
///
/// Directory-level events fire on add / remove / rename / attribute changes of the entries iCloud
/// materialises (downloads arrive as file replacements), which is exactly the signal we want. The
/// handler is coalesced with a short debounce so a burst of writes triggers a single refresh, and
/// it is delivered on the main queue.
final class DirectoryWatcher {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?

    /// - Parameter onChange: invoked on the main queue after a coalesced change is observed.
    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleFire() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    /// Coalesce a burst of filesystem events into one callback (~0.3s after the last event).
    private func scheduleFire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    deinit { stop() }
}
