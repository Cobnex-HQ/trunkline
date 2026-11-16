#if canImport(TrunklineCore)
import TrunklineCore
#endif
import Foundation

@MainActor
final class DesktopPairingCoordinator {
    private var task: Task<Void, Never>?
    private var generation: UUID?
    func replace(with operation: @escaping @MainActor () async -> Void) {
        cancel()
        let token = UUID(); generation = token
        task = Task { [weak self] in
            await operation()
            guard let self, self.generation == token else { return }
            self.task = nil; self.generation = nil
        }
    }
    func cancel() { task?.cancel(); task = nil; generation = nil }
    deinit { task?.cancel() }
}
