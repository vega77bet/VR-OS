import Foundation
import CoreGraphics

/// Stable, platform-independent definition of the Settings app's navigation
/// and data. UIKit rendering and Vision interaction use these same row IDs.
enum VRSettingsPage: String, CaseIterable {
    case home, visor, camera, hands, windows, appearance, cinema, internet, general, about

    var title: String {
        switch self {
        case .home: return "Ajustes"
        case .visor: return "Visor e lentes"
        case .camera: return "Câmera"
        case .hands: return "Mãos e gestos"
        case .windows: return "Janelas"
        case .appearance: return "Aparência"
        case .cinema: return "Cinema"
        case .internet: return "Internet e apps"
        case .general: return "Geral"
        case .about: return "Sobre o VR-OS"
        }
    }

    var icon: String {
        switch self {
        case .home: return "gearshape.fill"
        case .visor: return "viewfinder"
        case .camera: return "camera.fill"
        case .hands: return "hand.draw.fill"
        case .windows: return "square.on.square"
        case .appearance: return "paintpalette.fill"
        case .cinema: return "film.fill"
        case .internet: return "globe"
        case .general: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }

    var symbolGray: Double {
        switch self {
        case .home: return 0.48
        case .visor: return 0.54
        case .camera: return 0.38
        case .hands: return 0.58
        case .windows: return 0.43
        case .appearance: return 0.60
        case .cinema: return 0.34
        case .internet: return 0.52
        case .general: return 0.41
        case .about: return 0.63
        }
    }
}

enum VRSettingsRowKind: Equatable {
    case navigate(VRSettingsPage)
    case toggle
    case stepper
    case slider
    case choice
    case action
    case information
}

struct VRSettingsRow: Equatable {
    let id: String
    let title: String
    var subtitle: String = ""
    var symbol: String = ""
    let kind: VRSettingsRowKind

    static func nav(_ page: VRSettingsPage, hint: String = "") -> VRSettingsRow {
        VRSettingsRow(id: "open.\(page.rawValue)", title: page.title,
                      subtitle: hint, symbol: page.icon, kind: .navigate(page))
    }
}

struct VRSettingsSection {
    let title: String
    let rows: [VRSettingsRow]
}

/// Source of truth for ALL table section, row, page and search positions.
enum VRSettingsCatalog {
    static let categories: [VRSettingsPage] = [
        .visor, .camera, .hands, .windows, .appearance,
        .cinema, .internet, .general, .about
    ]

