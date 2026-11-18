import SwiftUI
import UIKit

/// One native text field keeps its responder and selection when revealing a passcode.
final class ConnectionPasscodeTextField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isSecureTextEntry = true
        textContentType = .password
        placeholder = "Connection passcode"
        accessibilityLabel = "Connection passcode"
        accessibilityIdentifier = "connection-passcode"
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        autocorrectionType = .no; autocapitalizationType = .none
        spellCheckingType = .no; smartQuotesType = .no; smartDashesType = .no
        returnKeyType = .go; enablesReturnKeyAutomatically = true
        clearsOnBeginEditing = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let reveal = UIButton(type: .system)
        reveal.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        reveal.accessibilityIdentifier = "connection-passcode-visibility"
        reveal.addTarget(self, action: #selector(toggleVisibility), for: .touchUpInside)
        rightView = reveal; rightViewMode = .always
        updateRevealButton()

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggleVisibility() { setPasswordVisible(isSecureTextEntry) }

    override func becomeFirstResponder() -> Bool {
        let wasFocused = isFirstResponder
        let savedText = text ?? ""
        let selection = selectionOffsets
        let focused = super.becomeFirstResponder()
        if focused && !wasFocused && isSecureTextEntry && !savedText.isEmpty {
            restoreText(savedText, selection: selection)
        }
        return focused
    }

    func setPasswordVisible(_ visible: Bool) {
        guard isSecureTextEntry == visible else { return }
        let savedText = text ?? ""
        let selection = selectionOffsets
        isSecureTextEntry = !visible
        restoreText(savedText, selection: selection)
        updateRevealButton()
    }
    private var selectionOffsets: (Int, Int)? {
        selectedTextRange.map {
            (offset(from: beginningOfDocument, to: $0.start), offset(from: beginningOfDocument, to: $0.end))
        }
    }
    private func restoreText(_ value: String, selection: (Int, Int)?) {
        // Secure fields otherwise replace their contents on the next key after
        // refocusing or hiding. Insert through UITextInput to clear that state.
        text = ""
        if isFirstResponder { super.insertText(value) } else { text = value }
        if let selection,
           let start = position(from: beginningOfDocument, offset: selection.0),
           let end = position(from: beginningOfDocument, offset: selection.1) {
            selectedTextRange = textRange(from: start, to: end)
        }
    }
    private func updateRevealButton() {
        guard let button = rightView as? UIButton else { return }
        button.setImage(UIImage(systemName: isSecureTextEntry ? "eye" : "eye.slash"), for: .normal)
        button.accessibilityLabel = isSecureTextEntry ? "Show passcode" : "Hide passcode"
    }
}

struct ConnectionPasscodeField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var enabled: Bool
    var submit: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func makeUIView(context: Context) -> ConnectionPasscodeTextField {
        let field = ConnectionPasscodeTextField(frame: .zero)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: ConnectionPasscodeTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.isEnabled = enabled; field.rightView?.isUserInteractionEnabled = enabled
        if scenePhase != .active { field.setPasswordVisible(false) }
        if focused && enabled && !field.isFirstResponder {
            // The field may just have entered the Form after choosing “Use passcode”.
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let coordinator, coordinator.parent.focused,
                      coordinator.parent.enabled, field.window != nil else { return }
                field.becomeFirstResponder()
            }
        } else if (!focused || !enabled) && field.isFirstResponder { field.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ConnectionPasscodeTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: max(44, (uiView.font?.lineHeight ?? 22) + 16))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ConnectionPasscodeField
        init(_ parent: ConnectionPasscodeField) { self.parent = parent }
        @objc func changed(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.focused { parent.focused = true }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focused { parent.focused = false }
            (textField as? ConnectionPasscodeTextField)?.setPasswordVisible(false)
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard parent.enabled, !parent.text.isEmpty else { return false }
            parent.focused = false; textField.resignFirstResponder(); parent.submit()
            return false
        }
    }
}
