import Foundation
import Combine

struct CinemaLibraryEntry: Codable, Identifiable {
    let id: UUID
    let filename: String
    var title: String
    var favorite: Bool
    var lastPlayed: Date
}

final class CinemaLibrary: ObservableObject {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VRMovieLibrary", isDirectory: true)
    }
    @Published private(set) var entries: [CinemaLibraryEntry] = []
    private let defaults: UserDefaults
    private let key = "vros.cinema.library.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let values = try? JSONDecoder().decode([CinemaLibraryEntry].self, from: data) {
            entries = values.filter {
                $0.filename == URL(fileURLWithPath: $0.filename).lastPathComponent &&
                FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent($0.filename).path)
            }
        }
    }

    func url(for entry: CinemaLibraryEntry) -> URL {
        Self.folder.appendingPathComponent(entry.filename)
    }

    func record(url: URL, title: String) {
        guard url.deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL else { return }
        if let index = entries.firstIndex(where: { $0.filename == url.lastPathComponent }) {
            entries[index].lastPlayed = Date()
        } else {
            entries.append(CinemaLibraryEntry(id: UUID(), filename: url.lastPathComponent,
                title: title, favorite: false, lastPlayed: Date()))
        }
        entries.sort { $0.lastPlayed > $1.lastPlayed }
        persist()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].favorite.toggle()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}
