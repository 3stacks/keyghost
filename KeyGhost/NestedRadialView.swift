import SwiftUI
import AppKit

/// Observable model for the radial. AppDelegate creates one per chord press
/// and mutates `highlighted` as arrow keys come in — SwiftUI animates the
/// transitions in place because the same view tree is kept alive (no NSHostingView
/// swaps on direction change).
@Observable
final class NestedRadialState {
    let rootKey: String
    let rootBinding: KeyBinding
    let nested: NestedBindings
    var highlighted: NestedDirection?

    init(rootKey: String, rootBinding: KeyBinding, nested: NestedBindings, highlighted: NestedDirection? = nil) {
        self.rootKey = rootKey
        self.rootBinding = rootBinding
        self.nested = nested
        self.highlighted = highlighted
    }
}

/// Cross-shaped overlay shown while a chord key with `nested` bindings is held.
/// The root binding sits in the centre; up/right/down/left tiles surround it.
/// Releasing the trigger executes either the highlighted direction's action
/// or the root binding if no direction was chosen.
struct NestedRadialView: View {
    @Bindable var state: NestedRadialState
    @State private var didAppear = false

    private static let tileOffset: CGFloat = 130

    var body: some View {
        radialCluster
            .frame(width: 380, height: 380)
            .padding(40)
            .background(panelBackground)
            .scaleEffect(didAppear ? 1 : 0.92)
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                // Spring the whole panel in. Tiles stagger from there.
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    didAppear = true
                }
            }
    }

    @ViewBuilder
    private var radialCluster: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                clusterContent
            }
        } else {
            clusterContent
        }
    }

    /// All 8 compass directions in clockwise order starting at north. Stagger
    /// slots use this ordering so the entrance animation reads as a clockwise
    /// sweep around the centre.
    private static let layoutOrder: [NestedDirection] = [
        .up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft
    ]

    private var clusterContent: some View {
        ZStack {
            ForEach(Array(Self.layoutOrder.enumerated()), id: \.element) { slot, direction in
                tile(direction: direction, action: state.nested.action(for: direction), slot: slot)
                    .offset(offset(for: direction))
            }
            centerTile
        }
    }

    private func offset(for direction: NestedDirection) -> CGSize {
        let r = Self.tileOffset
        // sin(45°) ≈ 0.7071 — equal radial distance for cardinals and diagonals,
        // so the cluster reads as an even compass rose.
        let d = r * 0.7071
        switch direction {
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

    private var centerTile: some View {
        NestedTileView(
            label: state.rootBinding.label ?? state.rootKey,
            keyHint: state.rootKey,
            bundleId: state.rootBinding.bundleId,
            isHighlighted: state.highlighted == nil,
            isCenter: true,
            staggerSlot: -1,
            didAppear: didAppear
        )
    }

    @ViewBuilder
    private func tile(direction: NestedDirection, action: NestedAction?, slot: Int) -> some View {
        if let action {
            NestedTileView(
                label: action.label ?? direction.shortName,
                keyHint: direction.glyph,
                bundleId: action.bundleId,
                isHighlighted: state.highlighted == direction,
                isCenter: false,
                staggerSlot: slot,
                didAppear: didAppear
            )
        } else {
            // Empty slot — keep layout consistent so present tiles don't shift.
            Color.clear.frame(width: NestedTileView.size, height: NestedTileView.size)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass: refraction, depth, dynamic light. The container
            // above lets the surrounding tiles' glass blend into this one.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }
}

private struct NestedTileView: View {
    static let size: CGFloat = 96

    let label: String
    let keyHint: String
    let bundleId: String?
    let isHighlighted: Bool
    let isCenter: Bool
    /// -1 for the centre tile; 0–3 for the cardinal directions in N, E, S, W
    /// order. Used to stagger entrance so tiles fade in 40ms apart.
    let staggerSlot: Int
    let didAppear: Bool

    @State private var icon: NSImage?
    @State private var revealed = false
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 4) {
            iconView
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
            Text(keyHint)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(width: Self.size, height: Self.size)
        .background(tileBackground)
        .scaleEffect(currentScale)
        .opacity(revealed ? 1 : 0)
        .shadow(color: isHighlighted ? Color.accentColor.opacity(0.55) : .clear, radius: 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHighlighted)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: pulsing)
        .task(id: bundleId) { loadIcon() }
        .onChange(of: didAppear) { _, appearing in
            guard appearing else { return }
            scheduleReveal()
        }
        .onAppear {
            if didAppear { scheduleReveal() }
            if isCenter { schedulePulse() }
        }
        .onChange(of: isHighlighted) { _, nowHighlighted in
            // Stop pulsing the centre as soon as the user picks a direction.
            if isCenter && !nowHighlighted { pulsing = false }
            if isCenter && nowHighlighted { schedulePulse() }
        }
    }

    private var currentScale: CGFloat {
        if !revealed { return 0.72 }
        if isHighlighted { return isCenter ? (pulsing ? 1.05 : 1.0) : 1.10 }
        return 1.0
    }

    @ViewBuilder
    private var tileBackground: some View {
        // No per-tile glass — Liquid Glass's surface refraction sits over the
        // tile bounds and washes out the icon. The accent fill + thicker
        // border on the highlighted tile, plus the outer shadow, do the work.
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape
            .fill(plainFill)
            .overlay(shape.strokeBorder(borderColor, lineWidth: isHighlighted ? 2 : 1))
    }

    private var plainFill: Color {
        if isHighlighted { return Color.accentColor.opacity(0.45) }
        return isCenter ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }

    private var borderColor: Color {
        isHighlighted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.18)
    }

    @ViewBuilder private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
        } else {
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private func loadIcon() {
        guard let bid = bundleId else {
            icon = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = IconResolver.icon(forBundleId: bid)
            DispatchQueue.main.async { self.icon = img }
        }
    }

    private func scheduleReveal() {
        // Centre reveals first, then N → E → S → W staggered (~25ms apart).
        let delaySteps = max(staggerSlot, 0)
        let delay = 0.02 + Double(delaySteps) * 0.025
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                self.revealed = true
            }
        }
    }

    private func schedulePulse() {
        // Subtle breathing on the centre tile while no direction is chosen.
        // Conveys "release now fires the root binding".
        guard isCenter && isHighlighted else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

private extension NestedDirection {
    var shortName: String {
        switch self {
        case .up: return "Up"
        case .upRight: return "Up-Right"
        case .right: return "Right"
        case .downRight: return "Down-Right"
        case .down: return "Down"
        case .downLeft: return "Down-Left"
        case .left: return "Left"
        case .upLeft: return "Up-Left"
        }
    }

    var glyph: String {
        switch self {
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
}
