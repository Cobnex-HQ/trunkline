import Foundation
import Darwin

public final class IncomingTransfer {
    public static let maximumSize: Int64 = 512 * 1024 * 1024
    public static let chunkSize = 128 * 1024
    public let destination: URL
    public let expectedSize: Int64
    public private(set) var received: Int64 = 0
    private let temporary: URL
    private let handle: FileHandle
    private var finished = false
    public init(destination: URL, expectedSize: Int64) throws {
        guard expectedSize >= 0, expectedSize <= Self.maximumSize else { throw TransferError.invalidSize }
        self.destination = destination; self.expectedSize = expectedSize
        temporary = destination.deletingLastPathComponent().appendingPathComponent(".trunkline-\(UUID().uuidString).part")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TransferError.cannotWrite }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    public func append(_ bytes: Data, offset: Int64) throws {
        guard !finished, offset == received, bytes.count <= Self.chunkSize, received + Int64(bytes.count) <= expectedSize else { throw TransferError.invalidChunk }
        try handle.write(contentsOf: bytes); received += Int64(bytes.count)
    }
    public func finish() throws {
        guard !finished, received == expectedSize else { throw TransferError.incomplete }
        try handle.synchronize(); try handle.close()
        // FileManager move does not replace an existing destination.
        try FileManager.default.moveItem(at: temporary, to: destination)
        finished = true
    }
    deinit { try? handle.close(); if !finished { try? FileManager.default.removeItem(at: temporary) } }
    public enum TransferError: LocalizedError {
        case invalidSize, cannotWrite, invalidChunk, incomplete
        public var errorDescription: String? {
            switch self {
            case .invalidSize: "Transfers support files up to 512 MB."
            case .cannotWrite: "Could not create the transferred file."
            case .invalidChunk: "Transfer data arrived out of order or exceeded the file size."
            case .incomplete: "The transfer is incomplete."
            }
        }
    }
}
