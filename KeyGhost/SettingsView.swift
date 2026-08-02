import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: BindingsStore
    /// Closes the hosting settings window. Cancel discards and closes.
    var onClose: () -> Void = {}
    @State private var selectedKey: String? = nil
    @State private var pending: [SlotRef: PendingChange] = [:]
    /// Bumped after a global Save or Cancel so the editor panel reloads its
    /// form from the store even though the selected key did not change.
    @State private var revision = 0

    var body: some View {
        VStack(spacing: 0) {
            // Main content scrolls when the window is short; the footer below
            // stays pinned so Save/Cancel are always reachable.
            ScrollView {
                VStack(spacing: 16) {
                    header
                    Divider()
                    KeyboardEditorGrid(store: store, selectedKey: $selectedKey, pending: pending)
                    Divider()
                    if let key = selectedKey {
                        BindingEditorPanel(store: store, key: key, pending: $pending, revision: revision)
                    } else {
                        Text("Click a key above to add or edit its binding.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var footer: some View {
        HStack {
            if !pending.isEmpty {
                Text(pending.count == 1 ? "1 unsaved change" : "\(pending.count) unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                discardPending()
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            Button("Save", action: commitPending)
                .keyboardShortcut(.defaultAction)
                .disabled(pending.isEmpty)
        }
    }

    /// Commit every pending change, across all keys and slots, in one pass.
    private func commitPending() {
        let grouped = Dictionary(grouping: pending, by: { $0.key.key })
        for (keyName, entries) in grouped {
            let existing = store.config.bindings.first(where: { $0.key.uppercased() == keyName })
            var newBundleId = existing?.bundleId
            var newLabel = existing?.label
            var newPassthrough = existing?.passthrough
            var newURL = existing?.url
            var newNested = existing?.nested

            for (ref, change) in entries {
                if let direction = ref.slot.direction {
                    switch change {
                    case .edit(let draft):
                        let action = NestedAction(
                            bundleId: draft.bundleId.isEmpty ? nil : draft.bundleId,
                            url: (draft.isURL && !draft.url.isEmpty) ? draft.url : nil,
                            label: draft.label.isEmpty ? nil : draft.label
                        )
                        newNested = nestedBindings(updating: newNested, direction: direction, action: action)
                    case .remove:
                        newNested = nestedBindings(updating: newNested, direction: direction, action: nil)
                    }
                } else {
                    switch change {
                    case .edit(let draft):
                        newBundleId = draft.bundleId.isEmpty ? nil : draft.bundleId
                        newLabel = draft.label.isEmpty ? nil : draft.label
                        newPassthrough = draft.isPassthrough ? true : nil
                        newURL = (draft.isURL && !draft.url.isEmpty) ? draft.url : nil
                    case .remove:
                        newBundleId = nil
                        newLabel = nil
                        newPassthrough = nil
                        newURL = nil
                    }
                }
            }

            if newBundleId == nil && newURL == nil && newNested == nil {
                store.remove(key: keyName)
            } else {
                store.upsert(KeyBinding(
                    key: existing?.key ?? keyName,
                    bundleId: newBundleId,
                    label: newLabel,
                    passthrough: newPassthrough,
                    url: newURL,
                    nested: newNested
                ))
            }
        }
        pending.removeAll()
        revision += 1
    }

    private func discardPending() {
        pending.removeAll()
        revision += 1
    }

    private var header: some View {
        HStack(spacing: 24) {
            HStack(spacing: 8) {
                Text("Trigger key:").foregroundStyle(.secondary)
                TriggerCaptureButton(
                    current: store.config.triggerKey ?? .capsLock,
                    onCapture: { store.updateTriggerKey($0) }
                )
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Hold delay:").foregroundStyle(.secondary)
                Slider(value: holdDelayBinding, in: 0...1000, step: 50)
                    .frame(width: 160)
                Text("\(Int(store.config.holdDelayMs ?? 250)) ms")
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 60, alignment: .leading)
            }
        }
    }

    private var holdDelayBinding: SwiftUI.Binding<Double> {
        SwiftUI.Binding(
            get: { Double(store.config.holdDelayMs ?? 250) },
            set: { store.updateHoldDelay(Int($0)) }
        )
    }
}

private struct TriggerCaptureButton: View {
    let current: TriggerKey
    let onCapture: (TriggerKey) -> Void
    @State private var isCapturing = false
    @State private var capture: TriggerKeyCapture?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: isCapturing ? "dot.circle.fill" : "keyboard")
                Text(isCapturing ? "Press a key…" : current.displayName)
                    .monospacedDigit()
            }
            .frame(width: 170)
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .tint(isCapturing ? .accentColor : Color.primary)
        .onDisappear { cancel() }
    }

    private func toggle() {
        if isCapturing { cancel() } else { start() }
    }

    private func start() {
        isCapturing = true
        let c = TriggerKeyCapture { [weak capture] tk in
            _ = capture // silence weak-capture warning
            onCapture(tk)
            DispatchQueue.main.async {
                self.isCapturing = false
                self.capture = nil
            }
        }
        c.start()
        capture = c
    }

    private func cancel() {
        capture?.cancel()
        capture = nil
        isCapturing = false
    }
}

/// Identifies one editable slot: a key's root binding or one nested direction.
private struct SlotRef: Hashable {
    let key: String  // always uppercased
    let slot: BindingEditorPanel.Slot
}

/// An unsaved edit for one slot. Drafts are staged in SettingsView so they
/// survive switching between keys, and the grid shows them as pending changes.
private struct BindingDraft: Equatable {
    var isURL: Bool
    var bundleId: String
    var url: String
    var label: String
    var isPassthrough: Bool

    var isValid: Bool { isURL ? !url.isEmpty : !bundleId.isEmpty }
}

/// A staged change for one slot. Nothing touches the store until the global
/// Save commits, so Cancel can discard removals as well as edits.
private enum PendingChange: Equatable {
    case edit(BindingDraft)
    case remove
}

private struct KeyboardEditorGrid: View {
    @Bindable var store: BindingsStore
    @Binding var selectedKey: String?
    let pending: [SlotRef: PendingChange]
    @State private var dropTargetedKey: String? = nil

    private static let rows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"]
    ]

    private static let validKeys: Set<String> = Set(rows.flatMap { $0 })

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 6) {
                    ForEach(Self.rows[rowIdx], id: \.self) { key in
                        cell(for: key)
                    }
                }
                .padding(.leading, CGFloat(rowIdx) * 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cell(for key: String) -> some View {
        let appBinding = store.config.bindings.first { $0.key.uppercased() == key }
        let base = EditorKeyCell(
            label: key,
            appBinding: appBinding,
            pendingBundleId: pendingRootBundleId(for: key),
            hasPending: pending.keys.contains { $0.key == key },
            isSelected: selectedKey == key,
            isDropTargeted: dropTargetedKey == key
        )
        .onTapGesture { selectedKey = key }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, targetKey: key)
        } isTargeted: { hovering in
            if hovering {
                dropTargetedKey = key
            } else if dropTargetedKey == key {
                dropTargetedKey = nil
            }
        }

        if appBinding != nil {
            base.draggable(key)
        } else {
            base
        }
    }

    /// Bundle id from a staged root edit, if it names an app. A staged
    /// removal contributes nothing — the cell falls back to the saved icon,
    /// dimmed like every other pending change.
    private func pendingRootBundleId(for key: String) -> String? {
        guard case .edit(let draft) = pending[SlotRef(key: key, slot: .root)],
              !draft.bundleId.isEmpty else { return nil }
        return draft.bundleId
    }

    private func handleDrop(items: [String], targetKey: String) -> Bool {
        guard let raw = items.first else { return false }
        let source = raw.uppercased()
        guard Self.validKeys.contains(source), source != targetKey.uppercased() else { return false }
        store.move(from: source, to: targetKey)
        selectedKey = targetKey
        return true
    }
}

