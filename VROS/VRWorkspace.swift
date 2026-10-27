import SwiftUI

/// Presentation state is shared by both eyes and independent of AR anchors.
struct VRWindowPresentation: Equatable {
    var minimized = false
    var scale: CGFloat = 1
}

@MainActor
final class VRWorkspace: ObservableObject {
    @Published private(set) var windows: [UUID: VRWindowPresentation] = [:]
    @Published private(set) var focused: UUID?

    func state(_ id: UUID) -> VRWindowPresentation {
        windows[id] ?? VRWindowPresentation()
    }

    func minimize(_ id: UUID) {
        var value = state(id)
        value.minimized.toggle()
        windows[id] = value
        if value.minimized && focused == id { focused = nil }
    }

    func focus(_ id: UUID) {
        var value = state(id)
        value.minimized = false
        windows[id] = value
        focused = focused == id ? nil : id
    }

    func resize(_ id: UUID, by amount: CGFloat) {
        guard amount.isFinite else { return }
        var value = state(id)
        value.scale = max(0.65, min(1.4, value.scale + amount))
        windows[id] = value
    }

    func remove(_ id: UUID) {
        windows.removeValue(forKey: id)
        if focused == id { focused = nil }
    }
}

enum VRWorkspaceCommand {
    case settings, camera, center, theme, hud, updates
    case minimize(UUID), focus(UUID), smaller(UUID), larger(UUID), close(UUID)
}

struct VRWorkspaceItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let command: VRWorkspaceCommand
}

/// The same rectangles drive SwiftUI buttons and Vision hit testing.
enum VRWorkspaceGeometry {
    static let pageSize = 6

    static func bounds(_ viewport: CGSize) -> CGRect {
        CGRect(x: viewport.width * 0.02, y: viewport.height * 0.03,
               width: viewport.width * 0.96, height: viewport.height * 0.94)
    }

    static func cell(_ index: Int, in viewport: CGSize) -> CGRect {
        let box = bounds(viewport)
        let width = (box.width - 22) / 2
        let height = (box.height - 82) / 3
        return CGRect(x: box.minX + 8 + CGFloat(index % 2) * (width + 6),
                      y: box.minY + 42 + CGFloat(index / 2) * (height + 6),
                      width: width, height: height)
    }

    static func item(at point: CGPoint, in viewport: CGSize) -> Int? {
        (0..<pageSize).first { cell($0, in: viewport).contains(point) }
    }
}

struct VRWorkspaceView: View {
    let items: [VRWorkspaceItem]
    let page: Int
    let viewport: CGSize
    let onSelect: (VRWorkspaceCommand) -> Void
    let onPage: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        let box = VRWorkspaceGeometry.bounds(viewport)
        let pages = max(1, (items.count + 5) / 6)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.045)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text("CENTRAL VR").tracking(1)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
            }
            .font(.system(size: 11, weight: .bold))
            .frame(width: box.width - 24, height: 30)
            .position(x: box.midX, y: box.minY + 18)
            ForEach(0..<6, id: \.self) { slot in
                let index = page * 6 + slot
                if items.indices.contains(index) {
                    let item = items[index]
                    let rect = VRWorkspaceGeometry.cell(slot, in: viewport)
                    Button { onSelect(item.command) } label: {
                        HStack(spacing: 5) {
                            VRChromeIcon(symbol: item.symbol, accent: .cyan)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 10, weight: .semibold))
                                Text(item.detail).font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .lineLimit(1).minimumScaleFactor(0.65)
                            Spacer(minLength: 0)
                        }.padding(6).frame(width: rect.width, height: rect.height)
                            .background(.white.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.position(x: rect.midX, y: rect.midY)
                }
            }
            HStack {
                Button { onPage(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(page == 0).frame(maxWidth: .infinity)
                Text("\(page + 1) / \(pages)").font(.system(size: 9))
                    .frame(maxWidth: .infinity)
                Button { onPage(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(page + 1 >= pages).frame(maxWidth: .infinity)
            }
            .frame(width: box.width - 16, height: 24)
            .position(x: box.midX, y: box.maxY - 14)
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .frame(width: viewport.width, height: viewport.height)
    }
}

struct VRChromeIcon: View {
    let symbol: String
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.27)
                    .fill(LinearGradient(colors: [accent.opacity(0.5), Color(white: 0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: side * 0.27)
                    .stroke(LinearGradient(colors: [.white.opacity(0.65), accent.opacity(0.15)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.8)
                Image(systemName: symbol)
                    .font(.system(size: side * 0.51, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.7), radius: 3, y: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        }
        .accessibilityHidden(true)
    }
}
