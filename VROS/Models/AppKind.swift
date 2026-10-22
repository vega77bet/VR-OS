import SwiftUI

enum AppKind: String, CaseIterable, Identifiable {
    case home, notes, clock, gallery, files, settings, spaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Início"
        case .notes: return "Notas"
        case .clock: return "Relógio"
        case .gallery: return "Galeria"
        case .files: return "Arquivos"
        case .settings: return "Ajustes"
        case .spaces: return "Espaços"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Seu espaço de trabalho"
        case .notes: return "Ideias em qualquer lugar"
        case .clock: return "Hora e cronômetro"
        case .gallery: return "Suas imagens"
        case .files: return "Documentos selecionados"
        case .settings: return "Personalize o sistema"
        case .spaces: return "Gerencie suas janelas"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .notes: return "note.text"
        case .clock: return "clock.fill"
        case .gallery: return "photo.on.rectangle.angled"
        case .files: return "folder.fill"
        case .settings: return "slider.horizontal.3"
        case .spaces: return "square.on.square"
        }
    }

    var tint: Color {
        switch self {
        case .home: return Color(red: 0.66, green: 0.77, blue: 1)
        case .notes: return Color(red: 1, green: 0.81, blue: 0.51)
        case .clock: return Color(red: 0.66, green: 0.89, blue: 0.82)
        case .gallery: return Color(red: 0.95, green: 0.68, blue: 0.81)
        case .files: return Color(red: 0.68, green: 0.79, blue: 1)
        case .settings: return Color(red: 0.82, green: 0.84, blue: 0.90)
        case .spaces: return Color(red: 0.78, green: 0.72, blue: 0.98)
        }
    }
}

struct SpatialWindow: Identifiable {
    let id: UUID
    let kind: AppKind
    let anchorID: UUID
    var scale: Float = 1
    let createdAt: Date = Date()
}

enum AccentStyle: String, CaseIterable, Identifiable {
    case ice, graphite, mint, amber, rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ice: return "Gelo"
        case .graphite: return "Grafite"
        case .mint: return "Menta"
        case .amber: return "Âmbar"
        case .rose: return "Rosa"
        }
    }

    var color: Color {
        switch self {
        case .ice: return Color(red: 0.67, green: 0.79, blue: 0.98)
        case .graphite: return Color(red: 0.80, green: 0.84, blue: 0.90)
        case .mint: return Color(red: 0.59, green: 0.87, blue: 0.77)
        case .amber: return Color(red: 1.0, green: 0.78, blue: 0.51)
        case .rose: return Color(red: 0.98, green: 0.70, blue: 0.78)
        }
    }

    var uiColor: UIColor { UIColor(color) }
}
