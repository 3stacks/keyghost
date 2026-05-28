import AppKit
import SwiftUI
import ApplicationServices
import IOKit.hid

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    private var config: BindingsConfig { store.config }

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
        if didShowOverlay {
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

        if result.dismiss {
            DispatchQueue.main.async {
                self.holdWorkItem?.cancel()
                self.holdWorkItem = nil
                self.hideOverlay()
                self.didShowOverlay = false
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
