import SwiftUI
import AppKit

struct KeyboardOverlayView: View {
    let bindings: [KeyBinding]

    private static let rows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"]
    ]

    private var lookup: [String: KeyBinding] {
        Dictionary(bindings.map { ($0.key.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                Image(systemName: "option")
                Image(systemName: "control")
                Image(systemName: "shift")
                Text("hyper")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Self.rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 8) {
                        ForEach(Self.rows[rowIdx], id: \.self) { key in
                            KeyCellView(label: key, binding: lookup[key])
                        }
                    }
                    .padding(.leading, CGFloat(rowIdx) * 22)
                }
            }
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct KeyCellView: View {
    let label: String
    let binding: KeyBinding?

    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 3) {
            iconView
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(binding != nil ? .primary : .secondary)
            Text(binding?.label ?? " ")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 64, height: 86)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(binding != nil ? Color.white.opacity(0.18) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(binding != nil ? 0.20 : 0.06), lineWidth: 1)
                )
        )
        .task(id: binding?.bundleId) { loadIcon() }
    }

    @ViewBuilder private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
        } else {
            Color.clear.frame(width: 34, height: 34)
        }
    }

    private func loadIcon() {
        guard let bid = binding?.bundleId else {
            icon = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = IconResolver.icon(forBundleId: bid)
            DispatchQueue.main.async {
                self.icon = img
            }
        }
    }
}
