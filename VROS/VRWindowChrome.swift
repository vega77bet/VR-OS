import SwiftUI

enum VRWindowAction: String, CaseIterable {
    case move, smaller, larger, focus, minimize, close
    var symbol: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .smaller: return "minus.magnifyingglass"
        case .larger: return "plus.magnifyingglass"
        case .focus: return "arrow.up.left.and.arrow.down.right"
        case .minimize: return "minus"
        case .close: return "xmark"
        }
    }
    var title: String {
        switch self {
        case .move: return "Mover janela"
        case .smaller: return "Diminuir"
        case .larger: return "Aumentar"
        case .focus: return "Expandir ou restaurar"
        case .minimize: return "Minimizar"
        case .close: return "Fechar"
        }
    }
}

enum VRWindowChromeGeometry {
    static func frame(center: CGPoint, dimensions: CGSize, viewport: CGSize) -> CGRect {
        let width = min(viewport.width * 0.94, max(130, dimensions.width * 0.94))
        let height: CGFloat = 28
        let bottomLimit = VRHomeCanvas(viewport: viewport).screen(CGPoint(x: 0, y: 326)).y
        let top = min(center.y + dimensions.height / 2 + 7, bottomLimit - height)
        return CGRect(x: center.x - width / 2, y: top, width: width, height: height)
    }
    static func button(_ action: VRWindowAction, frame: CGRect) -> CGRect {
        let slot = VRWindowAction.allCases.firstIndex(of: action) ?? 0
        let width = frame.width / CGFloat(VRWindowAction.allCases.count)
        return CGRect(x: frame.minX + CGFloat(slot) * width, y: frame.minY, width: width, height: frame.height)
    }
    static func hit(_ point: CGPoint, frame: CGRect) -> VRWindowAction? {
        guard frame.contains(point) else { return nil }
        return VRWindowAction.allCases.first { button($0, frame: frame).contains(point) }
    }
}

struct VRWindowChrome: View {
    let frame: CGRect
    let moving: Bool
    let onAction: (VRWindowAction) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(VRWindowAction.allCases, id: \.rawValue) { action in
                Button { onAction(action) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(moving && action == .move ? VRDS.Color.accent : VRDS.Color.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(action.title)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(VRDS.Color.surface.opacity(0.97), in: Capsule())
        .overlay(Capsule().stroke(VRDS.Color.borderStrong, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
