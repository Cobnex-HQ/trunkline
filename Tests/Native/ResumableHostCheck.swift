import Foundation

@main struct ResumableHostCheck {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResumableFileService(), ticket = FileTransferTicket()
        let offer = FileTransferOffer(ticket: ticket, path: "resume.txt", direction: .upload, size: 6)
        func request(_ service: HostFiles, _ request: FileTransferRequest) async -> FileTransferReply {
            let id = UUID()
            return await withCheckedContinuation { continuation in
                precondition(service.handle(.resumableFile(id: id, request: request)) { response in
                    guard case let .resumableFileReply(responseID, reply) = response, responseID == id else { fatalError("Missing request correlation") }
                    continuation.resume(returning: reply)
                })
            }
        }
        let first = HostFiles(root: root, resumable: store)
        let opened = await request(first, .open(offer)); precondition(opened.offset == 0)
        let written = await request(first, .write(ticket, offset: 0, bytes: Data("abc".utf8))); precondition(written.offset == 3)
        first.close()
        let second = HostFiles(root: root, resumable: store)
        let resumed = await request(second, .open(offer)); precondition(resumed.offset == 3)
        let completed = await request(second, .write(ticket, offset: 3, bytes: Data("def".utf8))); precondition(completed.complete)
        let bytes = try Data(contentsOf: root.appendingPathComponent("resume.txt")); precondition(bytes == Data("abcdef".utf8))
        print("PASS: upload resumes across real HostFiles connection lifetimes")
    }
}
