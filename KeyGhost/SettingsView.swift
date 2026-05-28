import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: BindingsStore
    @State private var selectedKey: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            KeyboardEditorGrid(store: store, selectedKey: $selectedKey)
            Divider()
            if let key = selectedKey {
                BindingEditorPanel(store: store, key: key)
            } else {
                Text("Click a key above to add or edit its binding.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 760, height: 600)
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

private struct KeyboardEditorGrid: View {
    @Bindable var store: BindingsStore
    @Binding var selectedKey: String?

    private static let rows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 6) {
                    ForEach(Self.rows[rowIdx], id: \.self) { key in
                        let appBinding = store.config.bindings.first { $0.key.uppercased() == key }
                        EditorKeyCell(
                            label: key,
                            appBinding: appBinding,
                            isSelected: selectedKey == key
                        )
                        .onTapGesture { selectedKey = key }
                    }
                }
                .padding(.leading, CGFloat(rowIdx) * 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EditorKeyCell: View {
    let label: String
    let appBinding: KeyBinding?
    let isSelected: Bool
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 2) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(appBinding != nil ? .primary : .secondary)
        }
        .frame(width: 54, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: isSelected ? 2 : 1)
                )
        )
        .contentShape(Rectangle())
        .task(id: appBinding?.bundleId) { loadIcon() }
    }

    private var bgColor: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if appBinding != nil { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.02)
    }

    private var strokeColor: Color {
        if isSelected { return Color.accentColor }
        if appBinding != nil { return Color.primary.opacity(0.18) }
        return Color.primary.opacity(0.08)
    }

    private func loadIcon() {
        guard let bid = appBinding?.bundleId else { icon = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = IconResolver.icon(forBundleId: bid)
            DispatchQueue.main.async { self.icon = img }
        }
    }
}

private struct BindingEditorPanel: View {
    @Bindable var store: BindingsStore
    let key: String

    enum Mode: String, CaseIterable {
        case application = "Application"
        case url = "URL"
    }

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

            Toggle("Passthrough — show icon but don't swallow the chord", isOn: $isPassthrough)
                .padding(.leading, 96)

            HStack {
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                Button("Remove", role: .destructive, action: remove)
                    .disabled(!existsInStore)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .onAppear(perform: load)
        .onChange(of: key) { _, _ in load() }
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

    private var existsInStore: Bool {
        store.config.bindings.contains { $0.key.uppercased() == key.uppercased() }
    }

    private var canSave: Bool {
        switch mode {
        case .application: return !bundleId.trimmingCharacters(in: .whitespaces).isEmpty
        case .url: return !urlString.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func load() {
        if let existing = store.config.bindings.first(where: { $0.key.uppercased() == key.uppercased() }) {
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

    private func save() {
        let trimmedBundle = bundleId.trimmingCharacters(in: .whitespaces)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let new = KeyBinding(
            key: key,
            bundleId: trimmedBundle.isEmpty ? nil : trimmedBundle,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            passthrough: isPassthrough ? true : nil,
            url: (mode == .url && !trimmedURL.isEmpty) ? trimmedURL : nil
        )
        store.upsert(new)
    }

    private func remove() {
        store.remove(key: key)
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
