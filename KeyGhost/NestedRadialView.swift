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

    // Tightened from 130 since tiles shrank to base-overlay dimensions (64×86).
    // Far enough that diagonals don't touch their cardinals, close enough that
    // the cluster reads as a single rosette instead of eight floating tiles.
    private static let tileOffset: CGFloat = 118

    var body: some View {
        radialCluster
            .frame(width: 320, height: 320)
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
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
            Color.clear.frame(width: NestedTileView.width, height: NestedTileView.height)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        // Matches KeyboardOverlayView.panelBackground (cornerRadius 22, same
        // material + border opacities) so the nested radial and the main
        // keyboard overlay read as variants of one surface, not two designs.
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }
}

private struct NestedTileView: View {
    // Dimensions and typography mirror KeyCellView in KeyboardOverlayView so
    // the nested radial and the base keyboard read as one design language.
    static let width: CGFloat = 64
    static let height: CGFloat = 86

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
        // Layout mirrors KeyCellView: icon → input glyph → semantic label.
        // The direction arrow plays the same role here that the letter plays
        // in the base overlay (it's "what you press"), so it gets the same
        // 11pt monospaced semibold treatment.
        VStack(spacing: 3) {
            iconView
            Text(keyHint)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
        }
        .frame(width: Self.width, height: Self.height)
        .background(tileBackground)
        .scaleEffect(currentScale)
        .opacity(revealed ? 1 : 0)
        // Green glow on the armed tile matches the chord-fired pulse in the
        // base overlay — green means "this is what KeyGhost will fire on
        // release" in both UIs, so the visual language stays consistent.
        .shadow(color: isHighlighted ? Color.green.opacity(0.50) : .clear, radius: 8)
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
        if isHighlighted { return isCenter ? (pulsing ? 1.04 : 1.0) : 1.08 }
        return 1.0
    }

    @ViewBuilder
    private var tileBackground: some View {
        // 10pt radius + white-opacity fills match KeyCellView. The "armed"
        // state swaps in green at the same intensity the chord-fired pulse
        // uses (0.32 fill / 0.95 border / 2px stroke).
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(plainFill)
            .overlay(shape.strokeBorder(borderColor, lineWidth: isHighlighted ? 2 : 1))
    }

    private var plainFill: Color {
        if isHighlighted { return Color.green.opacity(0.32) }
        // Centre = present (matches base "bound" cell); cardinals = lighter
        // (matches base "unbound" cell) so the root binding reads as primary.
        return isCenter ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }

    private var borderColor: Color {
        if isHighlighted { return Color.green.opacity(0.95) }
        return Color.white.opacity(isCenter ? 0.20 : 0.16)
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
