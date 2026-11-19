import AppKit
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class HostFiles {
    private let worker: HostFileWorker
    private let queue = DispatchQueue(label: "com.trunkline.file-service", qos: .utility)
    private let lifetime = FileRequestLifetime()
    private var pending = 0

    init(root: URL?, resumable: ResumableFileService = ResumableFileService()) { worker = HostFileWorker(root: root, resumable: resumable) }

    func handle(_ message: WireMessage, send: @escaping @MainActor (WireMessage) -> Void) -> Bool {
        switch message {
        case .requestClipboard:
            let value = NSPasteboard.general.string(forType: .string) ?? ""
            guard value.utf16.count <= 65536 else {
                send(.operationError(HostFileWorker.FileError.clipboardTooLarge.localizedDescription, context: .init(.clipboard))); return true
            }
            send(.clipboard(value)); return true
        case let .setClipboard(text):
            guard text.utf16.count <= 65536 else {
                send(.operationError(HostFileWorker.FileError.clipboardTooLarge.localizedDescription, context: .init(.clipboard))); return true
            }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            send(.clipboard(NSPasteboard.general.string(forType: .string) ?? "")); return true
        case .resumableFile, .mutateFile, .listFiles, .beginUpload, .beginUploadInFolder, .cancelFileTransfer, .uploadChunk, .download, .requestChunk:
            guard !lifetime.isCancelled else { return true }
            guard pending < 8 else {
                send(.operationError("Too many file requests. Wait for the current operation.", context: .init(.files))); return true
            }
            pending += 1
            let worker = worker, lifetime = lifetime
            queue.async { [weak self] in
                guard !lifetime.isCancelled else { return }
                var reply: WireMessage?
                _ = worker.handle(message) { reply = $0 }
                let response = reply
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pending -= 1
                    guard !lifetime.isCancelled, let response else { return }
                    send(response)
                }
            }
            return true
        default: return false
        }
    }

    func close() { lifetime.cancel() }
    deinit { lifetime.cancel() }
}

