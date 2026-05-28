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

    /// True if KeyGhost should display the icon but let the chord through to
    /// the OS (so a registered hotkey owner — Maccy, KONav, Shortcuts — handles it).
    var isPassthrough: Bool { passthrough == true }
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
