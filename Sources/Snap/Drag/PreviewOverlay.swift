import AppKit

/// The translucent rectangle shown while dragging a window toward an edge.
///
/// Click-through and present on every Space: without `canJoinAllSpaces` the
/// preview vanishes the moment a drag crosses to another Space, and without
/// `ignoresCycle` it pollutes the window cycling order.
@MainActor
final class PreviewOverlay {

    private let window: NSWindow
    private let preview = PreviewView()
    private var isVisible = false

    init() {
        window = NSWindow(contentRect: .zero,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = preview
        window.alphaValue = 0
    }

    func show(_ rect: CGRect) {
        if isVisible {
            // Animating between targets is what makes this feel considered
            // rather than mechanical — never hide and re-show.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(rect, display: true)
            }
        } else {
            window.setFrame(rect, display: false)
            window.orderFront(nil)
            isVisible = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.window.orderOut(nil)
            }
        })
    }

    /// Snap the preview shut at the moment of drop, rather than fading, so the
    /// real window appears to take its place.
    func dismissImmediately() {
        isVisible = false
        window.alphaValue = 0
        window.orderOut(nil)
    }
}

private final class PreviewView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)

        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }
}
