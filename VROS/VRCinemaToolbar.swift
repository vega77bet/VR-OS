import SwiftUI

enum VRCinemaDwellTarget: Equatable {
    case header(Int), closeLibrary, page(Int), item(Int)
    var key: String {
        switch self {
        case let .header(slot): return "header.\(slot)"
        case .closeLibrary: return "library.close"
        case let .page(delta): return "library.page.\(delta)"
        case let .item(index): return "library.item.\(index)"
        }
    }
}

enum VRCinemaDwellGeometry {
    static func target(at point: CGPoint, viewport: CGSize, libraryVisible: Bool,
                       page: Int, itemCount: Int) -> VRCinemaDwellTarget? {
        if !libraryVisible {
            return VRCinemaToolbarGeometry.slot(at: point, viewport: viewport).map { .header($0) }
        }
        let box = VRWorkspaceGeometry.bounds(viewport)
        guard box.contains(point) else { return nil }
        if point.y < box.minY + 36 && point.x > box.maxX - 45 { return .closeLibrary }
        if point.y > box.maxY - 28 {
            if point.x < box.midX - box.width / 6 && page > 0 { return .page(-1) }
            if point.x > box.midX + box.width / 6 && page + 1 < max(1, (itemCount + 5) / 6) { return .page(1) }
            return nil
        }
        if let slot = VRWorkspaceGeometry.item(at: point, in: viewport) {
            let index = page * 6 + slot
            if index < itemCount { return .item(index) }
        }
        return nil
    }
}

enum VRCinemaToolbarGeometry {
    static func rect(_ slot: Int, viewport: CGSize) -> CGRect {
        let width = max(1, (viewport.width - 32) / 5)
        return CGRect(x: 8 + CGFloat(slot) * (width + 4), y: 6, width: width, height: 32)
    }
    static func slot(at point: CGPoint, viewport: CGSize) -> Int? {
        (0..<5).first { rect($0, viewport: viewport).contains(point) }
    }
}

struct VRCinemaToolbar: View {
    let viewport: CGSize
    let action: (Int) -> Void
    private let labels = ["Controles", "Filmes", "Menu", "Assentos", "Sair"]
    private let symbols = ["slider.horizontal.3", "books.vertical.fill",
                           "line.3.horizontal", "chair.lounge.fill", "xmark"]
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<5, id: \.self) { index in
                let rect = VRCinemaToolbarGeometry.rect(index, viewport: viewport)
                Button { action(index) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: symbols[index]).font(.system(size: 11, weight: .bold))
                        Text(labels[index]).font(.system(size: 7, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }.frame(width: rect.width, height: rect.height)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).position(x: rect.midX, y: rect.midY)
            }
        }.foregroundStyle(.white).frame(width: viewport.width, height: 40)
    }
}
