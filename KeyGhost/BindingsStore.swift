import Foundation
import Observation

@Observable
final class BindingsStore {
    var config: BindingsConfig

    init() {
        self.config = BindingsLoader.load()
    }

    func reload() {
        config = BindingsLoader.load()
    }

    func upsert(_ binding: KeyBinding) {
        var list = config.bindings.filter { $0.key.uppercased() != binding.key.uppercased() }
        list.append(binding)
        list.sort { $0.key < $1.key }
        replace(bindings: list)
    }

    func remove(key: String) {
        let list = config.bindings.filter { $0.key.uppercased() != key.uppercased() }
        replace(bindings: list)
    }

    func updateTriggerKey(_ key: TriggerKey) {
        config = BindingsConfig(
            holdDelayMs: config.holdDelayMs,
            triggerKey: key,
            triggerModifiers: config.triggerModifiers,
            chordModifiers: config.chordModifiers,
            bindings: config.bindings
        )
        persist()
    }

    func updateHoldDelay(_ ms: Int) {
        config = BindingsConfig(
            holdDelayMs: ms,
            triggerKey: config.triggerKey,
            triggerModifiers: config.triggerModifiers,
            chordModifiers: config.chordModifiers,
            bindings: config.bindings
        )
        persist()
    }

    private func replace(bindings: [KeyBinding]) {
        config = BindingsConfig(
            holdDelayMs: config.holdDelayMs,
            triggerKey: config.triggerKey,
            triggerModifiers: config.triggerModifiers,
            chordModifiers: config.chordModifiers,
            bindings: bindings
        )
        persist()
    }

    private func persist() {
        do {
            try BindingsLoader.save(config)
        } catch {
            NSLog("KeyGhost: failed to save bindings: \(error)")
        }
    }
}
