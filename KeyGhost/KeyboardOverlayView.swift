import SwiftUI
import AppKit
import Observation

/// Shared state for the chord-fired pulse. The overlay is a cheatsheet for
/// users still building muscle memory — once the chord fires, a brief green
/// pulse on the pressed tile confirms KeyGhost saw the press and acted on
/// it. Power users who already know their bindings will release the trigger
/// fast enough that the overlay never appeared in the first place, so the
/// pulse is invisible to them; it only shows up while you're learning.
@Observable
final class OverlayPulseState {
    /// Key letter (uppercase) that just fired. Setting this triggers an
    /// animation in the matching KeyCellView; AppDelegate clears it back to
    /// nil after the pulse + overlay dismiss completes.
    var firedKey: String? = nil
    /// Nested radial session anchored to a key on this overlay. While set,
    /// the keyboard dims and the rosette blooms out of the pressed key's
    /// cell instead of replacing the whole overlay.
    var nestedState: NestedRadialState? = nil
}

/// Collects each key cell's bounds so the nested rosette can be positioned
/// exactly over the pressed key.
private struct KeyFramesKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct KeyboardOverlayView: View {
    let bindings: [KeyBinding]
    let pulseState: OverlayPulseState

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
        let radialUp = pulseState.nestedState != nil
        content
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
            .background(panelBackground)
            .scaleEffect(didAppear ? 1 : 0.94)
            .opacity(didAppear ? 1 : 0)
            // The rosette layer sits above the keyboard and is positioned over
            // the pressed key. It draws past the panel's bounds when the key
            // is near an edge — overlays don't clip, and the hosting view is
            // the full screen.
            .overlayPreferenceValue(KeyFramesKey.self) { frames in
                GeometryReader { proxy in
                    if let state = pulseState.nestedState,
                       let anchor = frames[state.rootKey.uppercased()] {
                        let rect = proxy[anchor]
                        NestedRadialClusterView(state: state)
                            // Fresh identity per session so the bloom replays
                            // when the user switches to another nested key.
                            .id(ObjectIdentifier(state))
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: radialUp)
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
                                didAppear: didAppear,
                                pulseState: pulseState
                            )
                            .anchorPreference(key: KeyFramesKey.self, value: .bounds) { [key: $0] }
                        }
                    }
                    .padding(.leading, CGFloat(rowIdx) * 22)
                }
            }
        }
        // Dim the cheatsheet while the rosette is up so the directional binds
        // read clearly over the neighbouring keys.
        .opacity(pulseState.nestedState != nil ? 0.35 : 1)
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
    let pulseState: OverlayPulseState

    @State private var icon: NSImage?
    @State private var revealed = false
    @State private var pulsing = false

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
        .scaleEffect((revealed ? 1 : 0.86) * (pulsing ? 1.07 : 1))
        .opacity(revealed ? 1 : 0)
        .task(id: binding?.bundleId) { loadIcon() }
        .onChange(of: didAppear) { _, appearing in
            guard appearing else { return }
            scheduleReveal()
        }
        .onChange(of: pulseState.firedKey) { _, fired in
            guard fired == label else { return }
            triggerPulse()
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
            .fill(pulsing
                  ? Color.green.opacity(0.32)
                  : (binding != nil ? Color.white.opacity(0.16) : Color.white.opacity(0.04)))
            .overlay(
                shape.strokeBorder(
                    pulsing ? Color.green.opacity(0.95)
                            : Color.white.opacity(binding != nil ? 0.20 : 0.06),
                    lineWidth: pulsing ? 2 : 1)
            )
            .shadow(color: pulsing ? Color.green.opacity(0.55) : .clear, radius: pulsing ? 8 : 0)
    }

    private func triggerPulse() {
        // Snap in, then ease back. The peak (~80ms) is what the eye latches
        // onto — the gentle decay just keeps it from looking like a glitch.
        withAnimation(.easeOut(duration: 0.08)) { pulsing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeIn(duration: 0.18)) { pulsing = false }
        }
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
