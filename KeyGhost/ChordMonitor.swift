import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.kogroup.keyghost", category: "chord")

/// Watches CGEvent keyDown events for hyper chords (e.g. ⌘⌥⌃⇧+letter) and
/// dispatches them to the launcher. The "is hyper held?" trigger lives in
/// CapsLockMonitor — Hyperkey synthesises modifiers in chord mode so we
/// can't reliably detect a held state from CGEvent flags alone.
enum ChordOutcome {
    /// KeyGhost handled it; swallow the original event.
    case swallow
    /// Let the event through but OR these modifier bits into its flags first,
    /// so downstream hotkey handlers (KONav, Maccy, Shortcuts.app) see the
    /// full chord they registered for.
    case rewriteFlags(CGEventFlags)
    /// No matching binding; pass through unchanged.
    case passthrough
}

final class ChordMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Optional flag-based fallback. Used in addition to the HID-state callback
    /// so users with a "real" 4-modifier hyperkey (Karabiner, etc.) still work
    /// even if their Caps Lock is HID-silent.
    private let chordMask: CGEventFlags
    private let isHyperHeld: () -> Bool
    private let onChord: (String) -> ChordOutcome

    init(
        chordMask: CGEventFlags,
        isHyperHeld: @escaping () -> Bool,
        onChord: @escaping (String) -> ChordOutcome
    ) {
        self.chordMask = chordMask
        self.isHyperHeld = isHyperHeld
        self.onChord = onChord
    }

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: ChordMonitor.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        log.notice("chord tap created and enabled")
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handleKeyDown(event: CGEvent, keyCode: Int64, flags: CGEventFlags) -> Unmanaged<CGEvent>? {
        let flagMatch = flags.intersection(chordMask) == chordMask
        let hidHyper = isHyperHeld()
        let isChord = flagMatch || hidHyper
        log.debug("keyDown code=\(keyCode, privacy: .public) flags=0x\(String(flags.rawValue, radix: 16), privacy: .public) flagMatch=\(flagMatch, privacy: .public) hidHyper=\(hidHyper, privacy: .public)")
        guard isChord, let letter = KeyCode.toLetter[keyCode] else {
            return Unmanaged.passUnretained(event)
        }
        switch onChord(letter) {
        case .swallow:
            return nil
        case .rewriteFlags(let addMods):
            event.flags = flags.union(addMods)
            log.debug("rewroteFlags to 0x\(String(event.flags.rawValue, radix: 16), privacy: .public)")
            return Unmanaged.passUnretained(event)
        case .passthrough:
            return Unmanaged.passUnretained(event)
        }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let m = Unmanaged<ChordMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = m.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let kc = event.getIntegerValueField(.keyboardEventKeycode)
            return m.handleKeyDown(event: event, keyCode: kc, flags: event.flags)
        }
        return Unmanaged.passUnretained(event)
    }
}
