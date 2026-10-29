import ARKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import SwiftUI
import UIKit
import simd

@main
struct VROSApp: App {
    var body: some Scene {
        WindowGroup {
            VRHomeView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

/// Windows are ARKit world-positioned for the lifetime of a tracking session.
/// They are not persistent anchors and do not survive app restarts.
enum PanelKind: Equatable {
    case content
    case updates
    case web
}

struct VRPanel: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var text: String
    var x: CGFloat = 0
    var y: CGFloat = 0
    var depth: Double = 1.5
    var anchor: SIMD3<Float>?
    var kind: PanelKind = .content
    var templateID: String? = nil
    var webApp: VRWebApp? = nil
}

private enum VRTheme: Int, CaseIterable {
    case graphite, cosmos, aurora, synthwave
    var title: String { ["Grafite", "Cosmos 360", "Aurora", "Synthwave"][rawValue] }
    var subtitle: String { ["Câmera real", "Estrelas 360°", "Céu boreal", "Grade retrô"][rawValue] }
    var symbol: String { ["camera.fill", "moon.stars.fill", "sparkles", "waveform.path"][rawValue] }
    var accent: Color {
        switch self {
        case .graphite: return Color(white: 0.82)
        case .cosmos: return Color(red: 0.68, green: 0.58, blue: 1)
        case .aurora: return Color(red: 0.36, green: 0.95, blue: 0.72)
        case .synthwave: return Color(red: 1, green: 0.36, blue: 0.76)
        }
    }
    var surface: Color {
        switch self {
        case .graphite: return Color(white: 0.18)
        case .cosmos: return Color(red: 0.12, green: 0.09, blue: 0.23)
        case .aurora: return Color(red: 0.04, green: 0.15, blue: 0.16)
        case .synthwave: return Color(red: 0.19, green: 0.04, blue: 0.20)
        }
    }
}

/// A spatial grab always begins on the plain white handle under a window.
/// Record camera axes ONCE so pose changes don't rewrite stationary anchors.
private struct WindowDrag {
    let panelID: UUID
    let initialAnchor: SIMD3<Float>
    let initialPointer: CGPoint
    let initialHandDepth: Float?
    let initialWindowDepth: Float
    let cameraRight: SIMD3<Float>
    let cameraUp: SIMD3<Float>
    let cameraBackward: SIMD3<Float>
    let horizontalMetresPerPoint: Float
    let verticalMetresPerPoint: Float
    var filteredPointer: CGPoint
    var filteredHandDepth: Float?
    var planarEnabled = false
    var planarConfirmations = 0
    var depthEnabled = false
    var depthConfirmations = 0
    var lastAppliedAnchor: SIMD3<Float>
}

private struct WebPinchGesture {
    let panelID: UUID
    let initialPointer: CGPoint
    let startScrollY: CGFloat
    let x: CGFloat
    let y: CGFloat
    var moved = false
}

private struct NotePinchGesture {
    let panelID: UUID
    let initialPointerY: CGFloat
    let startScrollY: CGFloat
}

/// In 0.5x mode we can drag angular window positions in two dimensions
/// even though ARKit world translation is unavailable.
private struct UltraWideDrag {
    let panelID: UUID
    let initialPointer: CGPoint
    let initialCentre: CGPoint
}

private struct VRSettingsPinch {
    let start: CGPoint
    let startingScroll: CGFloat
    var moved = false
    var sliderID: String?
}

private enum VRLauncherApp: Identifiable {
    case web(VRWebApp)
    case settings
    case files, photos
    static var all: [VRLauncherApp] {
        VRWebApp.allCases.map { .web($0) } + [.settings, .files, .photos]
    }
    var id: String {
        switch self {
        case let .web(app): return app.rawValue
        case .settings: return "settings"
        case .files: return "files"
        case .photos: return "photos"
        }
    }
    var title: String {
        switch self {
        case let .web(app): return app.title
        case .settings: return "Ajustes"
        case .files: return "Arquivos"
        case .photos: return "Fotos"
        }
    }
    var subtitle: String {
        switch self {
        case let .web(app): return app.description
        case .settings: return "Configurações do VR-OS"
        case .files: return "Importar e organizar cópias locais"
        case .photos: return "Galeria de imagens importadas"
        }
    }
    var symbol: String {
        switch self {
        case let .web(app): return app.symbol
        case .settings: return "gearshape.fill"
        case .files: return "folder.fill"
        case .photos: return "photo.on.rectangle"
        }
    }
    var accent: Color {
        switch self {
        case let .web(app): return app.accent
        case .settings: return Color(white: 0.72)
        case .files: return .blue
        case .photos: return .pink
        }
    }
}


struct VRHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false
    @StateObject private var runtime = VRRuntime()
    @StateObject private var ultraWide = VRUltraWideCamera()
    @State private var ultraWideMode = false
    @State private var cameraTransitioning = false
    // Full sensor frame is the honest default for a REAL 0.5x image.
    // User can opt into fill, which crops the sides inside narrow eye viewports.
    @State private var ultraFullFrame = true
    @State private var ultraInvertMotion = false
    @State private var ultraNotice: String?
    @State private var ultraPanelDirections: [UUID: SIMD3<Float>] = [:]
    @State private var ultraDrag: UltraWideDrag?
    @State private var eyeViewport = CGSize(width: 200, height: 390)
    @StateObject private var settings = VRSettingsSession()
    @StateObject private var dwell = VRDwellController()
    @StateObject private var joyCon = VRJoyConController()
    // Force the camera-free angular layout to redraw on every sensor frame.
    @State private var headMotionRevision = 0
    @StateObject private var homeLibrary = VRHomeLibrary()
    @StateObject private var keyboard = VRSpatialKeyboardSession()
    @AppStorage("vros.camera.enabled.v48") private var cameraEnabled = true
    @State private var movingWindowID: UUID?
    @State private var moveStartedAt: CGPoint?
    @State private var angularDirections: [UUID: SIMD3<Float>] = [:]
    @State private var settingsOpen = false
    @State private var settingsGesture: VRSettingsPinch?
    @State private var lensMenuOpen = false
    @StateObject private var updates = LiveUpdateManager()
    @State private var nextRemoteTemplateIndex = 0
    @State private var selectedTheme: VRTheme = .graphite
    @State private var themeMenuOpen = false
    @State private var appsOpen = false
    @State private var appsPage = 0
    @State private var dockExpanded = true
    @StateObject private var workspace = VRWorkspace()
    @StateObject private var media = VRMediaStore()
    @StateObject private var productivity = VRProductivityTools()
    @State private var mediaDragPoint: CGPoint?
    @State private var mediaMode: Bool? // nil=Central; false=Files; true=Photos
    @State private var importingMedia = false
    @State private var pickingImage = false
    @State private var pickedImage: PhotosPickerItem?
    @State private var pendingMediaDelete: UUID?
    @State private var webRevision = 0
    @State private var workspaceOpen = false
    @State private var workspacePage = 0
    @AppStorage("vros.scenery.v1") private var sceneryIndex = 0
    @State private var webSessions: [UUID: VRWebSession] = [:]
    @State private var noteSessions: [UUID: VRNoteSession] = [:]
    @State private var notePinchGesture: NotePinchGesture?
    @State private var appsWarning: String?
    @State private var webWindowZoom: CGFloat = 1.0
    @State private var focusedWebPanelID: UUID?
    @State private var webPinchGesture: WebPinchGesture?
    @State private var cinemaOpen = false
    @StateObject private var cinema = CinemaModel()
    @State private var panels: [VRPanel] = []
    @State private var lastPinch = false
    @State private var drag: WindowDrag?

    var body: some View {
        GeometryReader { geometry in
            let placement = settings.lens.placement(in: geometry.size)
            let eyeSize = placement.aperture
            ZStack {
                Color.black
                // Eye centres are not forced to 25%/75% of the screen.
                // Both live in the full landscape coordinate space, like
                // the supplied VR headset reference screenshot.
                lensEye(right: false, size: eyeSize)
                    .frame(width: eyeSize.width, height: eyeSize.height)
                    .clipShape(VRLensAperture(curvature: settings.lens.curvature))
                    // Mask visual pixels AND interactive touches outside the lens.
                    .contentShape(VRLensAperture(curvature: settings.lens.curvature))
                    .position(placement.left)
                lensEye(right: true, size: eyeSize)
                    .frame(width: eyeSize.width, height: eyeSize.height)
                    .clipShape(VRLensAperture(curvature: settings.lens.curvature))
                    // Mask visual pixels AND interactive touches outside the lens.
                    .contentShape(VRLensAperture(curvature: settings.lens.curvature))
                    .position(placement.right)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.black)
            .onReceive(runtime.$camera) { pose in
                guard cameraEnabled, let pose = pose else { return }
                anchorPendingPanels(pose: pose, size: eyeSize)
            }
            .onReceive(dwell.$headRotation) { _ in
                headMotionRevision &+= 1
                processDwell(size: eyeSize)
            }
            .onReceive(dwell.$normalizedPoint) { _ in
                processDwell(size: eyeSize)
            }
            .onReceive(dwell.$pulse) { _ in
                processDwell(size: eyeSize)
            }
            .onReceive(joyCon.$triggerPulse) { _ in
                processJoyConClick(size: eyeSize)
            }
            .onReceive(joyCon.$isConnected) { connected in
                if connected {
                    dwell.stop()
                } else {
                    dwell.setEnabled(settings.dwellEnabled)
                }
            }
            .onAppear { eyeViewport = eyeSize }
            .onChange(of: geometry.size) { nextSize in
                eyeViewport = settings.lens.placement(in: nextSize).aperture
            }
            .onChange(of: settings.lens) { newSettings in
                newSettings.save()
                eyeViewport = newSettings.placement(in: geometry.size).aperture
            }
            .onReceive(updates.$manifest) { remote in
                applyRemoteWindowContent(remote)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            let cameraUpgradeKey = "vros.camera.default.v49.applied"
            if !UserDefaults.standard.bool(forKey: cameraUpgradeKey) {
                cameraEnabled = true
                UserDefaults.standard.set(true, forKey: cameraUpgradeKey)
            }
            if let rawTheme = UserDefaults.standard.object(forKey: "vros.selectedTheme.v1") as? Int,
               let savedTheme = VRTheme(rawValue: rawTheme) {
                selectedTheme = savedTheme
            } else {
                selectedTheme = .cosmos
                UserDefaults.standard.set(VRTheme.cosmos.rawValue,
                                          forKey: "vros.selectedTheme.v1")
            }
            let savedWebZoom = UserDefaults.standard.double(forKey: "vros.webZoom.v1")
            webWindowZoom = savedWebZoom > 0
                ? min(1.55, max(0.65, CGFloat(savedWebZoom))) : 1.0
            ultraInvertMotion =
                UserDefaults.standard.bool(forKey: "vros.ultra.invertMotion.v1")
            if UserDefaults.standard.object(forKey: "vros.ultra.fullFrame.v1") != nil {
                ultraFullFrame =
                    UserDefaults.standard.bool(forKey: "vros.ultra.fullFrame.v1")
            }
            runtime.setPinchSensitivity(settings.pinchSensitivity)
            ultraWide.setPinchSensitivity(settings.pinchSensitivity)
            runtime.setHandTrackingEnabled(false)
            ultraWide.setHandTrackingEnabled(false)
            dwell.setDelay(settings.dwellDelay)
            joyCon.start()
            if joyCon.isConnected {
                dwell.stop()
            } else {
                dwell.setEnabled(settings.dwellEnabled)
            }
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIApplication.shared.isIdleTimerDisabled = true
            runtime.setCameraPreviewEnabled(cameraEnabled && !settingsOpen)
            runtime.setCinemaMode(cinemaOpen)
            if !cameraEnabled {
                runtime.stop()
                ultraWide.stop()
            } else if settings.cameraUltra && !ultraWideMode &&
               AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                toggleUltraWide()
            } else if ultraWideMode {
                // A reappearing root view must not restart ARKit while the
                // physical ultrawide lens is owned by AVCapture.
                runtime.stop()
                ultraWide.start()
            } else {
                runtime.start()
            }
            Task { await updates.checkIfStale() }
        }
        .fileImporter(isPresented: $importingMedia,
            allowedContentTypes: productivity.importingBackup ? [.json] : [.image, .pdf, .plainText, .movie],
            allowsMultipleSelection: false, onCompletion: handleFileImport)
        .modifier(VRProductivityDialogs(tools: productivity, media: media, settings: settings,
            onRestore: { sceneryIndex = $0; applySettingsChanges() },
            onLibraryChanged: { workspacePage = 0; pendingMediaDelete = nil }))
        .onChange(of: media.entries.count) { _ in changeWorkspacePage(0) }
        .photosPicker(isPresented: $pickingImage, selection: $pickedImage, matching: .images)
        .onChange(of: pickedImage) { item in
            guard let item = item else { return }
            Task {
                do {
                    if let file = try await item.loadTransferable(type: VRPickedImage.self) {
                        await media.importFile(file.url, deleteTemporarySource: true)
                    }
                } catch { media.message = error.localizedDescription }
                pickedImage = nil
            }
        }
        .onChange(of: selectedTheme) { _ in
            runtime.setCameraPreviewEnabled(cameraEnabled && !settingsOpen)
        }
        .onChange(of: focusedWebPanelID) { id in
            workspace.synchronizeFocus(id)
        }
        .onChange(of: settings.revision) { _ in
            applySettingsChanges()
        }
        .onChange(of: settings.dwellEnabled) { enabled in
            if !joyCon.isConnected {
                dwell.setEnabled(enabled)
            }
        }
        .onChange(of: settings.dwellDelay) { seconds in
            dwell.setDelay(seconds)
        }
        .onChange(of: ultraFullFrame) { enabled in
            UserDefaults.standard.set(enabled,
                                      forKey: "vros.ultra.fullFrame.v1")
        }
        .onChange(of: webWindowZoom) { zoom in
            UserDefaults.standard.set(Double(zoom), forKey: "vros.webZoom.v1")
            // Past 100% the web window has filled its eye viewport. Zoom
            // the PAGE rather than letting controls disappear offscreen.
            for browser in webSessions.values {
                browser.setPageZoom(max(1.0, zoom * 1.15))
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                for browser in webSessions.values { browser.suspendMedia() }
                wasBackgrounded = true
                if cinemaOpen { cinema.exit() }
                if ultraWideMode { ultraWide.stop() }
                dwell.stop()
                joyCon.stop()
                runtime.stop()
            } else if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                joyCon.start()
                if joyCon.isConnected {
                    dwell.stop()
                } else {
                    dwell.setEnabled(settings.dwellEnabled)
                }
                if ultraWideMode {
                    recenterUltraWide()
                    ultraWide.start()
                } else if cameraEnabled {
                    runtime.setCinemaMode(cinemaOpen)
                    runtime.resume()
                    if cinemaOpen { cinema.enter(camera: runtime.camera) }
                }
            }
        }
        .onDisappear {
            joyCon.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            if cinemaOpen { cinema.exit() }
            ultraWide.stop()
            dwell.stop()
            runtime.setCinemaMode(false)
            runtime.stop()
        }
    }

