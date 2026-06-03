import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.lukeboyle.keyghost", category: "chord")

/// Watches CGEvent keyDown events for hyper chords (e.g. ⌘⌥⌃⇧+letter) and
/// dispatches them to the launcher. The "is hyper held?" trigger lives in
/// CapsLockMonitor — Hyperkey synthesises modifiers in chord mode so we
/// can't reliably detect a held state from CGEvent flags alone.
enum ChordOutcome {
    /// KeyGhost handled it; swallow the original event.
    case swallow
    /// Let the event through but OR these modifier bits into its flags first,
    /// so downstream hotkey handlers (Maccy, Raycast, Shortcuts.app) see the
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
    /// Fires for every cardinal arrow keyDown/keyUp while a chord is held.
    /// `isDown == false` lets AppDelegate retract a held cardinal from the
    /// combined direction so diagonals dissolve back as the user releases
    /// one of the two arrows.
    private let onArrow: (NestedDirection, Bool) -> ChordOutcome

    init(
        chordMask: CGEventFlags,
        isHyperHeld: @escaping () -> Bool,
        onChord: @escaping (String) -> ChordOutcome,
        onArrow: @escaping (NestedDirection, Bool) -> ChordOutcome
    ) {
        self.chordMask = chordMask
        self.isHyperHeld = isHyperHeld
        self.onChord = onChord
        self.onArrow = onArrow
    }

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
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
        guard isChord else {
            return Unmanaged.passUnretained(event)
        }

        // Filter CGEvent autorepeats — we only act on the initial press of a
        // chord. Holding F shouldn't launch Chrome repeatedly; holding ↑
        // shouldn't toggle the radial direction every ~30ms.
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isAutorepeat {
            if KeyCode.toLetter[keyCode] != nil || KeyCode.toArrow[keyCode] != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let outcome: ChordOutcome
        if let letter = KeyCode.toLetter[keyCode] {
            outcome = onChord(letter)
        } else if let direction = KeyCode.toArrow[keyCode] {
            outcome = onArrow(direction, true)
        } else {
            return Unmanaged.passUnretained(event)
        }
        switch outcome {
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

    fileprivate func handleKeyUp(event: CGEvent, keyCode: Int64) -> Unmanaged<CGEvent>? {
        // Only arrow keyUps interest us — for retracting a held cardinal so
        // diagonals collapse back to the remaining arrow. Letter keyUps and
        // anything else pass through untouched; AppDelegate decides on
        // outcome based on whether nested mode is active.
        guard let direction = KeyCode.toArrow[keyCode] else {
            return Unmanaged.passUnretained(event)
        }
        let outcome = onArrow(direction, false)
        switch outcome {
        case .swallow:
            return nil
        case .rewriteFlags, .passthrough:
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

        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown {
            return m.handleKeyDown(event: event, keyCode: kc, flags: event.flags)
        }
        if type == .keyUp {
            return m.handleKeyUp(event: event, keyCode: kc)
        }
        return Unmanaged.passUnretained(event)
    }
}