    static func sections(for page: VRSettingsPage, search: String = "")
        -> [VRSettingsSection] {
        if page == .home {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty { return searchResults(query) }
            return [
                VRSettingsSection(title: "", rows: [
                    VRSettingsRow(id: "profile.about", title: "VR-OS",
                                  subtitle: "Preferências do ambiente virtual",
                                  symbol: "gearshape.fill", kind: .navigate(.about))
                ]),
                VRSettingsSection(title: "EXIBIÇÃO E CONTROLE", rows: [
                    .nav(.visor, hint: "Lentes, tamanho e IPD visual"),
                    .nav(.camera, hint: "ARKit e ultrawide 0,5x"),
                    .nav(.hands, hint: "Cursor, esqueleto e pinça"),
                    .nav(.windows, hint: "Tamanho e distância das janelas"),
                    .nav(.appearance, hint: "Temas e barra de status")
                ]),
                VRSettingsSection(title: "APLICATIVOS", rows: [
                    .nav(.cinema, hint: "Campo de visão e reprodução"),
                    .nav(.internet, hint: "Zoom e favoritos")
                ]),
                VRSettingsSection(title: "SISTEMA", rows: [
                    .nav(.general, hint: "Restaurar preferências"),
                    .nav(.about, hint: "Versão e privacidade")
                ])
            ]
        }
        switch page {
        case .home: return []
        case .visor:
            return [
                group("PERFIL DO VISOR", [
                    choice("visor.reference", "Referência", "Blocos curvos como na imagem", "rectangle.split.2x1"),
                    choice("visor.wide", "VR Box +", "Mais área útil nas lentes", "viewfinder"),
                    choice("visor.compact", "Compacto", "Aberturas menores", "square.dashed")
                ]),
                group("CALIBRAÇÃO", [
                    step("visor.size", "Tamanho dos olhos", "Escala das duas aberturas"),
                    step("visor.ipd", "Distância entre olhos", "Ajuste visual, não IPD físico"),
                    step("visor.height", "Altura", "Subir e descer os dois blocos"),
                    step("visor.zoom", "Zoom digital", "Mais zoom recorta a câmera"),
                    step("visor.curve", "Curvatura", "Máscara das bordas do visor")
                ]),
                group("", [
                    action("visor.reset", "Restaurar visor", "Voltar ao perfil Referência", "arrow.counterclockwise")
                ])
            ]
        case .camera:
            return [
                group("CAPTURA", [
                    toggle("camera.ultra", "Lente 0,5x real", "Usa a ultrawide física do iPhone"),
                    toggle("camera.full", "Mostrar imagem inteira", "Pode deixar barras pretas nos olhos"),
                    toggle("camera.invert", "Inverter movimento 3DoF", "Somente no modo 0,5x")
                ]),
                group("RASTREAMENTO", [
                    info("camera.info", "ARKit e 0,5x", "ARKit oferece 6DoF; ultrawide usa Vision e rotação 3DoF")
                ])
            ]
        case .hands:
            return [
                group("VISIBILIDADE", [
                    toggle("hands.skeleton", "Mostrar esqueleto", "Desenhar articulações detectadas"),
                    toggle("hands.cursor", "Mostrar cursor da mão", "Indicador da mão quando a câmera está disponível"),
                    step("hands.cursorSize", "Tamanho do cursor", "Círculo usado para apontar")
                ]),
                group("CONTROLE POR ALVO", [
                    toggle("hands.dwell", "Alvo por permanência", "Clique deixando o alvo parado sobre um botão"),
                    slide("hands.dwellDelay", "Tempo para clicar", "Tempo que o alvo precisa permanecer parado"),
                    action("hands.recenter", "Recentralizar alvo", "Voltar o alvo para o centro do visor", "scope")
                ]),
                group("RECONHECIMENTO", [
                    slide("hands.sensitivity", "Sensibilidade da pinça", "Ajusta o limiar Vision quando a câmera está disponível"),
                    info("hands.info", "Entrada alternativa", "O alvo funciona sem câmera; a pinça exige luz e câmera traseira")
                ])
            ]
        case .windows:
            return [
                group("PADRÃO DAS JANELAS", [
                    slide("windows.opacity", "Opacidade", "Fundo dos painéis da Home"),
                    step("windows.depth", "Distância inicial", "Distância das novas janelas"),
                    action("windows.center", "Centralizar janelas", "Trazer painéis para a frente", "scope")
                ])
            ]
        case .appearance:
            return [
                group("TEMA", [
                    choice("theme.0", "Grafite", "Câmera e tons de cinza", "circle.lefthalf.filled"),
                    choice("theme.1", "Cosmos", "Ambiente estrelado", "moon.stars.fill"),
                    choice("theme.2", "Aurora", "Luzes do norte", "sparkles"),
                    choice("theme.3", "Synthwave", "Grade retrofuturista", "waveform.path")
                ]),
                group("INTERFACE", [
                    toggle("appearance.hud", "Mostrar barra de status", "Versão, relógio e câmera"),
                    toggle("appearance.motion", "Reduzir animações", "Suavização do novo cursor"),
                    toggle("appearance.text", "Texto maior", "Aumenta os textos das linhas dos Ajustes")
                ])
            ]
        case .cinema:
            return [
                group("CÂMERA DO CINEMA", [
                    slide("cinema.fov", "Campo de visão", "Ângulo virtual do Cinema"),
                    toggle("cinema.invert", "Inverter direção do movimento", "Calibração da cabeça"),
                    toggle("cinema.immersive", "Tela imersiva", "Tela de cinema maior"),
                    toggle("cinema.eyes", "Trocar lado dos olhos", "Inverte a ordem 3D da imagem")
                ]),
                group("REPRODUÇÃO", [
                    toggle("cinema.autoControls", "Ocultar controles ao reproduzir", "Reduz distrações durante o filme")
                ])
            ]
        case .internet:
            return [
                group("NAVEGADOR", [
                    slide("web.zoom", "Tamanho das páginas", "Zoom das janelas web"),
                    action("web.clear", "Limpar favoritos", "Dois toques para confirmar", "trash"),
                    info("web.info", "Sites protegidos", "Streaming com DRM pode exigir Safari")
                ])
            ]
        case .general:
            return [
                group("PREFERÊNCIAS", [
                    action("general.reset", "Restaurar ajustes do VR-OS",
                           "Dois toques para confirmar. Não apaga arquivos.", "arrow.counterclockwise"),
                    info("general.storage", "Armazenamento local", "Preferências guardadas no iPhone")
                ]),
                group("DISPOSITIVO", [
                    info("general.hardware", "Compatibilidade",
                         "iPhone com ARKit, câmera e sensores de movimento")
                ])
            ]
        case .about:
            return [
                group("APLICATIVO", [
                    info("about.name", "Nome", "VR-OS"),
                    info("about.version", "Versão", installedVersion()),
                    info("about.source", "Projeto", "Aplicativo nativo Swift para iPhone")
                ]),
                group("PRIVACIDADE", [
                    info("about.privacy", "Câmera e mãos",
                         "Vision processa os quadros no próprio aparelho"),
                    info("about.spatial", "Precisão",
                         "Modo 0,5x não possui rastreamento 6DoF do ARKit")
                ])
            ]
        }
    }

