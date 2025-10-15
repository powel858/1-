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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        applyActiveAppearance(to: textView)
        let coordinator = context.coordinator
        textView.submitHandler = { [weak coordinator] in
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
            textView.string = text
            textView.moveToEndOfDocument(nil)
        }
        textView.isEditable = isEnabled
        if isEnabled {
            applyActiveAppearance(to: textView)
        } else {
            applyDisabledAppearance(to: textView)
        }
        textView.isSelectable = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SendableNSTextView
        weak var textView: NSTextView?

        init(parent: SendableNSTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            parent.applyActiveAppearance(to: textView)
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

        private func isReturn(_ event: NSEvent) -> Bool {
            guard event.keyCode == 36 else { return false }
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            if modifiers.isEmpty {
                return true
            }
            if modifiers == [.shift] {
                return false
            }
            return false
        }
    }

    private func applyActiveAppearance(to textView: NSTextView) {
        let color = NSColor.labelColor
        let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [
            .foregroundColor: color,
            .font: font
        ]
        let length = textView.string.utf16.count
        if length > 0 {
            textView.textStorage?.addAttributes([
                .foregroundColor: color,
                .font: font
            ], range: NSRange(location: 0, length: length))
        }
    }

    private func applyDisabledAppearance(to textView: NSTextView) {
        let color = NSColor.secondaryLabelColor
        let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [
            .foregroundColor: color,
            .font: font
        ]
        let length = textView.string.utf16.count
        if length > 0 {
            textView.textStorage?.addAttributes([
                .foregroundColor: color,
                .font: font
            ], range: NSRange(location: 0, length: length))
        }
    }
}
#else
private struct SendableUITextView: UIViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.keyboardDismissMode = .interactive
        textView.returnKeyType = .send
        textView.textColor = .label
        textView.tintColor = .label
        textView.typingAttributes = [
            .foregroundColor: UIColor.label,
            .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        ]
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = isEnabled
        let color: UIColor = isEnabled ? .label : .secondaryLabel
        uiView.textColor = color
        uiView.tintColor = color
        uiView.typingAttributes = [
            .foregroundColor: color,
            .font: uiView.font ?? UIFont.preferredFont(forTextStyle: .body)
        ]
        uiView.isSelectable = true
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SendableUITextView

        init(parent: SendableUITextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
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
}
#endif
