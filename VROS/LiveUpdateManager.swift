import Foundation
import SwiftUI


/// A data-only taskbar item. The remote server can reorder or hide known
/// actions, but it cannot introduce executable behavior or arbitrary URLs.
struct RemoteTaskbarItem: Codable, Identifiable, Equatable {
    let id: String
    let action: String
    let title: String
    let icon: String
    let enabled: Bool

    var resolvedAction: VRTaskbarAction? {
        VRTaskbarAction(rawValue: action)
    }
}

/// Safe, versioned visual configuration downloaded as JSON.
struct RemoteFrontendConfiguration: Codable, Equatable {
    let schema: Int
    let accentHex: String
    let surfaceHex: String
    let taskbarOpacity: Double
    let taskbar: [RemoteTaskbarItem]

    static let fallback = RemoteFrontendConfiguration(
        schema: 1,
        accentHex: "#50DEFF",
        surfaceHex: "#1B2029",
        taskbarOpacity: 0.96,
        taskbar: [
            RemoteTaskbarItem(id: "home", action: "home", title: "Central", icon: "home", enabled: true),
            RemoteTaskbarItem(id: "apps", action: "apps", title: "Apps", icon: "more", enabled: true),
            RemoteTaskbarItem(id: "cinema", action: "cinema", title: "Cinema", icon: "cinema", enabled: true),
            RemoteTaskbarItem(id: "files", action: "files", title: "Arquivos", icon: "files", enabled: true),
            RemoteTaskbarItem(id: "photos", action: "photos", title: "Fotos", icon: "photos", enabled: true),
            RemoteTaskbarItem(id: "browser", action: "browser", title: "Navegador", icon: "browser", enabled: true),
            RemoteTaskbarItem(id: "settings", action: "settings", title: "Ajustes", icon: "settings", enabled: true),
            RemoteTaskbarItem(id: "new-window", action: "newWindow", title: "Janela", icon: "library", enabled: true)
        ]
    )

    var enabledTaskbar: [RemoteTaskbarItem] {
        taskbar.filter { $0.enabled && $0.resolvedAction != nil }
    }

    var accentColor: Color { Color(vrHex: accentHex) }
    var surfaceColor: Color { Color(vrHex: surfaceHex) }

    var validated: Bool {
        guard schema == 1,
              Self.validHex(accentHex),
              Self.validHex(surfaceHex),
              (0.82...1).contains(taskbarOpacity),
              (3...8).contains(taskbar.count),
              (3...8).contains(enabledTaskbar.count)
        else { return false }

        var ids = Set<String>()
        var actions = Set<String>()
        let allowedIcons: Set<String> = [
            "home", "more", "cinema", "files", "photos",
            "browser", "settings", "library"
        ]

        for item in taskbar {
            guard item.id.count > 0, item.id.count <= 32,
                  ids.insert(item.id).inserted,
                  item.title.count > 0, item.title.count <= 18,
                  item.title.unicodeScalars.allSatisfy({ $0.value >= 0x20 }),
                  actions.insert(item.action).inserted,
                  item.resolvedAction != nil,
                  allowedIcons.contains(item.icon)
            else { return false }
        }
        return true
    }

    private static func validHex(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 7, scalars.first?.value == 35 else { return false }
        return scalars.dropFirst().allSatisfy {
            (48...57).contains($0.value) ||
            (65...70).contains($0.value) ||
            (97...102).contains($0.value)
        }
    }
}

/// A content-only update delivered over HTTPS. It NEVER downloads or executes Swift,
/// frameworks, scripts, plug-ins, or IPA files.
struct RemoteWindowTemplate: Codable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    let text: String
    let depth: Double
}

struct RemoteTheme: Codable {
    let surfaceGray: Double
    let surfaceOpacity: Double
    let dockGray: Double
}

struct RemoteManifest: Codable {
    let schema: Int
    let version: String
    let headline: String
    let message: String
    let theme: RemoteTheme
    let templates: [RemoteWindowTemplate]
    let latestNativeVersion: String
    let nativeReleaseURL: String
    let frontend: RemoteFrontendConfiguration?

