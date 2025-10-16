import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SendableTextView: View {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    var body: some View {
        #if os(macOS)
        SendableNSTextView(text: $text, isEnabled: isEnabled, onSubmit: onSubmit)
        #else
        SendableUITextView(text: $text, isEnabled: isEnabled, onSubmit: onSubmit)
        #endif
    }
}

#if os(macOS)
private struct SendableNSTextView: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.lineFragmentPadding = 4
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        Self.configureAppearance(for: textView, enabled: isEnabled)
        textView.submitHandler = { [weak coordinator = context.coordinator] in
            coordinator?.handleSubmit()
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.activeAttributes(for: textView, enabled: isEnabled)))
            textView.moveToEndOfDocument(nil)
        }
        textView.isEditable = isEnabled
        Self.configureAppearance(for: textView, enabled: isEnabled)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SendableNSTextView
        weak var textView: NSTextView?

        init(parent: SendableNSTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = textView else { return }
            SendableNSTextView.configureAppearance(for: textView, enabled: parent.isEnabled)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            SendableNSTextView.configureAppearance(for: textView, enabled: parent.isEnabled)
        }

        func handleSubmit() {
            guard parent.isEnabled else { return }
            parent.onSubmit()
        }
    }

    final class CustomTextView: NSTextView {
        var submitHandler: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if isReturn(event) {
                submitHandler?()
            } else {
                super.keyDown(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            if window?.firstResponder != self {
                window?.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }

        private func isReturn(_ event: NSEvent) -> Bool {
            guard event.keyCode == 36 else { return false }
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            return modifiers.isEmpty
        }
    }

    private static func configureAppearance(for textView: NSTextView, enabled: Bool) {
        let attributes = activeAttributes(for: textView, enabled: enabled)
        textView.textColor = attributes[.foregroundColor] as? NSColor
        textView.insertionPointColor = textView.textColor ?? .white
        textView.typingAttributes = attributes

        let length = textView.string.utf16.count
        if length > 0 {
            textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: length))
        }
    }

    private static func activeAttributes(for textView: NSTextView, enabled: Bool) -> [NSAttributedString.Key: Any] {
        let color: NSColor = enabled ? .controlTextColor : .secondaryLabelColor
        let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
        return [
            .foregroundColor: color,
            .font: font
        ]
    }
}
#else
private struct SendableUITextView: UIViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.keyboardDismissMode = .interactive
        textView.returnKeyType = .send
        Self.configureAppearance(for: textView, enabled: isEnabled)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.attributedText = NSAttributedString(string: text, attributes: Self.activeAttributes(for: uiView, enabled: isEnabled))
        }
        uiView.isEditable = isEnabled
        Self.configureAppearance(for: uiView, enabled: isEnabled)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SendableUITextView

        init(parent: SendableUITextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            SendableUITextView.configureAppearance(for: textView, enabled: parent.isEnabled)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            SendableUITextView.configureAppearance(for: textView, enabled: parent.isEnabled)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                guard parent.isEnabled else { return false }
                parent.onSubmit()
                return false
            }
            return true
        }
    }

    private static func configureAppearance(for textView: UITextView, enabled: Bool) {
        let attrs = activeAttributes(for: textView, enabled: enabled)
        textView.textColor = attrs[.foregroundColor] as? UIColor
        textView.tintColor = textView.textColor
        textView.typingAttributes = attrs
    }

    private static func activeAttributes(for textView: UITextView, enabled: Bool) -> [NSAttributedString.Key: Any] {
        let color: UIColor = enabled ? .label : .secondaryLabel
        let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        return [
            .foregroundColor: color,
            .font: font
        ]
    }
}
#endif
