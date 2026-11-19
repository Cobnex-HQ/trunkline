import Foundation
import Combine

@MainActor
public final class ResumableFileClient: ObservableObject {
    public enum State: Equatable { case idle, preparing, transferring, paused, cancelling, completed }
    @Published public private(set) var state: State = .idle
    @Published public private(set) var name = ""
    @Published public private(set) var received: Int64 = 0
    @Published public private(set) var total: Int64 = 0
    @Published public private(set) var error: String?
    @Published public private(set) var downloadedURL: URL?
    @Published public private(set) var connected = false
    public var progress: Double { Double(received) / Double(max(total, 1)) }
    public var isBusy: Bool { state != .idle && state != .completed }
    public var send: ((UUID, FileTransferRequest) -> Void)?
    public var onComplete: (() -> Void)?
    private var macID = ""
    private var offer: FileTransferOffer?
    private var disk: ResumableTransferDisk?
    private var revision: String?
    private var requestID: UUID?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()
    private var timeout: Duration
    public init(timeout: Duration = .seconds(20)) { self.timeout = timeout }
    public func connect(macID: String) {
        if self.macID != macID { reset(); self.macID = macID }
        connected = true
        if state == .cancelling { cancel() }
    }
    public func disconnect() {
        connected = false
        requestID = nil; deadline?.cancel()
        if state != .preparing { generation = UUID() }
        if state == .transferring { state = .paused; error = "Paused. Reconnect to this Mac, then Retry." }
        // Preparation copies a file locally. It may finish while offline, but sends nothing.
    }
    public func reset() {
        deadline?.cancel(); requestID = nil; generation = UUID()
        disk = nil; offer = nil; revision = nil
        state = .idle; received = 0; total = 0; name = ""; error = nil; downloadedURL = nil
    }
    public func upload(_ url: URL, parent: String) {
        guard connected, !isBusy else { return }
        reset(); state = .preparing; name = url.lastPathComponent
        let disk = ResumableTransferDisk(); self.disk = disk
        let generation = generation
        Task {
            do {
                let size = try await disk.prepareUpload(url)
                guard self.generation == generation else { return }
                self.total = size
                self.offer = FileTransferOffer(ticket: FileTransferTicket(), path: parent.isEmpty ? self.name : parent + "/" + self.name, direction: .upload, size: size)
                self.state = .paused
                if self.connected { self.retry() }
            } catch { if self.generation == generation { self.fail(error.localizedDescription) } }
        }
    }
    public func download(path: String, name: String) {
        guard connected, !isBusy else { return }
        reset(); self.name = name; disk = ResumableTransferDisk()
        offer = FileTransferOffer(ticket: FileTransferTicket(), path: path, direction: .download, size: 0)
        state = .paused; retry()
    }
    public func retry() {
        guard connected, state == .paused, let offer else { return }
        generation = UUID(); state = .transferring; error = nil
        issue(.open(offer))
    }
    public func cancel() {
        guard isBusy else { return }
        generation = UUID(); requestID = nil; deadline?.cancel(); disk = nil
        guard let offer else { reset(); return }
        state = .cancelling; error = nil
        if connected { issue(.cancel(offer.ticket)) }
        else { error = "Cancellation will finish when you reconnect to this Mac." }
    }
    private func issue(_ request: FileTransferRequest) {
        guard connected else { fail("Paused. Reconnect, then Retry."); return }
        deadline?.cancel()
        let id = UUID(); requestID = id
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.requestID == id else { return }
            self.requestID = nil
            if self.state == .cancelling { self.error = "Cancellation wasn’t confirmed. Retry cancellation after reconnecting." }
            else { self.fail("Transfer paused. Retry to continue from the last confirmed position.") }
        }
        send?(id, request)
    }
    public func receive(id: UUID, reply: FileTransferReply) {
        guard id == requestID, reply.id == offer?.ticket.id else { return }
        requestID = nil; deadline?.cancel()
        if let error = reply.error {
            if state == .cancelling { self.error = error } else { fail(error) }
            return
        }
        if state == .cancelling {
            if reply.cancelled {
                if reply.complete { state = .completed; received = reply.offset; total = reply.size; error = "The Mac finished saving this file before cancellation arrived."; onComplete?() }
                else { reset() }
            }
            return
        }
        guard state == .transferring, let offer, let disk,
              reply.size >= 0, reply.size <= IncomingTransfer.maximumSize,
              reply.offset >= 0, reply.offset <= reply.size else { fail("Invalid transfer reply."); return }
        total = reply.size
        let generation = generation
        Task {
            guard self.generation == generation, self.state == .transferring else { return }
            do {
                if offer.direction == .upload {
                    guard reply.size == offer.size else { throw IncomingTransfer.TransferError.invalidSize }
                    self.received = reply.offset
                    if reply.complete {
                        guard reply.offset == offer.size else { throw IncomingTransfer.TransferError.incomplete }
                        self.state = .completed; self.disk = nil; self.onComplete?(); return
                    }
                    let bytes = try await disk.read(offset: reply.offset)
                    guard self.generation == generation, self.connected else { return }
                    self.issue(.write(offer.ticket, offset: reply.offset, bytes: bytes))
                } else {
                    guard let remoteVersion = reply.revision, self.revision == nil || self.revision == remoteVersion else { throw TransferFailure.changed }
                    self.revision = remoteVersion
                    if let bytes = reply.bytes {
                        guard reply.offset - Int64(bytes.count) == self.received else { throw IncomingTransfer.TransferError.invalidChunk }
                        let url = try await disk.append(bytes, offset: self.received, total: reply.size, complete: reply.complete, name: self.name)
                        guard self.generation == generation else { return }
                        self.received = reply.offset
                        if reply.complete {
                            self.downloadedURL = url; self.state = .completed; self.onComplete?(); return
                        }
                    }
                    guard self.generation == generation, self.connected else { return }
                    // Disk may have finished its final write just as a connection closed.
                    let position = await disk.downloadPosition()
                    guard self.generation == generation, self.connected else { return }
                    self.received = position
                    self.issue(.read(offer.ticket, offset: position))
                }
            } catch { if self.generation == generation { self.fail(error.localizedDescription) } }
        }
    }
    private func fail(_ message: String) {
        deadline?.cancel(); requestID = nil; generation = UUID()
        state = .paused; error = message
    }
    private enum TransferFailure: LocalizedError {
        case changed
        var errorDescription: String? { "The Mac file changed. Cancel this transfer and download it again." }
    }
    deinit { deadline?.cancel() }
}

