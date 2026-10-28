import Foundation
import Combine
import CoreGraphics

enum VRHomeSection: String, CaseIterable, Identifiable {
    case all, apps, web, worlds, windows
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Tudo"
        case .apps: return "Aplicativos"
        case .web: return "Web"
        case .worlds: return "Ambientes"
        case .windows: return "Janelas"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .apps: return "app"
        case .web: return "globe"
        case .worlds: return "mountain.2"
        case .windows: return "rectangle.on.rectangle"
        }
    }
}

struct VRHomeEntry: Identifiable, Equatable {
    enum Kind { case native, web, world }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: String
    let kind: Kind

    static let catalog: [VRHomeEntry] = [
        .init(id: "cinema", title: "Cinema", detail: "Vídeos locais · 2D e 3D", symbol: "play.rectangle.fill", color: "E7A881", kind: .native),
        .init(id: "browser", title: "Navegador", detail: "Abas e sites HTTPS", symbol: "globe", color: "96B7D6", kind: .web),
        .init(id: "files", title: "Arquivos", detail: "Documentos e mídia local", symbol: "folder.fill", color: "8BAAC9", kind: .native),
        .init(id: "photos", title: "Fotos", detail: "Galeria de imagens", symbol: "photo.on.rectangle", color: "C7A4CA", kind: .native),
        .init(id: "notes", title: "Notas", detail: "Janelas de leitura", symbol: "note.text", color: "D6C69A", kind: .native),
        .init(id: "settings", title: "Ajustes", detail: "Preferências do VR-OS", symbol: "gearshape.fill", color: "ABB0BA", kind: .native),
        .init(id: "youtube", title: "YouTube", detail: "Site de vídeos", symbol: "play.rectangle", color: "D58D8D", kind: .web),
        .init(id: "netflix", title: "Netflix", detail: "Site · sujeito a DRM", symbol: "film", color: "C3818B", kind: .web),
        .init(id: "wikipedia", title: "Wikipedia", detail: "Enciclopédia na web", symbol: "books.vertical", color: "B7BAC1", kind: .web),
        .init(id: "twitch", title: "Twitch", detail: "Site de transmissões", symbol: "video", color: "AC94CE", kind: .web),
        .init(id: "lens", title: "Visor", detail: "Ajuste dos dois olhos", symbol: "eyeglasses", color: "93BDB6", kind: .native),
        .init(id: "tools", title: "Central VR", detail: "Janelas e ferramentas", symbol: "slider.horizontal.3", color: "AEB8C8", kind: .native),
        .init(id: "updates", title: "Atualizações", detail: "Conteúdo do VR-OS", symbol: "arrow.down.circle", color: "9DBBA8", kind: .native),
        .init(id: "compatibility", title: "Plataforma", detail: "Recursos desta versão", symbol: "info.circle", color: "B1B9C9", kind: .native),
        .init(id: "world.0", title: "Grafite", detail: "Ambiente escuro", symbol: "circle.lefthalf.filled", color: "9BA0A9", kind: .world),
        .init(id: "world.1", title: "Cosmos", detail: "Estrelas em 360°", symbol: "moon.stars", color: "B4A2D8", kind: .world),
        .init(id: "world.2", title: "Aurora", detail: "Céu boreal", symbol: "sparkles", color: "91C8B2", kind: .world),
        .init(id: "world.3", title: "Synthwave", detail: "Horizonte retrô", symbol: "waveform.path", color: "CA9CBF", kind: .world)
    ]
    static func find(_ id: String) -> VRHomeEntry? { catalog.first { $0.id == id } }
}

struct VRHomeWindow: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let minimized: Bool
}

