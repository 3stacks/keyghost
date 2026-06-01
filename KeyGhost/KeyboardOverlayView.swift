import SwiftUI
import AppKit

struct KeyboardOverlayView: View {
    let bindings: [KeyBinding]

    @State private var didAppear = false

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
        content
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
            .background(panelBackground)
            .scaleEffect(didAppear ? 1 : 0.94)
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    didAppear = true
                }
            }
    }

    private var content: some View {
        VStack(spacing: 14) {
            hyperBadge

            VStack(spacing: 8) {
                ForEach(Self.rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 8) {
                        ForEach(Self.rows[rowIdx].indices, id: \.self) { colIdx in
                            let key = Self.rows[rowIdx][colIdx]
                            KeyCellView(
                                label: key,
                                binding: lookup[key],
                                staggerSlot: rowIdx * 10 + colIdx,
                                didAppear: didAppear
                            )
                        }
                    }
                    .padding(.leading, CGFloat(rowIdx) * 22)
                }
            }
        }
    }

    private var hyperBadge: some View {
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
        .opacity(didAppear ? 1 : 0)
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

struct KeyCellView: View {
    let label: String
    let binding: KeyBinding?
    let staggerSlot: Int
    let didAppear: Bool

    @State private var icon: NSImage?
    @State private var revealed = false

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
        .background(cellBackground)
        .scaleEffect(revealed ? 1 : 0.86)
        .opacity(revealed ? 1 : 0)
        .task(id: binding?.bundleId) { loadIcon() }
        .onChange(of: didAppear) { _, appearing in
            guard appearing else { return }
            scheduleReveal()
        }
        .onAppear {
            if didAppear { scheduleReveal() }
        }
    }

    @ViewBuilder
    private var cellBackground: some View {
        // Single glass layer (the panel) is enough — per-cell glass on a 64×64
        // tile with a 34×34 icon stacks too much blur and washes the icon out.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(binding != nil ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
            .overlay(
                shape.strokeBorder(Color.white.opacity(binding != nil ? 0.20 : 0.06), lineWidth: 1)
            )
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

    private func scheduleReveal() {
        // Quick wave from top-left across the grid (~6ms per tile).
        let delay = 0.02 + Double(staggerSlot) * 0.006
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                self.revealed = true
            }
        }
    }
}
