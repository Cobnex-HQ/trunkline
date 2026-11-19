import SwiftUI
import AVFoundation

/// The accessory is scoped to the presenting desktop window, never a global saved Mac.
@available(iOS 27.0, *)
struct ExternalDisplayPresentation: UIViewControllerRepresentable {
    let source: UIViewController?
    let enabled: Bool
    func makeUIViewController(context: Context) -> ExternalDisplayRegistrationController {
        ExternalDisplayRegistrationController()
    }
    func updateUIViewController(_ controller: ExternalDisplayRegistrationController, context: Context) {
        controller.source = source?.view
        controller.enabled = enabled
        controller.synchronize()
    }
    static func dismantleUIViewController(_ controller: ExternalDisplayRegistrationController, coordinator: ()) {
        controller.stop()
    }
}

@available(iOS 27.0, *)
final class ExternalDisplayRegistrationController: UIViewController {
    private final class WeakRegistration {
        weak var value: ExternalDisplayRegistrationController?
        init(_ value: ExternalDisplayRegistrationController) { self.value = value }
    }
    private static var registrations: [String: WeakRegistration] = [:]
    let owner = UUID().uuidString
    weak var source: UIView?
    var enabled = false
    private var registration: UISceneAccessoryRegistration?
    private var observers: [NSObjectProtocol] = []
    static func context(_ owner: String) -> ExternalDisplayRegistrationController? {
        registrations[owner]?.value
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronize() }
        })
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        synchronize()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }
    func synchronize() {
        guard enabled, source?.window != nil, view.window != nil,
              UIApplication.shared.applicationState == .active else { suspend(); return }
        Self.registrations[owner] = WeakRegistration(self)
        if registration == nil {
            let configuration = UISceneConfiguration(name: "Remote desktop display", sessionRole: .windowExternalDisplayNonInteractive)
            configuration.delegateClass = ExternalDesktopSceneDelegate.self
            registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration, userInfo: owner))
        }
        registration?.isEnabled = true
    }
    private func suspend() {
        registration?.isEnabled = false
        TrunklineExternalVideo.shared().detachOwner(owner)
    }
    func stop() {
        suspend()
        if let registration { unregisterSceneAccessory(registration) }
        registration = nil
        Self.registrations.removeValue(forKey: owner)
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}

@available(iOS 27.0, *)
final class ExternalDesktopSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var owner: String?
    private var content: ExternalDesktopViewController?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, session.role == .windowExternalDisplayNonInteractive,
              let owner = options.sceneAccessoryUserInfo as? String else { return }
        self.owner = owner
        let content = ExternalDesktopViewController()
        self.content = content
        let window = UIWindow(windowScene: scene)
        window.rootViewController = content
        self.window = window
        window.isHidden = false
        attach()
    }
    private func attach() {
        guard let owner, let context = ExternalDisplayRegistrationController.context(owner),
              context.enabled, UIApplication.shared.applicationState == .active,
              let source = context.source, let content else { return }
        content.loadViewIfNeeded()
        _ = TrunklineExternalVideo.shared().attach(content.video, sourceView: source, owner: owner)
    }
    func sceneWillEnterForeground(_ scene: UIScene) { attach() }
    func sceneDidEnterBackground(_ scene: UIScene) { clear() }
    func sceneDidDisconnect(_ scene: UIScene) {
        clear()
        window = nil
        content = nil
    }
    private func clear() {
        if let content { TrunklineExternalVideo.shared().detach(content.video) }
    }
}

final class ExternalDesktopViewController: UIViewController {
    let video = AVSampleBufferDisplayLayer()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        video.videoGravity = .resizeAspect
        view.layer.addSublayer(video)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        video.frame = view.bounds
        CATransaction.commit()
    }
}