/// One library, recency list and pin set for both eyes. No service credentials
/// or remote catalog are borrowed from the reference project.
@MainActor
final class VRHomeLibrary: ObservableObject {
    @Published var visible = true
    @Published var quickSettings = false
    @Published var section: VRHomeSection = .all { didSet { page = 0 } }
    @Published var query = "" { didSet { page = 0 } }
    @Published var page = 0
    @Published var alphabetical = false
    @Published var hovered: String?
    @Published private(set) var pinned: [String]
    @Published private(set) var recent: [String]
    private let defaults: UserDefaults
    static let pageSize = 6

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let known = Set(VRHomeEntry.catalog.filter { $0.kind != .world }.map(\.id))
        func valid(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { known.contains($0) && seen.insert($0).inserted }
        }
        pinned = Array(valid(defaults.stringArray(forKey: "vros.home.pins.v48")
            ?? ["cinema", "browser", "files", "settings"]).prefix(4))
        recent = Array(valid(defaults.stringArray(forKey: "vros.home.recent.v48") ?? []).prefix(12))
    }

    var entries: [VRHomeEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
        let filtered = VRHomeEntry.catalog.filter { item in
            let inSection: Bool
            switch section {
            case .all: inSection = item.kind != .world
            case .apps: inSection = item.kind == .native
            case .web: inSection = item.kind == .web
            case .worlds: inSection = item.kind == .world
            case .windows: inSection = false
            }
            let text = (item.title + " " + item.detail).folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            return inSection && (needle.isEmpty || text.contains(needle))
        }
        return filtered.sorted { a, b in
            if alphabetical { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            let ai = recent.firstIndex(of: a.id) ?? Int.max
            let bi = recent.firstIndex(of: b.id) ?? Int.max
            if ai != bi { return ai < bi }
            return (VRHomeEntry.catalog.firstIndex(of: a) ?? 0) < (VRHomeEntry.catalog.firstIndex(of: b) ?? 0)
        }
    }

    func pageCount(windowCount: Int = 0) -> Int {
        max(1, ((section == .windows ? windowCount : entries.count) + Self.pageSize - 1) / Self.pageSize)
    }

    func turnPage(_ delta: Int, windowCount: Int) {
        page = max(0, min(pageCount(windowCount: windowCount) - 1, page + delta))
    }

    func opened(_ id: String) {
        guard let entry = VRHomeEntry.find(id), entry.kind != .world else { return }
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recent = Array(recent.prefix(12))
        defaults.set(recent, forKey: "vros.home.recent.v48")
    }

    func togglePin(_ id: String) {
        guard let entry = VRHomeEntry.find(id), entry.kind != .world else { return }
        if pinned.contains(id) { pinned.removeAll { $0 == id } }
        else {
            if pinned.count == 4 { pinned.removeLast() }
            pinned.append(id)
        }
        defaults.set(pinned, forKey: "vros.home.pins.v48")
    }

    func show(_ section: VRHomeSection = .all) {
        self.section = section
        visible = true
        quickSettings = false
        query = ""
    }
}

/// A fixed design space keeps drawing and hit tests identical at all headset
/// aperture sizes. Letterboxing is part of the same reversible transform.
struct VRHomeCanvas {
    static let size = CGSize(width: 640, height: 420)
    let viewport: CGSize
    var scale: CGFloat { max(0.001, min(viewport.width / 640, viewport.height / 420)) }
    var origin: CGPoint {
        CGPoint(x: (viewport.width - 640 * scale) / 2,
                y: (viewport.height - 420 * scale) / 2)
    }
    func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
    func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }
}

enum VRHomeAction: Equatable {
    case app(String), pin(String), section(VRHomeSection), window(UUID)
    case library, quick, search, sort, close, page(Int)
    case camera, recenter, pointer, settings, lens, worlds, brightness(Int)
    var key: String {
        switch self {
        case let .app(id): return "app." + id
        case let .pin(id): return "pin." + id
        case let .section(section): return "section." + section.rawValue
        case let .window(id): return "window." + id.uuidString
        case let .page(delta): return "page.\(delta)"
        case let .brightness(delta): return "brightness.\(delta)"
        default: return String(describing: self)
        }
    }
}

struct VRHomeTarget: Identifiable {
    enum Style { case rail, tile, control, dock, pin }
    let action: VRHomeAction
    let rect: CGRect
    let title: String
    var detail = ""
    let symbol: String
    var color = "B6BCC6"
    var selected = false
    var style: Style = .control
    var id: String { action.key + ".\(Int(rect.minX)).\(Int(rect.minY))" }
}

@MainActor
enum VRHomeLayout {
    static let card = CGRect(x: 14, y: 12, width: 612, height: 306)
    static let dock = CGRect(x: 14, y: 338, width: 612, height: 68)

