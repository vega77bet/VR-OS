import SwiftUI

enum VROSStyle {
    static let ink = Color(red: 0.065, green: 0.078, blue: 0.11)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let secondary = Color.white.opacity(0.64)
    static let border = Color.white.opacity(0.16)
    static let rounding: CGFloat = 26
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = VROSStyle.rounding

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(VROSStyle.border, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.22), radius: 25, y: 12)
    }
}

extension View {
    func glassPanel(radius: CGFloat = VROSStyle.rounding) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
            }
    }
}

struct DockItem: View {
    let symbol: String
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 38, height: 34)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
