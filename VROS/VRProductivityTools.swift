import SwiftUI
import UniformTypeIdentifiers

enum VRUtilityDialog {
    case search, rename(UUID), restore(VRSettingsBackup), message(String)
    var title: String {
        switch self {
        case .search: return "Buscar arquivos"
        case .rename: return "Renomear cópia"
        case .restore: return "Restaurar ajustes?"
        case .message: return "VR-OS"
        }
    }
}

@MainActor
final class VRProductivityTools: ObservableObject {
    @Published var dialog: VRUtilityDialog?
    @Published var draft = ""
    @Published var exporting = false
    @Published var document = VRExportDocument()
    var contentType: UTType = .json
    var filename = "VR-OS-ajustes"
    var importingBackup = false

    func export(_ data: Data, type: UTType, filename: String) {
        document = VRExportDocument(data: data)
        contentType = type; self.filename = filename; exporting = true
    }

    func readBackup(_ url: URL) async {
        do {
            let backup = try await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? 65_537) <= 65_536 else {
                    throw VRSettingsBackup.BackupError.invalid
                }
                return try VRSettingsBackup.decode(Data(contentsOf: url))
            }.value
            dialog = .restore(backup)
        } catch { dialog = .message(error.localizedDescription) }
    }
}

/// Native keyboard/export dialogs appear once; library/preview remain binocular.
struct VRProductivityDialogs: ViewModifier {
    @ObservedObject var tools: VRProductivityTools
    @ObservedObject var media: VRMediaStore
    let settings: VRSettingsSession
    let onRestore: (Int) -> Void
    let onLibraryChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $tools.exporting, document: tools.document,
                          contentType: tools.contentType, defaultFilename: tools.filename) { result in
                if case let .failure(error) = result,
                   (error as NSError).code != NSUserCancelledError {
                    tools.dialog = .message(error.localizedDescription)
                }
            }
            .alert(tools.dialog?.title ?? "VR-OS", isPresented: Binding(
                get: { tools.dialog != nil }, set: { if !$0 { tools.dialog = nil } }), presenting: tools.dialog) { dialog in
                switch dialog {
                case .search:
                    TextField("Nome do arquivo", text: $tools.draft)
                    Button("Buscar") { media.query = tools.draft; onLibraryChanged() }
                    Button("Cancelar", role: .cancel) {}
                case let .rename(id):
                    TextField("Nome", text: $tools.draft)
                    Button("Salvar") {
                        do { try media.rename(id, to: tools.draft); onLibraryChanged() }
                        catch { showAfterDismiss(error.localizedDescription) }
                    }
                    Button("Cancelar", role: .cancel) {}
                case let .restore(backup):
                    Button("Restaurar", role: .destructive) {
                        do { onRestore(try backup.apply(to: settings)) }
                        catch { showAfterDismiss(error.localizedDescription) }
                    }
                    Button("Cancelar", role: .cancel) {}
                case .message: Button("OK", role: .cancel) {}
                }
            } message: { dialog in
                switch dialog {
                case .restore: Text("Substitui visor, gestos, aparência e preferências de câmera/Cinema. Arquivos e contas são preservados.")
                case let .message(message): Text(message)
                case .search: Text("A busca ignora maiúsculas e acentos. Deixe vazio para mostrar tudo.")
                case .rename: Text("Altera apenas o nome exibido da cópia local.")
                }
            }
    }

    private func showAfterDismiss(_ message: String) {
        DispatchQueue.main.async { tools.dialog = .message(message) }
    }
}