    static func targets(_ model: VRHomeLibrary, windows: [VRHomeWindow]) -> [VRHomeTarget] {
        var result = [VRHomeTarget]()
        // Dock is always available, including when the library is dismissed.
        result.append(.init(action: .quick, rect: CGRect(x: 24, y: 348, width: 88, height: 48),
                            title: "", symbol: "clock", selected: model.quickSettings, style: .dock))
        result.append(.init(action: .recenter, rect: CGRect(x: 118, y: 348, width: 46, height: 48),
                            title: "Centralizar", symbol: "scope", style: .dock))
        result.append(.init(action: .search, rect: CGRect(x: 170, y: 348, width: 46, height: 48),
                            title: "Buscar", symbol: "magnifyingglass", style: .dock))
        result.append(.init(action: .camera, rect: CGRect(x: 222, y: 348, width: 46, height: 48),
                            title: "Câmera", symbol: "viewfinder", style: .dock))
        for (index, id) in model.pinned.enumerated() {
            guard let entry = VRHomeEntry.find(id) else { continue }
            result.append(.init(action: .app(id), rect: CGRect(x: 288 + CGFloat(index) * 56, y: 348, width: 50, height: 48),
                title: entry.title, symbol: entry.symbol, color: entry.color, style: .dock))
        }
        result.append(.init(action: .library, rect: CGRect(x: 550, y: 348, width: 62, height: 48),
            title: "Biblioteca", symbol: "square.grid.2x2.fill", selected: model.visible, style: .dock))
        guard model.visible || model.quickSettings else { return result }
        result.append(.init(action: .close, rect: CGRect(x: 578, y: 22, width: 36, height: 36),
                            title: "Fechar", symbol: "xmark"))
        if model.quickSettings {
            let items: [(VRHomeAction, String, String)] = [
                (.camera, "Câmera", "viewfinder"), (.recenter, "Centralizar", "scope"),
                (.lens, "Visor", "eyeglasses"), (.pointer, "Mira", "dot.scope"),
                (.worlds, "Ambientes", "mountain.2"), (.settings, "Ajustes", "gearshape")
            ]
            for (index, item) in items.enumerated() {
                result.append(.init(action: item.0, rect: CGRect(x: 36 + CGFloat(index % 3) * 191,
                    y: 76 + CGFloat(index / 3) * 78, width: 180, height: 68),
                    title: item.1, symbol: item.2, style: .tile))
            }
            result.append(.init(action: .brightness(-1), rect: CGRect(x: 160, y: 248, width: 58, height: 44), title: "Diminuir brilho", symbol: "sun.min"))
            result.append(.init(action: .brightness(1), rect: CGRect(x: 422, y: 248, width: 58, height: 44), title: "Aumentar brilho", symbol: "sun.max"))
            return result
        }
        for (index, section) in VRHomeSection.allCases.enumerated() {
            result.append(.init(action: .section(section), rect: CGRect(x: 28, y: 80 + CGFloat(index) * 41, width: 130, height: 36),
                title: section.title, symbol: section.symbol, selected: model.section == section, style: .rail))
        }
        result.append(.init(action: .search, rect: CGRect(x: 176, y: 26, width: 258, height: 35),
            title: model.query.isEmpty ? "Pesquisar" : model.query, symbol: "magnifyingglass"))
        result.append(.init(action: .sort, rect: CGRect(x: 444, y: 26, width: 124, height: 35),
            title: model.alphabetical ? "Nome" : "Recentes", symbol: "arrow.up.arrow.down"))
        let page = min(model.page, model.pageCount(windowCount: windows.count) - 1)
        if model.section == .windows {
            for (slot, window) in windows.dropFirst(page * 6).prefix(6).enumerated() {
                result.append(.init(action: .window(window.id), rect: cell(slot), title: window.title,
                    detail: window.minimized ? "Minimizada · restaurar" : "Aberta · mostrar",
                    symbol: window.symbol, style: .tile))
            }
        } else {
            for (slot, entry) in model.entries.dropFirst(page * 6).prefix(6).enumerated() {
                let box = cell(slot)
                result.append(.init(action: .app(entry.id), rect: box, title: entry.title,
                    detail: entry.detail, symbol: entry.symbol, color: entry.color, style: .tile))
                if entry.kind != .world {
                    result.append(.init(action: .pin(entry.id), rect: CGRect(x: box.maxX - 29, y: box.minY, width: 28, height: 28),
                        title: model.pinned.contains(entry.id) ? "Desafixar" : "Fixar no dock",
                        symbol: model.pinned.contains(entry.id) ? "pin.fill" : "pin", selected: model.pinned.contains(entry.id), style: .pin))
                }
            }
        }
        if page > 0 { result.append(.init(action: .page(-1), rect: CGRect(x: 230, y: 277, width: 48, height: 30), title: "Página anterior", symbol: "chevron.left")) }
        if page + 1 < model.pageCount(windowCount: windows.count) { result.append(.init(action: .page(1), rect: CGRect(x: 506, y: 277, width: 48, height: 30), title: "Próxima página", symbol: "chevron.right")) }
        return result
    }

    static func cell(_ slot: Int) -> CGRect {
        CGRect(x: 178 + CGFloat(slot % 3) * 145, y: 78 + CGFloat(slot / 3) * 98, width: 137, height: 91)
    }

    static func hit(_ point: CGPoint, viewport: CGSize, model: VRHomeLibrary, windows: [VRHomeWindow]) -> VRHomeAction? {
        let local = VRHomeCanvas(viewport: viewport).local(point)
        return targets(model, windows: windows).reversed().first { $0.rect.contains(local) }?.action
    }

    static func blocks(_ point: CGPoint, viewport: CGSize, model: VRHomeLibrary) -> Bool {
        let local = VRHomeCanvas(viewport: viewport).local(point)
        return dock.contains(local) || ((model.visible || model.quickSettings) && card.contains(local))
    }
}
