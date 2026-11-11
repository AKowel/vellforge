import AppKit
import Carbon.HIToolbox

/// A click-to-record shortcut field.
///
/// While recording it must intercept combinations that AppKit would otherwise
/// route to menus (⌘Q and friends), which is why `performKeyEquivalent` is
/// overridden as well as `keyDown`.
@MainActor
final class ShortcutRecorderView: NSView {

    var binding: KeyBinding? {
        didSet { needsDisplay = true }
    }

    /// Return `false` to reject the capture and stay in recording mode.
    var validate: ((KeyBinding) -> Bool)?
    var onChange: ((KeyBinding?) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        _ = capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)

        // Escape abandons the edit; Delete clears the shortcut entirely.
        if keyCode == UInt32(kVK_Escape) {
            isRecording = false
            window?.makeFirstResponder(nil)
            return true
        }
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            binding = nil
            onChange?(nil)
            isRecording = false
            window?.makeFirstResponder(nil)
            return true
        }

        let modifiers = KeyBinding.carbonModifiers(from: event.modifierFlags)
        let candidate = KeyBinding(keyCode: keyCode, modifiers: modifiers)

        // A shortcut with no modifiers would swallow ordinary typing everywhere.
        guard candidate.hasModifiers else { return true }
        guard validate?(candidate) ?? true else { return true }

        binding = candidate
        onChange?(candidate)
        isRecording = false
        window?.makeFirstResponder(nil)
        return true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   xRadius: 5, yRadius: 5)

        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                     : NSColor.controlBackgroundColor).setFill()
        rounded.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        rounded.lineWidth = isRecording ? 2 : 1
        rounded.stroke()

        let text: String
        let colour: NSColor
        if isRecording {
            text = "Press keys…"
            colour = .controlAccentColor
        } else if let binding {
            text = binding.displayString
            colour = .labelColor
        } else {
            text = "Click to set"
            colour = .tertiaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .medium : .regular),
            .foregroundColor: colour,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2),
                  withAttributes: attributes)
    }
}
