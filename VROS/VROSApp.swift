import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main
struct VROSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = SpatialEngine()
    @StateObject private var settings = WorkspaceSettings()

    @AppStorage("vros.notes") private var noteText = ""
    @State private var selectedImage: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var importedURLs: [URL] = []
    @State private var showingLauncher = false
    @State private var showingControls = false
    @State private var activeApp: AppKind?
    @State private var showingImporter = false
    @State private var showWelcome = true

    var body: some View {
        ZStack {
            ARSurface(engine: engine)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.10).ignoresSafeArea())

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)

                if showWelcome && engine.windows.isEmpty && activeApp == nil && !showingLauncher {
                    welcome
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if let app = activeApp {
                    appWindow(app)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showingLauncher {
                    launcher
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showingControls {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 14)
                dock
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 13)
        }
        .tint(settings.accent.color)
        .animation(settings.animations ? .spring(response: 0.36, dampingFraction: 0.86) : nil, value: activeApp)
        .animation(settings.animations ? .spring(response: 0.36, dampingFraction: 0.86) : nil, value: showingLauncher)
        .animation(settings.animations ? .spring(response: 0.36, dampingFraction: 0.86) : nil, value: showingControls)
        .onAppear { engine.settings = settings }
        .onReceive(NotificationCenter.default.publisher(for: .vrosOpenApp)) { notification in
            guard let raw = notification.object as? String, let kind = AppKind(rawValue: raw) else { return }
            open(kind)
        }
        .onChange(of: selectedImage) { item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                await MainActor.run { photoData = data }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importedURLs.append(contentsOf: urls)
        }
    }

    private var topBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(settings.accent.color)
                Text("VR OS")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("1.0")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 15)
            .frame(height: 43)
            .glassPanel(radius: 22)

            Spacer()

            if settings.showTracking {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.tracking == "Rastreamento ativo" ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(engine.tracking)
                        .lineLimit(1)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 12)
                .frame(height: 43)
                .glassPanel(radius: 22)
                .frame(maxWidth: 174)
            }

            Button {
                showingControls.toggle()
                showingLauncher = false
                activeApp = nil
                showWelcome = false
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 43, height: 43)
                    .glassPanel(radius: 22)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Seu espaço começa aqui.")
                .font(.system(size: 29, weight: .semibold, design: .rounded))
            Text("Abra o menu para escolher um aplicativo ou crie uma janela no ambiente.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 10) {
                Button {
                    showingLauncher = true
                    showWelcome = false
                } label: {
                    Label("Aplicativos", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    engine.add(.home)
                    showWelcome = false
                } label: {
                    Label("Criar janela", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 5)
        }
        .padding(22)
        .glassPanel()
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aplicativos").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Escolha o que abrir no espaço")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                closeButton { showingLauncher = false }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                ForEach(AppKind.allCases) { kind in
                    Button { open(kind) } label: {
                        VStack(spacing: 9) {
                            IconTile(symbol: kind.symbol, tint: kind.tint, size: 57)
                            Text(kind.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(22)
        .glassPanel()
    }

    private func appWindow(_ kind: AppKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                IconTile(symbol: kind.symbol, tint: kind.tint, size: 43)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                if kind == .files {
                    Button { showingImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("Importar arquivo")
                }
                Button {
                    engine.add(kind)
                    activeApp = nil
                } label: {
                    Image(systemName: "pin")
                        .font(.system(size: 16))
                }
                .accessibilityLabel("Fixar janela no ambiente")
                closeButton { activeApp = nil }
            }
            .padding(.bottom, 16)

            ScrollView {
                AppContentView(
                    kind: kind,
                    settings: settings,
                    engine: engine,
                    noteText: $noteText,
                    selectedImage: $selectedImage,
                    photoData: $photoData,
                    importedURLs: $importedURLs
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 390)
        }
        .padding(20)
        .glassPanel()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Central de controle")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                closeButton { showingControls = false }
            }

            HStack(spacing: 12) {
                controlButton("Recentrar", "viewfinder") {
                    engine.recenter()
                    showingControls = false
                }
                controlButton("Organizar", "square.grid.2x2") {
                    engine.recenter()
                    showingControls = false
                }
                controlButton("Fechar tudo", "xmark.rectangle") {
                    engine.closeAll()
                    showingControls = false
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Distância")
                    Spacer()
                    Text(String(format: "%.2f m", settings.distance))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.caption)
                Slider(value: $settings.distance, in: 0.7...2.4)
            }

            Button {
                open(.settings)
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Todos os ajustes")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(21)
        .glassPanel()
    }

    private func controlButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 11)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 75)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }

    private var dock: some View {
        HStack(spacing: 3) {
            DockItem(symbol: "house.fill", title: "Início", active: activeApp == .home) { open(.home) }
            DockItem(symbol: "square.grid.2x2.fill", title: "Apps", active: showingLauncher) {
                showingLauncher.toggle()
                activeApp = nil
                showingControls = false
                showWelcome = false
            }
            DockItem(symbol: "plus.app.fill", title: "Nova", active: false) {
                engine.add(.home)
                activeApp = nil
                showingLauncher = false
                showingControls = false
                showWelcome = false
            }
            DockItem(symbol: "square.on.square", title: "Janelas", active: activeApp == .spaces) { open(.spaces) }
            DockItem(symbol: "gearshape.fill", title: "Ajustes", active: activeApp == .settings) { open(.settings) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 12)
        .glassPanel(radius: 27)
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 29, height: 29)
                .background(.white.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fechar")
    }

    private func open(_ kind: AppKind) {
        activeApp = kind
        showingLauncher = false
        showingControls = false
        showWelcome = false
    }
}
