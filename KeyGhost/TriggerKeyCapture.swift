import Foundation
import IOKit.hid

/// One-shot HID listener that fires `onCapture` with the next recognised key
/// press, then tears itself down. Used by the Settings UI to let the user
/// click "Capture" and physically press their desired trigger key.
final class TriggerKeyCapture {
    private var manager: IOHIDManager?
    private var didFire = false
    private let onCapture: (TriggerKey) -> Void

    init(onCapture: @escaping (TriggerKey) -> Void) {
        self.onCapture = onCapture
    }

    func start() {
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
        IOHIDManagerRegisterInputValueCallback(mgr, TriggerKeyCapture.callback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }

    func cancel() {
        teardown()
    }

    private func teardown() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    private static let callback: IOHIDValueCallback = { ctx, _, _, value in
        guard let ctx else { return }
        let capture = Unmanaged<TriggerKeyCapture>.fromOpaque(ctx).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // We only care about presses (value=1) on the keyboard page.
        guard usagePage == UInt32(kHIDPage_KeyboardOrKeypad), intValue == 1 else { return }
        guard !capture.didFire, let tk = TriggerKey.from(hidUsage: Int(usage)) else { return }
        capture.didFire = true
        DispatchQueue.main.async {
            capture.teardown()
            capture.onCapture(tk)
        }
    }
}
