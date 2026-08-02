import AppKit

final class OverlayPanel: NSPanel {
    init() {
        // Placeholder rect — present() resizes the panel to the full usable
        // screen. The window must cover the whole screen because content is
        // clipped at the window bounds: a rosette anchored to a bottom-row
        // key reaches ~183pt below the keyboard panel and was losing its ↓
        // tile to the old fixed 960×680 frame.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    func present(contentView view: NSView) {
        // Size the window BEFORE installing the content view, then size the
        // view to match explicitly — autoresizing alone left a stale
        // pre-resize frame pinned to one corner, which both mis-centred the
        // content and clipped anything past the old bounds.
        if let screen = NSScreen.main {
            setFrame(screen.visibleFrame, display: false)
        }
        view.frame = NSRect(origin: .zero, size: contentRect(forFrameRect: frame).size)
        view.autoresizingMask = [.width, .height]
        contentView = view
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
