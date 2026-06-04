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

    // Compass radius from centre to each cardinal tile. Diagonals sit at
    // r * 0.7071 on each axis so all 8 directions land on the same circle —
    // angular spacing is uniform 45°, and the cluster reads as a true rosette.
    // 180 keeps a comfortable ~85 px gap between adjacent tile edges, so the
    // ring feels open instead of crammed.
    private static let tileOffset: CGFloat = 180

    var body: some View {
        // ZStack with a clear background fills the hosting view, which lets
        // SwiftUI centre the rosette in the OverlayPanel rather than pinning
        // it to the top-leading.
        ZStack {
            Color.clear
            radialCluster
                .frame(width: 520, height: 520)
                .padding(36)
                .background(panelBackground)
                .scaleEffect(didAppear ? 1 : 0.92)
                .opacity(didAppear ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Spacing controls how aggressively neighbouring tiles' glass
            // surfaces merge — larger value = more discrete tiles. At the new
            // tile-offset of 180 the tiles never quite touch, but raising
            // spacing keeps each one optically distinct rather than melting
            // into a single blob.
            GlassEffectContainer(spacing: 28) {
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
        // 32pt radius scales with the larger 520×520 cluster (was 22pt at
        // 320×320). Same material language as KeyboardOverlayView so the two
        // panels still read as one design family even at different sizes.
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
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

    var body: some View {
        tileContent
            .frame(width: Self.width, height: Self.height)
            .modifier(TileSurface(
                isHighlighted: isHighlighted,
                isCenter: isCenter
            ))
            .scaleEffect(currentScale)
            .opacity(revealed ? 1 : 0)
            // Green glow on the armed tile matches the chord-fired pulse in
            // the base overlay — green means "this is what KeyGhost will
            // fire on release" in both UIs, so the visual language stays
            // consistent.
            .shadow(color: isHighlighted ? Color.green.opacity(0.50) : .clear, radius: 8)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHighlighted)
            .task(id: bundleId) { loadIcon() }
            .onChange(of: didAppear) { _, appearing in
                guard appearing else { return }
                scheduleReveal()
            }
            .onAppear {
                if didAppear { scheduleReveal() }
            }
    }

    private var currentScale: CGFloat {
        // Only the entrance animation scales tiles. Once revealed they stay
        // at 1.0 — the green glass tint + thicker border already signal the
        // armed state, and growing a tile under your eyes was distracting
        // (it pulled focus away from the action you were about to commit).
        revealed ? 1.0 : 0.72
    }

    // Layout mirrors KeyCellView: icon → input glyph → semantic label. The
    // direction arrow plays the same role here that the letter plays in the
    // base overlay (it's "what you press"), so same 11pt mono semibold.
    private var tileContent: some View {
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
}

/// Tile surface: glass-behind-content on macOS 26, solid fill on earlier
/// systems. Applies `glassEffect` directly to the tile content (the
/// Apple-blessed pattern) so glass renders *behind* the icon, not as an
/// overlay on top of it. The previous attempt used `.background(...)` with
/// a glass-filled shape, which caused the glass material to sit visually
/// over the icon — a known quirk when nesting glassEffect inside a
/// .background modifier.
private struct TileSurface: ViewModifier {
    let isHighlighted: Bool
    let isCenter: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(tileGlass, in: .rect(cornerRadius: 10))
                .overlay(borderShape)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(plainFill)
                )
                .overlay(borderShape)
        }
    }

    @available(macOS 26.0, *)
    private var tileGlass: Glass {
        // Tinting the glass at the source lets the live refraction pick the
        // colour up at the edges and highlights — better than overlaying a
        // green fill on top, which would re-introduce the wash-out problem.
        if isHighlighted { return .regular.tint(.green.opacity(0.55)) }
        return .regular
    }

    private var plainFill: Color {
        if isHighlighted { return Color.green.opacity(0.32) }
        return isCenter ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }

    private var borderColor: Color {
        if isHighlighted { return Color.green.opacity(0.95) }
        return Color.white.opacity(isCenter ? 0.20 : 0.16)
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isHighlighted ? 2 : 0.5)
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
