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

/// Full-screen wrapper for radial-only sessions (chord landed before the
/// keyboard overlay appeared). Centres the rosette in the OverlayPanel.
/// When the keyboard overlay is up, KeyboardOverlayView embeds
/// NestedRadialClusterView directly, anchored to the pressed key.
struct NestedRadialView: View {
    @Bindable var state: NestedRadialState

    var body: some View {
        // ZStack with a clear background fills the hosting view, which lets
        // SwiftUI centre the rosette in the OverlayPanel rather than pinning
        // it to the top-leading.
        ZStack {
            Color.clear
            NestedRadialClusterView(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Cross-shaped rosette shown while a chord key with `nested` bindings is
/// held. The root binding sits in the centre; the 8 direction tiles pop in
/// around it. Releasing the trigger executes either the highlighted
/// direction's action or the root binding if no direction was chosen.
struct NestedRadialClusterView: View {
    @Bindable var state: NestedRadialState
    @State private var didAppear = false
    /// Slots (indices into `layoutOrder`) that already popped in. Tiles wait
    /// at their final positions, hidden, until their stagger turn comes.
    @State private var revealedSlots: Set<Int> = []

    // Ring tiles sit one key-pitch from the centre on a 3×3 grid — the same
    // 8pt gaps as the keyboard overlay — so anchored on a key, the rosette
    // occupies exactly where that key's neighbours are.
    private static let pitchX: CGFloat = NestedTileView.width + 8
    private static let pitchY: CGFloat = NestedTileView.height + 8

    var body: some View {
        // No shared panel behind the rosette — the tiles float free, each
        // carrying its own surface, echoing the key cells in Settings.
        radialCluster
            .frame(
                width: NestedTileView.width + Self.pitchX * 2,
                height: NestedTileView.height + Self.pitchY * 2
            )
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                // Centre tile snaps in, then the ring tiles pop in place with
                // a fast clockwise sweep from north — crisp, no drift.
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    didAppear = true
                }
                for slot in Self.layoutOrder.indices {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 + Double(slot) * 0.025) {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                            _ = revealedSlots.insert(slot)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var radialCluster: some View {
        if #available(macOS 26.0, *) {
            // Spacing controls how aggressively neighbouring tiles' glass
            // surfaces merge. On the snug key-pitch grid the gaps are only
            // 8pt, so keep the merge distance below that — the tiles must
            // stay discrete cells, not melt into one blob.
            GlassEffectContainer(spacing: 4) {
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
        // Ring tiles sit at their final grid positions from the start and
        // pop in place — no slide, just a quick staggered scale + fade.
        ZStack {
            ForEach(Array(Self.layoutOrder.enumerated()), id: \.element) { slot, direction in
                let revealed = revealedSlots.contains(slot)
                tile(direction: direction, action: state.nested.action(for: direction))
                    .offset(offset(for: direction))
                    .scaleEffect(revealed ? 1 : 0.9)
                    .opacity(revealed ? 1 : 0)
            }
            centerTile
                .scaleEffect(didAppear ? 1 : 0.9)
        }
    }

    private func offset(for direction: NestedDirection) -> CGSize {
        let x = Self.pitchX
        let y = Self.pitchY
        switch direction {
        case .up: return CGSize(width: 0, height: -y)
        case .upRight: return CGSize(width: x, height: -y)
        case .right: return CGSize(width: x, height: 0)
        case .downRight: return CGSize(width: x, height: y)
        case .down: return CGSize(width: 0, height: y)
        case .downLeft: return CGSize(width: -x, height: y)
        case .left: return CGSize(width: -x, height: 0)
        case .upLeft: return CGSize(width: -x, height: -y)
        }
    }

    private var centerTile: some View {
        NestedTileView(
            label: state.rootBinding.label ?? state.rootKey,
            keyHint: state.rootKey,
            bundleId: state.rootBinding.bundleId,
            isHighlighted: state.highlighted == nil,
            isCenter: true
        )
    }

    @ViewBuilder
    private func tile(direction: NestedDirection, action: NestedAction?) -> some View {
        if let action {
            NestedTileView(
                label: action.label ?? direction.shortName,
                keyHint: direction.glyph,
                bundleId: action.bundleId,
                isHighlighted: state.highlighted == direction,
                isCenter: false
            )
        } else {
            // Empty slot — keep layout consistent so present tiles don't shift.
            Color.clear.frame(width: NestedTileView.width, height: NestedTileView.height)
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

    @State private var icon: NSImage?

    // Entrance (the bloom out of the centre tile) is driven by the parent
    // rosette — this view only renders content, surface, and the armed state.
    var body: some View {
        tileContent
            .frame(width: Self.width, height: Self.height)
            .modifier(TileSurface(
                isHighlighted: isHighlighted,
                isCenter: isCenter
            ))
            // Green glow on the armed tile matches the chord-fired pulse in
            // the base overlay — green means "this is what KeyGhost will
            // fire on release" in both UIs, so the visual language stays
            // consistent.
            .shadow(color: isHighlighted ? Color.green.opacity(0.50) : .clear, radius: 8)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHighlighted)
            .task(id: bundleId) { loadIcon() }
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

    // 8pt continuous radius matches the key cells in the Settings editor, so
    // the live radial and the editor read as one design language.
    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(tileGlass, in: .rect(cornerRadius: 8))
                .overlay(borderShape)
        } else {
            // Without the shared panel each tile needs its own material to
            // stay readable over arbitrary desktop content.
            content
                .background(
                    Self.shape
                        .fill(plainFill)
                        .background(.ultraThinMaterial, in: Self.shape)
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
        Self.shape
            .strokeBorder(borderColor, lineWidth: isHighlighted ? 2 : 1)
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
