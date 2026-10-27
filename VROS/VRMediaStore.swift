import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import ImageIO
import PDFKit

enum VRMediaKind: String, Codable { case image, text, pdf, movie }

struct VRMediaEntry: Codable, Identifiable {
    let id: UUID
    let filename: String
    let title: String
    let kind: VRMediaKind
    let bytes: Int64
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
    @Published private(set) var image: UIImage?
    @Published private(set) var text: String?
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var pdfPage = 0
    @Published private(set) var textPages = 1
    @Published private(set) var textPage = ""
    private let folder: URL
    private var previewToken = UUID()

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VRFiles", isDirectory: true)
        if let data = try? Data(contentsOf: self.folder.appendingPathComponent("index.json")),
           let entries = try? JSONDecoder().decode([VRMediaEntry].self, from: data) {
            self.entries = entries.filter {
                Self.safeName($0.filename) && FileManager.default.fileExists(
                    atPath: self.folder.appendingPathComponent($0.filename).path)
            }
        }
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

    func open(_ entry: VRMediaEntry) async {
        let token = UUID()
        previewToken = token
        let source = url(for: entry)
        closePreview()
        previewToken = token
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
                guard previewToken == token else { return }
                guard let result = result else { throw MediaError.decode }
                image = UIImage(cgImage: result)
            case .text:
                let result = try await Task.detached { try String(contentsOf: source, encoding: .utf8) }.value
                guard previewToken == token else { return }
                text = result
                textPages = max(1, (result.count + 119) / 120)
                textPage = String(result.prefix(120))
            case .pdf:
                // PDFDocument is read on the main actor and shared between eyes.
                guard let document = PDFDocument(url: source), !document.isLocked,
                      document.pageCount > 0 else { throw MediaError.decode }
                pdf = document
                image = document.page(at: 0)?.thumbnail(of: CGSize(width: 650, height: 900), for: .mediaBox)
            case .movie: return
            }
            preview = entry
        } catch { message = error.localizedDescription }
    }

    func changePage(_ delta: Int) {
        if let pdf = pdf {
            let next = max(0, min(pdf.pageCount - 1, pdfPage + delta))
            if next != pdfPage {
                pdfPage = next
                image = pdf.page(at: next)?.thumbnail(of: CGSize(width: 650, height: 900), for: .mediaBox)
            }
        } else if text != nil {
            pdfPage = max(0, min(textPages - 1, pdfPage + delta))
            textPage = String((text ?? "").dropFirst(pdfPage * 120).prefix(120))
        }
    }

    var pageCount: Int { pdf?.pageCount ?? textPages }

    func closePreview() {
        previewToken = UUID()
        preview = nil; image = nil; text = nil; pdf = nil; pdfPage = 0
        textPages = 1; textPage = ""
    }

    func remove(_ entry: VRMediaEntry) throws {
        guard Self.safeName(entry.filename), entries.contains(where: { $0.id == entry.id }) else { return }
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
        case unsupported, size, decode
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Use imagem, PDF, texto UTF-8 ou vídeo."
            case .size: return "Limite de 40 MB para imagens/PDF e 1 MB para texto."
            case .decode: return "Não foi possível abrir este arquivo, ou ele está protegido."
            }
        }
    }
}

struct VRMediaPreview: View {
    @ObservedObject var store: VRMediaStore
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(store.preview?.title ?? "").lineLimit(1)
                Spacer(minLength: 0)
                Button("Fechar") { store.closePreview() }
            }.font(.system(size: 10, weight: .bold)).frame(height: 34)
            if let image = store.image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity)
            } else {
                Text(store.textPage).font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if store.pdf != nil || store.text != nil {
                HStack {
                    Button("Anterior") { store.changePage(-1) }
                        .disabled(store.pdfPage == 0)
                    Spacer()
                    Text("\(store.pdfPage + 1)/\(store.pageCount)").font(.system(size: 10))
                    Spacer()
                    Button("Próxima") { store.changePage(1) }
                        .disabled(store.pdfPage + 1 >= store.pageCount)
                }.font(.system(size: 10)).frame(height: 30)
            }
        }.padding(10).background(Color(white: 0.06)).foregroundStyle(.white)
    }
}
