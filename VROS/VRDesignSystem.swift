import SwiftUI

// MARK: - VR-OS Design System V44

enum VRDS {
    enum Color {
        static let background = SwiftUI.Color(red: 0.055, green: 0.067, blue: 0.090)
        static let surface = SwiftUI.Color(red: 0.105, green: 0.125, blue: 0.160)
        static let surfaceElevated = SwiftUI.Color(red: 0.145, green: 0.165, blue: 0.205)
        static let surfacePressed = SwiftUI.Color(red: 0.205, green: 0.230, blue: 0.275)
        static let border = SwiftUI.Color.white.opacity(0.12)
        static let borderStrong = SwiftUI.Color.white.opacity(0.22)
        static let primary = SwiftUI.Color(red: 0.918, green: 0.941, blue: 0.969)
        static let secondary = SwiftUI.Color(red: 0.620, green: 0.675, blue: 0.760)
        static let muted = SwiftUI.Color(red: 0.390, green: 0.445, blue: 0.525)
        static let accent = SwiftUI.Color(red: 0.314, green: 0.871, blue: 1.0)
        static let selected = SwiftUI.Color(red: 0.682, green: 0.545, blue: 1.0)
        static let destructive = SwiftUI.Color(red: 1.0, green: 0.365, blue: 0.420)
        static let success = SwiftUI.Color(red: 0.300, green: 0.900, blue: 0.670)
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        static let headline = SwiftUI.Font.system(size: 19, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 16, weight: .regular, design: .rounded)
        static let bodyEmphasized = SwiftUI.Font.system(size: 16, weight: .semibold, design: .rounded)
        static let caption = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
        static let micro = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)
    }

    enum Metrics {
        static let cornerSmall: CGFloat = 10
        static let cornerMedium: CGFloat = 16
        static let cornerLarge: CGFloat = 24
        static let iconSmall: CGFloat = 18
        static let iconMedium: CGFloat = 24
        static let iconLarge: CGFloat = 32
        static let controlHeight: CGFloat = 48
        static let taskbarHeight: CGFloat = 66
        static let horizontalPadding: CGFloat = 18
        static let contentSpacing: CGFloat = 12
        static let minimumHitTarget: CGFloat = 44
    }
}

enum VRIconStyle {
    case outline
    case filled
}

struct VRIcon: View {
    let name: String
    var style: VRIconStyle = .outline
    var state: VRIconState = .normal
    var size: CGFloat = VRDS.Metrics.iconMedium
    var accessibilityText: String?

    enum VRIconState {
        case normal
        case active
        case disabled
        case selected

        var assetSuffix: String {
            switch self {
            case .normal: return ""
            case .active: return "_active"
            case .disabled: return "_disabled"
            case .selected: return "_selected"
            }
        }

        var tint: SwiftUI.Color {
            switch self {
            case .normal: return VRDS.Color.primary
            case .active: return VRDS.Color.accent
            case .disabled: return VRDS.Color.muted
            case .selected: return VRDS.Color.selected
            }
        }
    }

    var body: some View {
        let prefix = style == .filled ? "_filled" : ""
        Image("vr_\(name)\(prefix)\(state.assetSuffix)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(state == .disabled ? 0.55 : 1)
            .accessibilityLabel(accessibilityText ?? name)
    }
}

struct VRSurface<Content: View>: View {
    var elevated = false
    var padding: CGFloat = VRDS.Metrics.horizontalPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(elevated ? VRDS.Color.surfaceElevated : VRDS.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: VRDS.Metrics.cornerMedium)
                    .stroke(VRDS.Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VRDS.Metrics.cornerMedium))
    }
}

struct VRPrimaryButtonStyle: ButtonStyle {
    var tint: SwiftUI.Color = VRDS.Color.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VRDS.Font.bodyEmphasized)
            .foregroundStyle(VRDS.Color.background)
            .frame(minHeight: VRDS.Metrics.controlHeight)
            .padding(.horizontal, 18)
            .background(configuration.isPressed ? tint.opacity(0.72) : tint)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct VRSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VRDS.Font.bodyEmphasized)
            .foregroundStyle(VRDS.Color.primary)
            .frame(minHeight: VRDS.Metrics.controlHeight)
            .padding(.horizontal, 18)
            .background(configuration.isPressed ? VRDS.Color.surfacePressed : VRDS.Color.surfaceElevated)
            .overlay(Capsule().stroke(VRDS.Color.borderStrong, lineWidth: 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct VRIconButton: View {
    let icon: String
    var style: VRIconStyle = .outline
    var state: VRIcon.VRIconState = .normal
    var label: String
    var size: CGFloat = VRDS.Metrics.minimumHitTarget
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VRIcon(name: icon, style: style, state: state,
                   size: VRDS.Metrics.iconMedium, accessibilityText: label)
                .frame(width: size, height: size)
                .background(VRDS.Color.surface)
                .overlay(Circle().stroke(VRDS.Color.border, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .contentShape(Circle())
    }
}
