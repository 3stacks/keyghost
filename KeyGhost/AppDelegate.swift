import AppKit
import SwiftUI
import ApplicationServices
import IOKit.hid
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayPanel?
    private var chordMonitor: ChordMonitor?
    private var triggerMonitor: TriggerKeyMonitor?
    private var settingsWindow: NSWindow?
    private var configWatcher: DispatchSourceFileSystemObject?

    let store = BindingsStore()

    private var isTriggerHeld = false
    private var didShowOverlay = false
    private var holdWorkItem: DispatchWorkItem?
    private var activeTriggerKey: TriggerKey = .capsLock

    // Nested radial state — non-nil while a chord with `nested` is held.
    // Trigger release commits: the highlighted direction's action, or the
    // root binding if no direction was chosen.
    //
    // The state object outlives individual SwiftUI renders so that arrow
    // updates mutate it in place — letting SwiftUI animate highlight changes
    // smoothly instead of swapping the NSHostingView each tick.
    private var nestedState: NestedRadialState?

    // Currently-held cardinal arrows. Set of {up,right,down,left} only; the
    // resolved direction (incl. diagonals like upRight) is computed from this
    // set on every change. KeyUp removes; keyDown inserts.
    private var heldArrows: Set<NestedDirection> = []

    private var config: BindingsConfig { store.config }

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    // Show update alerts as regular windows; LSUIElement apps have no Dock icon
    // to host the gentle reminder banner.
    var supportsGentleScheduledUpdateReminders: Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        watchConfigFile()
        startMonitors()
        observeStoreChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        chordMonitor?.stop()
        triggerMonitor?.stop()
        configWatcher?.cancel()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard.badge.eye", accessibilityDescription: "KeyGhost")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(showOverlayManually), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Overlay", action: #selector(hideOverlayManually), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Bindings", action: #selector(reload), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Reveal Bindings File", action: #selector(revealConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Grant Accessibility…", action: #selector(promptForAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Grant Input Monitoring…", action: #selector(promptForInputMonitoring), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyGhost", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func startMonitors() {
        // CGEventTap and IOHIDManager both need permission grants on macOS 14+.
        let axTrusted = AXIsProcessTrusted()
        let inputTrusted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

        let chordMask = ModifierMask.parse(config.chordModifiers) ?? ModifierMask.defaultHyper
        let chord = ChordMonitor(
            chordMask: chordMask,
            isHyperHeld: { [weak self] in
                MainActor.assumeIsolated { self?.isTriggerHeld ?? false }
            },
            onChord: { [weak self] letter in
                guard let self else { return .passthrough }
                return self.handleChord(letter: letter)
            },
            onArrow: { [weak self] direction, isDown in
                guard let self else { return .passthrough }
                return self.handleArrow(direction: direction, isDown: isDown)
            }
        )
        chord.start()
        chordMonitor = chord

        let triggerKey = config.triggerKey ?? .capsLock
        activeTriggerKey = triggerKey
        startTriggerMonitor(for: triggerKey)

        if !axTrusted { promptForAccessibility() }
        if !inputTrusted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if !axTrusted || !inputTrusted {
            updateStatusItemForUntrustedState()
        }
    }

    private func startTriggerMonitor(for key: TriggerKey) {
        triggerMonitor?.stop()
        let monitor = TriggerKeyMonitor(
            usage: key.hidUsage,
            onPressed: { [weak self] in self?.handleTriggerPressed() },
            onReleased: { [weak self] in self?.handleTriggerReleased() }
        )
        monitor.start()
        triggerMonitor = monitor
    }

    private func observeStoreChanges() {
        // Re-register on every change — Observation's onChange fires once, then needs re-arming.
        withObservationTracking {
            _ = store.config.triggerKey
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTriggerKeyIfChanged()
                self?.observeStoreChanges()
            }
        }
    }

    private func applyTriggerKeyIfChanged() {
        let newKey = config.triggerKey ?? .capsLock
        guard newKey != activeTriggerKey else { return }
        activeTriggerKey = newKey
        startTriggerMonitor(for: newKey)
    }

    private func updateStatusItemForUntrustedState() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard.badge.eye.fill", accessibilityDescription: "KeyGhost (permissions required)")
            button.contentTintColor = .systemOrange
        }
    }

    private func handleTriggerPressed() {
        guard !isTriggerHeld else { return }
        isTriggerHeld = true
        didShowOverlay = false
        let delay = config.holdDelayMs ?? 250
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isTriggerHeld else { return }
            self.didShowOverlay = true
            self.showOverlay()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: item)
    }

    private func handleTriggerReleased() {
        isTriggerHeld = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        let wasInNested = nestedState != nil
        // Nested chord open → commit the selection (or root fallback) on release.
        if wasInNested {
            exitNestedMode(execute: true)
        }

        // Dismiss whichever overlay variant is up — the main keyboard or the
        // nested radial. The wasInNested check covers radial-only sessions
        // (which don't set didShowOverlay).
        if didShowOverlay || wasInNested {
            hideOverlay()
            didShowOverlay = false
        }
    }

    nonisolated private func handleChord(letter: String) -> ChordOutcome {
        let result = MainActor.assumeIsolated { () -> (binding: KeyBinding?, dismiss: Bool) in
            let binding = self.config.bindings.first(where: { $0.key.uppercased() == letter })
            return (binding, self.didShowOverlay)
        }
        guard let binding = result.binding else { return .passthrough }

        // A binding with nested options doesn't fire immediately — it opens the
        // radial overlay and waits for arrow + trigger-release to commit.
        if let nested = binding.nested, nested.hasAny {
            DispatchQueue.main.async {
                // Cancel any in-flight hold timer / dismiss the main keyboard
                // overlay — the radial replaces both.
                self.holdWorkItem?.cancel()
                self.holdWorkItem = nil
                self.didShowOverlay = false
                self.enterNestedMode(letter: letter, binding: binding, nested: nested)
            }
            return .swallow
        }

        if result.dismiss {
            DispatchQueue.main.async {
                self.holdWorkItem?.cancel()
                self.holdWorkItem = nil
                self.hideOverlay()
                self.didShowOverlay = false
            }
        }

        // Different letter chord came in while a nested radial was open — drop
        // the radial without firing the previous binding and treat this as a
        // fresh chord.
        DispatchQueue.main.async {
            if self.nestedState != nil {
                self.exitNestedMode(execute: false)
            }
        }

        if binding.isPassthrough {
            return .rewriteFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        }

        if let urlString = binding.url {
            let bundleId = binding.bundleId
            DispatchQueue.main.async {
                Launcher.openURL(urlString, inBundleId: bundleId)
            }
            return .swallow
        }

        guard let bundleId = binding.bundleId else { return .passthrough }
        DispatchQueue.main.async {
            Launcher.launch(bundleId: bundleId)
        }
        return .swallow
    }

    nonisolated private func handleArrow(direction: NestedDirection, isDown: Bool) -> ChordOutcome {
        let isInNested = MainActor.assumeIsolated { self.nestedState != nil }
        guard isInNested else { return .passthrough }
        DispatchQueue.main.async {
            if isDown {
                self.processArrowDown(direction)
            } else {
                // keyUp only retracts from the held set; highlight sticks so
                // that releasing the arrow before the trigger still commits
                // the user's choice. Diagonals are settled by simultaneous
                // keyDowns; release order doesn't undo them.
                self.heldArrows.remove(direction)
            }
        }
        return .swallow
    }

    private func enterNestedMode(letter: String, binding: KeyBinding, nested: NestedBindings) {
        // Key repeat fires keyDown every ~30ms while held — without this guard
        // we'd re-present the overlay (alpha 0 → 1 fade) on every tick and it
        // would visibly flash.
        if let existing = nestedState, existing.rootKey == letter {
            return
        }
        let state = NestedRadialState(rootKey: letter, rootBinding: binding, nested: nested, highlighted: nil)
        nestedState = state
        presentRadial(state: state)
    }

    private func processArrowDown(_ direction: NestedDirection) {
        guard let state = nestedState else { return }
        let prevHighlighted = state.highlighted
        heldArrows.insert(direction)
        let resolved = Self.resolveDirection(from: heldArrows)

        // Tap-toggle: pressing the same lone cardinal that's already highlighted
        // clears the selection — gives the user an undo path. Autorepeats are
        // already filtered by ChordMonitor, so this only fires on fresh presses.
        let isToggle = heldArrows == [direction] && prevHighlighted == direction
        var next: NestedDirection? = isToggle ? nil : resolved

        // If the resolved direction has no action defined, drop back to nil
        // so the centre tile keeps pulsing (signalling "release fires root")
        // instead of leaving a confusing dead state with no glow anywhere.
        if let n = next, state.nested.action(for: n) == nil {
            next = nil
        }
        // Mutate the observable model — SwiftUI animates the highlight change
        // in place without re-presenting the panel.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            state.highlighted = next
        }
    }

    /// Combine the set of held cardinal arrows into a single direction. Two
    /// adjacent cardinals (e.g. up + right) resolve to the diagonal between
    /// them; opposing pairs (up + down or left + right) cancel out, falling
    /// back to whichever orthogonal axis is still defined.
    static func resolveDirection(from held: Set<NestedDirection>) -> NestedDirection? {
        let up = held.contains(.up)
        let down = held.contains(.down)
        let left = held.contains(.left)
        let right = held.contains(.right)

        // Opposing arrows on the same axis cancel each other — neither wins.
        let vertical: NestedDirection? = (up == down) ? nil : (up ? .up : .down)
        let horizontal: NestedDirection? = (left == right) ? nil : (right ? .right : .left)

        switch (vertical, horizontal) {
        case (.up, .right): return .upRight
        case (.up, .left): return .upLeft
        case (.down, .right): return .downRight
        case (.down, .left): return .downLeft
        case (.some(let v), nil): return v
        case (nil, .some(let h)): return h
        case (nil, nil): return nil
        // Exhaustiveness for the compiler — vertical only ever produces
        // .up/.down/nil and horizontal only .left/.right/nil.
        default: return nil
        }
    }

    private func exitNestedMode(execute: Bool) {
        let state = nestedState
        nestedState = nil
        heldArrows.removeAll()
        if execute, let state {
            commitNestedSelection(binding: state.rootBinding, direction: state.highlighted)
        }
    }

    private func commitNestedSelection(binding: KeyBinding, direction: NestedDirection?) {
        if let dir = direction,
           let action = binding.nested?.action(for: dir) {
            executeAction(bundleId: action.bundleId, url: action.url)
            return
        }
        // No arrow pressed → fall back to the root binding's action.
        executeAction(bundleId: binding.bundleId, url: binding.url)
    }

    private func executeAction(bundleId: String?, url: String?) {
        if let urlString = url {
            Launcher.openURL(urlString, inBundleId: bundleId)
            return
        }
        if let bid = bundleId {
            Launcher.launch(bundleId: bid)
        }
    }

    private func presentRadial(state: NestedRadialState) {
        if overlay == nil { overlay = OverlayPanel() }
        guard let overlay else { return }
        let host = NSHostingView(rootView: NestedRadialView(state: state))
        host.frame = NSRect(x: 0, y: 0, width: overlay.frame.width, height: overlay.frame.height)
        overlay.present(contentView: host)
    }

    private func watchConfigFile() {
        let url = BindingsLoader.configURL
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.store.reload()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatcher = source
    }

    private func showOverlay() {
        if overlay == nil { overlay = OverlayPanel() }
        guard let overlay else { return }
        let host = NSHostingView(rootView: KeyboardOverlayView(bindings: config.bindings))
        host.frame = NSRect(x: 0, y: 0, width: overlay.frame.width, height: overlay.frame.height)
        overlay.present(contentView: host)
    }

    private func hideOverlay() {
        overlay?.dismiss()
    }

    @objc private func showOverlayManually() { showOverlay() }
    @objc private func hideOverlayManually() { hideOverlay() }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: store)
            let host = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: host)
            win.title = "KeyGhost Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func promptForInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func reload() {
        store.reload()
    }

    @objc private func revealConfig() {
        let url = BindingsLoader.configURL
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    @objc private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