    static let fallback = RemoteManifest(
        schema: 1,
        version: "integrada",
        headline: "VR OS 4.3 · ESTÁVEL",
        message: "Janelas e Cinema com rolagem, favoritos, FOV e calibração.",
        theme: RemoteTheme(surfaceGray: 0.19, surfaceOpacity: 0.97, dockGray: 0.19),
        templates: [
            RemoteWindowTemplate(
                id: "inicio", title: "Início", symbol: "square.grid.2x2",
                text: "Bem-vindo ao VR OS.\n"
                    + "Segure a linha branca para mover uma janela.\n"
                    + "Use os botões de subir/descer ou pinça para rolar textos.\n"
                    + "No navegador, salve favoritos e use o zoom de página.",
                depth: 1.5
            ),
            RemoteWindowTemplate(
                id: "notas", title: "Notas", symbol: "note.text",
                text: "Janelas com conteúdo atualizável pela internet.\n"
                    + "ARKit fixa as posições durante a sessão.\n"
                    + "A profundidade da mão é uma estimativa.",
                depth: 1.6
            )
        ],
        latestNativeVersion: "4.3",
        nativeReleaseURL: "https://github.com/vega77bet/VR-OS/actions",
        frontend: .fallback
    )

    var validated: Bool {
        guard schema == 1,
              version.count > 0, version.count <= 40,
              headline.count > 0, headline.count <= 72,
              message.count <= 500,
              (0.07...0.42).contains(theme.surfaceGray),
              (0.75...1).contains(theme.surfaceOpacity),
              (0.07...0.42).contains(theme.dockGray),
              (1...12).contains(templates.count),
              latestNativeVersion.count <= 20,
              let url = URL(string: nativeReleaseURL),
              url.scheme == "https",
              url.host == "github.com",
              url.path.hasPrefix("/vega77bet/VR-OS/"),
              frontend.map { $0.validated } ?? true
        else { return false }

        var ids = Set<String>()
        for template in templates {
            guard template.id.count > 0, template.id.count <= 40,
                  ids.insert(template.id).inserted,
                  template.title.count > 0, template.title.count <= 40,
                  template.text.count <= 750,
                  template.symbol.count > 0, template.symbol.count <= 45,
                  template.symbol.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }),
                  (0.65...4).contains(template.depth)
            else { return false }
        }
        return true
    }
}

/// Hosts just a JSON manifest at a public Vercel URL, separate from our private
/// GitHub repository. There is no password, API token or executable payload.
@MainActor
final class LiveUpdateManager: ObservableObject {
    static let endpoint = URL(string: "https://vr-os-content-updates.vercel.app/manifest.json")!
    private static let cacheKey = "vros.liveManifest.v1"
    private static let lastCheckedKey = "vros.liveManifest.lastChecked.v1"
    private static let minimumCheckInterval: TimeInterval = 15 * 60

    @Published private(set) var manifest = RemoteManifest.fallback
    @Published private(set) var frontend = RemoteFrontendConfiguration.fallback
    @Published private(set) var statusMessage = "Toque em Buscar para conferir novidades."
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    init() {
        let timestamp = UserDefaults.standard.double(forKey: Self.lastCheckedKey)
        if timestamp.isFinite && timestamp > 0 {
            lastChecked = Date(timeIntervalSince1970: timestamp)
        }
        if let cache = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode(RemoteManifest.self, from: cache),
           saved.validated {
            manifest = saved
            frontend = saved.frontend ?? .fallback
            statusMessage = "Conteúdo salvo pronto para uso offline."
        }
    }

    func checkIfStale() async {
        if let lastChecked,
           Date().timeIntervalSince(lastChecked) < Self.minimumCheckInterval {
            return
        }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = "Buscando atualizações…"
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                throw UpdateError.server
            }
            guard !data.isEmpty, data.count <= 64_000,
                  let remote = try? JSONDecoder().decode(RemoteManifest.self, from: data),
                  remote.validated else {
                throw UpdateError.invalidManifest
            }
            let previousVersion = manifest.version
            manifest = remote
            frontend = remote.frontend ?? .fallback
            lastChecked = Date()
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            UserDefaults.standard.set(lastChecked?.timeIntervalSince1970 ?? 0,
                                      forKey: Self.lastCheckedKey)
            statusMessage = previousVersion == remote.version
                ? "Tudo atualizado · \(remote.version)"
                : "Novidades aplicadas! · \(remote.version)"
        } catch {
            statusMessage = "Sem conexão ou atualização indisponível. Usando dados salvos."
        }
    }

    private enum UpdateError: Error {
        case server
        case invalidManifest
    }
}
