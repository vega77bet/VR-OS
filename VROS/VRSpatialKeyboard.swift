import SwiftUI

enum VRKeyboardDestination: Equatable {
    case library, settings, browser(UUID)
}

@MainActor
final class VRSpatialKeyboardSession: ObservableObject {
    @Published var destination: VRKeyboardDestination?
    @Published var text = ""
    @Published var title = "Pesquisar"
    @Published var symbols = false
    @Published var uppercase = false
    @Published var hovered: String?

    func open(_ destination: VRKeyboardDestination, title: String, text: String) {
        self.text = String(text.prefix(512))
        self.title = title
        symbols = false
        uppercase = false
        self.destination = destination
    }

    func type(_ key: String) {
        switch key {
        case "delete": text = String(text.dropLast())
        case "clear": text = ""
        case "symbols": symbols.toggle()
        case "shift": uppercase.toggle()
        case "space": if text.count < 512 { text += " " }
        case "close", "enter": break
        default: if text.count < 512 { text += uppercase ? key.uppercased() : key }
        }
    }
}

struct VRSpatialKey: Identifiable {
    let id: String
    let label: String
    let rect: CGRect
}

enum VRKeyboardGeometry {
    static func keys(symbols: Bool, uppercase: Bool) -> [VRSpatialKey] {
        let characters: [String] = symbols
            ? ["1234567890", "@#€%&*()-+", ".,:;?!=_/"]
            : ["qwertyuiop", "asdfghjklç", "zxcvbnm./"]
        let rows: [[String]] = characters.map { row in row.map { String($0) } }
        var result: [VRSpatialKey] = []
        for (row, keys) in rows.enumerated() {
            let width: CGFloat = 52
            let gap: CGFloat = 6
            let x = (640 - CGFloat(keys.count) * (width + gap) + gap) / 2
            for (column, key) in keys.enumerated() {
                result.append(.init(id: key, label: uppercase ? key.uppercased() : key,
                    rect: CGRect(x: x + CGFloat(column) * (width + gap), y: 126 + CGFloat(row) * 58, width: width, height: 50)))
            }
        }
        result += [
            .init(id: "close", label: "Fechar", rect: CGRect(x: 538, y: 22, width: 76, height: 38)),
            .init(id: "clear", label: "Limpar", rect: CGRect(x: 526, y: 74, width: 86, height: 38)),
            .init(id: "symbols", label: symbols ? "ABC" : "123", rect: CGRect(x: 30, y: 304, width: 76, height: 50)),
            .init(id: "shift", label: "⇧", rect: CGRect(x: 112, y: 304, width: 58, height: 50)),
            .init(id: "space", label: "Espaço", rect: CGRect(x: 176, y: 304, width: 210, height: 50)),
            .init(id: "delete", label: "⌫", rect: CGRect(x: 392, y: 304, width: 84, height: 50)),
            .init(id: "enter", label: "Ir", rect: CGRect(x: 482, y: 304, width: 128, height: 50))
        ]
        return result
    }

    static func hit(_ point: CGPoint, viewport: CGSize, symbols: Bool, uppercase: Bool) -> String? {
        let local = VRHomeCanvas(viewport: viewport).local(point)
        return keys(symbols: symbols, uppercase: uppercase).first { $0.rect.contains(local) }?.id
    }
}

struct VRSpatialKeyboard: View {
    @ObservedObject var session: VRSpatialKeyboardSession
    let viewport: CGSize
    let onKey: (String) -> Void
    var body: some View {
        let canvas = VRHomeCanvas(viewport: viewport)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28).fill(VRDS.Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(VRDS.Color.border))
                .frame(width: 620, height: 370).position(x: 320, y: 195)
            Text(session.title).font(.system(size: 22, weight: .semibold))
                .position(x: 220, y: 40)
            Text(session.text.isEmpty ? "Digite com a mira ou por toque" : session.text)
                .font(.system(size: 18)).lineLimit(1).truncationMode(.head)
                .foregroundStyle(session.text.isEmpty ? VRDS.Color.secondary : VRDS.Color.primary)
                .padding(.horizontal, 14).frame(width: 480, height: 40, alignment: .leading)
                .background(VRDS.Color.background, in: Capsule()).position(x: 270, y: 93)
            ForEach(VRKeyboardGeometry.keys(symbols: session.symbols, uppercase: session.uppercase)) { key in
                Button { onKey(key.id) } label: {
                    Text(key.label).font(.system(size: 19, weight: .medium))
                        .frame(width: key.rect.width, height: key.rect.height)
                        .foregroundStyle(key.id == "enter" ? VRDS.Color.background : VRDS.Color.primary)
                        .background(key.id == "enter" ? VRDS.Color.primary :
                            (session.hovered == key.id ? VRDS.Color.surfacePressed : VRDS.Color.surfaceElevated),
                            in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel(key.label)
                    .position(x: key.rect.midX, y: key.rect.midY)
            }
            Text("VR-OS  ·  Teclado espacial").font(.system(size: 12)).foregroundStyle(VRDS.Color.secondary)
                .position(x: 320, y: 395)
        }
        .foregroundStyle(VRDS.Color.primary)
        .frame(width: 640, height: 420)
        .scaleEffect(canvas.scale)
        .position(x: viewport.width / 2, y: viewport.height / 2)
        .frame(width: viewport.width, height: viewport.height)
        .background(.black.opacity(0.78))
    }
}