    private static func installedVersion() -> String {
        // Read the signed/installed bundle, not a stale hardcoded HUD value.
        let dictionary = Bundle.main.infoDictionary ?? [:]
        let version = dictionary["CFBundleShortVersionString"] as? String
            ?? "4.7.0"
        let build = dictionary["CFBundleVersion"] as? String ?? "21"
        return "\(version) · build \(build)"
    }

    private static func searchResults(_ query: String) -> [VRSettingsSection] {
        let cleaned = query.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                    locale: Locale(identifier: "pt_BR"))
        let matches = categories.compactMap { page -> VRSettingsRow? in
            let name = page.title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                           locale: Locale(identifier: "pt_BR"))
            let children = sections(for: page)
                .flatMap(\.rows)
                .map { "\($0.title) \($0.subtitle)" }
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "pt_BR"))
            return name.contains(cleaned) || children.contains(cleaned)
                ? .nav(page, hint: "Abrir \(page.title)") : nil
        }
        return matches.isEmpty
            ? [group("BUSCA", [info("search.empty", "Nenhum resultado",
                                    "Tente outro termo")])]
            : [group("RESULTADOS", matches)]
    }

    private static func group(_ title: String, _ rows: [VRSettingsRow])
        -> VRSettingsSection {
        VRSettingsSection(title: title, rows: rows)
    }
    private static func toggle(_ id: String, _ title: String, _ subtitle: String)
        -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle, kind: .toggle)
    }
    private static func step(_ id: String, _ title: String, _ subtitle: String)
        -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle, kind: .stepper)
    }
    private static func slide(_ id: String, _ title: String, _ subtitle: String)
        -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle, kind: .slider)
    }
    private static func choice(_ id: String, _ title: String, _ subtitle: String,
                               _ symbol: String) -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle,
                      symbol: symbol, kind: .choice)
    }
    private static func action(_ id: String, _ title: String, _ subtitle: String,
                               _ symbol: String) -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle,
                      symbol: symbol, kind: .action)
    }
    private static func info(_ id: String, _ title: String, _ subtitle: String)
        -> VRSettingsRow {
        VRSettingsRow(id: id, title: title, subtitle: subtitle,
                      kind: .information)
    }
}

