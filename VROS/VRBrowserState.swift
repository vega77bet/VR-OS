import Foundation

struct VRBrowserTab: Identifiable, Equatable, Codable {
    let id: UUID
    var url: URL
    init(url: URL) { id = UUID(); self.url = url }
}

struct VRBrowserSnapshot: Codable {
    var tabs: [VRBrowserTab]
    var active: UUID
}

enum VRBrowserURL {
    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty &&
            url.user == nil && url.password == nil
    }
    static func resolve(_ input: String) -> URL? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if input.contains("://") {
            guard let url = URL(string: input),
                  isAllowed(url) else { return nil }
            return url
        }
        if input.contains(":") && !input.contains(".") { return nil }
        if input.contains(" ") || !input.contains(".") {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: input)]
            return components?.url
        }
        return resolve("https://" + input)
    }
}
