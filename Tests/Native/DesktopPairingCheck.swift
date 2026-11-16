import Foundation

@main struct DesktopPairingCheck {
    @MainActor static func main() async {
        let coordinator = DesktopPairingCoordinator()
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        var firstCancelled = false, secondCancelled = false
        var firstFinished = false, secondFinished = false
        func waitFor(_ predicate: () -> Bool) async {
            for _ in 0..<100 {
                if predicate() { return }
                try? await Task.sleep(for: .milliseconds(5))
            }
            print("FAIL: pairing retry did not run while the old request was pending"); exit(1)
        }
        coordinator.replace {
            await withCheckedContinuation { first = $0 }
            firstCancelled = Task.isCancelled; firstFinished = true
        }
        await waitFor { first != nil }
        coordinator.replace {
            await withCheckedContinuation { second = $0 }
            secondCancelled = Task.isCancelled; secondFinished = true
        }
        await waitFor { second != nil }
        first?.resume()
        await waitFor { firstFinished }
        // The retired attempt's completion must not clear the newer task handle.
        coordinator.cancel()
        second?.resume()
        await waitFor { secondFinished }
        guard firstCancelled, secondCancelled else {
            print("FAIL: replacement/disconnect did not cancel the correct pairing tasks"); exit(1)
        }
        var recovered = false
        coordinator.replace { recovered = true }
        await waitFor { recovered }
        print("PASS: pairing retries supersede pending work; late completion cannot orphan the current attempt; disconnect and subsequent retry recover")
    }
}
