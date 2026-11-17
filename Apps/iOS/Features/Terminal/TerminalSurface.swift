#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import SwiftTerm

enum TerminalShortcut: CaseIterable {
    case escape, tab, controlC, controlD, up, down, left, right
    var title: String {
        switch self {
        case .escape: "Esc"
        case .tab: "Tab"
        case .controlC: "⌃C"
        case .controlD: "⌃D"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
    var accessibilityLabel: String {
        switch self {
        case .escape: "Escape"
        case .tab: "Tab"
        case .controlC: "Control C"
        case .controlD: "Control D"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        }
    }
    func bytes(applicationCursor: Bool) -> [UInt8] {
        let prefix: UInt8 = applicationCursor ? 79 : 91
        return switch self {
        case .escape: [27]
        case .tab: [9]
        case .controlC: [3]
        case .controlD: [4]
        case .up: [27, prefix, 65]
        case .down: [27, prefix, 66]
        case .left: [27, prefix, 68]
        case .right: [27, prefix, 67]
        }
    }
}

@MainActor final class TerminalShortcutInput {
    weak var terminal: SessionTerminalView?
    func send(_ key: TerminalShortcut) {
        guard let terminal else { return }
        terminal.send(key.bytes(applicationCursor: terminal.getTerminal().applicationCursor))
    }
}

struct TerminalSurface: UIViewRepresentable {
    let model: ConnectionModel
    let sessionID: UUID
    @Binding var showKeyboard: Bool
    var fontSize: CGFloat = 14
    var input: TerminalShortcutInput? = nil
    var acceptsInput = true
    func makeCoordinator() -> Coordinator { Coordinator(model: model, id: sessionID, keyboard: $showKeyboard, input: input) }
    func makeUIView(context: Context) -> SessionTerminalView {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        #if DEBUG && targetEnvironment(simulator)
        let terminal: SessionTerminalView = ProcessInfo.processInfo.arguments.contains("--ui-review")
            ? ReviewTerminalView(frame: .zero, font: font) : SessionTerminalView(frame: .zero, font: font)
        #else
        let terminal = SessionTerminalView(frame: .zero, font: font)
        #endif
        terminal.terminalDelegate = context.coordinator
        terminal.acceptsInput = acceptsInput
        input?.terminal = terminal
        terminal.onFocusChange = { [weak coordinator = context.coordinator, weak terminal] in
            guard let terminal else { return }
            coordinator?.synchronizeFocus(from: terminal)
        }
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.accessibilityLabel = "Mac terminal session"
        model.onTerminalData = { [weak terminal, sessionID] id, bytes, reset in
            guard id == sessionID, let terminal else { return }
            if reset { terminal.getTerminal().resetToInitialState() }
            terminal.feed(byteArray: Array(bytes)[...])
        }
        DispatchQueue.main.async {
            model.send(.attachTerminal(id: sessionID))
            let term = terminal.getTerminal()
            model.send(.resizeTerminal(id: sessionID, columns: term.cols, rows: term.rows))
        }
        return terminal
    }
    func updateUIView(_ terminal: SessionTerminalView, context: Context) {
        context.coordinator.keyboard = $showKeyboard
        terminal.acceptsInput = acceptsInput
        if terminal.font.pointSize != fontSize {
            terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        context.coordinator.requestKeyboard(showKeyboard && acceptsInput, terminal: terminal)
    }
    static func dismantleUIView(_ terminal: SessionTerminalView, coordinator: Coordinator) {
        coordinator.active = false
        terminal.onFocusChange = nil
        terminal.terminalDelegate = nil
        if coordinator.input?.terminal === terminal { coordinator.input?.terminal = nil }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        weak var model: ConnectionModel?
        let id: UUID
        var keyboard: Binding<Bool>
        var active = true
        let input: TerminalShortcutInput?
        private var lastKeyboardRequest: Bool?
        init(model: ConnectionModel, id: UUID, keyboard: Binding<Bool>, input: TerminalShortcutInput? = nil) {
            self.model = model; self.id = id; self.keyboard = keyboard; self.input = input
        }
        func requestKeyboard(_ requested: Bool, terminal: SessionTerminalView) {
            // A native dismissal may precede the deferred binding update. Only a new
            // SwiftUI request may change focus; ordinary redraws must not reclaim it.
            guard lastKeyboardRequest != requested else { return }
            lastKeyboardRequest = requested
            if requested, !terminal.isFirstResponder { _ = terminal.becomeFirstResponder() }
            else if !requested, terminal.isFirstResponder { _ = terminal.resignFirstResponder() }
            synchronizeFocus(from: terminal)
        }
        func synchronizeFocus(from terminal: SessionTerminalView) {
            // Avoid mutating SwiftUI state during updateUIView; read the latest focus
            // so rapid native focus changes cannot publish an obsolete event.
            DispatchQueue.main.async { [weak self, weak terminal] in
                guard let self, self.active, let terminal else { return }
                let focused = terminal.isFirstResponder
                if self.keyboard.wrappedValue != focused { self.keyboard.wrappedValue = focused }
            }
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { model?.send(.resizeTerminal(id: id, columns: newCols, rows: newRows)) }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard active, (source as? SessionTerminalView)?.acceptsInput != false else { return }
            let bytes = Array(data)
            for offset in stride(from: 0, to: bytes.count, by: 16384) {
                model?.send(.terminalInput(id: id, bytes: Data(bytes[offset..<min(bytes.count, offset+16384)])))
            }
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        // Terminal output cannot automatically open URLs or read/write the iPhone clipboard.
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func bell(source: TerminalView) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

class SessionTerminalView: TerminalView {
    var onFocusChange: (() -> Void)?
    var acceptsInput = true {
        didSet { if !acceptsInput { _ = resignFirstResponder() } }
    }
    override var canBecomeFirstResponder: Bool { acceptsInput && super.canBecomeFirstResponder }
    func pageHistory(up: Bool) {
        if getTerminal().isCurrentBufferAlternate {
            if acceptsInput { send(up ? EscapeSequences.cmdPageUp : EscapeSequences.cmdPageDown) }
        } else {
            let bottom = max(0, contentSize.height - bounds.height)
            let next = contentOffset.y + (up ? -1 : 1) * bounds.height * 0.8
            setContentOffset(CGPoint(x: 0, y: min(bottom, max(0, next))), animated: false)
            flashScrollIndicators()
        }
    }
    func jumpToLatest() {
        setContentOffset(CGPoint(x: 0, y: max(0, contentSize.height - bounds.height)), animated: false)
    }
    override init(frame: CGRect, font: UIFont?) {
        super.init(frame: frame, font: font)
        inputAccessoryView = TerminalInputAccessory(terminal: self)
        showsVerticalScrollIndicator = true
        keyboardDismissMode = .interactive
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:font:)") }
    override func becomeFirstResponder() -> Bool {
        guard acceptsInput else { return false }
        let wasFocused = isFirstResponder
        let result = super.becomeFirstResponder()
        if isFirstResponder != wasFocused { onFocusChange?() }
        return result
    }
    override func resignFirstResponder() -> Bool {
        let wasFocused = isFirstResponder
        let result = super.resignFirstResponder()
        if !isFirstResponder { (inputAccessoryView as? TerminalInputAccessory)?.deactivate() }
        if isFirstResponder != wasFocused { onFocusChange?() }
        return result
    }
}

/// A single native, self-sizing key row. Keys scroll rather than shrinking below
/// touch size; More and Dismiss remain reachable at every window width.
final class TerminalInputAccessory: UIInputView {
    private weak var terminal: TerminalView?
    private let scroll = UIScrollView()
    private var keys: [UIButton] = []
    private var control: UIButton!
    private var more: UIButton!
    private var dismiss: UIButton!
    private var repeatTimer: Timer?
    private var keyHeight: CGFloat = 44

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: terminal.bounds.width, height: 52), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .secondarySystemBackground
        scroll.showsHorizontalScrollIndicator = true
        scroll.delaysContentTouches = true
        scroll.isAccessibilityElement = false
        addSubview(scroll)
        addKey("Esc", label: "Escape") { $0.send([27]) }
        control = makeButton("Ctrl", label: "Control") { [weak self] in
            guard let self, let terminal = self.terminal else { return }
            terminal.controlModifier.toggle()
            self.syncControl()
        }
        keys.append(control); scroll.addSubview(control)
        addKey("Tab", label: "Tab") { $0.send([9]) }
        for (symbol, label, normal, application) in [
            ("arrow.left", "Left arrow", EscapeSequences.moveLeftNormal, EscapeSequences.moveLeftApp),
            ("arrow.down", "Down arrow", EscapeSequences.moveDownNormal, EscapeSequences.moveDownApp),
            ("arrow.up", "Up arrow", EscapeSequences.moveUpNormal, EscapeSequences.moveUpApp),
            ("arrow.right", "Right arrow", EscapeSequences.moveRightNormal, EscapeSequences.moveRightApp)
        ] {
            let button = addKey(nil, symbol: symbol, label: label) { terminal in
                terminal.send(terminal.getTerminal().applicationCursor ? application : normal)
            }
            button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(repeatArrow(_:))))
        }
        addKey("⌃C", label: "Control C") { $0.send([3]) }
        addKey("⌃D", label: "Control D") { $0.send([4]) }
        more = makeButton(nil, symbol: "ellipsis", label: "More terminal keys", action: nil)
        more.showsMenuAsPrimaryAction = true
        more.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.extraKeys() ?? [])
        }])
        dismiss = makeButton(nil, symbol: "keyboard.chevron.compact.down", label: "Hide keyboard") { [weak self] in
            _ = self?.terminal?.resignFirstResponder()
        }
        addSubview(more); addSubview(dismiss)
        NotificationCenter.default.addObserver(self, selector: #selector(syncControl), name: .terminalViewControlModifierReset, object: terminal)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: TerminalInputAccessory, _: UITraitCollection) in
            self.updateTypography()
        }
        updateTypography()
    }
    required init?(coder: NSCoder) { fatalError("Use init(terminal:)") }
    deinit { repeatTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: keyHeight + 8) }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: targetSize.width, height: intrinsicContentSize.height)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let left = max(8, safeAreaInsets.left), right = max(8, safeAreaInsets.right)
        let fixedWidth = keyHeight + 8
        dismiss.frame = CGRect(x: bounds.width - right - fixedWidth, y: 4, width: fixedWidth, height: keyHeight)
        more.frame = CGRect(x: dismiss.frame.minX - 8 - fixedWidth, y: 4, width: fixedWidth, height: keyHeight)
        let available = max(0, more.frame.minX - 8 - left)
        let minimumWidth = keys.reduce(CGFloat(44)) { width, button in
            max(width, ceil(button.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: keyHeight)).width))
        }
        let rowWidth = min(available, CGFloat(keys.count) * (minimumWidth + 8) - 8)
        let visibleKeys = max(1, min(keys.count, Int((rowWidth + 8) / (minimumWidth + 8))))
        let width = max(minimumWidth, (rowWidth - CGFloat(visibleKeys - 1) * 8) / CGFloat(visibleKeys))
        // Fit complete, equally sized keys before More. Extra keys remain scrollable.
        // Measuring titles also keeps accessibility text inside its touch target.
        scroll.frame = CGRect(x: left, y: 0, width: rowWidth, height: keyHeight + 8)
        var x: CGFloat = 0
        for button in keys {
            button.frame = CGRect(x: x, y: 4, width: width, height: keyHeight)
            x += width + 8
        }
        scroll.contentSize = CGSize(width: max(0, x - 8), height: scroll.bounds.height)
        scroll.contentOffset.x = min(max(0, scroll.contentOffset.x), max(0, scroll.contentSize.width - scroll.bounds.width))
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { deactivate() }
    }
    func deactivate() {
        repeatTimer?.invalidate(); repeatTimer = nil
        terminal?.controlModifier = false
    }
    @objc private func syncControl() {
        control.isSelected = terminal?.controlModifier ?? false
        control.accessibilityValue = control.isSelected ? "On" : "Off"
    }
    private func updateTypography() {
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .medium), compatibleWith: traitCollection)
        keyHeight = max(44, ceil(font.lineHeight + 16))
        for button in keys + [more, dismiss].compactMap({ $0 }) {
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes; attributes.font = font; return attributes
            }
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: font)
        }
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    private func makeButton(_ title: String?, symbol: String? = nil, label: String, action: (() -> Void)?) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = symbol.flatMap(UIImage.init(systemName:))
        configuration.baseForegroundColor = UIColor(named: "AccentColor") ?? .tintColor
        configuration.background.cornerRadius = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = "terminal.key.\(label)"
        if let action { button.addAction(UIAction { _ in action() }, for: .touchUpInside) }
        return button
    }
    @discardableResult private func addKey(_ title: String?, symbol: String? = nil, label: String, action: @escaping (TerminalView) -> Void) -> UIButton {
        let button = makeButton(title, symbol: symbol, label: label) { [weak self] in
            guard let terminal = self?.terminal else { return }
            action(terminal)
        }
        keys.append(button); scroll.addSubview(button)
        return button
    }
    @objc private func repeatArrow(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state != .changed else { return }
        repeatTimer?.invalidate(); repeatTimer = nil
        guard gesture.state == .began, let button = gesture.view as? UIButton else { return }
        button.sendActions(for: .touchUpInside)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak button, weak self] timer in
            guard self?.window != nil else { timer.invalidate(); return }
            button?.sendActions(for: .touchUpInside)
        }
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func extraKeys() -> [UIMenuElement] {
        func action(_ title: String, send: @escaping (TerminalView) -> Void) -> UIAction {
            UIAction(title: title) { [weak self] _ in
                guard let terminal = self?.terminal else { return }
                send(terminal)
            }
        }
        let navigation = UIMenu(title: "Navigation", children: [
            action("Home") { $0.send($0.getTerminal().applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal) },
            action("End") { $0.send($0.getTerminal().applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal) },
            action("Page Up") { ($0 as? SessionTerminalView)?.pageHistory(up: true) },
            action("Page Down") { ($0 as? SessionTerminalView)?.pageHistory(up: false) },
            action("Latest output") { ($0 as? SessionTerminalView)?.jumpToLatest() },
            action("Insert") { $0.send(EscapeSequences.cmdInsert) },
            action("Forward Delete") { $0.send(EscapeSequences.cmdDelKey) },
            action("Back Tab") { $0.send(EscapeSequences.cmdBackTab) }
        ])
        let functions = UIMenu(title: "Function keys", children: EscapeSequences.cmdF.enumerated().map { index, bytes in
            action("F\(index + 1)") { $0.send(bytes) }
        })
        let symbols = UIMenu(title: "Symbols", children: ["~", "|", "/", "-", "[", "]", "{", "}", "<", ">", "&", "+", "*", "=", "%", "`", "\\"].map { text in
            action(text) { $0.insertText(text) }
        })
        let mouse = UIAction(title: "Mouse reporting", image: UIImage(systemName: "cursorarrow"), state: terminal?.allowMouseReporting == true ? .on : .off) { [weak self] _ in
            self?.terminal?.allowMouseReporting.toggle()
        }
        return [navigation, functions, symbols, mouse]
    }
}

#if DEBUG && targetEnvironment(simulator)
private final class ReviewTerminalView: SessionTerminalView {
    private var hasSample = false
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !hasSample, bounds.width > 44, bounds.height > 44 else { return }
        hasSample = true
        getTerminal().setCursorStyle(.steadyBlock)
        feed(text: "\u{001B}[36m~/project\u{001B}[0m % swift build\r\nBuilding for debugging…\r\nBuild complete.\r\n\r\n\u{001B}[36m~/project\u{001B}[0m % ")
    }
}
#endif