private struct EditorKeyCell: View {
    let label: String
    let appBinding: KeyBinding?
    /// Bundle id from an unsaved root draft, if it names an app.
    let pendingBundleId: String?
    /// True if any slot on this key has an unsaved draft.
    let hasPending: Bool
    let isSelected: Bool
    let isDropTargeted: Bool
    @State private var icon: NSImage?

    /// The pending draft's icon wins so the cell previews the upcoming change.
    private var displayBundleId: String? { pendingBundleId ?? appBinding?.bundleId }

    var body: some View {
        VStack(spacing: 2) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .opacity(hasPending ? 0.4 : 1)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle((appBinding != nil || hasPending) ? .primary : .secondary)
        }
        .frame(width: 54, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: (isSelected || isDropTargeted) ? 2 : 1)
                )
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .task(id: displayBundleId) { loadIcon() }
    }

    private var bgColor: Color {
        if isDropTargeted { return Color.accentColor.opacity(0.4) }
        if isSelected { return Color.accentColor.opacity(0.25) }
        if appBinding != nil || hasPending { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.02)
    }

    private var strokeColor: Color {
        if isDropTargeted || isSelected { return Color.accentColor }
        if hasPending { return Color.accentColor.opacity(0.5) }
        if appBinding != nil { return Color.primary.opacity(0.18) }
        return Color.primary.opacity(0.08)
    }

    private func loadIcon() {
        guard let bid = displayBundleId else { icon = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = IconResolver.icon(forBundleId: bid)
            DispatchQueue.main.async { self.icon = img }
        }
    }
}