    private var homeWindows: [VRHomeWindow] {
        panels.map { VRHomeWindow(id: $0.id, title: $0.title, symbol: $0.icon,
                                 minimized: workspace.state($0.id).minimized) }
    }

    private func shellAction(at point: CGPoint, size: CGSize) -> VRHomeAction? {
        guard !settingsOpen, !workspaceOpen, !lensMenuOpen, !themeMenuOpen,
              media.preview == nil, !media.loadingPreview else { return nil }
        return VRHomeLayout.hit(point, viewport: size, model: homeLibrary, windows: homeWindows)
    }

    private func performHomeAction(_ action: VRHomeAction) {
        switch action {
        case .library:
            homeLibrary.visible.toggle(); homeLibrary.quickSettings = false
            homeLibrary.query = ""; homeLibrary.page = 0
            focusedWebPanelID = nil; movingWindowID = nil
        case .quick:
            homeLibrary.quickSettings.toggle(); homeLibrary.visible = false
        case .close:
            homeLibrary.visible = false; homeLibrary.quickSettings = false
        case let .section(section): homeLibrary.section = section
        case .search:
            if homeLibrary.section == .windows { homeLibrary.section = .all }
            keyboard.open(.library, title: "Pesquisar na Biblioteca", text: homeLibrary.query)
        case .sort: homeLibrary.alphabetical.toggle(); homeLibrary.page = 0
        case let .pin(id): homeLibrary.togglePin(id)
        case let .page(delta): homeLibrary.turnPage(delta, windowCount: panels.count)
        case let .window(id):
            if workspace.state(id).minimized { workspace.minimize(id) }
            homeLibrary.visible = false; homeLibrary.quickSettings = false
            centreAllWindows()
            focusedWebPanelID = id
        case .camera: setCameraEnabled(!cameraEnabled)
        case .recenter: centreAllWindows()
        case .pointer: dwell.recenter()
        case .settings: openSettings()
        case .lens:
            homeLibrary.visible = false; homeLibrary.quickSettings = false
            focusedWebPanelID = nil; lensMenuOpen = true
        case .worlds: homeLibrary.show(.worlds)
        case let .brightness(delta):
            UIScreen.main.brightness = max(0.05, min(1, UIScreen.main.brightness + CGFloat(delta) * 0.1))
            // Observable update refreshes the percentage in both eyes.
            homeLibrary.hovered = nil
        case let .app(id):
            homeLibrary.opened(id)
            homeLibrary.visible = false; homeLibrary.quickSettings = false
            if id.hasPrefix("world."), let index = Int(id.dropFirst(6)), let theme = VRTheme(rawValue: index) {
                chooseTheme(theme); homeLibrary.show(.worlds); return
            }
            if let app = VRWebApp(rawValue: id) { openWebApp(app); return }
            switch id {
            case "cinema": activateDock(2)
            case "settings": openSettings()
            case "files": performWorkspace(.files)
            case "photos": performWorkspace(.photos)
            case "notes": activateDock(0)
            case "lens": performHomeAction(.lens)
            case "tools": mediaMode = nil; workspaceOpen = true; workspacePage = 0
            case "updates": openUpdatesWindow()
            case "compatibility":
                let panel = VRPanel(title: "VR-OS · Plataforma iPhone", icon: "info.circle",
                    text: "RECURSOS NATIVOS\nBiblioteca, dock, teclado espacial, olhar de 1 segundo, janelas, ambientes, navegador HTTPS, fotos, arquivos e Cinema 2D/SBS/OU.\n\nRASTREAMENTO\nSem câmera: orientação Core Motion (3DoF). Câmera traseira: ARKit + Joy-Con; 0,5x depende de lente disponível.\n\nCOMPATIBILIDADE\nAPKs Android, Monado, VrApi e jogos Quest não executam nesta versão iOS. WebXR imersivo não foi integrado.\n\nSERVIÇOS\nConta, amigos, chamadas e assistente não estão conectados. Nenhum backend ou chave de outro aplicativo é utilizado.")
                panels.append(panel)
                registerUltraWindow(panel)
            default: break
            }
        }
    }

    private func setCameraEnabled(_ enabled: Bool) {
        cameraEnabled = enabled
        centreAllWindows()
        if enabled {
            if settings.cameraUltra { toggleUltraWide() }
            else { runtime.start() }
        } else {
            runtime.stop()
            if ultraWideMode {
                ultraWide.stop { ultraWideMode = false; cameraTransitioning = false }
            }
            for index in panels.indices { panels[index].anchor = nil }
        }
    }

    private func performKeyboardKey(_ key: String) {
        if key == "close" { keyboard.destination = nil; return }
        if key == "enter" {
            switch keyboard.destination {
            case .library:
                homeLibrary.query = keyboard.text; homeLibrary.visible = true
                homeLibrary.quickSettings = false
            case .settings: settings.searchText = keyboard.text
            case let .browser(id):
                webSessions[id]?.address = keyboard.text
                webSessions[id]?.navigate()
            case nil: break
            }
            keyboard.destination = nil
        } else { keyboard.type(key) }
    }

    private func chromeHit(at point: CGPoint, size: CGSize) -> (UUID, VRWindowAction)? {
        for panel in panels.reversed() where !workspace.state(panel.id).minimized &&
            (focusedWebPanelID == nil || focusedWebPanelID == panel.id) {
            guard let center = displayedPanelCenter(panel, size: size, right: false) else { continue }
            let frame = VRWindowChromeGeometry.frame(center: center,
                dimensions: displayedPanelSize(panel, size: size), viewport: size)
            if let action = VRWindowChromeGeometry.hit(point, frame: frame) { return (panel.id, action) }
        }
        return nil
    }

    private func performWindowAction(_ action: VRWindowAction, id: UUID, size: CGSize) {
        switch action {
        case .close: close(id)
        case .minimize:
            workspace.minimize(id)
            if focusedWebPanelID == id { focusedWebPanelID = nil }
        case .focus:
            workspace.focus(id)
            focusedWebPanelID = workspace.focused
        case .smaller: workspace.resize(id, by: -0.1)
        case .larger: workspace.resize(id, by: 0.1)
        case .move:
            focusedWebPanelID = nil
            movingWindowID = movingWindowID == id ? nil : id
            moveStartedAt = dwellCenter(in: size)
        }
    }

