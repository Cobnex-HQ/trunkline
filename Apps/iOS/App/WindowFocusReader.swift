import SwiftUI

/// Only the key window may use the shared device clipboard.
struct WindowFocusReader: UIViewRepresentable {
    var changed: (Bool) -> Void
    var disconnected: () -> Void
    func makeUIView(context: Context) -> FocusView { FocusView(changed: changed, disconnected: disconnected) }
    func updateUIView(_ view: FocusView, context: Context) { view.changed = changed }
    final class FocusView: UIView {
        var changed: (Bool) -> Void
        private var disconnected: () -> Void
        private weak var owningScene: UIWindowScene?
        private var tokens: [NSObjectProtocol] = []
        init(changed: @escaping (Bool) -> Void, disconnected: @escaping () -> Void) {
            self.changed = changed
            self.disconnected = disconnected
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            tokens.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let scene = self.owningScene, note.object as? UIScene === scene else { return }
                    self.disconnected()
                }
            })
            for name in [UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window, note.object as? UIWindow === window else { return }
                        self.changed(window.isKeyWindow)
                    }
                })
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { owningScene = scene }
            let focused = window?.isKeyWindow == true
            DispatchQueue.main.async { [weak self] in self?.changed(focused) }
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
