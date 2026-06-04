import AppKit

final class OverlayPanel: NSPanel {
    init() {
        // 960×680 is sized to comfortably hold both layouts the panel hosts:
        // the keyboard overlay (~820 wide) plus its shadow, and the larger
        // nested radial (~620 across including the outermost tile bounds and
        // its glow). Centered on screen by the panel placement code below.
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
        contentView = view
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = frame.width
            let h = frame.height
            setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: true)
        }
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
