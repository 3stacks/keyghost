import Foundation
import CoreGraphics

struct KeyBinding: Codable, Hashable {
    let key: String
    let bundleId: String?
    let label: String?
    let passthrough: Bool?
    /// If set, KeyGhost opens this URL. Combined with `bundleId`, it opens
    /// the URL in that specific app (e.g. https://mail.google.com in Chrome).
    /// Without `bundleId`, the system default handler is used.
    let url: String?

    /// Optional secondary actions reachable by holding the chord and pressing
    /// an arrow key before releasing the trigger. Releasing without selecting
    /// a direction falls back to the root binding above.
    let nested: NestedBindings?

    /// True if KeyGhost should display the icon but let the chord through to
    /// the OS (so a registered hotkey owner — Maccy, Raycast, Shortcuts — handles it).
    var isPassthrough: Bool { passthrough == true }

    /// True if any nested direction has an action defined.
    var hasNested: Bool { nested?.hasAny == true }
}

/// One slot of the compass while a chord is held. Cardinals come from a
/// single arrow keyDown; diagonals come from two adjacent cardinals held
/// simultaneously (e.g. ↑ + → → upRight).
enum NestedDirection: String, Codable, Hashable, CaseIterable {
    case up, upRight, right, downRight, down, downLeft, left, upLeft

    /// Cardinals correspond 1:1 to a physical arrow key.
    var isCardinal: Bool {
        switch self {
        case .up, .right, .down, .left: return true
        case .upRight, .downRight, .downLeft, .upLeft: return false
        }
    }
}

/// Secondary action invoked by releasing the trigger after pressing an arrow.
/// Mirrors the shape of a KeyBinding minus `passthrough` and `nested` (no
/// recursion for now — keeps the radial menu shallow).
struct NestedAction: Codable, Hashable {
    let bundleId: String?
    let url: String?
    let label: String?
}

struct NestedBindings: Codable, Hashable {
    let up: NestedAction?
    let upRight: NestedAction?
    let right: NestedAction?
    let downRight: NestedAction?
    let down: NestedAction?
    let downLeft: NestedAction?
    let left: NestedAction?
    let upLeft: NestedAction?

    init(
        up: NestedAction? = nil,
        upRight: NestedAction? = nil,
        right: NestedAction? = nil,
        downRight: NestedAction? = nil,
        down: NestedAction? = nil,
        downLeft: NestedAction? = nil,
        left: NestedAction? = nil,
        upLeft: NestedAction? = nil
    ) {
        self.up = up
        self.upRight = upRight
        self.right = right
        self.downRight = downRight
        self.down = down
        self.downLeft = downLeft
        self.left = left
        self.upLeft = upLeft
    }

    func action(for direction: NestedDirection) -> NestedAction? {
        switch direction {
        case .up: return up
        case .upRight: return upRight
        case .right: return right
        case .downRight: return downRight
        case .down: return down
        case .downLeft: return downLeft
        case .left: return left
        case .upLeft: return upLeft
        }
    }

    var hasAny: Bool {
        up != nil || upRight != nil || right != nil || downRight != nil
            || down != nil || downLeft != nil || left != nil || upLeft != nil
    }
}

struct BindingsConfig: Codable {
    let holdDelayMs: Int?
    let triggerKey: TriggerKey?
    let triggerModifiers: [String]?
    let chordModifiers: [String]?
    let bindings: [KeyBinding]

    static let `default` = BindingsConfig(
        holdDelayMs: 250,
        triggerKey: .capsLock,
        triggerModifiers: nil,
        chordModifiers: nil,
        bindings: []
    )
}

enum ModifierMask {
    static let defaultHyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    static func parse(_ names: [String]?) -> CGEventFlags? {
        guard let names else { return nil }
        var mask: CGEventFlags = []
        for n in names {
            switch n.lowercased() {
            case "command", "cmd": mask.insert(.maskCommand)
            case "option", "alt", "opt": mask.insert(.maskAlternate)
            case "control", "ctrl": mask.insert(.maskControl)
            case "shift": mask.insert(.maskShift)
            case "fn": mask.insert(.maskSecondaryFn)
            default: break
            }
        }
        return mask
    }
}

enum BindingsLoader {
    static var configURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("KeyGhost", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bindings.json")
    }

    static func load() -> BindingsConfig {
        let url = configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            seedFromBundle(to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(BindingsConfig.self, from: data)
        else {
            return .default
        }
        return cfg
    }

    static func save(_ config: BindingsConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    private static func seedFromBundle(to dest: URL) {
        guard let src = Bundle.module.url(forResource: "bindings.example", withExtension: "json"),
              let data = try? Data(contentsOf: src)
        else { return }
        try? data.write(to: dest)
    }
}