private actor ResumableTransferDisk {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trunkline-resume-" + UUID().uuidString)
    private var upload: FileHandle?
    private var incoming: IncomingTransfer?
    private var finishedURL: URL?
    private var position: Int64 = 0
    func prepareUpload(_ source: URL) throws -> Int64 {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= IncomingTransfer.maximumSize else { throw IncomingTransfer.TransferError.invalidSize }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let snapshot = directory.appendingPathComponent("upload")
        try FileManager.default.copyItem(at: source, to: snapshot)
        upload = try FileHandle(forReadingFrom: snapshot)
        let copiedSize = Int64(try upload!.seekToEnd())
        guard copiedSize == size else { throw IncomingTransfer.TransferError.incomplete }
        return copiedSize
    }
    func read(offset: Int64) throws -> Data {
        guard let upload else { throw IncomingTransfer.TransferError.incomplete }
        try upload.seek(toOffset: UInt64(offset))
        return try upload.read(upToCount: IncomingTransfer.chunkSize) ?? Data()
    }
    func append(_ bytes: Data, offset: Int64, total: Int64, complete: Bool, name: String) throws -> URL? {
        if let finishedURL {
            guard offset == position, bytes.isEmpty, complete else { throw IncomingTransfer.TransferError.invalidChunk }
            return finishedURL
        }
        if incoming == nil {
            guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("/"), name != ".", name != ".." else { throw IncomingTransfer.TransferError.invalidChunk }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            incoming = try IncomingTransfer(destination: directory.appendingPathComponent(name), expectedSize: total)
        }
        guard let incoming, incoming.expectedSize == total else { throw IncomingTransfer.TransferError.invalidSize }
        try incoming.append(bytes, offset: offset); position = incoming.received
        if complete { try incoming.finish(); finishedURL = incoming.destination; self.incoming = nil }
        return finishedURL
    }
    func downloadPosition() -> Int64 { position }
    deinit { try? upload?.close(); try? FileManager.default.removeItem(at: directory) }
}
