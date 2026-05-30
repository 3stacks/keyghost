import SwiftUI
import AppKit

/// Cross-shaped overlay shown while a chord key with `nested` bindings is held.
/// The root binding sits in the centre; up/right/down/left tiles surround it.
/// `highlighted` is the direction currently selected by the user's arrow press;
/// releasing the trigger executes either that direction's action or the root
/// binding if no direction was highlighted.
struct NestedRadialView: View {
    let rootKey: String
    let rootBinding: KeyBinding
    let nested: NestedBindings
    let highlighted: NestedDirection?

    var body: some View {
        ZStack {
            // North
            tile(direction: .up, action: nested.up)
                .offset(y: -110)
            // East
            tile(direction: .right, action: nested.right)
                .offset(x: 110)
            // South
            tile(direction: .down, action: nested.down)
                .offset(y: 110)
            // West
            tile(direction: .left, action: nested.left)
                .offset(x: -110)

            // Centre — the root binding itself, highlighted when no direction
            // is chosen so the user knows "release now" launches the default.
            centerTile
        }
        .frame(width: 360, height: 360)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var centerTile: some View {
        NestedTileView(
            label: rootBinding.label ?? rootKey,
            keyHint: rootKey,
            bundleId: rootBinding.bundleId,
            isHighlighted: highlighted == nil,
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
                isHighlighted: highlighted == direction,
                isCenter: false
            )
        } else {
            // Empty slot — keep layout consistent so present tiles don't shift.
            Color.clear.frame(width: NestedTileView.size, height: NestedTileView.size)
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

    @State private var icon: NSImage?

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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isHighlighted ? 2 : 1)
                )
                .shadow(color: isHighlighted ? Color.accentColor.opacity(0.45) : .clear, radius: 8)
        )
        .task(id: bundleId) { loadIcon() }
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

    private var backgroundColor: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.28)
        }
        return isCenter ? Color.white.opacity(0.18) : Color.white.opacity(0.12)
    }

    private var borderColor: Color {
        isHighlighted ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.18)
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

private extension NestedDirection {
    var shortName: String {
        switch self {
        case .up: return "Up"
        case .right: return "Right"
        case .down: return "Down"
        case .left: return "Left"
        }
    }

    var glyph: String {
        switch self {
        case .up: return "↑"
        case .right: return "→"
        case .down: return "↓"
        case .left: return "←"
        }
    }
}