/// Rebuild a NestedBindings with one direction's action replaced. Returns nil
/// when the result holds no actions at all.
private func nestedBindings(updating current: NestedBindings?, direction: NestedDirection, action: NestedAction?) -> NestedBindings? {
    func slot(_ d: NestedDirection) -> NestedAction? {
        direction == d ? action : current?.action(for: d)
    }
    let result = NestedBindings(
        up: slot(.up),
        upRight: slot(.upRight),
        right: slot(.right),
        downRight: slot(.downRight),
        down: slot(.down),
        downLeft: slot(.downLeft),
        left: slot(.left),
        upLeft: slot(.upLeft)
    )
    return result.hasAny ? result : nil
}

/// Effective content of one radial slot: saved binding merged with any
/// pending draft, so the preview shows the upcoming state.
private struct RadialSlotPreview: Identifiable {
    let slot: BindingEditorPanel.Slot
    let bundleId: String?
    let label: String?
    let hasAction: Bool
    let isPending: Bool
    var id: BindingEditorPanel.Slot { slot }
}

/// Compact compass rosette mirroring NestedRadialView's layout: root binding
/// in the centre, the 8 directional binds around it. Clicking a tile selects
/// that slot in the editor. Pending drafts render dimmed, matching the grid.
private struct RadialPreviewView: View {
    let keyLabel: String
    let previews: [RadialSlotPreview]
    let selected: BindingEditorPanel.Slot
    let onSelect: (BindingEditorPanel.Slot) -> Void

    private static let radius: CGFloat = 58

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(previews) { preview in
                    RadialPreviewTile(
                        preview: preview,
                        keyLabel: keyLabel,
                        isSelected: selected == preview.slot
                    )
                    .offset(Self.offset(for: preview.slot))
                    .onTapGesture { onSelect(preview.slot) }
                }
            }
            .frame(width: 164, height: 164)
            Text("Click a slot to edit it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private static func offset(for slot: BindingEditorPanel.Slot) -> CGSize {
        let r = radius
        // sin(45°) ≈ 0.7071 — same even compass rose as the live overlay.
        let d = r * 0.7071
        switch slot {
        case .root: return .zero
        case .up: return CGSize(width: 0, height: -r)
        case .upRight: return CGSize(width: d, height: -d)
        case .right: return CGSize(width: r, height: 0)
        case .downRight: return CGSize(width: d, height: d)
        case .down: return CGSize(width: 0, height: r)
        case .downLeft: return CGSize(width: -d, height: d)
        case .left: return CGSize(width: -r, height: 0)
        case .upLeft: return CGSize(width: -d, height: -d)
        }
    }
}

private struct RadialPreviewTile: View {
    let preview: RadialSlotPreview
    let keyLabel: String
    let isSelected: Bool
    @State private var icon: NSImage?

    private var size: CGFloat { preview.slot == .root ? 44 : 38 }
    private var hint: String { preview.slot == .root ? keyLabel : preview.slot.displayLabel }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgColor)
            if preview.hasAction {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isSelected ? 2 : 1)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [3, 2])
                    )
            }
            content
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .help(helpText)
        .task(id: preview.bundleId) { loadIcon() }
    }

    @ViewBuilder
    private var content: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size - 16, height: size - 16)
                .opacity(preview.isPending ? 0.4 : 1)
        } else {
            Text(hint)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(preview.hasAction ? .primary : .tertiary)
                .opacity(preview.isPending ? 0.4 : 1)
        }
    }

    private var helpText: String {
        let name = preview.slot == .root ? "Root" : preview.slot.displayLabel
        guard preview.hasAction else { return "\(name) — empty" }
        let what = preview.label ?? preview.bundleId ?? "action"
        return preview.isPending ? "\(name) — \(what) (unsaved)" : "\(name) — \(what)"
    }

    private var bgColor: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if preview.hasAction { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.02)
    }

    private var strokeColor: Color {
        if isSelected { return Color.accentColor }
        if preview.isPending { return Color.accentColor.opacity(0.5) }
        if preview.hasAction { return Color.primary.opacity(0.18) }
        return Color.primary.opacity(0.12)
    }

    private func loadIcon() {
        guard let bid = preview.bundleId else { icon = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = IconResolver.icon(forBundleId: bid)
            DispatchQueue.main.async { self.icon = img }
        }
    }
}

