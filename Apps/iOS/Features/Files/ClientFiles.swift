import Foundation
import Combine
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class ClientFiles: ObservableObject {
    @Published private(set) var features: Set<FileFeature> = []
    @Published private(set) var mutation: UUID?
    @Published private(set) var cancellation: UUID?
    @Published private(set) var requiresReconnect = false
    @Published var entries: [RemoteFile] = []
    @Published var path = ""
    @Published var isLoading = false
    @Published private(set) var hasLoadedListing = false
    var isRefreshingListing: Bool { isLoading && hasLoadedListing && requestedPath == path }
    @Published var transferName: String?
    @Published var progress = 0.0
    @Published var downloadedURL: URL?
    @Published var error: String?
    let clipboard = ClipboardTransfer()
    private var clipboardMacID = ""
    private var clipboardPreferences = MacPreferencesStore()
    @Published var clipboardText = ""
    @Published var clipboardError: String?
    var send: ((WireMessage) -> Void)?
    var onReconnect: (() -> Void)?
    private var outgoing: (size: Int64, offset: Int64, id: UUID?)?
    private var incoming: UUID?
    private let worker = ClientFileWorker()
    private let diskQueue = DispatchQueue(label: "com.trunkline.client-files", qos: .utility)
    private var transferGeneration = UUID()
    private var diskPending = false
    private let operationTimeout: Duration
    private let cancellationTimeout: Duration
    private var deadline: Task<Void, Never>?
    private var requestedPath: String?
    init(operationTimeout: Duration = .seconds(30), cancellationTimeout: Duration = .seconds(10)) {
        self.operationTimeout = operationTimeout; self.cancellationTimeout = cancellationTimeout
        clipboard.send = { [weak self] in self?.send?($0) }
    }
    func configureClipboard(macID: String, defaults: UserDefaults) {
        clipboard.reset()
        clipboardMacID = macID
        clipboardPreferences = MacPreferencesStore(defaults: defaults)
        clipboard.mode = clipboardPreferences.load(macID).clipboard
        clipboard.activate()
    }
    func setClipboardSyncMode(_ mode: ClipboardSyncMode) {
        var preferences = clipboardPreferences.load(clipboardMacID)
        preferences.clipboard = mode
        clipboardPreferences.save(preferences, for: clipboardMacID)
        clipboard.mode = mode
    }
    var isBusy: Bool { transferName != nil || mutation != nil || cancellation != nil || isLoading || requiresReconnect }
    var isCancelling: Bool { cancellation != nil }
    var canUploadHere: Bool { path.isEmpty || features.contains(.folderUpload) }
    func configure(fileFeatures: [String]?) {
        features = Set((fileFeatures ?? []).compactMap(FileFeature.init(rawValue:)))
    }
    func list(_ path: String = "") {
        guard !isBusy else { return }
        isLoading = true; requestedPath = path; error = nil; armDeadline()
        send?(.listFiles(path: path))
    }
    func mutate(_ action: FileMutation) {
        guard !isBusy else { return }
        guard features.contains(.mutations) else {
            error = "Update Trunkline on your Mac to edit files and folders."; return
        }
        let id = UUID(); mutation = id; error = nil; armDeadline(); send?(.mutateFile(id: id, action: action))
    }
    func parent() {
        let components = path.split(separator: "/").dropLast()
        list(components.joined(separator: "/"))
    }
    func download(_ file: RemoteFile) {
        guard !isBusy else { return }
        transferName = file.name; progress = 0; error = nil; armDeadline(); send?(.download(path: file.path))
    }
    func upload(_ url: URL) {
        guard !isBusy else { return }
        guard canUploadHere else {
            error = "Update Trunkline on your Mac to upload into folders. You can still upload to the shared folder."; return
        }
        transferName = url.lastPathComponent; progress = 0; error = nil; armDeadline()
        let parent = path
        performDiskWork({ try $0.openUpload(url) }, remoteStarted: false) { client, size in
            client.outgoing = (size, 0, nil)
            client.armDeadline()
            client.send?(parent.isEmpty ? .beginUpload(name: url.lastPathComponent, size: size)
                : .beginUploadInFolder(parent: parent, name: url.lastPathComponent, size: size))
        }
    }
    @discardableResult func handle(_ message: WireMessage) -> Bool {
        if case let .operationError(text, context?) = message {
            if context.domain == .clipboard { clipboard.fail(text); clipboardError = text; return true }
            guard context.domain == .files else { return false }
        }
        // Ordered cancellation acknowledgement is a barrier: replies from the
        // transfer being cancelled must never enter the next transfer's state.
        if cancellation != nil || requiresReconnect {
            switch message {
            case .uploadReady, .transferProgress, .uploadComplete, .downloadStarted, .downloadChunk, .operationError: return true
            default: break
            }
        }
        do {
            switch message {
            case let .fileTransferCancelled(id):
                guard cancellation == id else { return true }
                let notice = requiresReconnect ? nil : error
                clearTransfer(); list(path)
                error = notice
            case let .fileMutationResult(id, error):
                guard mutation == id else { return true }
                stopDeadline(); mutation = nil
                if let error { self.error = error } else { list(path) }
            case let .fileList(path, entries):
                guard requestedPath == path else { return true }
                stopDeadline(); requestedPath = nil
                if self.path != path { self.path = path }
                if self.entries != entries { self.entries = entries }
                hasLoadedListing = true
                isLoading = false
            case let .uploadReady(id):
                guard var current = outgoing, current.id == nil, !diskPending else { throw IncomingTransfer.TransferError.invalidChunk }
                current.id = id; outgoing = current; armDeadline(); sendUploadChunk()
            case let .transferProgress(id, received, total):
                guard let current = outgoing, current.id == id, !diskPending, received == current.offset, total == current.size else { throw IncomingTransfer.TransferError.invalidChunk }
                progress = Double(received) / Double(max(total, 1)); armDeadline(); sendUploadChunk()
            case let .uploadComplete(id):
                guard let current = outgoing, current.id == id, !diskPending, current.offset == current.size else { throw IncomingTransfer.TransferError.incomplete }
                performDiskWork({ try $0.closeUpload() }) { client, _ in
                    client.outgoing = nil; client.stopDeadline(); client.transferName = nil
                    client.progress = 1; client.list(client.path)
                }
            case let .downloadStarted(id, name, size):
                guard transferName != nil, incoming == nil, outgoing == nil, !diskPending, !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("/"), name != ".", name != ".." else { throw IncomingTransfer.TransferError.invalidChunk }
                downloadedURL = nil; incoming = id; armDeadline()
                performDiskWork({ try $0.openDownload(name: name, size: size) }) { client, _ in
                    client.armDeadline(); client.send?(.requestChunk(id: id, offset: 0))
                }
            case let .downloadChunk(id, offset, bytes, last):
                guard incoming == id, !diskPending else { throw IncomingTransfer.TransferError.invalidChunk }
                performDiskWork({ try $0.appendDownload(bytes, offset: offset, last: last) }) { client, result in
                    client.progress = Double(result.received) / Double(max(result.total, 1))
                    if let url = result.url {
                        client.stopDeadline(); client.downloadedURL = url; client.incoming = nil; client.transferName = nil
                    } else { client.armDeadline(); client.send?(.requestChunk(id: id, offset: result.received)) }
                }
            case let .operationError(message, _):
                if transferName != nil { cancelTransfer() } else { clearTransfer() }
                isLoading = false; requestedPath = nil; error = message
            case let .clipboard(text): clipboard.receive(text); clipboardText = text; clipboardError = nil
            default: return false
            }
        } catch { cancelTransfer(); self.error = error.localizedDescription }
        return true
    }
    private func sendUploadChunk() {
        guard let current = outgoing, let id = current.id else { return }
        performDiskWork({ try $0.readUpload(offset: current.offset, size: current.size) }) { client, bytes in
            client.outgoing = (current.size, current.offset + Int64(bytes.count), id)
            client.armDeadline()
            client.send?(.uploadChunk(id: id, offset: current.offset, bytes: bytes))
        }
    }
    /// Only one chunk can be in flight. Disk state stays on one queue; UI/protocol
    /// state stays on MainActor. Reset/cancel invalidates callbacks immediately,
    /// and queues resource cleanup before any subsequent transfer can open a file.
    private func performDiskWork<Value>(_ work: @escaping (ClientFileWorker) throws -> Value,
                                        remoteStarted: Bool = true,
                                        completion: @escaping @MainActor (ClientFiles, Value) -> Void) {
        precondition(!diskPending)
        diskPending = true
        let generation = transferGeneration, worker = worker
        diskQueue.async { [weak self] in
            dispatchPrecondition(condition: .notOnQueue(.main))
            let result = Result { try work(worker) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.transferGeneration == generation else { return }
                self.diskPending = false
                switch result {
                case let .success(value): completion(self, value)
                case let .failure(error):
                    if remoteStarted { self.cancelTransfer() } else { self.clearTransfer() }
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func cancelTransfer() {
        guard transferName != nil, cancellation == nil, !requiresReconnect else { return }
        guard features.contains(.cancellation) else {
            // A legacy host has no acknowledgement barrier. Keep Files blocked
            // until the user reconnects, without disrupting their desktop session.
            stopDeadline(); releaseTransferResources(); transferName = nil
            requiresReconnect = true
            error = "Reconnect to continue file transfers. This Mac needs an update to cancel transfers without disconnecting."
            return
        }
        let id = UUID(); cancellation = id
        releaseTransferResources()
        armDeadline(cancelling: true)
        send?(.cancelFileTransfer(id: id))
    }
    private func releaseTransferResources() {
        transferGeneration = UUID(); diskPending = false; outgoing = nil; incoming = nil
        // A final write may have completed on disk before cancellation invalidated
        // its UI callback. Keep only a file that was actually published for sharing.
        let worker = worker, removeDownloaded = downloadedURL == nil
        diskQueue.async { worker.release(removeDownloaded: removeDownloaded) }
    }
    private func clearTransfer() {
        stopDeadline(); requiresReconnect = false
        mutation = nil
        cancellation = nil; releaseTransferResources(); transferName = nil; progress = 0
    }
    private func stopDeadline() { deadline?.cancel(); deadline = nil }
    private func armDeadline(cancelling: Bool = false) {
        stopDeadline()
        let delay = cancelling ? cancellationTimeout : operationTimeout
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            self.deadline = nil
            if self.cancellation != nil {
                self.requiresReconnect = true; self.transferName = nil
                self.error = "The Mac didn’t confirm cancellation. Reconnect to continue."
            } else if self.transferName != nil {
                self.error = "The transfer stopped responding. Try again."
                self.cancelTransfer()
            } else {
                self.isLoading = false; self.requestedPath = nil; self.mutation = nil
                self.error = "The Mac didn’t respond. Refresh to try again."
            }
        }
    }
    func reset() {
        features = []
        clipboard.reset()
        clearTransfer(); entries = []; path = ""; isLoading = false; hasLoadedListing = false; clipboardText = ""
        requestedPath = nil; error = nil; clipboardError = nil
        downloadedURL = nil
        let worker = worker
        diskQueue.async { worker.release(removeDownloaded: true) }
    }
    deinit {
        let worker = worker
        diskQueue.async { worker.release(removeDownloaded: true) }
    }
}

/// Owned by ClientFiles, but accessed only from its serial utility queue.
/// No FileHandle, IncomingTransfer or security-scoped lifetime crosses to the UI.
private final class ClientFileWorker: @unchecked Sendable {
    private var upload: (url: URL, handle: FileHandle, scoped: Bool)?
    private var download: IncomingTransfer?
    private var temporaryDirectory: URL?
    private var downloadFinished = false

    func openUpload(_ url: URL) throws -> Int64 {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= IncomingTransfer.maximumSize else { throw IncomingTransfer.TransferError.invalidSize }
            upload = (url, try FileHandle(forReadingFrom: url), scoped)
            return Int64(size)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func readUpload(offset: Int64, size: Int64) throws -> Data {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let upload else { throw IncomingTransfer.TransferError.incomplete }
        let bytes = try upload.handle.read(upToCount: IncomingTransfer.chunkSize) ?? Data()
        guard !bytes.isEmpty || offset == size, offset + Int64(bytes.count) <= size else { throw IncomingTransfer.TransferError.incomplete }
        return bytes
    }
    func closeUpload() throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let current = upload else { return }
        defer {
            if current.scoped { current.url.stopAccessingSecurityScopedResource() }
            upload = nil
        }
        try current.handle.close()
    }
    func openDownload(name: String, size: Int64) throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        release(removeDownloaded: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trunkline-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        download = try IncomingTransfer(destination: directory.appendingPathComponent(name), expectedSize: size)
    }
    func appendDownload(_ bytes: Data, offset: Int64, last: Bool) throws -> (received: Int64, total: Int64, url: URL?) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let current = download else { throw IncomingTransfer.TransferError.invalidChunk }
        try current.append(bytes, offset: offset)
        if last {
            try current.finish(); downloadFinished = true; download = nil
        }
        return (current.received, current.expectedSize, last ? current.destination : nil)
    }
    func release(removeDownloaded: Bool) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        try? closeUpload(); download = nil
        if removeDownloaded || !downloadFinished {
            if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
            temporaryDirectory = nil; downloadFinished = false
        }
    }
}
