import Foundation
import IOKit.hid
import os

private let log = Logger(subsystem: "com.lukeboyle.keyghost", category: "trigger")

/// User-selectable trigger keys. Anything on the keyboard HID page (0x07) that
/// reliably fires press/release events works — that's basically anything except
/// the Globe/Fn key (which lives on a different page on Apple keyboards).
enum TriggerKey: String, CaseIterable, Codable {
    case capsLock
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19, f20
    case rightShift, rightControl, rightOption, rightCommand
    case leftShift, leftControl, leftOption, leftCommand

    var displayName: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .rightShift: return "Right Shift"
        case .rightControl: return "Right Control"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .leftShift: return "Left Shift"
        case .leftControl: return "Left Control"
        case .leftOption: return "Left Option"
        case .leftCommand: return "Left Command"
        }
    }

    /// USB HID Keyboard usage code (page 0x07).
    var hidUsage: Int {
        switch self {
        case .capsLock: return 0x39
        case .f1: return 0x3A
        case .f2: return 0x3B
        case .f3: return 0x3C
        case .f4: return 0x3D
        case .f5: return 0x3E
        case .f6: return 0x3F
        case .f7: return 0x40
        case .f8: return 0x41
        case .f9: return 0x42
        case .f10: return 0x43
        case .f11: return 0x44
        case .f12: return 0x45
        case .f13: return 0x68
        case .f14: return 0x69
        case .f15: return 0x6A
        case .f16: return 0x6B
        case .f17: return 0x6C
        case .f18: return 0x6D
        case .f19: return 0x6E
        case .f20: return 0x6F
        case .leftControl: return 0xE0
        case .leftShift: return 0xE1
        case .leftOption: return 0xE2
        case .leftCommand: return 0xE3
        case .rightControl: return 0xE4
        case .rightShift: return 0xE5
        case .rightOption: return 0xE6
        case .rightCommand: return 0xE7
        }
    }

    static func from(hidUsage: Int) -> TriggerKey? {
        TriggerKey.allCases.first { $0.hidUsage == hidUsage }
    }
}

/// Reads the raw trigger key press directly from the HID layer, beneath any
/// user-space remapping (Hyperkey, Karabiner, macOS Modifier Keys). The
/// CGEventTap sees only what those remappers produce; this sees the physical
/// key. The trigger is configurable via BindingsConfig.triggerKey.
final class TriggerKeyMonitor {
    private var manager: IOHIDManager?
    private let usage: Int
    private let onPressed: () -> Void
    private let onReleased: () -> Void

    init(usage: Int, onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.usage = usage
        self.onPressed = onPressed
        self.onReleased = onReleased
    }

    @discardableResult
    func start() -> Bool {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, criteria as CFArray)
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, TriggerKeyMonitor.callback, opaque)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        let usageHex = String(usage, radix: 16)
        log.notice("HID manager open result=\(result, privacy: .public) usage=0x\(usageHex, privacy: .public)")
        manager = mgr
        return result == kIOReturnSuccess
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    private static let callback: IOHIDValueCallback = { ctx, _, _, value in
        guard let ctx else { return }
        let monitor = Unmanaged<TriggerKeyMonitor>.fromOpaque(ctx).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == UInt32(kHIDPage_KeyboardOrKeypad), Int(usage) == monitor.usage else { return }
        let intValue = IOHIDValueGetIntegerValue(value)
        log.debug("trigger value=\(intValue, privacy: .public)")
        if intValue == 1 {
            DispatchQueue.main.async { monitor.onPressed() }
        } else {
            DispatchQueue.main.async { monitor.onReleased() }
        }
    }
}