private struct BindingEditorPanel: View {
    @Bindable var store: BindingsStore
    let key: String
    @Binding var pending: [SlotRef: PendingChange]
    /// See SettingsView.revision — forces a reload after global Save/Cancel.
    let revision: Int

    enum Mode: String, CaseIterable {
        case application = "Application"
        case url = "URL"
    }

    enum Slot: Hashable, CaseIterable {
        case root
        case up, upRight, right, downRight, down, downLeft, left, upLeft

        var displayLabel: String {
            switch self {
            case .root: return "Root"
            case .up: return "↑"
            case .upRight: return "↗"
            case .right: return "→"
            case .downRight: return "↘"
            case .down: return "↓"
            case .downLeft: return "↙"
            case .left: return "←"
            case .upLeft: return "↖"
            }
        }

        var direction: NestedDirection? {
            switch self {
            case .root: return nil
            case .up: return .up
            case .upRight: return .upRight
            case .right: return .right
            case .downRight: return .downRight
            case .down: return .down
            case .downLeft: return .downLeft
            case .left: return .left
            case .upLeft: return .upLeft
            }
        }
    }

    @State private var slot: Slot = .root
    @State private var mode: Mode = .application
    @State private var bundleId: String = ""
    @State private var urlString: String = ""
    @State private var label: String = ""
    @State private var isPassthrough: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Key: \(key)")
                    .font(.title3.bold())
                Spacer()
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    row("Editing") {
                        Picker("Slot", selection: $slot) {
                            ForEach(Slot.allCases, id: \.self) { s in
                                Text(slotLabel(s)).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    row("Application") {
                        TextField("com.apple.Terminal", text: $bundleId)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseApp() }
                    }

                    if mode == .url {
                        row("URL") {
                            TextField("https://example.com", text: $urlString)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    row("Label") {
                        TextField("Display name", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }

                    if slot == .root {
                        Toggle("Passthrough — show icon but don't swallow the chord", isOn: $isPassthrough)
                            .padding(.leading, 96)
                    } else {
                        Text(slotHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 96)
                    }

                    HStack {
                        Button(removeButtonTitle, role: .destructive, action: remove)
                            .disabled(!canRemove)
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                RadialPreviewView(
                    keyLabel: key,
                    previews: Slot.allCases.map(slotPreview),
                    selected: slot,
                    onSelect: { slot = $0 }
                )
            }
        }
        .padding(.horizontal, 4)
        .onAppear(perform: load)
        .onChange(of: key) { _, _ in
            slot = .root
            load()
        }
        .onChange(of: slot) { _, _ in load() }
        .onChange(of: revision) { _, _ in load() }
        .onChange(of: mode) { _, _ in stage() }
        .onChange(of: bundleId) { _, _ in stage() }
        .onChange(of: urlString) { _, _ in stage() }
        .onChange(of: label) { _, _ in stage() }
        .onChange(of: isPassthrough) { _, _ in stage() }
    }

    @ViewBuilder
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title + ":")
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slotLabel(_ s: Slot) -> String {
        let base = s.displayLabel
        if pending[SlotRef(key: key.uppercased(), slot: s)] != nil {
            return "\(base) ◦"
        }
        guard let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() }) else {
            return base
        }
        if let direction = s.direction {
            return existing.nested?.action(for: direction) != nil ? "\(base) •" : base
        }
        let rootSet = existing.bundleId != nil || existing.url != nil
        return rootSet ? "\(base) •" : base
    }

