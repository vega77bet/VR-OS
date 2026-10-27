import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import ImageIO
import PDFKit
import CoreText

enum VRMediaKind: String, Codable { case image, text, pdf, movie }

struct VRMediaEntry: Codable, Identifiable {
    let id: UUID
    let filename: String
    var title: String
    let kind: VRMediaKind
    let bytes: Int64
    var favorite: Bool? = nil
    /// Text: UTF-16 offset. PDF: zero-based page. Optional for V36 indexes.
    var readingPosition: Int? = nil
    var readerSize: Int? = nil
}

struct VRPickedImage: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let ext = received.file.pathExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: url)
            return VRPickedImage(url: url)
        }
    }
}

@MainActor
final class VRMediaStore: ObservableObject {
    @Published private(set) var entries: [VRMediaEntry] = []
    @Published var message: String?
    @Published private(set) var importing = false
    @Published private(set) var preview: VRMediaEntry?
    @Published private(set) var loadingPreview = false
    @Published private(set) var image: UIImage?
    @Published private(set) var text: String?
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var pdfPage = 0
    @Published private(set) var textPages = 1
    @Published private(set) var textPage = ""
    @Published var query = ""
    @Published var favoritesOnly = false
    @Published var sort: VRMediaSort = .recent
    @Published var kindFilter: VRMediaKind?
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var quarterTurns = 0
    @Published private(set) var pan = CGSize.zero
    @Published private(set) var readerSize = 12
    private var chunks: [String] = []
    private var chunkOffsets: [Int] = []
    private var readingViewport = CGSize(width: 200, height: 110)
    private var gallery: [UUID] = []
    private let folder: URL
    private var previewToken = UUID()

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VRFiles", isDirectory: true)
        if let data = try? Data(contentsOf: self.folder.appendingPathComponent("index.json")),
           let entries = try? JSONDecoder().decode([VRMediaEntry].self, from: data) {
            self.entries = entries.filter {
                Self.safeName($0.filename) && $0.bytes >= 0 && FileManager.default.fileExists(
                    atPath: self.folder.appendingPathComponent($0.filename).path)
            }
        }
    }

    func visibleEntries(photosOnly: Bool) -> [VRMediaEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = entries.filter {
            (!photosOnly || $0.kind == .image) &&
            (kindFilter == nil || $0.kind == kindFilter) &&
            (!favoritesOnly || $0.favorite == true) &&
            (needle.isEmpty || $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        switch sort {
        case .recent: return values
        case .name: return values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size: return values.sorted { $0.bytes > $1.bytes }
        }
    }

    func toggleFavorite(_ id: UUID) throws {
        try edit(id) { $0.favorite = !($0.favorite ?? false) }
    }

    func rename(_ id: UUID, to title: String) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !name.contains("/"), !name.contains("\\"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw MediaError.name }
        try edit(id) { $0.title = name }
        if preview?.id == id { preview = entries.first { $0.id == id } }
    }

    private func edit(_ id: UUID, _ change: (inout VRMediaEntry) -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let previous = entries
        change(&entries[index])
        do { try persist() } catch { entries = previous; throw error }
    }

    func resetFilters() {
        query = ""; favoritesOnly = false; sort = .recent; kindFilter = nil
    }

    nonisolated static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." &&
            !name.contains("/") && !name.contains("\\")
    }

    nonisolated static func kind(for url: URL) -> VRMediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .plainText) { return .text }
        if type.conforms(to: .movie) { return .movie }
        return nil
    }

    func url(for entry: VRMediaEntry) -> URL { folder.appendingPathComponent(entry.filename) }

    func importFile(_ source: URL, deleteTemporarySource: Bool = false) async {
        guard !importing else {
            if deleteTemporarySource { try? FileManager.default.removeItem(at: source) }
            return
        }
        importing = true
        defer { importing = false }
        let folder = self.folder
        do {
            let entry = try await Task.detached(priority: .userInitiated) {
                let access = source.startAccessingSecurityScopedResource()
                defer {
                    if access { source.stopAccessingSecurityScopedResource() }
                    if deleteTemporarySource { try? FileManager.default.removeItem(at: source) }
                }
                guard let kind = Self.kind(for: source) else { throw MediaError.unsupported }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { throw MediaError.unsupported }
                let bytes = Int64(values.fileSize ?? 0)
                // Video copies are streamed by FileManager; preview formats are bounded.
                guard bytes > 0, kind == .movie || bytes <= 40_000_000 else { throw MediaError.size }
                if kind == .text && bytes > 1_000_000 { throw MediaError.size }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let filename = UUID().uuidString + "." + source.pathExtension.lowercased()
                let destination = folder.appendingPathComponent(filename)
                do { try FileManager.default.copyItem(at: source, to: destination) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
                return VRMediaEntry(id: UUID(), filename: filename,
                    title: source.lastPathComponent, kind: kind, bytes: bytes)
            }.value
            entries.insert(entry, at: 0)
            do { try persist() }
            catch {
                entries.removeAll { $0.id == entry.id }
                try? FileManager.default.removeItem(at: url(for: entry))
                throw error
            }
            message = "Cópia importada; o original foi preservado"
        } catch { message = error.localizedDescription }
    }

    func open(_ requested: VRMediaEntry, gallery ids: [UUID] = []) async {
        guard let entry = entries.first(where: { $0.id == requested.id }), Self.safeName(entry.filename) else { return }
        let token = UUID()
        previewToken = token
        let source = url(for: entry)
        closePreview()
        previewToken = token
        loadingPreview = true
        defer { if previewToken == token { loadingPreview = false } }
        gallery = ids
        readerSize = max(10, min(16, entry.readerSize ?? 12))
        do {
            switch entry.kind {
            case .image:
                let result = await Task.detached {
                    guard let source = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                    ] as CFDictionary)
                }.value
                guard previewToken == token, entries.contains(where: { $0.id == entry.id }) else { return }
                guard let result = result else { throw MediaError.decode }
                image = UIImage(cgImage: result)
            case .text:
                let result = try await Task.detached { try String(contentsOf: source, encoding: .utf8) }.value
                guard previewToken == token, entries.contains(where: { $0.id == entry.id }) else { return }
                text = result
                try paginateText(position: entry.readingPosition ?? 0)
            case .pdf:
                // PDFDocument is read on the main actor and shared between eyes.
                guard let document = PDFDocument(url: source), !document.isLocked,
                      document.pageCount > 0 else { throw MediaError.decode }
                pdf = document
                pdfPage = max(0, min(document.pageCount - 1, entry.readingPosition ?? 0))
                image = document.page(at: pdfPage)?.thumbnail(of: CGSize(width: 650, height: 900), for: .mediaBox)
            case .movie: return
            }
            preview = entry
        } catch { if previewToken == token { message = error.localizedDescription } }
    }

    private func paginateText(position: Int) throws {
        let value = text ?? ""
        let string = value as NSString
        let attributed = NSAttributedString(string: value, attributes: [
            .font: UIFont.systemFont(ofSize: CGFloat(readerSize))
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: readingViewport), transform: nil)
        var pages: [String] = []
        var offsets: [Int] = []
        var offset = 0
        while offset < string.length {
            guard pages.count < 10_000 else { throw MediaError.layout }
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw MediaError.layout }
            pages.append(string.substring(with: NSRange(location: offset, length: visible.length)))
            offsets.append(offset)
            offset += visible.length
        }
        chunks = pages.isEmpty ? [""] : pages
        chunkOffsets = offsets.isEmpty ? [0] : offsets
        textPages = chunks.count
        pdfPage = chunkOffsets.lastIndex(where: { $0 <= max(0, position) }) ?? 0
        textPage = chunks[pdfPage]
    }

    func adjustReaderSize(_ delta: Int) {
        guard text != nil else { return }
        let position = chunkOffsets.indices.contains(pdfPage) ? chunkOffsets[pdfPage] : 0
        let previous = readerSize
        readerSize = max(10, min(16, readerSize + max(-6, min(6, delta))))
        do { try paginateText(position: position) }
        catch { readerSize = previous; message = error.localizedDescription; return }
        saveReadingPosition()
    }

    func configureReadingViewport(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite else { return }
        // Reserve a little space for SwiftUI's text rendering metrics.
        let next = CGSize(width: max(60, size.width - 4), height: max(40, size.height - 8))
        guard next != readingViewport else { return }
        let previous = readingViewport
        readingViewport = next
        if text != nil {
            let position = chunkOffsets.indices.contains(pdfPage) ? chunkOffsets[pdfPage] : 0
            do { try paginateText(position: position); saveReadingPosition() }
            catch { readingViewport = previous; message = error.localizedDescription }
        }
    }

    private func saveReadingPosition() {
        guard let entry = preview, entry.kind == .pdf || entry.kind == .text else { return }
        let position = text != nil && chunkOffsets.indices.contains(pdfPage) ? chunkOffsets[pdfPage] : pdfPage
        do { try edit(entry.id) { $0.readingPosition = position; $0.readerSize = readerSize } }
        catch { message = "Não foi possível salvar a posição: " + error.localizedDescription }
    }

    func setZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        let next = max(1, min(4, value))
        let ratio = zoom > 1 ? (next - 1) / (zoom - 1) : 0
        pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
        zoom = next
        if zoom == 1 { pan = .zero }
    }

    func moveImage(by delta: CGSize, viewport: CGSize) {
        guard delta.width.isFinite, delta.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite, zoom > 1 else { return }
        let x = max(0, viewport.width * (zoom - 1) / 2)
        let y = max(0, viewport.height * (zoom - 1) / 2)
        pan = CGSize(width: max(-x, min(x, pan.width + delta.width)),
                     height: max(-y, min(y, pan.height + delta.height)))
    }

    func rotateImage() { quarterTurns = (quarterTurns + 1) % 4; pan = .zero }
    func resetImage() { zoom = 1; quarterTurns = 0; pan = .zero }

    var galleryPosition: String {
        guard let id = preview?.id, let index = gallery.firstIndex(of: id) else { return "Foto" }
        return "\(index + 1)/\(gallery.count)"
    }

    func browsePhoto(_ delta: Int) async {
        guard let id = preview?.id else { return }
        let ids = gallery.filter { id in entries.contains { $0.id == id && $0.kind == .image } }
        guard let index = ids.firstIndex(of: id) else { return }
        let next = max(0, min(ids.count - 1, index + max(-1, min(1, delta))))
        guard next != index, let entry = entries.first(where: { $0.id == ids[next] }) else { return }
        await open(entry, gallery: ids)
    }

    func changePage(_ delta: Int) {
        if let pdf = pdf {
            let next = max(0, min(pdf.pageCount - 1, pdfPage + max(-pdf.pageCount, min(pdf.pageCount, delta))))
            if next != pdfPage {
                pdfPage = next
                image = pdf.page(at: next)?.thumbnail(of: CGSize(width: 650, height: 900), for: .mediaBox)
            }
        } else if text != nil {
            pdfPage = max(0, min(textPages - 1, pdfPage + max(-textPages, min(textPages, delta))))
            textPage = chunks[pdfPage]
        }
        saveReadingPosition()
    }

    var pageCount: Int { pdf?.pageCount ?? textPages }

    func closePreview() {
        previewToken = UUID()
        loadingPreview = false
        preview = nil; image = nil; text = nil; pdf = nil; pdfPage = 0
        textPages = 1; textPage = ""
        chunks = []; chunkOffsets = []; gallery = []; resetImage()
    }

    func remove(_ requested: VRMediaEntry) throws {
        guard let entry = entries.first(where: { $0.id == requested.id }), Self.safeName(entry.filename) else { return }
        // Commit metadata first; roll back it if the one owned copy cannot be removed.
        let previous = entries
        entries.removeAll { $0.id == entry.id }
        do {
            try persist()
            try FileManager.default.removeItem(at: url(for: entry))
        } catch { entries = previous; try? persist(); throw error }
        if preview?.id == entry.id { closePreview() }
    }

    private func persist() throws {
        try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("index.json"), options: .atomic)
    }

    enum MediaError: LocalizedError {
        case unsupported, size, decode, name, layout
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Use imagem, PDF, texto UTF-8 ou vídeo."
            case .size: return "Limite de 40 MB para imagens/PDF e 1 MB para texto."
            case .decode: return "Não foi possível abrir este arquivo, ou ele está protegido."
            case .name: return "Use um nome de 1 a 120 caracteres, sem barras ou quebras de linha."
            case .layout: return "O texto excede o limite de 10.000 páginas neste visor."
            }
        }
    }
}

enum VRMediaSort: Int, CaseIterable {
    case recent, name, size
    var title: String { ["Recentes", "Nome", "Tamanho"][rawValue] }
}
