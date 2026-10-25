import Foundation
import SwiftUI

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

    static let fallback = RemoteManifest(
        schema: 1,
        version: "integrada",
        headline: "VR OS 3.1 · ESPACIAL",
        message: "Conecte à internet para buscar novos temas e janelas.",
        theme: RemoteTheme(surfaceGray: 0.19, surfaceOpacity: 0.97, dockGray: 0.19),
        templates: [
            RemoteWindowTemplate(
                id: "inicio", title: "Início", symbol: "square.grid.2x2",
                text: "Bem-vindo ao VR OS.\n"
                    + "Segure a pinça para pegar janelas.\n"
                    + "Arraste a barra inferior para ajustar o Z.",
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
        latestNativeVersion: "3.1",
        nativeReleaseURL: "https://github.com/vega77bet/VR-OS/actions"
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
              url.path.hasPrefix("/vega77bet/VR-OS/")
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

    @Published private(set) var manifest = RemoteManifest.fallback
    @Published private(set) var statusMessage = "Toque em Buscar para conferir novidades."
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    init() {
        if let cache = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode(RemoteManifest.self, from: cache),
           saved.validated {
            manifest = saved
            statusMessage = "Conteúdo salvo pronto para uso offline."
        }
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
            lastChecked = Date()
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
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
