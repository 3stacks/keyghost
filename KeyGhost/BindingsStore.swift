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

    /// Move the binding at `sourceKey` to `targetKey`. If `targetKey` already
    /// has a binding, the two are swapped so the interaction is reversible.
    func move(from sourceKey: String, to targetKey: String) {
        let upperSource = sourceKey.uppercased()
        let upperTarget = targetKey.uppercased()
        guard upperSource != upperTarget else { return }
        guard let source = config.bindings.first(where: { $0.key.uppercased() == upperSource }) else { return }
        let target = config.bindings.first(where: { $0.key.uppercased() == upperTarget })

        var list = config.bindings.filter {
            let k = $0.key.uppercased()
            return k != upperSource && k != upperTarget
        }
        list.append(KeyBinding(
            key: targetKey,
            bundleId: source.bundleId,
            label: source.label,
            passthrough: source.passthrough,
            url: source.url,
            nested: source.nested
        ))
        if let target {
            list.append(KeyBinding(
                key: sourceKey,
                bundleId: target.bundleId,
                label: target.label,
                passthrough: target.passthrough,
                url: target.url,
                nested: target.nested
            ))
        }
        list.sort { $0.key < $1.key }
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