    private var existsInStore: Bool {
        let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() })
        if let direction = slot.direction {
            return existing?.nested?.action(for: direction) != nil
        }
        return existing?.bundleId != nil || existing?.url != nil
    }

    private var removeButtonTitle: String {
        slot == .root ? "Remove" : "Clear direction"
    }

    /// Remove is available when the slot has something saved to remove, or a
    /// staged edit to discard. A slot already staged for removal has nothing
    /// left to do.
    private var canRemove: Bool {
        switch pending[slotRef] {
        case .remove: return false
        case .edit: return true
        case nil: return existsInStore
        }
    }

    private var slotHint: String {
        switch slot {
        case .root: return ""
        case .up, .right, .down, .left:
            return "Held-chord direction. Press this arrow while holding the chord, then release the trigger to fire."
        case .upRight, .downRight, .downLeft, .upLeft:
            return "Diagonal. Hold the chord, press both adjacent arrows (e.g. ↑ + →), then release the trigger to fire."
        }
    }

    /// The effective content of a slot for the radial preview: a pending
    /// change wins over the saved binding so the preview shows what Save
    /// will produce. A staged removal previews as an empty pending slot.
    private func slotPreview(_ s: Slot) -> RadialSlotPreview {
        switch pending[SlotRef(key: key.uppercased(), slot: s)] {
        case .edit(let draft):
            return RadialSlotPreview(
                slot: s,
                bundleId: draft.bundleId.isEmpty ? nil : draft.bundleId,
                label: draft.label.isEmpty ? nil : draft.label,
                hasAction: true,
                isPending: true
            )
        case .remove:
            return RadialSlotPreview(slot: s, bundleId: nil, label: nil, hasAction: false, isPending: true)
        case nil:
            break
        }
        let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() })
        if let direction = s.direction {
            guard let action = existing?.nested?.action(for: direction) else {
                return RadialSlotPreview(slot: s, bundleId: nil, label: nil, hasAction: false, isPending: false)
            }
            return RadialSlotPreview(
                slot: s, bundleId: action.bundleId, label: action.label,
                hasAction: true, isPending: false
            )
        }
        let rootSet = existing?.bundleId != nil || existing?.url != nil
        return RadialSlotPreview(
            slot: s, bundleId: existing?.bundleId, label: existing?.label,
            hasAction: rootSet, isPending: false
        )
    }

    private var slotRef: SlotRef {
        SlotRef(key: key.uppercased(), slot: slot)
    }

    private func currentDraft() -> BindingDraft {
        BindingDraft(
            isURL: mode == .url,
            bundleId: bundleId.trimmingCharacters(in: .whitespaces),
            url: urlString.trimmingCharacters(in: .whitespaces),
            label: label.trimmingCharacters(in: .whitespaces),
            isPassthrough: slot == .root && isPassthrough
        )
    }

    /// What the form would show for the current slot with no unsaved edits.
    private func savedDraft() -> BindingDraft {
        let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() })
        if let direction = slot.direction {
            let action = existing?.nested?.action(for: direction)
            return BindingDraft(
                isURL: action?.url != nil,
                bundleId: action?.bundleId ?? "",
                url: action?.url ?? "",
                label: action?.label ?? "",
                isPassthrough: false
            )
        }
        return BindingDraft(
            isURL: existing?.url != nil,
            bundleId: existing?.bundleId ?? "",
            url: existing?.url ?? "",
            label: existing?.label ?? "",
            isPassthrough: existing?.isPassthrough ?? false
        )
    }

    /// Stage the form as a pending edit for the current slot. A draft equal to
    /// the saved binding unstages anything (including a staged removal — the
    /// user typed the saved values back). An invalid draft only unstages an
    /// edit; a staged removal survives its own emptied form. Runs on every
    /// field change, so switching keys never loses an edit.
    private func stage() {
        let draft = currentDraft()
        if draft == savedDraft() {
            pending.removeValue(forKey: slotRef)
        } else if draft.isValid {
            pending[slotRef] = .edit(draft)
        } else if case .edit = pending[slotRef] {
            pending.removeValue(forKey: slotRef)
        }
    }

    private func load() {
        switch pending[slotRef] {
        case .edit(let draft):
            mode = draft.isURL ? .url : .application
            bundleId = draft.bundleId
            urlString = draft.url
            label = draft.label
            isPassthrough = draft.isPassthrough
            return
        case .remove:
            mode = .application
            bundleId = ""
            urlString = ""
            label = ""
            isPassthrough = false
            return
        case nil:
            break
        }
        let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() })
        if let direction = slot.direction {
            let action = existing?.nested?.action(for: direction)
            bundleId = action?.bundleId ?? ""
            urlString = action?.url ?? ""
            label = action?.label ?? ""
            isPassthrough = false
            mode = (action?.url != nil) ? .url : .application
        } else if let existing {
            bundleId = existing.bundleId ?? ""
            urlString = existing.url ?? ""
            label = existing.label ?? ""
            isPassthrough = existing.isPassthrough
            mode = (existing.url != nil) ? .url : .application
        } else {
            bundleId = ""
            urlString = ""
            label = ""
            isPassthrough = false
            mode = .application
        }
    }

    /// Stage a removal of the current slot — the store is untouched until the
    /// global Save. On a slot with nothing saved, this just discards the
    /// staged draft. Root removals clear only the root action; directional
    /// binds keep their own slots.
    private func remove() {
        if existsInStore {
            pending[slotRef] = .remove
        } else {
            pending.removeValue(forKey: slotRef)
        }
        load()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                bundleId = id
                if label.isEmpty {
                    label = bundle.infoDictionary?["CFBundleName"] as? String
                        ?? url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }
}