    private func placeMovingWindow(at point: CGPoint, size: CGSize) {
        guard let id = movingWindowID else { return }
        defer { movingWindowID = nil; moveStartedAt = nil }
        guard point.y > 38, let index = panels.firstIndex(where: { $0.id == id }) else { return }
        if cameraEnabled && !ultraWideMode {
            panels[index].anchor = runtime.worldPoint(at: point, viewport: size, depth: Float(panels[index].depth))
        } else if ultraWideMode {
            ultraPanelDirections[id] = VRUltraWideWindowProjection.anchoredDirection(at: point, viewport: size, headRotation: effectiveUltraRotation)
        } else {
            angularDirections[id] = VRUltraWideWindowProjection.anchoredDirection(at: point, viewport: size, headRotation: effectiveDwellRotation)
            panels[index].x = (point.x - size.width / 2) / max(1, size.width / 2)
            panels[index].y = (point.y - size.height / 2) / max(1, size.height / 2)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let backup = productivity.importingBackup
        productivity.importingBackup = false
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task {
                if backup { await productivity.readBackup(url) }
                else { await media.importFile(url) }
            }
        case let .failure(error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            if backup { productivity.dialog = .message(error.localizedDescription) }
            else { media.message = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func lensEye(right: Bool, size: CGSize) -> some View {
        if cinemaOpen {
            CinemaEyeView(rightEye: right, runtime: runtime,
                          cinema: cinema, updates: updates,
                          dwell: dwell, dwellDelay: settings.dwellDelay,
                          onExit: { exitCinema() })
        } else {
            eyeView(right: right, size: size)
        }
    }

    /// Native Settings shares existing runtime objects, rather than
    /// creating a mock preferences screen with nonfunctional controls.
    private func openSettings() {
        guard !cinemaOpen else { return }
        synchronizeRuntimePreferences()
        homeLibrary.visible = false
        homeLibrary.quickSettings = false
        keyboard.destination = nil
        appsOpen = false
        lensMenuOpen = false
        themeMenuOpen = false
        focusedWebPanelID = nil
        settingsGesture = nil
        lastPinch = false
        settings.searchText = ""
        settings.enter(.home)
        settingsOpen = true
        // The opaque Settings surface needs only the camera pose.
        // not need CGImage rendering behind the stereo UI.
        runtime.setCameraPreviewEnabled(false)
        ultraWide.setDisplayEnabled(false)
        dockExpanded = false
    }

    private func synchronizeRuntimePreferences() {
        settings.cameraUltra = ultraWideMode
        settings.fullCameraFrame = ultraFullFrame
        settings.invertUltraMotion = ultraInvertMotion
        settings.themeIndex = selectedTheme.rawValue
        settings.webZoom = webWindowZoom
        settings.cinemaFOV = cinema.cinemaFovDegrees
        settings.cinemaInvert = cinema.invertTracking
        settings.cinemaImmersive = cinema.immersiveScreen
        settings.cinemaSwapEyes = cinema.swapEyes
        settings.cinemaAutoControls = cinema.showControlsAutomatically
    }

    private func closeSettings() {
        settingsOpen = false
        runtime.setCameraPreviewEnabled(cameraEnabled && !settingsOpen)
        ultraWide.setDisplayEnabled(true)
        settingsGesture = nil
        lastPinch = false
        settings.notice = nil
        settings.pendingConfirmation = nil
    }

    private func centreAllWindows() {
        dwell.recenter()
        angularDirections.removeAll()
        if ultraWideMode {
            recenterUltraWide()
        } else {
            for index in panels.indices {
                panels[index].x = 0
                panels[index].y = 0
                panels[index].anchor = nil
            }
        }
    }

    private func applySettingsChanges() {
        if let theme = VRTheme(rawValue: settings.themeIndex),
           selectedTheme != theme { chooseTheme(theme) }
        if ultraFullFrame != settings.fullCameraFrame {
            ultraFullFrame = settings.fullCameraFrame
        }
        if ultraInvertMotion != settings.invertUltraMotion {
            ultraInvertMotion = settings.invertUltraMotion
            UserDefaults.standard.set(ultraInvertMotion,
                                      forKey: "vros.ultra.invertMotion.v1")
            if ultraWideMode { recenterUltraWide() }
        }
        if abs(webWindowZoom - settings.webZoom) > 0.005 {
            webWindowZoom = settings.webZoom
        }
        if abs(cinema.cinemaFovDegrees - settings.cinemaFOV) > 0.5 {
            cinema.adjustCinemaFOV(settings.cinemaFOV -
                                   cinema.cinemaFovDegrees)
        }
        if cinema.invertTracking != settings.cinemaInvert {
            cinema.toggleTrackingDirection()
        }
        if cinema.immersiveScreen != settings.cinemaImmersive {
            cinema.toggleImmersive()
        }
        if cinema.swapEyes != settings.cinemaSwapEyes {
            cinema.toggleEyeOrder()
        }
        if cinema.showControlsAutomatically != settings.cinemaAutoControls {
            cinema.showControlsAutomatically = settings.cinemaAutoControls
        }
        runtime.setPinchSensitivity(settings.pinchSensitivity)
        ultraWide.setPinchSensitivity(settings.pinchSensitivity)
        dwell.setDelay(settings.dwellDelay)
        dwell.setEnabled(settings.dwellEnabled)

        if let request = settings.command {
            settings.command = nil
            switch request.kind {
            case .recenterWindows:
                centreAllWindows()
            case .recenterDwell:
                dwell.recenter()
            case .clearFavorites:
                UserDefaults.standard.removeObject(
                    forKey: "vros.web.favorites.v1")
                for session in webSessions.values {
                    session.clearFavorites()
                }
            case .restoreAll:
                sceneryIndex = 0
                centreAllWindows()
                cinema.resetPlacement()
                UserDefaults.standard.removeObject(forKey: "vros.note.fontSize.v1")
                for note in noteSessions.values { note.resetFontSize() }
                UserDefaults.standard.set(false,
                                          forKey: "vros.ultra.invertMotion.v1")
            }
        }
        if cameraEnabled && settings.cameraUltra != ultraWideMode && !cameraTransitioning {
            toggleUltraWide()
        }
    }

    private func toggleUltraWide() {
        guard !cameraTransitioning, !cinemaOpen else { return }
        cameraEnabled = true
        // Dock requests also update the shared desired mode. Keep that intent
        // even if Settings closes before the capture transition completes.
        if !settingsOpen { settings.cameraUltra = !ultraWideMode }
        cameraTransitioning = true
        lastPinch = false
        drag = nil
        webPinchGesture = nil
        notePinchGesture = nil
        appsOpen = false
        themeMenuOpen = false
        lensMenuOpen = false
        if ultraWideMode {
            // Wait for AVCapture to release the physical lens before ARKit resumes.
            ultraWide.stop { [self] in
                ultraWideMode = false
                ultraPanelDirections.removeAll()
                ultraDrag = nil
                ultraNotice = nil
                runtime.setCameraPreviewEnabled(cameraEnabled && !settingsOpen)
                if scenePhase == .active && cameraEnabled { runtime.resume() }
                cameraTransitioning = false
                if settings.cameraUltra && cameraEnabled { toggleUltraWide() }
            }
        } else {
            // Snapshot the ARKit window screen positions before suspending it.
            // In ultrawide mode, those points become ANGULAR bearings (3DoF)
            // so head turns can keep windows in approximately fixed directions.
            ultraPanelDirections.removeAll()
            for panel in panels {
                let location = windowCenter(panel, size: eyeViewport, right: false)
                    ?? CGPoint(x: eyeViewport.width / 2,
                               y: eyeViewport.height / 2)
                ultraPanelDirections[panel.id] =
                    VRUltraWideWindowProjection.screenRay(
                        at: location, viewport: eyeViewport)
            }
            runtime.stop()
            ultraWideMode = true
            ultraWide.setDisplayEnabled(!settingsOpen)
            ultraNotice = nil
            dockExpanded = false
            ultraWide.start { started in
                guard cameraEnabled else {
                    ultraWide.stop()
                    ultraWideMode = false
                    cameraTransitioning = false
                    return
                }
                guard scenePhase == .active else {
                    ultraWide.stop()
                    cameraTransitioning = false
                    return
                }
                if !started {
                    // No physical lens or camera permission: do not leave
                    // the user trapped in a black 0.5x mode.
                    ultraWideMode = false
                    ultraPanelDirections.removeAll()
                    settings.cameraUltra = false
                    settings.notice = "Câmera 0,5x indisponível; ARKit restaurado"
                    runtime.setCameraPreviewEnabled(cameraEnabled && !settingsOpen)
                    runtime.resume()
                }
                cameraTransitioning = false
                // A Settings switch may have been changed while capture
                // was starting: apply the newest desired state afterwards.
                if started && !settings.cameraUltra {
                    toggleUltraWide()
                }
            }
        }
    }

    // In camera-free VR, an anchored window moves opposite the head's
    // physical rotation. Invert the stored delta so the user's visible
    // movement follows the expected direction.
    private var effectiveDwellRotation: simd_quatf {
        simd_inverse(dwell.headRotation)
    }

    private var effectiveUltraRotation: simd_quatf {
        ultraInvertMotion ? simd_inverse(ultraWide.motionDelta)
                          : ultraWide.motionDelta
    }

    private func toggleUltraMotionDirection() {
        ultraInvertMotion.toggle()
        UserDefaults.standard.set(ultraInvertMotion,
                                  forKey: "vros.ultra.invertMotion.v1")
        recenterUltraWide()
    }

    private func recenterUltraWide() {
        guard ultraWideMode else { return }
        // When windows are outside the headset's view, recenter intentionally
        // restores them in front instead of preserving invisible bearings.
        var newDirections: [UUID: SIMD3<Float>] = [:]
        for panel in panels {
            let position = CGPoint(
                x: eyeViewport.width / 2 + panel.x * eyeViewport.width / 2,
                y: eyeViewport.height / 2 + panel.y * eyeViewport.height / 2)
            newDirections[panel.id] = VRUltraWideWindowProjection.screenRay(
                at: position, viewport: eyeViewport)
        }
        ultraPanelDirections = newDirections
        ultraWide.recenterMotion()
        ultraNotice = "Mira e janelas recentralizadas à frente"
    }

    private func eyeView(right: Bool, size: CGSize) -> some View {
        // Read the revision so SwiftUI invalidates both eye canvases when
        // Core Motion publishes a new head rotation.
        let _ = headMotionRevision
        let w = size.width
        let h = size.height
        let shownHand = TrackedHand()
        return ZStack {
            if ultraWideMode {
                if let frame = ultraWide.image {
                    if ultraFullFrame {
                        Image(decorative: frame, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .frame(width: w, height: h)
                            .scaleEffect(settings.lens.cameraZoom)
                            .allowsHitTesting(false)
                    } else {
                        Image(decorative: frame, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(width: w, height: h)
                            .scaleEffect(settings.lens.cameraZoom)
                            .clipped()
                            .allowsHitTesting(false)
                    }
                } else {
                    Color.black.overlay {
                        VStack(spacing: 6) {
                            ProgressView().tint(.white)
                            Text(ultraWide.status).font(.system(size: 11))
                        }
                        .foregroundStyle(.white)
                    }
                }
            } else if cameraEnabled, let frame = runtime.cameraImage {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .scaleEffect(settings.lens.cameraZoom)
                    .clipped()
                    .allowsHitTesting(false)
                VRCameraThemeOverlay(accent: selectedTheme.accent, size: size)
            } else if sceneryIndex != 0 {
                VRSceneryView(scenery: VRScenery(rawValue: sceneryIndex) ?? .original,
                              camera: runtime.camera, headRotation: cameraEnabled ? nil : dwell.headRotation)
            } else if selectedTheme == .cosmos {
                SpaceSkyView(camera: runtime.camera, size: size,
                             headRotation: cameraEnabled ? nil : dwell.headRotation)
            } else if selectedTheme == .aurora || selectedTheme == .synthwave {
                ThemeAtmosphereView(isAurora: selectedTheme == .aurora,
                                    camera: runtime.camera, size: size,
                                    headRotation: cameraEnabled ? nil : dwell.headRotation)
            } else {
                VRHomeBackdrop()
                    .overlay(alignment: .top) {
                        Text(runtime.cameraStatus).font(.system(size: 9))
                            .foregroundStyle(VRDS.Color.secondary).padding(6)
                    }
            }

            if selectedTheme == .graphite && !ultraWideMode {
                Color.black.opacity(0.10).allowsHitTesting(false)
            }

            ForEach(panels) { panel in
                if !workspace.state(panel.id).minimized,
                   (focusedWebPanelID == nil || focusedWebPanelID == panel.id),
                   let center = displayedPanelCenter(panel, size: size, right: right) {
                    let dimensions = displayedPanelSize(panel, size: size)
                    panelView(panel, size: size, right: right)
                        .frame(width: dimensions.width, height: dimensions.height)
                        .position(center)
                    VRWindowChrome(
                        frame: VRWindowChromeGeometry.frame(center: center, dimensions: dimensions, viewport: size),
                        moving: movingWindowID == panel.id,
                        onAction: { performWindowAction($0, id: panel.id, size: size) })
                        .position(x: center.x, y: VRWindowChromeGeometry.frame(
                            center: center, dimensions: dimensions, viewport: size).midY)
                        .allowsHitTesting(!homeLibrary.visible && !homeLibrary.quickSettings)
                    if cameraEnabled && focusedWebPanelID != panel.id {
                        grabHandle(panel, size: size)
                            .position(grabHandleCenter(center, panel: panel, size: size))
                    }
                }
            }

            if focusedWebPanelID == nil {

                if themeMenuOpen {
                    themePicker(size: size).position(x: w / 2, y: h / 2)
                }
                if lensMenuOpen {
                    lensCalibrationPanel(size: size)
                        .position(x: w / 2, y: h / 2)
                        .zIndex(10)
                }

            }

            if ultraWideMode {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Button { recenterUltraWide() } label: {
                            Label("Mira", systemImage: "scope")
                                .frame(maxWidth: .infinity)
                        }
                        Button { ultraFullFrame.toggle() } label: {
                            Label(ultraFullFrame ? "Preencher" : "Tela toda",
                                  systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        Button { toggleUltraMotionDirection() } label: {
                            Text(ultraInvertMotion ? "Inv." : "Mov.")
                                .frame(maxWidth: .infinity)
                        }
                        Button { toggleUltraWide() } label: {
                            Label("ARKit", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(cameraTransitioning)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .labelStyle(.titleOnly)
                    .padding(5)
                    .background(.black.opacity(0.83),
                                in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 0)
                    Text(ultraNotice ??
                         "0,5x REAL · câmera + cabeça 3DoF · sem mãos")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(6)
                        .background(.black.opacity(0.78), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }

            if shownHand.visible && settings.showSkeleton && !settingsOpen {
                HandSkeletonOverlay(hand: shownHand) { joint in
                    mappedPoint(joint, size: size)
                }
                .allowsHitTesting(false)
            }

            if shownHand.visible && settings.showCursor && !settingsOpen && !joyCon.isConnected {
                let cursor = interactionPoint(shownHand.point, size: size)
                VRPrecisionCursor(pinching: shownHand.pinching, size: settings.cursorSize,
                                  reduceMotion: settings.reduceMotion)
                .position(cursor)
                .allowsHitTesting(false)
            }

            if joyCon.isConnected {
                VRJoyConRay(
                    start: CGPoint(x: w * 0.84, y: h * 0.90),
                    end: joyCon.primaryPoint(in: size),
                    color: .cyan
                )
                .zIndex(89)
                if joyCon.connectedCount > 1 {
                    VRJoyConRay(
                        start: CGPoint(x: w * 0.16, y: h * 0.90),
                        end: joyCon.secondaryPoint(in: size),
                        color: .purple
                    )
                    .zIndex(88)
                }
            }

            if dwell.active && !joyCon.isConnected {
                VRDwellCursor(progress: dwell.progress,
                              reduceMotion: settings.reduceMotion)
                    .position(dwellCenter(in: size))
                    .zIndex(90)
            }

            if let focusedID = focusedWebPanelID {
                Button {
                    if workspace.focused == focusedID { workspace.focus(focusedID) }
                    focusedWebPanelID = nil
                } label: {
                    Label("Restaurar", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .bold))
                        .padding(7).background(.black.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
                .position(x: w - 52, y: 18)
                .zIndex(40)
            }

            if !settingsOpen && !workspaceOpen && !themeMenuOpen && !lensMenuOpen && media.preview == nil && !media.loadingPreview {
                VRHomeShell(library: homeLibrary, viewport: size, windows: homeWindows,
                    cameraEnabled: cameraEnabled, motionAvailable: dwell.motionAvailable,
                    dwellDelay: settings.dwellDelay, showHUD: settings.showHUD,
                    notice: appsWarning, onAction: performHomeAction)
                    .zIndex(42)
                if movingWindowID != nil {
                    Button { movingWindowID = nil; moveStartedAt = nil } label: {
                        Text("Olhe para o novo local · cancelar")
                            .font(.system(size: 10, weight: .medium)).padding(8)
                            .background(VRDS.Color.surface, in: Capsule())
                    }.buttonStyle(.plain).position(x: w / 2, y: 20).zIndex(43)
                }
            }
            if keyboard.destination != nil {
                VRSpatialKeyboard(session: keyboard, viewport: size, onKey: performKeyboardKey)
                    .zIndex(65)
            }
            if workspaceOpen {
                VRWorkspaceView(items: workspaceItems, page: workspacePage, viewport: size,
                    title: mediaMode == nil ? "CENTRAL VR" : (mediaMode == true ? "FOTOS" : "ARQUIVOS"),
                    onSelect: performWorkspace, onPage: changeWorkspacePage,
                    onClose: { workspaceOpen = false })
                    .zIndex(45)
            }

            if mediaMode != nil && workspaceOpen, let message = media.message {
                Text(message).font(.system(size: 9)).lineLimit(2)
                    .foregroundStyle(.white).padding(5)
                    .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
                    .frame(maxWidth: w * 0.9).position(x: w / 2, y: h - 20)
                    .allowsHitTesting(false).zIndex(47)
            }
            if media.preview != nil || media.loadingPreview {
                VRMediaPreview(store: media).frame(width: w, height: h).zIndex(60)
                if shownHand.visible {
                    VRPrecisionCursor(pinching: shownHand.pinching, size: settings.cursorSize,
                                      reduceMotion: settings.reduceMotion)
                        .position(interactionPoint(shownHand.point, size: size)).zIndex(61)
                }
            }
            if settingsOpen {
                VRSettingsScreen(session: settings, rightEye: right,
                                 onClose: { closeSettings() },
                                 onSearch: { keyboard.open(.settings, title: "Buscar nos Ajustes", text: settings.searchText) })
                    .frame(width: w, height: h)
                    .zIndex(50)
                // Accessibility: disabling the Home cursor must NEVER
                // hide the pointer used to re-enable it in Settings.
                if shownHand.visible {
                    let cursor = interactionPoint(shownHand.point, size: size)
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.95),
                                    lineWidth: shownHand.pinching ? 3 : 2)
                            .frame(width: shownHand.pinching ? 28 : 22,
                                   height: shownHand.pinching ? 28 : 22)
                        Circle().fill(.white).frame(width: 5, height: 5)
                    }
                    .scaleEffect(settings.cursorSize)
                    .shadow(color: .black.opacity(0.9), radius: 4)
                    .position(cursor)
                    .allowsHitTesting(false)
                    .zIndex(51)
                }
            }
        }
        .frame(width: w, height: h)
        .background(.black)
        .clipped()
    }

    private func statusBar(size: CGSize) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill((ultraWideMode ? ultraWide.active : runtime.spatialTracking)
                          ? Color.white : Color.gray)
                    .frame(width: 5, height: 5)
                Text("VR OS " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                    as? String ?? "4.5"))
                    .tracking(0.5)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 1)
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    HStack(spacing: 3) {
                        Text(timeline.date, format: .dateTime.hour().minute())
                        if UIDevice.current.batteryLevel >= 0 {
                            Image(systemName: "battery.100percent")
                            Text("\(Int(UIDevice.current.batteryLevel * 100))%")
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            Text(ultraWideMode
                 ? (ultraWide.active
                    ? "Câmera 0,5x · cabeça \(ultraWide.motionAvailable ? "3DoF" : "indisponível")"
                    : ultraWide.status)
                 : runtime.cameraStatus)
                .font(.system(size: 10))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(selectedTheme.surface.opacity(0.94), in: Capsule())
        .frame(maxWidth: size.width * 0.88)
    }

    // The menu lives above the edge of the camera view so hands can reach it.
    private func dockCenterY(_ size: CGSize) -> CGFloat {
        // Rendering, Vision hit-testing and placement share one rectangle.
        VRTaskbarGeometry.barRect(viewport: size).midY
    }

    /// Adjust the OPTICAL viewport, not the physical 0.5x camera.
    /// Changes apply identically to both eyes and persist across app launches.
    private func adjustLens(row: Int, direction: Int) {
        var next = settings.lens
        let step = CGFloat(direction)
        switch row {
        case 0: next.scale = max(0.75, min(1.40, next.scale + step * 0.05))
        case 1: next.spacing = max(-0.075, min(0.12, next.spacing + step * 0.012))
        case 2:
            next.verticalOffset = max(-0.16, min(0.16,
                                               next.verticalOffset + step * 0.015))
        case 3:
            next.cameraZoom = max(0.80, min(1.30,
                                          next.cameraZoom + step * 0.05))
        case 4:
            next.curvature = max(0, min(1, next.curvature + step * 0.125))
        default: return
        }
        settings.lens = next
    }

    private func lensCalibrationPanel(size: CGSize) -> some View {
        VRLensCalibrationView(lens: $settings.lens, isOpen: $lensMenuOpen,
                              viewport: size)
    }

    private func dock(size: CGSize) -> some View {
        VRTaskbar(viewport: size,
                  items: updates.frontend.enabledTaskbar,
                  active: activeTaskbarAction(),
                  reduceMotion: settings.reduceMotion,
                  accent: updates.frontend.accentColor,
                  surface: updates.frontend.surfaceColor,
                  surfaceOpacity: updates.frontend.taskbarOpacity,
                  onAction: activateTaskbar)
    }

    private func activeTaskbarAction() -> VRTaskbarAction? {
        if settingsOpen { return .settings }
        if cinemaOpen { return .cinema }
        if appsOpen { return .apps }
        if mediaMode == false && workspaceOpen { return .files }
        if mediaMode == true && workspaceOpen { return .photos }
        if workspaceOpen { return .home }
        return nil
    }

    private func panelView(_ panel: VRPanel, size: CGSize,
                           right: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: panel.icon)
                    .foregroundStyle(.white.opacity(0.75))
                Text(panel.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if panel.kind == .web {
                    Button {
                        focusedWebPanelID = focusedWebPanelID == panel.id ? nil : panel.id
                        appsOpen = false
                        themeMenuOpen = false
                    } label: {
                        Image(systemName: focusedWebPanelID == panel.id
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Button {
                    close(panel.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.76))
                }
                .buttonStyle(.plain)
            }

            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)

            if panel.kind == .web, let browser = webSessions[panel.id] {
                VRWebWindow(session: browser, rightEye: right,
                    onAddress: { keyboard.open(.browser(panel.id), title: "Endereço ou pesquisa", text: browser.address) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if panel.kind == .updates {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Conteúdo: " + updates.manifest.version)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(updates.statusMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("Versão instalada: \(updates.installedNativeVersion)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.65))
                    if updates.nativeUpdateAvailable {
                        Text("Nova versão: \(updates.manifest.latestNativeVersion)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.yellow)
                        Button {
                            updates.openNativeUpdate()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Baixar IPA pela internet")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.blue.opacity(0.78),
                                        in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Task { await updates.check() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text(updates.isChecking ? "Buscando…" : "Buscar atualizações")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .disabled(updates.isChecking)
                    .buttonStyle(.plain)
                }
            } else if let note = noteSessions[panel.id] {
                VStack(spacing: 3) {
                    VRNoteScrollSurface(session: note, rightEye: right)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 6) {
                        Button { note.adjustFontSize(-1) } label: {
                            Text("A−").frame(maxWidth: .infinity)
                        }
                        Button { note.scrollBy(-90) } label: {
                            Image(systemName: "arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        Button { note.scrollBy(90) } label: {
                            Image(systemName: "arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        Button { note.adjustFontSize(1) } label: {
                            Text("A+").frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(panel.text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(nil)
            }

            if panel.kind != .web { Spacer(minLength: 0) }
            if focusedWebPanelID != panel.id {
                Text(panel.kind == .web
                     ? "Pinça: tocar e rolar o site · linha branca: mover"
                     : "Pegue a linha branca abaixo para mover em 3D")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VRDS.Color.surface.opacity(settings.windowOpacity),
            in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(VRDS.Color.borderStrong, lineWidth: 0.7))
        .shadow(color: .black.opacity(0.50), radius: 11, y: 5)
        .onAppear {
            if panel.kind == .content && noteSessions[panel.id] == nil {
                noteSessions[panel.id] = VRNoteSession(text: panel.text)
            }
        }
    }

    private func displayedPanelSize(_ panel: VRPanel, size: CGSize) -> CGSize {
        VRGestureGeometry.visiblePanelSize(
            original: CGSize(width: panelWidth(panel, size: size),
                             height: panelHeight(panel, size: size)),
            scale: windowScale(panel) * workspace.state(panel.id).scale,
            viewport: size,
            isWeb: panel.kind == .web,
            isFocused: focusedWebPanelID == panel.id
        )
    }

    private func displayedPanelCenter(_ panel: VRPanel, size: CGSize,
                                      right: Bool) -> CGPoint? {
        if focusedWebPanelID == panel.id {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        if ultraWideMode {
            return ultraWindowCenter(panel, size: size, right: right)
        }
        if !cameraEnabled {
            let position = CGPoint(x: size.width / 2 + panel.x * size.width / 2,
                                   y: size.height / 2 + panel.y * size.height / 2)
            let direction = angularDirections[panel.id] ?? VRUltraWideWindowProjection.screenRay(at: position, viewport: size)
            guard let point = VRUltraWideWindowProjection.project(direction,
                headRotation: effectiveDwellRotation, viewport: size) else { return nil }
            let offset = min(CGFloat(10), CGFloat(7 / max(panel.depth, 0.65)))
            return CGPoint(x: point.x + (right ? -offset : offset), y: point.y)
        }
        return windowCenter(panel, size: size, right: right)
    }

    /// Rotational head tracking only: windows retain approximate angular
    /// bearings. This does not pretend to be spatial ARKit world tracking.
    private func ultraWindowCenter(_ panel: VRPanel, size: CGSize,
                                   right: Bool) -> CGPoint? {
        let defaultPosition = CGPoint(
            x: size.width / 2 + panel.x * size.width / 2,
            y: size.height / 2 + panel.y * size.height / 2)
        let direction = ultraPanelDirections[panel.id] ??
            VRUltraWideWindowProjection.screenRay(
                at: defaultPosition, viewport: size)
        guard let center = VRUltraWideWindowProjection.project(
            direction, headRotation: effectiveUltraRotation, viewport: size)
        else { return nil }
        let parallax = min(CGFloat(10), CGFloat(7 / max(panel.depth, 0.65)))
        return CGPoint(x: center.x + (right ? -parallax : parallax),
                       y: center.y)
    }

    /// The web windows are larger than note cards so sites can be used.
    private func panelWidth(_ panel: VRPanel, size: CGSize) -> CGFloat {
        panel.kind == .web ? size.width * 0.98 : panelWidth(size)
    }

    private func panelHeight(_ panel: VRPanel, size: CGSize) -> CGFloat {
        panel.kind == .web ? size.height * 0.84 : panelHeight(size)
    }

    /// The handle is only a white line, without a track, numbers, or thumb.
    private func grabHandleWidth(_ panel: VRPanel, size: CGSize) -> CGFloat {
        min(size.width * 0.72, max(70, displayedPanelSize(panel, size: size).width * 0.68))
    }

    private func grabHandleCenter(_ center: CGPoint, panel: VRPanel,
                                  size: CGSize) -> CGPoint {
        CGPoint(x: center.x,
                y: center.y + displayedPanelSize(panel, size: size).height / 2 + 22)
    }

    private func grabHandle(_ panel: VRPanel, size: CGSize) -> some View {
        let held = drag?.panelID == panel.id
        return Capsule()
            .fill(Color.white.opacity(held ? 1 : 0.94))
            .frame(width: grabHandleWidth(panel, size: size), height: held ? 7 : 5)
            .shadow(color: .white.opacity(held ? 0.65 : 0.25),
                    radius: held ? 7 : 3)
            .frame(height: 26)
            .allowsHitTesting(false)
    }

    private func themePicker(size: CGSize) -> some View {
        let width = min(size.width * 0.86, 330)
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "paintpalette.fill")
                Text("TEMAS").tracking(2)
                Spacer()
                Button { themeMenuOpen = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(VRTheme.allCases, id: \.rawValue) { theme in
                    Button { chooseTheme(theme) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: theme.symbol).font(.system(size: 23))
                            Text(theme.title).font(.system(size: 12, weight: .bold))
                            Text(theme.subtitle).font(.system(size: 9)).opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: min(86, max(44, (size.height - 94) / 2)))
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(theme == selectedTheme ? theme.accent : Color.white.opacity(0.25),
                                    lineWidth: theme == selectedTheme ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 5) {
                ForEach(VRTheme.allCases, id: \.rawValue) { theme in
                    Circle().fill(theme == selectedTheme ? theme.accent : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(width: width)
        .background(Color(white: 0.07).opacity(0.97), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17)
            .stroke(selectedTheme.accent.opacity(0.6), lineWidth: 1))
    }

    private func chooseTheme(_ theme: VRTheme) {
        sceneryIndex = 0
        selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "vros.selectedTheme.v1")
        themeMenuOpen = false
    }

    private func panelWidth(_ size: CGSize) -> CGFloat { min(350, size.width * 0.75) }
    private func panelHeight(_ size: CGSize) -> CGFloat { min(180, size.height * 0.39) }
    private func windowScale(_ panel: VRPanel) -> CGFloat {
        if ultraWideMode {
            // No depth measurement in 3DoF; keep virtual depth manually.
            let scale = min(2.5, max(0.3, CGFloat(1.5 / panel.depth)))
            return panel.kind == .web ? scale * webWindowZoom : scale
        }
        // Perspective must use the actual distance from the AR camera to
        // the window's world anchor, not a cosmetic scale tied to slider Z.
        guard let anchor = panel.anchor, let camera = runtime.camera else {
            let normal = min(2.5, max(0.3, CGFloat(1.5 / panel.depth)))
            return panel.kind == .web ? normal * webWindowZoom : normal
        }
        let position = camera.transform.columns.3
        let distance = simd_distance(anchor, SIMD3<Float>(position.x, position.y, position.z))
        let normal = min(2.5, max(0.3, CGFloat(1.5 / max(distance, 0.1))))
        return panel.kind == .web ? normal * webWindowZoom : normal
    }

    private func windowCenter(_ panel: VRPanel, size: CGSize, right: Bool) -> CGPoint? {
        if let anchor = panel.anchor {
            return runtime.projectedPoint(anchor, viewport: size, rightEye: right)
        }
        let fakeParallax: CGFloat = right ? -8 : 8
        return CGPoint(x: size.width / 2 + panel.x * size.width / 2 + fakeParallax,
                       y: size.height / 2 + panel.y * size.height / 2)
    }

    private func anchorPendingPanels(pose: ARCamera, size: CGSize) {
        for index in panels.indices where panels[index].anchor == nil {
            let panel = panels[index]
            let p = CGPoint(x: size.width / 2 + panel.x * size.width / 2,
                            y: size.height / 2 + panel.y * size.height / 2)
            panels[index].anchor = runtime.worldPoint(at: p, viewport: size,
                                                      depth: Float(panel.depth), using: pose)
        }
    }

    /// Map Vision's normalized joint coordinates through the exact video
    /// scaling used in this eye, including the optional full-frame 0.5x fit.
    private func mappedPoint(_ raw: CGPoint, size: CGSize) -> CGPoint {
        // Preview pixels are deliberately hidden in Settings and themes.
        // Keep the same sensor dimensions so the pointer does not jump.
        let resolution = ultraWideMode ? ultraWide.imageResolution :
            (runtime.camera?.imageResolution ?? .zero)
        guard resolution.width > 0, resolution.height > 0 else {
            return CGPoint(x: raw.x * size.width, y: raw.y * size.height)
        }
        let iw = resolution.width
        let ih = resolution.height
        let scale = (ultraWideMode && ultraFullFrame
            ? min(size.width / iw, size.height / ih)
            : max(size.width / iw, size.height / ih)) * settings.lens.cameraZoom
        return CGPoint(x: raw.x * iw * scale + (size.width - iw * scale) / 2,
                       y: raw.y * ih * scale + (size.height - ih * scale) / 2)
    }

    /// With the complete 0.5x image letterboxed, map the *interaction
    /// cursor* across the whole eye so headset buttons remain reachable.
    /// The drawn skeleton stays aligned to the true camera image crop.
    private func interactionPoint(_ raw: CGPoint, size: CGSize) -> CGPoint {
        if ultraWideMode && ultraFullFrame {
            return CGPoint(x: raw.x * size.width, y: raw.y * size.height)
        }
        return mappedPoint(raw, size: size)
    }

    /// The reticle is a fixed center-screen target. Head motion moves the
    /// windows behind it; it must never make the reticle itself drift.
    private func dwellCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func processJoyConClick(size: CGSize) {
        guard joyCon.isConnected, !cinemaOpen else { return }
        let point = joyCon.triggerPoint(in: size)
        guard dwellTargetKey(at: point, size: size) != nil else { return }
        triggerDwell(at: point, size: size)
    }

    private func processDwell(size: CGSize) {
        guard dwell.active, !joyCon.isConnected, !cinemaOpen else { return }
        let point = dwellCenter(in: size)
        let key = dwellTargetKey(at: point, size: size)
        if dwell.updateTarget(key) {
            triggerDwell(at: point, size: size)
        }
    }

    private func dwellTargetKey(at point: CGPoint, size: CGSize) -> String? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        guard !productivity.exporting, !importingMedia, !pickingImage,
              productivity.dialog == nil else { return nil }

        if keyboard.destination != nil {
            let key = VRKeyboardGeometry.hit(point, viewport: size,
                symbols: keyboard.symbols, uppercase: keyboard.uppercase)
            if keyboard.hovered != key { keyboard.hovered = key }
            return key.map { "keyboard." + $0 }
        }
        if settingsOpen {
            if let direction = VRSettingsScrollGeometry.direction(at: point, viewport: size) {
                return "settings.scroll.\(direction)"
            }
            let zone = VRSettingsInputGeometry.classify(
                point, viewport: size, page: settings.page)
            switch zone {
            case .close:
                return "settings.close"
            case .back:
                return "settings.back"
            case .search:
                return "settings.search"
            case .none:
                return nil
            case .table:
                let top = VRSettingsInputGeometry.tableTop(page: settings.page)
                guard let row = settings.row(at: point, topInset: top) else {
                    return nil
                }
                if row.kind == .information { return nil }
                if row.kind == .slider {
                    guard settings.isSliderHit(at: point, topInset: top) else {
                        return nil
                    }
                    return "settings.slider." + row.id + "." +
                        String(Int(point.x / 12))
                }
                return "settings.row." + row.id + "." +
                    String(Int(point.x / 18))
            }
        }

        if media.preview != nil || media.loadingPreview {
            guard let action = VRMediaPreviewGeometry.action(at: point, in: size)
            else { return nil }
            return "media." + String(action.rawValue)
        }

        if workspaceOpen {
            let box = VRWorkspaceGeometry.bounds(size)
            if point.y < box.minY + 36 && point.x > box.maxX - 45 {
                return "workspace.close"
            }
            if point.y > box.maxY - 28 {
                if point.x < box.midX - box.width / 6 && workspacePage > 0 {
                    return "workspace.previous"
                }
                let pageCount = max(1, (workspaceItems.count + 5) / 6)
                if point.x > box.midX + box.width / 6 &&
                    workspacePage + 1 < pageCount {
                    return "workspace.next"
                }
                return nil
            }
            if let slot = VRWorkspaceGeometry.item(at: point, in: size) {
                let index = workspacePage * VRWorkspaceGeometry.pageSize + slot
                guard workspaceItems.indices.contains(index) else { return nil }
                return "workspace.item." + workspaceItems[index].id
            }
            return nil
        }

        if lensMenuOpen {
            guard let action = VRLensMenuGeometry.action(at: point, viewport: size)
            else { return nil }
            switch action {
            case .close: return "lens.close"
            case let .profile(index): return "lens.profile." + String(index)
            case let .adjust(row, direction):
                return "lens.adjust." + String(row) + "." + String(direction)
            }
        }

        if !themeMenuOpen && !lensMenuOpen, let action = shellAction(at: point, size: size) {
            if homeLibrary.hovered != action.key { homeLibrary.hovered = action.key }
            return "home." + action.key
        }
        if homeLibrary.hovered != nil { homeLibrary.hovered = nil }
        if VRHomeLayout.blocks(point, viewport: size, model: homeLibrary) { return nil }
        if let id = movingWindowID {
            if point.y <= 38 { return "move.cancel" }
            guard let start = moveStartedAt, hypot(point.x - start.x, point.y - start.y) > 24 else { return nil }
            return "move.place." + id.uuidString + "." + String(Int(point.x / 18)) + "." + String(Int(point.y / 18))
        }
        if let (id, action) = chromeHit(at: point, size: size) {
            return "chrome." + id.uuidString + "." + action.rawValue
        }
        if ultraWideMode && point.y <= 44 {
            return "ultrawide.top." + String(Int(point.x / max(1, size.width / 4)))
        }

        if let focusedID = focusedWebPanelID {
            if point.y < 38 && point.x > size.width - 106 {
                return "web.restore"
            }
            guard let panel = panels.first(where: { $0.id == focusedID }),
                  let center = displayedPanelCenter(panel, size: size, right: false)
            else { return nil }
            let dimensions = displayedPanelSize(panel, size: size)
            guard CGRect(x: center.x - dimensions.width / 2,
                         y: center.y - dimensions.height / 2,
                         width: dimensions.width, height: dimensions.height)
                .contains(point) else { return nil }
            return "web.focused." + String(Int(point.x / 12)) + "." +
                String(Int(point.y / 12))
        }

        if appsOpen {
            let count = VRLauncherApp.all.count
            let warning = appsWarning != nil
            if let direction = VRGestureGeometry.compactAppPageDelta(
                at: point, viewport: size, count: count, warning: warning) {
                return "apps.page." + String(direction)
            }
            if let index = VRGestureGeometry.compactAppRow(
                at: point, viewport: size, count: count, warning: warning,
                page: appsPage) {
                return "apps.row." + String(index)
            }
            if let fraction = VRGestureGeometry.compactAppZoomFraction(
                at: point, viewport: size, count: count, warning: warning) {
                return "apps.zoom." + String(Int(fraction * 20))
            }
            return nil
        }

        if themeMenuOpen {
            let width = min(size.width * 0.86, 330)
            let x = point.x - (size.width - width) / 2
            let y = point.y - (size.height - 250) / 2
            guard x >= 0, x <= width, y >= 32, y <= 225 else {
                return nil
            }
            let column = x < width / 2 ? 0 : 1
            let row = y < 128 ? 0 : 1
            return "theme." + String(row * 2 + column)
        }


        for panel in panels.reversed() where !workspace.state(panel.id).minimized {
            guard let center = displayedPanelCenter(panel, size: size, right: false)
            else { continue }
            let dimensions = displayedPanelSize(panel, size: size)
            let rect = CGRect(x: center.x - dimensions.width / 2,
                              y: center.y - dimensions.height / 2,
                              width: dimensions.width, height: dimensions.height)
            guard rect.contains(point) else { continue }
            let dx = point.x - center.x
            let dy = point.y - center.y
            if panel.kind == .web {
                let handle = grabHandleCenter(center, panel: panel, size: size)
                if abs(point.x - handle.x) <=
                    grabHandleWidth(panel, size: size) / 2 + 12 &&
                    abs(point.y - handle.y) <= 21 {
                    return nil
                }
                return "web.panel." + panel.id.uuidString + "." +
                    String(Int(point.x / 12)) + "." + String(Int(point.y / 12))
            }
            if dx > dimensions.width / 2 - 40 &&
                dy < -dimensions.height / 2 + 40 {
                return "panel.close." + panel.id.uuidString
            }
            if panel.kind == .updates &&
                dy > -dimensions.height / 2 + 40 &&
                dy < dimensions.height / 2 - 35 {
                return "panel.update." + panel.id.uuidString
            }
            if panel.kind == .content, noteSessions[panel.id] != nil,
               dy > dimensions.height / 2 - 63 &&
               dy < dimensions.height / 2 - 24 {
                return "note.toolbar." + panel.id.uuidString + "." +
                    String(Int((dx + dimensions.width / 2 - 12) / 40))
            }
            return nil
        }
        return nil
    }

    private func triggerDwell(at point: CGPoint, size: CGSize) {
        if keyboard.destination != nil {
            if let key = VRKeyboardGeometry.hit(point, viewport: size, symbols: keyboard.symbols, uppercase: keyboard.uppercase) { performKeyboardKey(key) }
            return
        }
        if settingsOpen {
            if let direction = VRSettingsScrollGeometry.direction(at: point, viewport: size) {
                settings.scrollBy(CGFloat(direction) * size.height * 0.6)
                return
            }
            let zone = VRSettingsInputGeometry.classify(
                point, viewport: size, page: settings.page)
            switch zone {
            case .close:
                closeSettings()
            case .back:
                settings.back()
            case .table:
                let top = VRSettingsInputGeometry.tableTop(page: settings.page)
                _ = settings.handlePinchTap(
                    at: point, viewport: size, topInset: top)
            case .search:
                keyboard.open(.settings, title: "Buscar nos Ajustes", text: settings.searchText)
            case .none:
                break
            }
            return
        }

        if media.preview != nil || media.loadingPreview,
           let action = VRMediaPreviewGeometry.action(at: point, in: size) {
            media.performPreview(action)
            return
        }

        if workspaceOpen {
            let box = VRWorkspaceGeometry.bounds(size)
            if point.y < box.minY + 36 && point.x > box.maxX - 45 {
                workspaceOpen = false
            } else if point.y > box.maxY - 28 {
                if point.x < box.midX - box.width / 6 {
                    changeWorkspacePage(-1)
                } else if point.x > box.midX + box.width / 6 {
                    changeWorkspacePage(1)
                }
            } else if let slot = VRWorkspaceGeometry.item(at: point, in: size) {
                let index = workspacePage * VRWorkspaceGeometry.pageSize + slot
                if workspaceItems.indices.contains(index) {
                    performWorkspace(workspaceItems[index].command)
                }
            }
            return
        }

        if !themeMenuOpen && !lensMenuOpen, let action = shellAction(at: point, size: size) { performHomeAction(action); return }
        if VRHomeLayout.blocks(point, viewport: size, model: homeLibrary) { return }
        if movingWindowID != nil { placeMovingWindow(at: point, size: size); return }
        if let (id, action) = chromeHit(at: point, size: size) { performWindowAction(action, id: id, size: size); return }
        let syntheticHand = TrackedHand(
            point: point,
            visible: true,
            pinching: true,
            joints: Array(repeating: nil, count: 21),
            estimatedDepth: nil,
            worldPoint: nil)
        beganPinch(point, hand: syntheticHand, size: size)

        // Web content uses a press/release pair in the existing input path.
        // Complete that pair immediately for a dwell click.
        if let gesture = webPinchGesture {
            webSessions[gesture.panelID]?.tapFromPinch(x: gesture.x, y: gesture.y)
            webPinchGesture = nil
        }
    }

    /// A held pinch scrolls the PRIMARY UITableView, while the other eye
    /// renders exactly the same offset. Short pinches dispatch the same row
    /// actions as UIKit touches. Dragging a slider never scrolls the page.
    private func processSettingsGesture(_ hand: TrackedHand, size: CGSize) {
        guard hand.visible else {
            // Vision losing the hand is NOT the same as fingers separating.
            // Cancel held gestures without clicking any destructive control.
            settingsGesture = nil
            lastPinch = false
            return
        }
        let pointer = interactionPoint(hand.point, size: size)
        if hand.pinching {
            if settingsGesture == nil {
                let top = settings.page == .home
                    ? VRSettingsScreen.toolbarHeight +
                      VRSettingsScreen.searchHeight
                    : VRSettingsScreen.toolbarHeight
                let row = settings.row(at: pointer, topInset: top)
                let sliderID: String?
                if let row = row, row.kind == .slider,
                   settings.isSliderHit(at: pointer, topInset: top) {
                    sliderID = row.id
                } else {
                    sliderID = nil
                }
                settingsGesture = VRSettingsPinch(
                    start: pointer, startingScroll: settings.scrollOffset,
                    sliderID: sliderID)
                if let id = sliderID {
                    settings.setNormalized(id, fraction: settings.sliderFraction(
                        x: pointer.x, width: size.width,
                        localY: pointer.y - top))
                }
            } else if var gesture = settingsGesture {
                let deltaY = pointer.y - gesture.start.y
                let travelled = hypot(pointer.x - gesture.start.x, deltaY)
                if let id = gesture.sliderID {
                    if travelled > 5 { gesture.moved = true }
                    let top = settings.page == .home
                        ? VRSettingsScreen.toolbarHeight +
                          VRSettingsScreen.searchHeight
                        : VRSettingsScreen.toolbarHeight
                    settings.setNormalized(id, fraction: settings.sliderFraction(
                        x: pointer.x, width: size.width,
                        localY: gesture.start.y - top))
                } else if VRSettingsInputGeometry.isScroll(
                    from: gesture.start, to: pointer) {
                    gesture.moved = true
                    if VRSettingsInputGeometry.classify(gesture.start,
                        viewport: size, page: settings.page) == .table {
                        let desired = gesture.startingScroll - deltaY
                        settings.scrollBy(desired - settings.scrollOffset)
                    }
                }
                settingsGesture = gesture
            }
        } else {
            finishSettingsPinch(size: size)
        }
        lastPinch = hand.pinching
    }

    private func finishSettingsPinch(size: CGSize) {
        guard let gesture = settingsGesture else { return }
        settingsGesture = nil
        guard !gesture.moved, gesture.sliderID == nil else { return }
        let pointer = gesture.start
        switch VRSettingsInputGeometry.classify(
            pointer, viewport: size, page: settings.page) {
        case .close:
            closeSettings()
        case .back:
            settings.back()
        case .search:
            settings.focusSearchRequest += 1
        case .table:
            _ = settings.handlePinchTap(
                at: pointer, viewport: size,
                topInset: VRSettingsInputGeometry.tableTop(
                    page: settings.page))
        case .none:
            break
        }
    }

    private func processGesture(_ hand: TrackedHand, size: CGSize) {
        guard productivity.dialog == nil, !productivity.exporting, !importingMedia, !pickingImage else {
            lastPinch = hand.visible && hand.pinching
            mediaDragPoint = nil
            return
        }
        if keyboard.destination != nil {
            if hand.visible && hand.pinching && !lastPinch,
               let key = VRKeyboardGeometry.hit(interactionPoint(hand.point, size: size), viewport: size,
                   symbols: keyboard.symbols, uppercase: keyboard.uppercase) { performKeyboardKey(key) }
            lastPinch = hand.visible && hand.pinching
            return
        }
        if settingsOpen {
            processSettingsGesture(hand, size: size)
            return
        }
        if media.preview != nil || media.loadingPreview {
            if hand.visible && hand.pinching {
                let point = interactionPoint(hand.point, size: size)
                let content = VRMediaPreviewGeometry.content(size)
                if !lastPinch {
                    if let action = VRMediaPreviewGeometry.action(at: point, in: size) {
                        media.performPreview(action)
                    } else if content.contains(point), media.image != nil, media.zoom > 1 {
                        mediaDragPoint = point
                    }
                } else if let previous = mediaDragPoint {
                    media.moveImage(by: CGSize(width: point.x - previous.x, height: point.y - previous.y),
                                    viewport: content.size)
                    mediaDragPoint = point
                }
            } else { mediaDragPoint = nil }
            lastPinch = hand.visible && hand.pinching
            return
        }
        if workspaceOpen {
            if hand.visible && hand.pinching && !lastPinch {
                let point = interactionPoint(hand.point, size: size)
                let box = VRWorkspaceGeometry.bounds(size)
                if point.y < box.minY + 36 {
                    if point.x > box.maxX - 45 { workspaceOpen = false }
                } else if point.y > box.maxY - 28 {
                    if point.x < box.midX - box.width / 6 { changeWorkspacePage(-1) }
                    if point.x > box.midX + box.width / 6 { changeWorkspacePage(1) }
                } else if let slot = VRWorkspaceGeometry.item(at: point, in: size) {
                    let index = workspacePage * 6 + slot
                    if workspaceItems.indices.contains(index) {
                        performWorkspace(workspaceItems[index].command)
                    }
                }
            }
            lastPinch = hand.visible && hand.pinching
            return
        }
        // Cinema owns pinch gestures while open. Never activate the OS dock
        // behind the movie when changing stereo playback settings.
        guard !cinemaOpen else { return }
        guard hand.visible else {
            lastPinch = false
            drag = nil
            ultraDrag = nil
            webPinchGesture = nil
            notePinchGesture = nil
            return
        }

        let pointer = interactionPoint(hand.point, size: size)
        if hand.pinching && !lastPinch {
            beganPinch(pointer, hand: hand, size: size)
        } else if hand.pinching, var held = drag,
                  let index = panels.firstIndex(where: { $0.id == held.panelID }) {
            updateSpatialGrab(hand, pointer: pointer, held: &held, panelIndex: index)
            drag = held
        } else if hand.pinching, let held = ultraDrag {
            // True ultrawide Vision fingertip controls a 2D angular window
            // anchor. No fake metre translation or depth data is invented.
            let destination = CGPoint(
                x: held.initialCentre.x + pointer.x - held.initialPointer.x,
                y: held.initialCentre.y + pointer.y - held.initialPointer.y)
            ultraPanelDirections[held.panelID] =
                VRUltraWideWindowProjection.anchoredDirection(
                    at: destination, viewport: size,
                    headRotation: effectiveUltraRotation)
        } else if hand.pinching, var webGesture = webPinchGesture {
            let dx = pointer.x - webGesture.initialPointer.x
            let dy = pointer.y - webGesture.initialPointer.y
            if hypot(dx, dy) > 13 { webGesture.moved = true }
            if webGesture.moved {
                webSessions[webGesture.panelID]?.scrollFromPinch(
                    startY: webGesture.startScrollY, fingerDeltaY: dy)
            }
            webPinchGesture = webGesture
        } else if hand.pinching, let noteGesture = notePinchGesture {
            noteSessions[noteGesture.panelID]?.scrollFromPinch(
                startY: noteGesture.startScrollY,
                fingerDeltaY: pointer.y - noteGesture.initialPointerY)
        } else if !hand.pinching {
            if lastPinch, let gesture = webPinchGesture, !gesture.moved {
                webSessions[gesture.panelID]?.tapFromPinch(x: gesture.x, y: gesture.y)
            }
            webPinchGesture = nil
            notePinchGesture = nil
            drag = nil
            ultraDrag = nil
        }
        lastPinch = hand.pinching
    }

    private func updateSpatialGrab(_ hand: TrackedHand, pointer: CGPoint,
                                   held: inout WindowDrag, panelIndex: Int) {
        guard runtime.spatialTracking else { return }

        // Vision produces noisy fingertip estimates while fingers are touching.
        let alpha: CGFloat = 0.26
        held.filteredPointer = CGPoint(
            x: held.filteredPointer.x + (pointer.x - held.filteredPointer.x) * alpha,
            y: held.filteredPointer.y + (pointer.y - held.filteredPointer.y) * alpha
        )
        let dx = held.filteredPointer.x - held.initialPointer.x
        let dy = held.filteredPointer.y - held.initialPointer.y
        let travel = hypot(dx, dy)

        if !held.planarEnabled {
            held.planarConfirmations = travel >= 16 ? held.planarConfirmations + 1 : 0
            if held.planarConfirmations >= 3 { held.planarEnabled = true }
        }

        // Consume the fingertip noise deadzone instead of causing a grab jump.
        let remaining = held.planarEnabled ? max(0, travel - 16) : 0
        let factor = travel > 0 ? remaining / travel : 0
        let deltaX = Float(dx * factor)
        let deltaY = Float(dy * factor)
        let moveXY = held.cameraRight * (deltaX * held.horizontalMetresPerPoint)
                   - held.cameraUp * (deltaY * held.verticalMetresPerPoint)

        // Hand depth is only an estimate from palm size (no LiDAR on this phone).
        // Clamp outliers and low-pass filter before allowing Z movement.
        if let raw = hand.estimatedDepth, let old = held.filteredHandDepth {
            let bounded = max(old - 0.12, min(old + 0.12, raw))
            held.filteredHandDepth = old * 0.76 + bounded * 0.24
        }
        var targetDepth = held.initialWindowDepth
        if let baseline = held.initialHandDepth,
           let filtered = held.filteredHandDepth {
            let handDisplacement = filtered - baseline
            if !held.depthEnabled {
                held.depthConfirmations = abs(handDisplacement) >= 0.10
                    ? held.depthConfirmations + 1 : 0
                if held.depthConfirmations >= 3 { held.depthEnabled = true }
            }
            if held.depthEnabled {
                // Pushing the hand outward makes the window come forward
                // (larger/nearer), as requested; pulling back moves it away.
                let beyondNoise = max(0, abs(handDisplacement) - 0.10)
                let signed = handDisplacement >= 0 ? beyondNoise : -beyondNoise
                targetDepth = max(0.65, min(4.0,
                    held.initialWindowDepth - signed * 2.4))
            }
        }

        // A camera-relative depth change becomes a true world-space translation.
        let moveZ = held.cameraBackward * (held.initialWindowDepth - targetDepth)
        let candidate = held.initialAnchor + moveXY + moveZ

        // Never rewrite a world anchor for negligible landmark movement.
        guard simd_distance(candidate, held.lastAppliedAnchor) >= 0.018 else { return }
        held.lastAppliedAnchor = candidate
        panels[panelIndex].anchor = candidate
        panels[panelIndex].depth = Double(targetDepth)
    }

    private func beganPinch(_ pointer: CGPoint, hand: TrackedHand, size: CGSize) {
        if keyboard.destination != nil {
            if let key = VRKeyboardGeometry.hit(pointer, viewport: size, symbols: keyboard.symbols, uppercase: keyboard.uppercase) { performKeyboardKey(key) }
            return
        }
        if let action = shellAction(at: pointer, size: size) { performHomeAction(action); return }
        if VRHomeLayout.blocks(pointer, viewport: size, model: homeLibrary) { return }
        if let (id, action) = chromeHit(at: pointer, size: size) { performWindowAction(action, id: id, size: size); return }
        if let id = focusedWebPanelID, pointer.y < 38,
           pointer.x > size.width - 106 {
            if workspace.focused == id { workspace.focus(id) }
            focusedWebPanelID = nil
            return
        }
        if lensMenuOpen {
            // Vision pinch never triggers SwiftUI Button.touchUpInside, so
            // menu hit positions must match VRLensMenuGeometry exactly.
            if let action = VRLensMenuGeometry.action(at: pointer, viewport: size) {
                switch action {
                case .close:
                    lensMenuOpen = false
                case let .profile(index):
                    if let selected = VRLensProfile(rawValue: index) {
                        settings.lens.choose(selected)
                    }
                case let .adjust(row, direction):
                    adjustLens(row: row, direction: direction)
                }
            }
            return
        }
        // A real hand pinch can also reach ultrawide's lens/headset switches.
        if ultraWideMode && pointer.y <= 44 {
            let quarter = size.width / 4
            if pointer.x < quarter {
                recenterUltraWide()
            } else if pointer.x < quarter * 2 {
                ultraFullFrame.toggle()
            } else if pointer.x < quarter * 3 {
                toggleUltraMotionDirection()
            } else {
                toggleUltraWide()
            }
            return
        }
        if let focusedID = focusedWebPanelID {
            if let panel = panels.first(where: { $0.id == focusedID }) {
                _ = beginWebPanelPinch(panel, pointer: pointer, size: size)
            } else {
                focusedWebPanelID = nil
            }
            return
        }
        if appsOpen {
            let count = VRLauncherApp.all.count
            let warning = appsWarning != nil
            let pageCount = VRGestureGeometry.compactAppPageCount(
                viewport: size, warning: warning, count: count)
            if let direction = VRGestureGeometry.compactAppPageDelta(
                at: pointer, viewport: size, count: count, warning: warning) {
                appsPage = max(0, min(pageCount - 1, appsPage + direction))
            } else if let index = VRGestureGeometry.compactAppRow(
                at: pointer, viewport: size, count: count,
                warning: warning, page: appsPage) {
                openLauncherApp(VRLauncherApp.all[index])
            } else if let fraction = VRGestureGeometry.compactAppZoomFraction(
                at: pointer, viewport: size, count: count, warning: warning) {
                webWindowZoom = 0.65 + fraction * 0.90
            } else {
                // Tap outside to dismiss, but never select an invisible row.
                let width = VRGestureGeometry.appMenuWidth(viewport: size)
                let left = (size.width - width) / 2
                let height = VRGestureGeometry.compactAppMenuHeight(
                    viewport: size, warning: warning, count: count)
                if pointer.x < left || pointer.x > left + width ||
                   abs(pointer.y - size.height / 2) > height / 2 {
                    appsOpen = false
                }
            }
            return
        }
        if themeMenuOpen {
            let width = min(size.width * 0.86, 330)
            let x = pointer.x - (size.width - width) / 2
            let y = pointer.y - (size.height - 250) / 2
            if x >= 0 && x <= width && y >= 32 && y <= 225 {
                let column = x < width / 2 ? 0 : 1
                let row = y < 128 ? 0 : 1
                chooseTheme(VRTheme.allCases[row * 2 + column])
            } else { themeMenuOpen = false }
            return
        }
        // Only the white line is a 3D movement handle. Its hit area is
        // larger than its visible thickness for comfortable hand gestures.
        for panel in panels.reversed() where !workspace.state(panel.id).minimized {
            if ultraWideMode {
                guard let center = displayedPanelCenter(
                    panel, size: size, right: false) else { continue }
                let handle = grabHandleCenter(center, panel: panel, size: size)
                guard abs(pointer.x - handle.x) <=
                          grabHandleWidth(panel, size: size) / 2 + 12,
                      abs(pointer.y - handle.y) <= 21 else { continue }
                ultraDrag = UltraWideDrag(
                    panelID: panel.id, initialPointer: pointer,
                    initialCentre: CGPoint(
                        x: center.x - min(CGFloat(10),
                            CGFloat(7 / max(panel.depth, 0.65))),
                        y: center.y))
                return
            }
            guard let center = windowCenter(panel, size: size, right: false),
                  let anchor = panel.anchor,
                  let pose = runtime.camera, runtime.spatialTracking else { continue }
            let handle = grabHandleCenter(center, panel: panel, size: size)
            guard abs(pointer.x - handle.x) <= grabHandleWidth(panel, size: size) / 2 + 12,
                  abs(pointer.y - handle.y) <= 21 else { continue }

            let transform = pose.transform
            let cameraSpace = simd_inverse(transform)
                * SIMD4<Float>(anchor.x, anchor.y, anchor.z, 1)
            let depth = max(0.65, min(4.0, -cameraSpace.z))
            let resolution = pose.imageResolution
            let fillScale = max(size.width / max(resolution.width, 1),
                                size.height / max(resolution.height, 1))
            let fx = max(1, pose.intrinsics.columns.0.x * Float(fillScale))
            let fy = max(1, pose.intrinsics.columns.1.y * Float(fillScale))
            let right = SIMD3<Float>(transform.columns.0.x,
                                     transform.columns.0.y,
                                     transform.columns.0.z)
            let up = SIMD3<Float>(transform.columns.1.x,
                                  transform.columns.1.y,
                                  transform.columns.1.z)
            let backward = SIMD3<Float>(transform.columns.2.x,
                                        transform.columns.2.y,
                                        transform.columns.2.z)
            drag = WindowDrag(
                panelID: panel.id, initialAnchor: anchor,
                initialPointer: pointer, initialHandDepth: hand.estimatedDepth,
                initialWindowDepth: depth,
                cameraRight: right, cameraUp: up, cameraBackward: backward,
                horizontalMetresPerPoint: depth / fx,
                verticalMetresPerPoint: depth / fy,
                filteredPointer: pointer, filteredHandDepth: hand.estimatedDepth,
                lastAppliedAnchor: anchor
            )
            return
        }
        for panel in panels.reversed() where !workspace.state(panel.id).minimized {
            guard let center = displayedPanelCenter(panel, size: size, right: false)
            else { continue }
            let dimensions = displayedPanelSize(panel, size: size)
            let dx = pointer.x - center.x
            let dy = pointer.y - center.y
            guard abs(dx) < dimensions.width / 2,
                  abs(dy) < dimensions.height / 2 else { continue }
            if panel.kind == .web {
                _ = beginWebPanelPinch(panel, pointer: pointer, size: size)
                return
            }
            if dx > dimensions.width / 2 - 40 &&
               dy < -dimensions.height / 2 + 40 {
                close(panel.id)
                return
            }
            if panel.kind == .updates && dy > -dimensions.height / 2 + 40 &&
                dy < dimensions.height / 2 - 35 {
                Task { await updates.check() }
                return
            }
            if panel.kind == .content, let note = noteSessions[panel.id] {
                if dy > dimensions.height / 2 - 63 &&
                   dy < dimensions.height / 2 - 24 {
                    let localX = dx + dimensions.width / 2 - 12
                    let cellWidth = max(1, (dimensions.width - 24) / 4)
                    let slot = max(0, min(3, Int(localX / cellWidth)))
                    switch slot {
                    case 0: note.adjustFontSize(-1)
                    case 1: note.scrollBy(-95)
                    case 2: note.scrollBy(95)
                    default: note.adjustFontSize(1)
                    }
                    return
                }
                if dy > -dimensions.height / 2 + 39 &&
                   dy < dimensions.height / 2 - 65 {
                    notePinchGesture = NotePinchGesture(
                        panelID: panel.id,
                        initialPointerY: pointer.y,
                        startScrollY: note.offsetY
                    )
                }
            }
            return
        }
    }

    /// The website is now usable without touching the iPhone: short pinch
    /// selects a link/button and a held vertical pinch scrolls the page.
    /// This is a best-effort WebKit DOM click, not a trusted system tap.
    @discardableResult
    private func beginWebPanelPinch(_ panel: VRPanel, pointer: CGPoint,
                                    size: CGSize) -> Bool {
        guard panel.kind == .web,
              let browser = webSessions[panel.id],
              let center = displayedPanelCenter(panel, size: size, right: false)
        else { return false }
        let dims = displayedPanelSize(panel, size: size)
        let left = center.x - dims.width / 2
        let top = center.y - dims.height / 2
        let x = pointer.x - left
        let y = pointer.y - top
        guard x >= 0 && x <= dims.width, y >= 0 && y <= dims.height
        else { return false }

        if y <= 42 {
            if x >= dims.width - 45 {
                close(panel.id)
            } else if x >= dims.width - 98 {
                focusedWebPanelID = focusedWebPanelID == panel.id ? nil : panel.id
                appsOpen = false
                themeMenuOpen = false
            }
            return true
        }
        // Header includes a bookmark star and address-Go shortcut.
        if y >= 43 && y < 77 {
            if x >= dims.width - 49 {
                browser.navigate()
            } else if x >= dims.width - 83 {
                browser.toggleFavorite()
            } else {
                keyboard.open(.browser(panel.id), title: "Endereço ou pesquisa", text: browser.address)
            }
            return true
        }

        // The WebWindow has a navigation row and a second row for scrolling.
        if y >= 76 && y < 111 {
            let slot = VRGestureGeometry.webToolbarSlot(
                localX: x, width: dims.width)
            switch slot {
            case 0: browser.back()
            case 1: browser.forward()
            case 2: browser.reload()
            case 3: browser.goHome()
            case 4: browser.openInSafari()
            case 5: browser.adjustPageZoom(-0.15)
            default: browser.adjustPageZoom(0.15)
            }
            return true
        }
        if y >= 111 && y < 145 {
            if x < dims.width * 0.28 {
                browser.scrollByPage(-1)
            } else if x > dims.width * 0.72 {
                browser.scrollByPage(1)
            }
            return true
        }

        if !browser.favorites.isEmpty && y >= 144 && y < 177 {
            if let index = VRGestureGeometry.webFavoriteSlot(
                localX: x, width: dims.width,
                count: browser.favorites.count) {
                browser.openFavorite(index)
            }
            return true
        }

        let contentTop = top + VRGestureGeometry.webContentTop(
            hasFavorites: !browser.favorites.isEmpty)
        let contentBottom = top + dims.height - 30
        guard pointer.y >= contentTop && pointer.y <= contentBottom,
              dims.height > 180 else { return true }
        webPinchGesture = WebPinchGesture(
            panelID: panel.id,
            initialPointer: pointer,
            startScrollY: browser.primary?.scrollView.contentOffset.y ?? 0,
            x: max(0.01, min(0.99, (x - 12) / max(1, dims.width - 24))),
            y: max(0.01, min(0.99,
                (pointer.y - contentTop) / max(1, contentBottom - contentTop)))
        )
        return true
    }

    private func adjustDepth(_ id: UUID, to rawValue: Double, size: CGSize,
                             lockedCenter: CGPoint? = nil) {
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
        let value = min(4.0, max(0.65, rawValue))
        // Move the window's world position along the camera-to-window ray.
        // This changes real spatial parallax as well as apparent size.
        let center = lockedCenter ?? windowCenter(panels[index], size: size, right: false)
        if let center = center,
           let anchor = runtime.worldPoint(at: center, viewport: size, depth: Float(value)) {
            panels[index].anchor = anchor
            panels[index].depth = value
        }
    }

    private func close(_ id: UUID) {
        angularDirections.removeValue(forKey: id)
        if movingWindowID == id { movingWindowID = nil; moveStartedAt = nil }
        workspace.remove(id)
        panels.removeAll { $0.id == id }
        webSessions.removeValue(forKey: id)
        noteSessions.removeValue(forKey: id)
        if webSessions.count < 3 { appsWarning = nil }
        if notePinchGesture?.panelID == id { notePinchGesture = nil }
        if drag?.panelID == id { drag = nil }
        if ultraDrag?.panelID == id { ultraDrag = nil }
        ultraPanelDirections.removeValue(forKey: id)
        if webPinchGesture?.panelID == id { webPinchGesture = nil }
        if focusedWebPanelID == id { focusedWebPanelID = nil }
    }

    private func applyRemoteWindowContent(_ manifest: RemoteManifest) {
        for index in panels.indices {
            guard let templateID = panels[index].templateID,
                  let template = manifest.templates.first(where: { $0.id == templateID })
            else { continue }
            panels[index].title = template.title
            panels[index].icon = template.symbol
            panels[index].text = template.text
            noteSessions[panels[index].id]?.text = template.text
            // Keep user's chosen depth / anchor: live content updates should not
            // teleport already-placed windows.
        }
    }

    private func registerUltraWindow(_ panel: VRPanel) {
        if !cameraEnabled {
            let point = CGPoint(x: eyeViewport.width / 2 + panel.x * eyeViewport.width / 2,
                                y: eyeViewport.height / 2 + panel.y * eyeViewport.height / 2)
            angularDirections[panel.id] = VRUltraWideWindowProjection.anchoredDirection(
                at: point, viewport: eyeViewport, headRotation: effectiveDwellRotation)
        }
        guard ultraWideMode else { return }
        let point = CGPoint(
            x: eyeViewport.width / 2 + panel.x * eyeViewport.width / 2,
            y: eyeViewport.height / 2 + panel.y * eyeViewport.height / 2)
        ultraPanelDirections[panel.id] =
            VRUltraWideWindowProjection.anchoredDirection(
                at: point, viewport: eyeViewport,
                headRotation: effectiveUltraRotation)
    }

    private func openRemoteWindow() {
        let templates = updates.manifest.templates
        guard !templates.isEmpty else { return }
        let template = templates[nextRemoteTemplateIndex % templates.count]
        nextRemoteTemplateIndex += 1
        let panel = VRPanel(
            title: template.title,
            icon: template.symbol,
            text: template.text,
            x: CGFloat((nextRemoteTemplateIndex % 3) - 1) * 0.14,
            y: CGFloat(nextRemoteTemplateIndex % 2 == 0 ? -0.38 : -0.28),
            depth: template.depth,
            templateID: template.id
        )
        panels.append(panel)
        registerUltraWindow(panel)
    }

    private func openUpdatesWindow() {
        if panels.contains(where: { $0.kind == .updates }) { return }
        let panel = VRPanel(
            title: "Atualizações online",
            icon: "arrow.down.circle",
            text: "",
            x: 0.08,
            y: -0.30,
            depth: Double(settings.defaultDepth),
            kind: .updates
        )
        panels.append(panel)
        registerUltraWindow(panel)
    }

    private func openLauncherApp(_ item: VRLauncherApp) {
        switch item {
        case let .web(app): openWebApp(app)
        case .settings: openSettings()
        case .files: performWorkspace(.files)
        case .photos: performWorkspace(.photos)
        }
    }

    private func openWebApp(_ app: VRWebApp) {
        homeLibrary.opened(app.rawValue)
        if let existing = panels.first(where: { $0.webApp == app && webSessions[$0.id] != nil }) {
            if workspace.state(existing.id).minimized { workspace.minimize(existing.id) }
            focusedWebPanelID = existing.id
            appsOpen = false
            return
        }
        // Each web app uses one WKWebView per eye. Keep a small cap so five
        // streaming apps cannot exhaust an iPhone's memory in the headset.
        guard webSessions.count < 3 else {
            homeLibrary.show(.windows)
            appsWarning = "Limite de 3 sites. Feche uma janela web para abrir outro."
            return
        }
        appsWarning = nil
        let browser = VRWebSession(app: app)
        browser.setPageZoom(max(1.0, webWindowZoom * 1.15))
        let newPanel = VRPanel(
            title: app.title, icon: app.symbol,
            text: app.description,
            x: 0,
            y: -0.02,
            depth: Double(settings.defaultDepth),
            kind: .web,
            webApp: app
        )
        webSessions[newPanel.id] = browser
        panels.append(newPanel)
        registerUltraWindow(newPanel)
        appsOpen = false
        themeMenuOpen = false
        dockExpanded = false
    }

    private func appsLauncher(size: CGSize) -> some View {
        let count = VRLauncherApp.all.count
        let warning = appsWarning != nil
        let rows = VRGestureGeometry.compactAppRows(
            viewport: size, warning: warning, count: count)
        let pages = VRGestureGeometry.compactAppPageCount(
            viewport: size, warning: warning, count: count)
        let page = min(max(0, appsPage), pages - 1)
        let visibleApps = Array(VRLauncherApp.all.dropFirst(page * rows)
            .prefix(rows))
        return VStack(spacing: VRGestureGeometry.appRowGap) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                Text("CENTRAL DE APPS").tracking(0.7)
                Spacer(minLength: 0)
                Button { appsOpen = false } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11, weight: .bold))
            .frame(height: VRGestureGeometry.appHeaderHeight)
            HStack(spacing: 8) {
                Text("Tamanho das janelas")
                    .font(.system(size: 10))
                Slider(value: $webWindowZoom, in: 0.65...1.55, step: 0.05)
                    .tint(.cyan)
                Text("\(Int(webWindowZoom * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 35)
            }
            .frame(height: VRGestureGeometry.appZoomHeight)
            if let warning = appsWarning {
                Text(warning)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.yellow)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(height: VRGestureGeometry.appWarningHeight)
            }
            HStack(spacing: 2) {
                Button { appsPage = max(0, page - 1) } label: {
                    Text("◀ Ant.")
                        .frame(maxWidth: .infinity)
                }
                .disabled(page == 0)
                Text("\(page + 1)/\(pages)")
                    .frame(maxWidth: .infinity)
                Button { appsPage = min(pages - 1, page + 1) } label: {
                    Text("Próx. ▶")
                        .frame(maxWidth: .infinity)
                }
                .disabled(page >= pages - 1)
            }
            .font(.system(size: 9, weight: .semibold))
            .frame(height: VRGestureGeometry.compactAppPagerHeight)
            ForEach(visibleApps) { app in
                Button { openLauncherApp(app) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(app.accent)
                            .frame(width: 29)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.title)
                                .font(.system(size: 12, weight: .bold))
                            Text(app.subtitle)
                                .font(.system(size: 9))
                                .lineLimit(2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: VRGestureGeometry.appRowHeight)
                    .padding(.horizontal, 7)
                    .background(.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: min(size.width * 0.89, 330))
        .foregroundStyle(.white)
        .background(Color(white: 0.065).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.21), lineWidth: 1))
    }


    private var workspaceItems: [VRWorkspaceItem] {
        if let photos = mediaMode {
            var list = [
                VRWorkspaceItem(id: "media.back", title: "Central", detail: "Voltar", symbol: "chevron.left", command: .mediaBack),
                VRWorkspaceItem(id: "media.import", title: photos ? "Escolher fotos" : "Importar arquivo",
                    detail: media.importing ? "Importando…" : "O original é preservado", symbol: "plus",
                    command: photos ? .importPhoto : .importFile),
                VRWorkspaceItem(id: "media.search", title: "Buscar", detail: media.query.isEmpty ? "Por nome" : media.query,
                    symbol: "magnifyingglass", command: .mediaSearch),
                VRWorkspaceItem(id: "media.sort", title: "Ordenar", detail: media.sort.title,
                    symbol: "arrow.up.arrow.down", command: .mediaSort),
                VRWorkspaceItem(id: "media.favorites", title: "Favoritos", detail: media.favoritesOnly ? "Somente favoritos" : "Todos os itens",
                    symbol: "star.fill", command: .mediaFavorites),
                VRWorkspaceItem(id: "media.filter", title: photos ? "Limpar filtros" : "Tipo de arquivo",
                    detail: photos ? "Mostrar todas as fotos" : (media.kindFilter?.rawValue ?? "Todos"),
                    symbol: "line.3.horizontal.decrease.circle", command: photos ? .mediaReset : .mediaFilter),
                VRWorkspaceItem(id: "media.reset", title: "Limpar busca e filtros", detail: "Voltar à lista completa",
                    symbol: "arrow.counterclockwise", command: .mediaReset)
            ]
            let visible = media.visibleEntries(photosOnly: photos)
            if visible.isEmpty {
                list[2] = VRWorkspaceItem(id: "media.search", title: "Nenhum resultado", detail: "Buscar por outro nome",
                    symbol: "magnifyingglass", command: .mediaSearch)
            }
            for entry in visible {
                list.append(VRWorkspaceItem(id: entry.id.uuidString, title: entry.title,
                    detail: ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file),
                    symbol: entry.kind == .image ? "photo" : "doc",
                    command: .mediaOpen(entry.id)))
                list.append(VRWorkspaceItem(id: entry.id.uuidString + ".favorite",
                    title: entry.favorite == true ? "Remover favorito" : "Favoritar", detail: entry.title,
                    symbol: entry.favorite == true ? "star.fill" : "star", command: .mediaFavorite(entry.id)))
                list.append(VRWorkspaceItem(id: entry.id.uuidString + ".rename", title: "Renomear", detail: entry.title,
                    symbol: "pencil", command: .mediaRename(entry.id)))
                list.append(VRWorkspaceItem(id: entry.id.uuidString + ".delete",
                    title: pendingMediaDelete == entry.id ? "Confirmar exclusão" : "Excluir cópia",
                    detail: entry.title, symbol: "trash", command: .mediaDelete(entry.id)))
            }
            return list
        }
        let _ = webRevision
        var items = [
            VRWorkspaceItem(id: "settings", title: "Ajustes", detail: "Preferências", symbol: "gearshape.fill", command: .settings),
            VRWorkspaceItem(id: "camera", title: "Câmera", detail: ultraWideMode ? "0,5x ativo" : "ARKit ativo", symbol: "camera.aperture", command: .camera),
            VRWorkspaceItem(id: "center", title: "Centralizar", detail: "Trazer janelas", symbol: "scope", command: .center),
            VRWorkspaceItem(id: "themes", title: "Ambiente", detail: selectedTheme.title, symbol: "sparkles", command: .theme),
            VRWorkspaceItem(id: "hud", title: "Barra de status", detail: settings.showHUD ? "Visível" : "Oculta", symbol: "rectangle.topthird.inset.filled", command: .hud),
            VRWorkspaceItem(id: "updates", title: "Atualizações", detail: "Buscar conteúdo", symbol: "arrow.down.circle.fill", command: .updates)
        ]
        items += [
            VRWorkspaceItem(id: "files", title: "Arquivos", detail: "Cópias locais", symbol: "folder.fill", command: .files),
            VRWorkspaceItem(id: "photos", title: "Fotos", detail: "Imagens importadas", symbol: "photo", command: .photos)
        ]
        items += [
            VRWorkspaceItem(id: "diagnostics", title: "Diagnóstico", detail: "Câmera, mão e temperatura", symbol: "waveform.path.ecg", command: .diagnostics),
            VRWorkspaceItem(id: "diagnostics.export", title: "Exportar diagnóstico", detail: "Relatório local em texto", symbol: "square.and.arrow.up", command: .exportDiagnostics),
            VRWorkspaceItem(id: "backup.export", title: "Salvar ajustes", detail: "Exportar backup JSON", symbol: "externaldrive.badge.checkmark", command: .exportBackup),
            VRWorkspaceItem(id: "backup.restore", title: "Restaurar backup", detail: "Escolher arquivo de ajustes", symbol: "arrow.counterclockwise.circle", command: .restoreBackup)
        ]
        let hand = ultraWideMode ? ultraWide.hand : runtime.hand
        items += [
            VRWorkspaceItem(id: "hands", title: "Mãos e calibração",
                detail: hand.visible ? "\(hand.joints.compactMap { $0 }.count)/21 pontos" : "Mostre a mão",
                symbol: "hand.draw.fill", command: .hands),
            VRWorkspaceItem(id: "motion", title: "Animações",
                detail: settings.reduceMotion ? "Reduzidas" : "Ativas",
                symbol: "sparkles", command: .motion),
            VRWorkspaceItem(id: "calibrate", title: "Calibrar pinça",
                detail: "Ative com a pinça fechada", symbol: "hand.pinch.fill",
                command: .calibrateHands)
        ]
        for scenery in VRScenery.allCases {
            items.append(VRWorkspaceItem(id: "scene.\(scenery.rawValue)", title: scenery.title,
                detail: sceneryIndex == scenery.rawValue ? "Selecionado" : "Aplicar ambiente",
                symbol: "globe.americas.fill", command: .scenery(scenery.rawValue)))
        }
        for panel in panels {
            if let browser = webSessions[panel.id] {
                items += [
                    VRWorkspaceItem(id: "\(panel.id).tab.new", title: "Nova aba", detail: panel.title,
                        symbol: "plus.square", command: .newTab(panel.id)),
                    VRWorkspaceItem(id: "\(panel.id).tab.next", title: "Trocar aba",
                        detail: "\(browser.tabs.count) abas", symbol: "square.on.square", command: .nextTab(panel.id)),
                    VRWorkspaceItem(id: "\(panel.id).tab.close", title: "Fechar aba", detail: panel.title,
                        symbol: "xmark.square", command: .closeTab(panel.id)),
                    VRWorkspaceItem(id: "\(panel.id).history.clear", title: "Limpar histórico",
                        detail: "Apagar URLs salvas", symbol: "clock.arrow.circlepath", command: .clearHistory(panel.id)),
                    VRWorkspaceItem(id: "\(panel.id).safari", title: "Abrir no Safari",
                        detail: "Alternativa para streaming protegido", symbol: "safari",
                        command: .externalWeb(panel.id))
                ]
                if browser.lastClosedURL != nil {
                    items.append(VRWorkspaceItem(id: "\(panel.id).tab.reopen", title: "Reabrir aba fechada", detail: panel.title,
                        symbol: "arrow.uturn.backward", command: .reopenTab(panel.id)))
                }
                for (index, tab) in browser.tabs.enumerated() {
                    items.append(VRWorkspaceItem(id: "\(panel.id).tab.\(tab.id)",
                        title: "Aba \(index + 1)" + (tab.id == browser.activeTabID ? " · ativa" : ""),
                        detail: tab.url.host ?? tab.url.absoluteString, symbol: "globe", command: .selectTab(panel.id, tab.id)))
                }
                for (index, url) in browser.history.prefix(6).enumerated() {
                    items.append(VRWorkspaceItem(id: "\(panel.id).history.\(index)",
                        title: url.host ?? "Histórico", detail: url.absoluteString,
                        symbol: "clock", command: .history(panel.id, url.absoluteString)))
                }
            }
            let state = workspace.state(panel.id)
            items += [
                VRWorkspaceItem(id: "\(panel.id).min", title: panel.title, detail: state.minimized ? "Restaurar janela" : "Minimizar janela", symbol: "minus.rectangle", command: .minimize(panel.id)),
                VRWorkspaceItem(id: "\(panel.id).focus", title: "Maximizar", detail: panel.title, symbol: "arrow.up.left.and.arrow.down.right", command: .focus(panel.id)),
                VRWorkspaceItem(id: "\(panel.id).small", title: "Diminuir", detail: "\(Int(state.scale * 100))%", symbol: "minus.magnifyingglass", command: .smaller(panel.id)),
                VRWorkspaceItem(id: "\(panel.id).large", title: "Aumentar", detail: "\(Int(state.scale * 100))%", symbol: "plus.magnifyingglass", command: .larger(panel.id)),
                VRWorkspaceItem(id: "\(panel.id).close", title: "Fechar", detail: panel.title, symbol: "xmark.rectangle", command: .close(panel.id))
            ]
        }
        return items
    }

    private func changeWorkspacePage(_ delta: Int) {
        let maximum = max(0, (workspaceItems.count - 1) / 6)
        workspacePage = max(0, min(maximum, workspacePage + delta))
    }

    private func performWorkspace(_ command: VRWorkspaceCommand) {
        homeLibrary.visible = false
        homeLibrary.quickSettings = false
        defer { if workspaceOpen { changeWorkspacePage(0) } }
        switch command {
        case .settings: workspaceOpen = false; openSettings()
        case .camera: toggleUltraWide()
        case .center: centreAllWindows()
        case .theme: workspaceOpen = false; themeMenuOpen = true
        case .hud: settings.showHUD.toggle()
        case .hands:
            workspaceOpen = false
            openSettings()
            settings.enter(.hands)
            let hand = ultraWideMode ? ultraWide.hand : runtime.hand
            settings.notice = hand.visible
                ? "\(hand.joints.compactMap { $0 }.count)/21 pontos · ajuste a sensibilidade e teste a pinça"
                : "Mostre a palma com boa luz e ajuste a sensibilidade"
        case .motion: settings.reduceMotion.toggle()
        case .calibrateHands:
            let hand = ultraWideMode ? ultraWide.hand : runtime.hand
            workspaceOpen = false
            openSettings()
            settings.enter(.hands)
            guard hand.visible, hand.pinching,
                  let thumb = hand.joints[4], let tip = hand.joints[8],
                  let index = hand.joints[5], let little = hand.joints[17] else {
                settings.notice = "Feche a pinça sobre Calibrar na Central com boa luz"
                return
            }
            let palm = max(0.04, hypot(index.x - little.x, index.y - little.y))
            let ratio = hypot(thumb.x - tip.x, thumb.y - tip.y) / palm
            let sensitivity = max(0, min(1, (ratio + 0.06 - 0.43) / 0.18 + 0.5))
            settings.setNormalized("hands.sensitivity", fraction: sensitivity)
            settings.notice = "Amostra de pinça aplicada; teste abrir e fechar a mão"
        case .files, .photos:
            if case .photos = command { mediaMode = true } else { mediaMode = false }
            media.resetFilters()
            workspacePage = 0; pendingMediaDelete = nil; workspaceOpen = true
            appsOpen = false; media.message = nil
        case .mediaBack: mediaMode = nil; workspacePage = 0; pendingMediaDelete = nil
        case .importFile: if !media.importing { productivity.importingBackup = false; importingMedia = true }
        case .importPhoto: if !media.importing { pickingImage = true }
        case .mediaSearch:
            productivity.draft = media.query; productivity.dialog = .search
        case .mediaSort:
            media.sort = VRMediaSort(rawValue: (media.sort.rawValue + 1) % VRMediaSort.allCases.count) ?? .recent
            workspacePage = 0; pendingMediaDelete = nil
        case .mediaFavorites:
            media.favoritesOnly.toggle(); workspacePage = 0; pendingMediaDelete = nil
        case .mediaFilter:
            let kinds: [VRMediaKind?] = [nil, .image, .text, .pdf, .movie]
            let index = kinds.firstIndex(where: { $0 == media.kindFilter }) ?? 0
            media.kindFilter = kinds[(index + 1) % kinds.count]
            workspacePage = 0; pendingMediaDelete = nil
        case .mediaReset: media.resetFilters(); workspacePage = 0; pendingMediaDelete = nil
        case let .mediaFavorite(id):
            pendingMediaDelete = nil
            do { try media.toggleFavorite(id); changeWorkspacePage(0) }
            catch { media.message = error.localizedDescription }
        case let .mediaRename(id):
            guard let entry = media.entries.first(where: { $0.id == id }) else { return }
            pendingMediaDelete = nil
            productivity.draft = entry.title; productivity.dialog = .rename(id)
        case let .mediaOpen(id):
            pendingMediaDelete = nil
            guard let entry = media.entries.first(where: { $0.id == id }) else { return }
            if entry.kind == .movie {
                guard !ultraWideMode else {
                    media.message = "Volte ao ARKit para abrir este vídeo no Cinema"
                    return
                }
                workspaceOpen = false
                activateDock(2)
                cinema.loadMovie(media.url(for: entry), displayTitle: entry.title)
            } else {
                let gallery = media.visibleEntries(photosOnly: true).map(\.id)
                Task { await media.open(entry, gallery: gallery) }
            }
        case let .mediaDelete(id):
            guard let entry = media.entries.first(where: { $0.id == id }) else { return }
            guard pendingMediaDelete == id else { pendingMediaDelete = id; return }
            pendingMediaDelete = nil
            do { try media.remove(entry); changeWorkspacePage(0) }
            catch { media.message = error.localizedDescription }
        case .movie, .favoriteMovie, .deleteMovie, .cinemaTool: break
        case let .newTab(id): webSessions[id]?.newTab(); webRevision += 1
        case let .externalWeb(id): webSessions[id]?.openInSafari()
        case let .nextTab(id): webSessions[id]?.nextTab(); webRevision += 1
        case let .closeTab(id): webSessions[id]?.closeActiveTab(); webRevision += 1
        case let .reopenTab(id): webSessions[id]?.reopenClosedTab(); webRevision += 1; changeWorkspacePage(0)
        case let .selectTab(id, tab): webSessions[id]?.selectTab(tab); webRevision += 1
        case .diagnostics:
            let text = diagnosticReport()
            if let index = panels.firstIndex(where: { $0.templateID == "local.diagnostics" }) {
                panels[index].text = text
                noteSessions[panels[index].id]?.text = text
                noteSessions[panels[index].id]?.scroll(to: 0)
                if workspace.state(panels[index].id).minimized { workspace.minimize(panels[index].id) }
            } else {
                let panel = VRPanel(title: "Diagnóstico VR-OS", icon: "waveform.path.ecg", text: text,
                    depth: Double(settings.defaultDepth), templateID: "local.diagnostics")
                panels.append(panel); registerUltraWindow(panel)
            }
            workspaceOpen = false
        case .exportDiagnostics:
            productivity.export(Data(diagnosticReport().utf8), type: .plainText, filename: "VR-OS-diagnostico")
        case .exportBackup:
            do {
                synchronizeRuntimePreferences()
                let backup = VRSettingsBackup(settings: settings, scenery: sceneryIndex)
                productivity.export(try backup.encoded(), type: .json, filename: "VR-OS-ajustes")
            } catch { productivity.dialog = .message(error.localizedDescription) }
        case .restoreBackup:
            guard !cameraTransitioning else { return }
            productivity.importingBackup = true; importingMedia = true
        case .clearHistory:
            for browser in webSessions.values { browser.clearHistory() }
            webRevision += 1; changeWorkspacePage(0)
        case let .history(id, url):
            guard let browser = webSessions[id] else { return }
            browser.address = url
            browser.navigate()
            if workspace.state(id).minimized { workspace.minimize(id) }
            focusedWebPanelID = id
            workspaceOpen = false
        case let .scenery(index):
            sceneryIndex = index
            if index != 0 && ultraWideMode { toggleUltraWide() }
        case .updates:
            workspaceOpen = false
            openUpdatesWindow()
            Task { await updates.check() }
        case let .minimize(id):
            workspace.minimize(id)
            if workspace.state(id).minimized && focusedWebPanelID == id { focusedWebPanelID = nil }
        case let .focus(id):
            workspace.focus(id)
            focusedWebPanelID = workspace.focused
            workspaceOpen = false
        case let .smaller(id): workspace.resize(id, by: -0.1)
        case let .larger(id): workspace.resize(id, by: 0.1)
        case let .close(id): close(id); changeWorkspacePage(0)
        }
    }

    private func diagnosticReport() -> String {
        let hand = ultraWideMode ? ultraWide.hand : runtime.hand
        let bytes = media.entries.reduce(Int64(0)) { total, entry in
            let result = total.addingReportingOverflow(entry.bytes)
            return result.overflow ? Int64.max : result.partialValue
        }
        return VRDiagnostics.report(camera: ultraWideMode ? ultraWide.status : runtime.cameraStatus,
            tracking: ultraWideMode ? (ultraWide.motionAvailable ? "3DoF" : "Sem sensor") :
                (runtime.spatialTracking ? "ARKit normal" : "ARKit limitado"),
            handPoints: hand.visible ? hand.joints.compactMap { $0 }.count : 0,
            pinching: hand.visible && hand.pinching, mediaCount: media.entries.count,
            mediaBytes: bytes, webCount: webSessions.count)
    }

    private func exitCinema() {
        cinema.exit()
        cinemaOpen = false
        runtime.setCinemaMode(false)
        dockExpanded = false
        lastPinch = false
    }

    private func activateTaskbar(_ action: VRTaskbarAction) {
        switch action {
        case .home:
            mediaMode = nil
            workspacePage = 0
            workspaceOpen.toggle()
            appsOpen = false
            themeMenuOpen = false
            lensMenuOpen = false
        case .apps:
            activateDock(1)
        case .cinema:
            activateDock(2)
        case .files:
            performWorkspace(.files)
        case .photos:
            performWorkspace(.photos)
        case .browser:
            openLauncherApp(.web(.browser))
        case .settings:
            openSettings()
        case .newWindow:
            activateDock(0)
        }
    }

    private func activateDock(_ slot: Int) {
        switch slot {
        case 0:
            let count = panels.count + 1
            panels.append(VRPanel(
                title: "Janela \(count)", icon: "macwindow",
                text: "GUIA DO VR-OS V48\n\n"
                    + "1. A mira acompanha sua cabeça. Pare sobre um botão por 1 segundo para selecionar.\n\n"
                    + "2. Biblioteca: abra apps, pesquise, fixe atalhos e recupere janelas minimizadas.\n\n"
                    + "3. A barra abaixo da janela permite mover, redimensionar, expandir, minimizar e fechar. Para mover, selecione as setas, olhe para o novo local e aguarde.\n\n"
                    + "4. O relógio abre ajustes rápidos. Centralizar traz as janelas para a frente e recalibra a mira.\n\n"
                    + "5. O teclado espacial pesquisa apps e permite digitar endereços no Navegador.\n\n"
                    + "6. Cinema: Controles abre reprodução e ajustes, Filmes abre a biblioteca local e Sair volta ao Home.\n\n"
                    + "7. A câmera é opcional. Ligue pelo dock quando quiser testar ARKit e rastreamento de mão. Visor ajusta os dois olhos para seu VR Box.",
                x: CGFloat((count % 3) - 1) * 0.15,
                y: CGFloat(count % 2 == 0 ? -0.38 : -0.28),
                depth: Double(settings.defaultDepth)))
            if let newPanel = panels.last { registerUltraWindow(newPanel) }
        case 1:
            homeLibrary.show()
            themeMenuOpen = false
            lensMenuOpen = false
        case 2:
            homeLibrary.visible = false
            homeLibrary.quickSettings = false
            if ultraWideMode {
                ultraNotice = "Cinema usa ARKit · volte ao modo normal"
                dockExpanded = false
                return
            }
            for browser in webSessions.values { browser.suspendMedia() }
            drag = nil
            webPinchGesture = nil
            appsOpen = false
            themeMenuOpen = false
            lensMenuOpen = false
            runtime.setCinemaMode(true)
            cinema.enter(camera: runtime.camera)
            if cinema.controlsVisible { cinema.toggleMenu() }
            cinemaOpen = true
        case 3:
            mediaMode = nil
            workspacePage = 0
            workspaceOpen.toggle()
            appsOpen = false
            themeMenuOpen = false
        case 4:
            themeMenuOpen.toggle()
            if themeMenuOpen { appsOpen = false; lensMenuOpen = false }
        case 5:
            if ultraWideMode {
                recenterUltraWide()
            } else {
                for index in panels.indices {
                    panels[index].x = 0
                    panels[index].y = 0
                    panels[index].anchor = nil
                }
            }
        case 6:
            toggleUltraWide()
        case 7:
            lensMenuOpen.toggle()
            if lensMenuOpen {
                appsOpen = false
                themeMenuOpen = false
            }
        default:
            break
        }
    }
}

