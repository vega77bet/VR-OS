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
    @State private var panels = [
        VRPanel(title: "Bem-vindo ao VR OS", icon: "square.stack.3d.up",
                text: "Janelas fixas no ambiente com ARKit.\n"
                    + "Segure a linha branca sob a janela com a pinça.\n"
                    + "Mova a mão para posicionar a janela no espaço.", y: -0.34, depth: 1.5)
    ]
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
                guard let pose = pose else { return }
                anchorPendingPanels(pose: pose, size: eyeSize)
            }
            .onReceive(runtime.$hand) { hand in
                if !ultraWideMode { processGesture(hand, size: eyeSize) }
            }
            .onReceive(ultraWide.$hand) { hand in
                if ultraWideMode { processGesture(hand, size: eyeSize) }
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
            selectedTheme = VRTheme(rawValue:
                UserDefaults.standard.integer(forKey: "vros.selectedTheme.v1")) ?? .graphite
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
            UIDevice.current.isBatteryMonitoringEnabled = true
            runtime.setCameraPreviewEnabled(selectedTheme == .graphite)
            runtime.setCinemaMode(cinemaOpen)
            if settings.cameraUltra && !ultraWideMode &&
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
        .onChange(of: selectedTheme) { theme in
            runtime.setCameraPreviewEnabled(
                theme == .graphite && !settingsOpen)
        }
        .onChange(of: focusedWebPanelID) { id in
            workspace.synchronizeFocus(id)
        }
        .onChange(of: settings.revision) { _ in
            applySettingsChanges()
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
                runtime.stop()
            } else if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                if ultraWideMode {
                    recenterUltraWide()
                    ultraWide.start()
                } else {
                    runtime.setCinemaMode(cinemaOpen)
                    runtime.resume()
                    if cinemaOpen { cinema.enter(camera: runtime.camera) }
                }
            }
        }
        .onDisappear {
            if cinemaOpen { cinema.exit() }
            ultraWide.stop()
            runtime.setCinemaMode(false)
            runtime.stop()
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
        appsOpen = false
        lensMenuOpen = false
        themeMenuOpen = false
        focusedWebPanelID = nil
        settingsGesture = nil
        lastPinch = false
        settings.searchText = ""
        settings.enter(.home)
        settingsOpen = true
        // The opaque Settings surface needs camera pose + Vision but does
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
        runtime.setCameraPreviewEnabled(selectedTheme == .graphite)
        ultraWide.setDisplayEnabled(true)
        settingsGesture = nil
        lastPinch = false
        settings.notice = nil
        settings.pendingConfirmation = nil
    }

    private func centreAllWindows() {
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

        if let request = settings.command {
            settings.command = nil
            switch request.kind {
            case .recenterWindows:
                centreAllWindows()
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
        if settings.cameraUltra != ultraWideMode && !cameraTransitioning {
            toggleUltraWide()
        }
    }

    private func toggleUltraWide() {
        guard !cameraTransitioning, !cinemaOpen else { return }
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
                runtime.setCameraPreviewEnabled(
                    selectedTheme == .graphite && !settingsOpen)
                if scenePhase == .active { runtime.resume() }
                cameraTransitioning = false
                if settings.cameraUltra { toggleUltraWide() }
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
                    runtime.setCameraPreviewEnabled(
                        selectedTheme == .graphite && !settingsOpen)
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
        let w = size.width
        let h = size.height
        let shownHand = ultraWideMode ? ultraWide.hand : runtime.hand
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
            } else if sceneryIndex != 0 {
                VRSceneryView(scenery: VRScenery(rawValue: sceneryIndex) ?? .original,
                              camera: runtime.camera)
            } else if selectedTheme == .cosmos {
                SpaceSkyView(camera: runtime.camera, size: size)
            } else if selectedTheme == .aurora || selectedTheme == .synthwave {
                ThemeAtmosphereView(isAurora: selectedTheme == .aurora,
                                    camera: runtime.camera, size: size)
            } else if let frame = runtime.cameraImage {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .scaleEffect(settings.lens.cameraZoom)
                    .clipped()
                    .allowsHitTesting(false)
            } else {
                Color.black.overlay {
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Iniciando câmera")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.75))
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
                    if focusedWebPanelID != panel.id {
                        grabHandle(panel, size: size)
                            .position(grabHandleCenter(center, panel: panel, size: size))
                    }
                }
            }

            if focusedWebPanelID == nil {
                if settings.showHUD {
                    statusBar(size: size)
                        .position(x: w / 2, y: ultraWideMode ? 76 : 28)
                }

                if themeMenuOpen {
                    themePicker(size: size).position(x: w / 2, y: h / 2)
                }
                if appsOpen {
                    appsLauncher(size: size).position(x: w / 2, y: h / 2)
                }
                if lensMenuOpen {
                    lensCalibrationPanel(size: size)
                        .position(x: w / 2, y: h / 2)
                        .zIndex(10)
                }

                dock(size: size)
                    .position(x: w / 2, y: dockCenterY(size))
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
                         "0,5x REAL · mão Vision + cabeça 3DoF · sem 6DoF")
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

            if shownHand.visible && settings.showCursor && !settingsOpen {
                let cursor = interactionPoint(shownHand.point, size: size)
                VRPrecisionCursor(pinching: shownHand.pinching, size: settings.cursorSize,
                                  reduceMotion: settings.reduceMotion)
                .position(cursor)
                .allowsHitTesting(false)
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
                                 onClose: { closeSettings() })
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
                    ? "Vision: \(ultraWide.hand.visible ? "mão visível" : "sem mão") · cabeça \(ultraWide.motionAvailable ? "3DoF" : "indisponível")"
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
                VRWebWindow(session: browser, rightEye: right)
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
            (selectedTheme == .graphite ? Color(white: updates.manifest.theme.surfaceGray) : selectedTheme.surface)
                .opacity(updates.manifest.theme.surfaceOpacity *
                         settings.windowOpacity),
            in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(selectedTheme.accent.opacity(0.45), lineWidth: 1))
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
        // The taskbar uses the same rectangles for drawing and Vision.
        if let action = VRTaskbarGeometry.action(at: pointer, viewport: size,
                                     items: updates.frontend.enabledTaskbar) {
            activateTaskbar(action)
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
        if let existing = panels.first(where: { $0.webApp == app && webSessions[$0.id] != nil }) {
            if workspace.state(existing.id).minimized { workspace.minimize(existing.id) }
            focusedWebPanelID = existing.id
            appsOpen = false
            return
        }
        // Each web app uses one WKWebView per eye. Keep a small cap so five
        // streaming apps cannot exhaust an iPhone's memory in the headset.
        guard webSessions.count < 3 else {
            appsWarning = "Limite de 3 apps abertos. Feche uma janela para continuar."
            appsOpen = true
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
                text: "GUIA RÁPIDO DO VR-OS V21\n\n"
                    + "1. Pinça na linha branca: arraste a janela pelo ambiente.\n\n"
                    + "2. Segure a pinça sobre este texto e mova a mão para ROLAR a janela.\n\n"
                    + "3. Use as setas ↑/↓ para subir e descer. A−/A+ deixam o texto menor ou maior.\n\n"
                    + "4. Apps: Ajustes, YouTube, Netflix, Navegador, Twitch e Wikipedia. "
                    + "A estrela salva favoritos, a lupa ajusta zoom e o ícone de expandir abre o Modo Foco.\n\n"
                    + "5. Cinema: poltronas selecionadas por olhar por 1,5 s. "
                    + "Use Centralizar e Mirar tela antes de testar os movimentos.\n\n"
                    + "6. A dock vira um botão no canto para liberar a visão. "
                    + "Toque nesse botão para reabrir as ferramentas.\n\n"
                    + "7. O campo óptico depende das lentes do headset; "
                    + "se sentir desconforto, pare e ajuste o encaixe.",
                x: CGFloat((count % 3) - 1) * 0.15,
                y: CGFloat(count % 2 == 0 ? -0.38 : -0.28),
                depth: Double(settings.defaultDepth)))
            if let newPanel = panels.last { registerUltraWindow(newPanel) }
        case 1:
            appsOpen.toggle()
            if appsOpen {
                appsPage = 0
                themeMenuOpen = false
                lensMenuOpen = false
            }
        case 2:
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