private final class FileRequestLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// All filesystem state is confined to HostFiles' serial queue, preserving
/// chunk order while directory traversal and fsync cannot block UI or input.
private final class HostFileWorker: @unchecked Sendable {
    let root: URL?
    private var upload: (UUID, IncomingTransfer)?
    private var download: (id: UUID, handle: FileHandle, size: Int64, offset: Int64)?
    private let resumable: ResumableFileService
    init(root: URL?, resumable: ResumableFileService) { self.root = root; self.resumable = resumable }
    func handle(_ message: WireMessage, send: (WireMessage) -> Void) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        do {
            switch message {
            case let .resumableFile(id, request):
                send(.resumableFileReply(id: id, reply: resumable.handle(request, root: root)))
            case let .cancelFileTransfer(id):
                upload = nil
                try? download?.handle.close(); download = nil
                send(.fileTransferCancelled(id: id))
            case let .mutateFile(id, action):
                do {
                    guard upload == nil, download == nil else { throw FileError.busyOrInvalid }
                    let plan = try action.resolve(root: requireRoot())
                    if let destination = plan.destination, FileManager.default.fileExists(atPath: destination.path) { throw FileError.exists }
                    switch action {
                    case .createFolder: try FileManager.default.createDirectory(at: plan.destination!, withIntermediateDirectories: false)
                    case .rename: try FileManager.default.moveItem(at: plan.source!, to: plan.destination!)
                    case .trash: try FileManager.default.trashItem(at: plan.source!, resultingItemURL: nil)
                    }
                    send(.fileMutationResult(id: id, error: nil))
                } catch { send(.fileMutationResult(id: id, error: error.localizedDescription)) }
            case let .listFiles(path):
                let root = try requireRoot()
                let folder = try ShareDirectory.resolve(path, root: root)
                let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)
                guard urls.count <= 2000 else { throw FileError.tooManyFiles }
                let files = try urls.compactMap { url -> RemoteFile? in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
                    guard values.isSymbolicLink != true else { return nil }
                    let relative = path.isEmpty ? url.lastPathComponent : path + "/" + url.lastPathComponent
                    _ = try ShareDirectory.resolve(relative, root: root)
                    return RemoteFile(name: url.lastPathComponent, path: relative, isDirectory: values.isDirectory == true, size: Int64(values.fileSize ?? 0))
                }.sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
                send(.fileList(path: path, entries: files))
            case let .beginUpload(name, size):
                try beginUpload(parent: "", name: name, size: size, send: send)
            case let .beginUploadInFolder(parent, name, size):
                try beginUpload(parent: parent, name: name, size: size, send: send)
            case let .uploadChunk(id, offset, bytes):
                guard let (expectedID, incoming) = upload, id == expectedID else { throw FileError.busyOrInvalid }
                try incoming.append(bytes, offset: offset)
                if incoming.received == incoming.expectedSize {
                    try incoming.finish(); upload = nil; send(.uploadComplete(id: id))
                } else { send(.transferProgress(id: id, received: incoming.received, total: incoming.expectedSize)) }
            case let .download(path):
                guard download == nil, upload == nil else { throw FileError.busyOrInvalid }
                let url = try ShareDirectory.resolve(path, root: requireRoot())
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= IncomingTransfer.maximumSize else { throw IncomingTransfer.TransferError.invalidSize }
                let id = UUID(); download = (id, try FileHandle(forReadingFrom: url), Int64(size), 0)
                send(.downloadStarted(id: id, name: url.lastPathComponent, size: Int64(size)))
            case let .requestChunk(id, offset):
                guard var current = download, current.id == id, current.offset == offset else { throw FileError.busyOrInvalid }
                let bytes = try current.handle.read(upToCount: IncomingTransfer.chunkSize) ?? Data()
                let remaining = current.size - offset
                guard bytes.count <= remaining, !bytes.isEmpty || remaining == 0 else { throw IncomingTransfer.TransferError.incomplete }
                current.offset += Int64(bytes.count)
                let last = current.offset == current.size
                send(.downloadChunk(id: id, offset: offset, bytes: bytes, last: last))
                if last { try current.handle.close(); download = nil } else { download = current }
            default: return false
            }
        } catch {
            upload = nil
            try? download?.handle.close(); download = nil
            send(.operationError(error.localizedDescription, context: .init(.files)))
        }
        return true
    }
    private func beginUpload(parent: String, name: String, size: Int64, send: (WireMessage) -> Void) throws {
        guard upload == nil, download == nil, !name.hasPrefix(".") else { throw FileError.busyOrInvalid }
        let root = try requireRoot()
        let folder = try ShareDirectory.resolve(parent, root: root)
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw FileError.busyOrInvalid }
        let destination = try FileMutation.createFolder(parent: parent, name: name).resolve(root: root).destination!
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FileError.exists }
        let incoming = try IncomingTransfer(destination: destination, expectedSize: size)
        let id = UUID(); upload = (id, incoming)
        send(.uploadReady(id: id))
    }
    private func requireRoot() throws -> URL { guard let root else { throw FileError.noFolder }; return root }
    deinit { try? download?.handle.close() }
    enum FileError: LocalizedError {
        case noFolder, exists, busyOrInvalid, tooManyFiles, clipboardTooLarge
        var errorDescription: String? {
            switch self {
            case .noFolder: "Choose a shared folder in Trunkline on your Mac first."
            case .exists: "A file with that name already exists. Rename it before uploading."
            case .busyOrInvalid: "Another transfer is active, or the file request is invalid."
            case .tooManyFiles: "This folder has too many entries. Choose a smaller folder on your Mac."
            case .clipboardTooLarge: "Clipboard text is limited to 65,536 characters."
            }
        }
    }
}
