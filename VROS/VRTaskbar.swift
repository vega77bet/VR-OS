import SwiftUI

// MARK: - VR-OS Taskbar V45

enum VRTaskbarAction: String, CaseIterable, Identifiable {
    case home
    case apps
    case cinema
    case files
    case photos
    case browser
    case settings
    case newWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Central"
        case .apps: return "Apps"
        case .cinema: return "Cinema"
        case .files: return "Arquivos"
        case .photos: return "Fotos"
        case .browser: return "Navegador"
        case .settings: return "Ajustes"
        case .newWindow: return "Janela"
        }
    }
}

enum VRTaskbarGeometry {
    static func visibleItems(_ items: [RemoteTaskbarItem]) -> [RemoteTaskbarItem] {
        items.filter { $0.enabled && $0.resolvedAction != nil }
    }

    static func barRect(viewport: CGSize) -> CGRect {
        let width = min(max(1, viewport.width - 12), 560)
        let height = min(64, max(52, viewport.height * 0.18))
        return CGRect(x: (viewport.width - width) / 2,
                      y: viewport.height - height - 8,
                      width: width,
                      height: height)
    }

    static func itemRect(_ index: Int, viewport: CGSize, count: Int) -> CGRect {
        let bar = barRect(viewport: viewport)
        let gap: CGFloat = 4
        let inset: CGFloat = 5
        let width = max(1, (bar.width - inset * 2 -
                             gap * CGFloat(max(0, count - 1))) /
                            CGFloat(max(1, count)))
        return CGRect(x: bar.minX + inset + CGFloat(index) * (width + gap),
                      y: bar.minY + inset,
                      width: width,
                      height: bar.height - inset * 2)
    }

    static func action(at point: CGPoint, viewport: CGSize,
                       items: [RemoteTaskbarItem]) -> VRTaskbarAction? {
        let visible = visibleItems(items)
        guard let index = visible.indices.first(where: {
            itemRect($0, viewport: viewport, count: visible.count)
                .insetBy(dx: -5, dy: -7)
                .contains(point)
        }) else { return nil }
        return visible[index].resolvedAction
    }
}

struct VRTaskbar: View {
    let viewport: CGSize
    let items: [RemoteTaskbarItem]
    let active: VRTaskbarAction?
    let reduceMotion: Bool
    let accent: Color
    let surface: Color
    let surfaceOpacity: Double
    let onAction: (VRTaskbarAction) -> Void

    private var visibleItems: [RemoteTaskbarItem] {
        VRTaskbarGeometry.visibleItems(items)
    }

    var body: some View {
        let bar = VRTaskbarGeometry.barRect(viewport: viewport)

        HStack(spacing: 0) {
            ForEach(visibleItems) { item in
                if let action = item.resolvedAction {
                    let selected = active == action
                    Button {
                        onAction(action)
                    } label: {
                        VStack(spacing: 3) {
                            VRIcon(
                                name: item.icon,
                                state: selected ? .active : .normal,
                                size: 20,
                                accessibilityText: item.title
                            )
                            Text(item.title)
                                .font(VRDS.Font.micro)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                        }
                        .foregroundStyle(selected ? accent : VRDS.Color.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selected ? accent.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(selected ? accent : .clear)
                                .frame(width: 18, height: 2)
                                .padding(.bottom, 4)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(VRTaskbarButtonStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(item.title)
                }
            }
        }
        .padding(5)
        .frame(width: bar.width, height: bar.height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(surface.opacity(surfaceOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VRDS.Color.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Barra de tarefas do VR-OS")
    }
}

private struct VRTaskbarButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                       value: configuration.isPressed)
    }
}
