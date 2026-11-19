import Foundation
import Darwin

public struct FileTransferTicket: Codable, Equatable, Sendable {
    public let id: UUID
    public let secret: UUID
    public init(id: UUID = UUID(), secret: UUID = UUID()) { self.id = id; self.secret = secret }
}
public struct FileTransferOffer: Codable, Equatable, Sendable {
    public enum Direction: String, Codable, Sendable { case upload, download }
    public let ticket: FileTransferTicket
    public let path: String
    public let direction: Direction
    public let size: Int64
    public init(ticket: FileTransferTicket, path: String, direction: Direction, size: Int64) {
        self.ticket = ticket; self.path = path; self.direction = direction; self.size = size
    }
}
public enum FileTransferRequest: Codable, Equatable, Sendable {
    case open(FileTransferOffer)
    case write(FileTransferTicket, offset: Int64, bytes: Data)
    case read(FileTransferTicket, offset: Int64)
    case cancel(FileTransferTicket)
    public var ticket: FileTransferTicket {
        switch self { case let .open(offer): offer.ticket
        case let .write(ticket, _, _), let .read(ticket, _), let .cancel(ticket): ticket }
    }
}
public struct FileTransferReply: Codable, Equatable, Sendable {
    public let id: UUID
    public var offset: Int64 = 0
    public var size: Int64 = 0
    public var bytes: Data?
    public var revision: String?
    public var complete = false
    public var cancelled = false
    public var error: String?
    public init(id: UUID) { self.id = id }
}

/// Retained by the host across authenticated connections. Tickets are unguessable
/// capabilities, scoped to the selected shared root. No UI or network work runs here.
public final class ResumableFileService: @unchecked Sendable {
    private final class Record {
        let offer: FileTransferOffer, root: URL, destination: URL
        var incoming: IncomingTransfer?
        var handle: FileHandle?
        var revision: String?
        var size: Int64
        var received: Int64 = 0
        var complete = false
        var cancelled = false
        var touched = Date()
        init(_ offer: FileTransferOffer, root: URL, destination: URL) {
            self.offer = offer; self.root = root; self.destination = destination; size = offer.size
        }
        deinit { try? handle?.close() }
    }
    private var records: [UUID: Record] = [:]
    private let lock = NSLock()
    public init() {}
    public func discardAll() { lock.withLock { records.removeAll() } }
    public func handle(_ request: FileTransferRequest, root: URL?) -> FileTransferReply {
        lock.withLock {
            records = records.filter { Date().timeIntervalSince($0.value.touched) < 1800 }
            let ticket = request.ticket
            var reply = FileTransferReply(id: ticket.id)
            do {
                guard let selectedRoot = root else { throw Failure("Choose a shared folder on the Mac first.") }
                let root = selectedRoot.standardizedFileURL.resolvingSymlinksInPath()
                if case let .open(offer) = request, records[ticket.id] == nil {
                    guard records.values.filter({ !$0.complete && !$0.cancelled }).count < 4 else {
                        throw Failure("Too many paused transfers. Cancel one or wait for it to expire.")
                    }
                    if records.count >= 64, let oldest = records.filter({ $0.value.complete || $0.value.cancelled }).min(by: { $0.value.touched < $1.value.touched })?.key { records[oldest] = nil }
                    let destination = try ShareDirectory.resolve(offer.path, root: root)
                    guard destination != root, !destination.lastPathComponent.hasPrefix(".") else { throw Failure("Choose a regular file in the shared folder.") }
                    let record = Record(offer, root: root, destination: destination)
                    if offer.direction == .upload {
                        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure("A file with that name already exists.") }
                        record.incoming = try IncomingTransfer(destination: destination, expectedSize: offer.size)
                    } else {
                        let descriptor = open(destination.path, O_RDONLY | O_NOFOLLOW)
                        guard descriptor >= 0 else { throw Failure("The file cannot be opened.") }
                        record.handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                        record.revision = try Self.version(record.handle!)
                        record.size = Int64(try record.handle!.seekToEnd())
                        guard record.size <= IncomingTransfer.maximumSize else { throw IncomingTransfer.TransferError.invalidSize }
                    }
                    records[ticket.id] = record
                }
                if case .cancel = request, records[ticket.id] == nil { reply.cancelled = true; return reply }
                guard let record = records[ticket.id], record.offer.ticket == ticket, record.root == root else {
                    throw Failure("This transfer expired or belongs to a different connection. Start it again.")
                }
                record.touched = Date()
                if case .cancel = request {
                    record.incoming = nil; try? record.handle?.close(); record.handle = nil; record.cancelled = true
                    reply.cancelled = true
                    reply.complete = record.complete && record.offer.direction == .upload
                    reply.offset = record.received; reply.size = record.size
                    return reply
                }
                guard !record.cancelled else { throw Failure("This transfer was cancelled. Start a new transfer.") }
                guard try ShareDirectory.resolve(record.offer.path, root: root) == record.destination else {
                    throw Failure("The shared folder changed. Start the transfer again.")
                }
                reply.size = record.size; reply.revision = record.revision
                switch request {
                case let .open(offer):
                    guard offer == record.offer else { throw Failure("The transfer details changed.") }
                    if record.offer.direction == .download { try verifySource(record) }
                    reply.offset = record.received; reply.complete = record.complete
                case let .write(_, offset, bytes):
                    guard record.offer.direction == .upload else { throw Failure("Invalid transfer direction.") }
                    if record.complete { reply.offset = record.size; reply.complete = true; return reply }
                    guard let incoming = record.incoming else { throw Failure("The transfer is unavailable.") }
                    try incoming.append(bytes, offset: offset)
                    record.received = incoming.received
                    if incoming.received == incoming.expectedSize {
                        try incoming.finish(); record.incoming = nil; record.complete = true
                    }
                    reply.offset = record.received; reply.complete = record.complete
                case let .read(_, offset):
                    guard record.offer.direction == .download, offset >= 0, offset <= record.size, let handle = record.handle else { throw Failure("Invalid download offset.") }
                    try verifySource(record)
                    try handle.seek(toOffset: UInt64(offset))
                    let bytes = try handle.read(upToCount: Int(min(Int64(IncomingTransfer.chunkSize), record.size - offset))) ?? Data()
                    guard !bytes.isEmpty || offset == record.size else { throw IncomingTransfer.TransferError.incomplete }
                    try verifySource(record)
                    reply.bytes = bytes; reply.offset = offset + Int64(bytes.count); reply.complete = reply.offset == record.size
                    record.complete = reply.complete
                case .cancel: break
                }
            } catch { reply.error = error.localizedDescription }
            return reply
        }
    }
    private func verifySource(_ record: Record) throws {
        guard let handle = record.handle, try Self.version(handle) == record.revision else { throw Failure("The Mac file changed. Cancel this transfer and download it again.") }
        let descriptor = open(record.destination.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure("The Mac file is no longer available.") }
        let current = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? current.close() }
        guard try Self.version(current) == record.revision else { throw Failure("The Mac file was replaced. Start a new download.") }
    }
    private static func version(_ handle: FileHandle) throws -> String {
        var value = stat()
        guard fstat(handle.fileDescriptor, &value) == 0, (value.st_mode & S_IFMT) == S_IFREG else { throw Failure("Choose a regular file.") }
        return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
