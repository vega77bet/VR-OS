import Foundation
import Combine
import AVFoundation
import UIKit

struct CinemaLibraryEntry: Codable, Identifiable {
    let id: UUID
    let filename: String
    var title: String
    var favorite: Bool
    var lastPlayed: Date
    var mode: String? = nil
}

final class CinemaLibrary: ObservableObject {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VRMovieLibrary", isDirectory: true)
    }
    @Published private(set) var entries: [CinemaLibraryEntry] = []
    @Published private(set) var covers: [UUID: UIImage] = [:]
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
        for entry in entries { loadCover(entry) }
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
        if let entry = entries.first(where: { $0.filename == url.lastPathComponent }),
           covers[entry.id] == nil { loadCover(entry) }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].favorite.toggle()
        persist()
    }

    func saveMode(_ mode: String, for url: URL) {
        guard let index = entries.firstIndex(where: { $0.filename == url.lastPathComponent }) else { return }
        entries[index].mode = mode
        persist()
    }

    func remove(_ id: UUID) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let target = url(for: entry)
        guard target.deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: target)
        entries.removeAll { $0.id == id }
        covers.removeValue(forKey: id)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    private func loadCover(_ entry: CinemaLibraryEntry) {
        let source = url(for: entry)
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 100)
            guard let result = try? await generator.image(at: .zero) else { return }
            await MainActor.run { self.covers[entry.id] = UIImage(cgImage: result.image) }
        }
    }
}
