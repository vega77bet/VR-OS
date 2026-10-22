import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AppContentView: View {
    let kind: AppKind
    @ObservedObject var settings: WorkspaceSettings
    @ObservedObject var engine: SpatialEngine
    @Binding var noteText: String
    @Binding var selectedImage: PhotosPickerItem?
    @Binding var photoData: Data?
    @Binding var importedURLs: [URL]

    var body: some View {
        Group {
            switch kind {
            case .home: home
            case .notes: notes
            case .clock: ClockContent()
            case .gallery: gallery
            case .files: files
            case .settings: preferences
            case .spaces: spaces
            }
        }
        .foregroundStyle(.white)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seu espaço, suas regras.")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Abra aplicativos pelo lançador ou fixe janelas ao seu redor. Toque em uma janela espacial para abrir o conteúdo.")
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                stat("Janelas", "\(engine.windows.count)", "square.on.square")
                stat("ARKit", engine.available ? "Ativo" : "Indisponível", "viewfinder")
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(settings.accent.color)
            Text(value).font(.system(size: 18, weight: .semibold))
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bloco de notas", systemImage: "pencil.line")
                .foregroundStyle(settings.accent.color)
            TextEditor(text: $noteText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
                .frame(minHeight: 180)
            Text("Salvo automaticamente neste iPhone.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $selectedImage, matching: .images) {
                Label("Escolher foto", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(settings.accent.color.opacity(0.23), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                emptyState("photo.on.rectangle.angled", "Escolha uma imagem da fototeca.")
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documentos importados")
                .font(.headline)
            Text("Arquivos ficam disponíveis na sessão atual.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            if importedURLs.isEmpty {
                emptyState("folder", "Use o botão Importar no topo da janela.")
            } else {
                ForEach(importedURLs, id: \.absoluteString) { url in
                    Label(url.lastPathComponent, systemImage: "doc")
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("Aparência").font(.headline)
            HStack(spacing: 13) {
                ForEach(AccentStyle.allCases) { accent in
                    Button {
                        settings.accent = accent
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if settings.accent == accent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.title)
                }
            }
            settingSlider("Distância inicial", value: $settings.distance, range: 0.7...2.4, suffix: "m")
            settingSlider("Escala das janelas", value: $settings.windowSize, range: 0.6...1.6, suffix: "×")
            settingSlider("Opacidade", value: $settings.panelOpacity, range: 0.65...1, suffix: "")
            Toggle("Mostrar rastreamento", isOn: $settings.showTracking)
            Toggle("Resposta tátil", isOn: $settings.haptics)
            Toggle("Animações", isOn: $settings.animations)
            Button("Restaurar ajustes") { settings.restoreDefaults() }
                .foregroundStyle(settings.accent.color)
                .padding(.top, 8)
        }
        .tint(settings.accent.color)
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue) + suffix)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Slider(value: value, in: range)
        }
    }

    private var spaces: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(engine.windows.count) janelas abertas")
                    .font(.headline)
                Spacer()
                Button("Fechar todas") { engine.closeAll() }
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .disabled(engine.windows.isEmpty)
            }
            if engine.windows.isEmpty {
                emptyState("square.on.square", "Nenhuma janela no espaço.")
            } else {
                ForEach(engine.windows) { window in
                    HStack(spacing: 12) {
                        IconTile(symbol: window.kind.symbol, tint: window.kind.tint, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(window.kind.title).font(.subheadline.weight(.medium))
                            Text("Escala \(String(format: "%.1f", window.scale))×")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Button { engine.select(window.id) } label: {
                            Image(systemName: engine.selectedID == window.id ? "checkmark.circle.fill" : "circle")
                        }
                        Button(role: .destructive) { engine.remove(window.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func emptyState(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(settings.accent.color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct ClockContent: View {
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let duration = elapsed + (startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
            VStack(alignment: .leading, spacing: 18) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 47, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .foregroundStyle(.white.opacity(0.6))
                Divider().overlay(.white.opacity(0.15))
                Text("Cronômetro").font(.headline)
                Text(String(format: "%02d:%02d.%01d", Int(duration) / 60, Int(duration) % 60, Int(duration * 10) % 10))
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .monospacedDigit()
                HStack {
                    Button(startedAt == nil ? "Iniciar" : "Pausar") {
                        if let start = startedAt {
                            elapsed += Date().timeIntervalSince(start)
                            startedAt = nil
                        } else {
                            startedAt = Date()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Zerar") {
                        startedAt = nil
                        elapsed = 0
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
