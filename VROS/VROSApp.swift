import ARKit
import SwiftUI

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

struct VRHomeView: View {
    @StateObject private var runtime = VRRuntime()
    @StateObject private var updates = LiveUpdateManager()
    @State private var nextRemoteTemplateIndex = 0
    @State private var selectedTheme: VRTheme = .graphite
    @State private var themeMenuOpen = false
    @State private var appsOpen = false
    @State private var dockExpanded = true
    @State private var webSessions: [UUID: VRWebSession] = [:]
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
            let eyeSize = CGSize(width: geometry.size.width / 2, height: geometry.size.height)
            HStack(spacing: 0) {
                if cinemaOpen {
                    CinemaEyeView(rightEye: false, runtime: runtime, cinema: cinema, updates: updates,
                                  onExit: { exitCinema() })
                    CinemaEyeView(rightEye: true, runtime: runtime, cinema: cinema, updates: updates,
                                  onExit: { exitCinema() })
                } else {
                    eyeView(right: false, size: eyeSize)
                    eyeView(right: true, size: eyeSize)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .overlay(alignment: .center) {
                Rectangle().fill(.black).frame(width: 3).allowsHitTesting(false)
            }
            .onReceive(runtime.$camera) { pose in
                guard let pose = pose else { return }
                anchorPendingPanels(pose: pose, size: eyeSize)
            }
            .onReceive(runtime.$hand) { hand in
                processGesture(hand, size: eyeSize)
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
            runtime.start()
            Task { await updates.check() }
        }
        .onChange(of: webWindowZoom) { zoom in
            UserDefaults.standard.set(Double(zoom), forKey: "vros.webZoom.v1")
        }
        .onDisappear {
            runtime.setCinemaMode(false)
            runtime.stop()
        }
    }

    private func eyeView(right: Bool, size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            if selectedTheme == .cosmos {
                SpaceSkyView(camera: runtime.camera, size: size)
            } else if selectedTheme == .aurora || selectedTheme == .synthwave {
                ThemeAtmosphereView(isAurora: selectedTheme == .aurora,
                                    camera: runtime.camera, size: size)
            } else if let frame = runtime.cameraImage {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
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

            if selectedTheme == .graphite {
                Color.black.opacity(0.10).allowsHitTesting(false)
            }

            ForEach(panels) { panel in
                if focusedWebPanelID == nil || focusedWebPanelID == panel.id,
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
                statusBar(size: size)
                    .position(x: w / 2, y: 28)

                if themeMenuOpen {
                    themePicker(size: size).position(x: w / 2, y: h / 2)
                }
                if appsOpen {
                    appsLauncher(size: size).position(x: w / 2, y: h / 2)
                }

                dock(size: size)
                    .position(x: dockExpanded ? w / 2 : 24,
                              y: dockExpanded ? dockCenterY(size) : h - 24)
            }

            if runtime.hand.visible {
                HandSkeletonOverlay(hand: runtime.hand) { joint in
                    mappedPoint(joint, size: size)
                }
                .allowsHitTesting(false)

                let cursor = mappedPoint(runtime.hand.point, size: size)
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: runtime.hand.pinching ? 3 : 2)
                        .frame(width: runtime.hand.pinching ? 29 : 21,
                               height: runtime.hand.pinching ? 29 : 21)
                    Circle().fill(.white).frame(width: 5, height: 5)
                }
                .shadow(color: .black, radius: 3)
                .position(cursor)
                .allowsHitTesting(false)
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
                    .fill(runtime.spatialTracking ? Color.white : Color.gray)
                    .frame(width: 5, height: 5)
                Text(updates.manifest.headline)
                    .tracking(1.0)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(runtime.cameraStatus)
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
    private func dockCenterY(_ size: CGSize) -> CGFloat { size.height * 0.91 }

    private func dock(size: CGSize) -> some View {
        Group {
            if dockExpanded {
                HStack(spacing: 5) {
                    dockButton("plus.rectangle.on.rectangle", "Janela", slot: 0, size: size)
                    dockButton("square.grid.2x2.fill", "Apps", slot: 1, size: size)
                    dockButton("film.stack.fill", "Cinema", slot: 2, size: size)
                    dockButton("arrow.down.circle", "Atualizar", slot: 3, size: size)
                    dockButton("paintpalette.fill", "Temas", slot: 4, size: size)
                    dockButton("scope", "Centro", slot: 5, size: size)
                }
                .padding(5)
                .background(selectedTheme.surface.opacity(0.95),
                            in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1))
            } else {
                Button { dockExpanded = true } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 37, height: 37)
                        .background(selectedTheme.surface.opacity(0.93),
                                    in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir menu do VR-OS")
            }
        }
    }

    private func dockButton(_ symbol: String, _ label: String, slot: Int,
                            size: CGSize) -> some View {
        Button {
            activateDock(slot)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(label).font(.system(size: 9, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(width: max(24, (size.width - 50) / 6), height: 48)
            .background(selectedTheme.accent.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
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
            } else {
                Text(panel.text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
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
                .opacity(updates.manifest.theme.surfaceOpacity),
            in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(selectedTheme.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.50), radius: 11, y: 5)
    }

    private func displayedPanelSize(_ panel: VRPanel, size: CGSize) -> CGSize {
        if focusedWebPanelID == panel.id {
            return CGSize(width: size.width * 0.995, height: size.height * 0.99)
        }
        let scale = windowScale(panel)
        return CGSize(width: panelWidth(panel, size: size) * scale,
                      height: panelHeight(panel, size: size) * scale)
    }

    private func displayedPanelCenter(_ panel: VRPanel, size: CGSize,
                                      right: Bool) -> CGPoint? {
        if focusedWebPanelID == panel.id {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        return windowCenter(panel, size: size, right: right)
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
        min(size.width * 0.72, max(70, panelWidth(panel, size: size) * windowScale(panel) * 0.68))
    }

    private func grabHandleCenter(_ center: CGPoint, panel: VRPanel,
                                  size: CGSize) -> CGPoint {
        CGPoint(x: center.x,
                y: center.y + panelHeight(panel, size: size) * windowScale(panel) / 2 + 22)
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
                        .frame(height: 86)
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
        selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "vros.selectedTheme.v1")
        themeMenuOpen = false
    }

    private func panelWidth(_ size: CGSize) -> CGFloat { min(350, size.width * 0.75) }
    private func panelHeight(_ size: CGSize) -> CGFloat { min(180, size.height * 0.39) }
    private func windowScale(_ panel: VRPanel) -> CGFloat {
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

    /// Image(decorative:) is .scaledToFill for each eye; use the SAME crop for joints.
    private func mappedPoint(_ raw: CGPoint, size: CGSize) -> CGPoint {
        guard let image = runtime.cameraImage else {
            return CGPoint(x: raw.x * size.width, y: raw.y * size.height)
        }
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let scale = max(size.width / iw, size.height / ih)
        return CGPoint(x: raw.x * iw * scale - (iw * scale - size.width) / 2,
                       y: raw.y * ih * scale - (ih * scale - size.height) / 2)
    }

    private func processGesture(_ hand: TrackedHand, size: CGSize) {
        // Cinema owns pinch gestures while open. Never activate the OS dock
        // behind the movie when changing stereo playback settings.
        guard !cinemaOpen else { return }
        guard hand.visible else {
            lastPinch = false
            drag = nil
            webPinchGesture = nil
            return
        }

        let pointer = mappedPoint(hand.point, size: size)
        if hand.pinching && !lastPinch {
            beganPinch(pointer, hand: hand, size: size)
        } else if hand.pinching, var held = drag,
                  let index = panels.firstIndex(where: { $0.id == held.panelID }) {
            updateSpatialGrab(hand, pointer: pointer, held: &held, panelIndex: index)
            drag = held
        } else if hand.pinching, var webGesture = webPinchGesture {
            let dx = pointer.x - webGesture.initialPointer.x
            let dy = pointer.y - webGesture.initialPointer.y
            if hypot(dx, dy) > 13 { webGesture.moved = true }
            if webGesture.moved {
                webSessions[webGesture.panelID]?.scrollFromPinch(
                    startY: webGesture.startScrollY, fingerDeltaY: dy)
            }
            webPinchGesture = webGesture
        } else if !hand.pinching {
            if lastPinch, let gesture = webPinchGesture, !gesture.moved {
                webSessions[gesture.panelID]?.tapFromPinch(x: gesture.x, y: gesture.y)
            }
            webPinchGesture = nil
            drag = nil
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
        if let focusedID = focusedWebPanelID {
            if let panel = panels.first(where: { $0.id == focusedID }) {
                _ = beginWebPanelPinch(panel, pointer: pointer, size: size)
            } else {
                focusedWebPanelID = nil
            }
            return
        }
        if appsOpen {
            // Use the same rows/spacing as appsLauncher, including the
            // zoom slider and newly installed site entries. Previously the
            // hardcoded 3-row map opened the WRONG app after V13.
            let width = min(size.width * 0.89, 330)
            let menuLeft = (size.width - width) / 2
            let warningHeight: CGFloat = appsWarning == nil ? 0 : 32
            let menuHeight = 20 + 17 + 22 +
                CGFloat(VRWebApp.allCases.count) * 49 +
                CGFloat(VRWebApp.allCases.count + 1) * 7 + warningHeight
            let menuTop = (size.height - menuHeight) / 2
            let zoomTop = menuTop + 10 + 17 + 7
            let firstRowTop = zoomTop + 22 + 7 + warningHeight
            let localX = pointer.x - menuLeft
            if localX >= 0 && localX <= width {
                let localRowY = pointer.y - firstRowTop
                if localRowY >= 0 {
                    let index = Int(localRowY / 56)
                    if index >= 0 && index < VRWebApp.allCases.count &&
                       localRowY - CGFloat(index) * 56 <= 49 {
                        openWebApp(VRWebApp.allCases[index])
                    }
                } else if pointer.y >= zoomTop && pointer.y < zoomTop + 22 {
                    let fraction = max(0, min(1, (localX - 110) / max(1, width - 157)))
                    webWindowZoom = 0.65 + fraction * 0.90
                }
            } else {
                appsOpen = false
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
        // When hidden, the dock shrinks to a small bottom-left launcher.
        // Otherwise its large touch area blocked the website grab handle.
        if !dockExpanded {
            if pointer.x < 49 && abs(pointer.y - (size.height - 24)) < 26 {
                dockExpanded = true
                return
            }
        } else {
            let dockWidth = max(24, (size.width - 50) / 6) * 6 + 5 * 5 + 10
            let dockLeft = (size.width - dockWidth) / 2
            if abs(pointer.y - dockCenterY(size)) <= 37 &&
               pointer.x >= dockLeft - 8 &&
               pointer.x <= dockLeft + dockWidth + 8 {
                let cell = max(24, (size.width - 50) / 6) + 5
                let slot = min(5, max(0, Int((pointer.x - dockLeft - 5) / cell)))
                activateDock(slot)
                dockExpanded = false
                return
            }
        }

        // Only the white line is a 3D movement handle. Its hit area is
        // larger than its visible thickness for comfortable hand gestures.
        for panel in panels.reversed() {
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
        for panel in panels.reversed() {
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
            // A pinch on the panel itself does not drag it.
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
        // WebWindow's second toolbar row: Back, Forward, Reload, Home, Safari.
        if y >= 76 && y < 110 {
            let slot = min(4, max(0,
                Int((x - 12) / max(1, (dims.width - 24) / 5))))
            switch slot {
            case 0: browser.back()
            case 1: browser.forward()
            case 2: browser.reload()
            case 3: browser.goHome()
            default: browser.openInSafari()
            }
            return true
        }

        let contentTop = top + 112
        let contentBottom = top + dims.height - 43
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
        panels.removeAll { $0.id == id }
        webSessions.removeValue(forKey: id)
        if webSessions.count < 3 { appsWarning = nil }
        if drag?.panelID == id { drag = nil }
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
            // Keep user's chosen depth / anchor: live content updates should not
            // teleport already-placed windows.
        }
    }

    private func openRemoteWindow() {
        let templates = updates.manifest.templates
        guard !templates.isEmpty else { return }
        let template = templates[nextRemoteTemplateIndex % templates.count]
        nextRemoteTemplateIndex += 1
        panels.append(VRPanel(
            title: template.title,
            icon: template.symbol,
            text: template.text,
            x: CGFloat((nextRemoteTemplateIndex % 3) - 1) * 0.14,
            y: CGFloat(nextRemoteTemplateIndex % 2 == 0 ? -0.38 : -0.28),
            depth: template.depth,
            templateID: template.id
        ))
    }

    private func openUpdatesWindow() {
        if panels.contains(where: { $0.kind == .updates }) { return }
        panels.append(VRPanel(
            title: "Atualizações online",
            icon: "arrow.down.circle",
            text: "",
            x: 0.08,
            y: -0.30,
            depth: 1.3,
            kind: .updates
        ))
    }

    private func openWebApp(_ app: VRWebApp) {
        // Each web app uses one WKWebView per eye. Keep a small cap so five
        // streaming apps cannot exhaust an iPhone's memory in the headset.
        guard webSessions.count < 3 else {
            appsWarning = "Limite de 3 apps abertos. Feche uma janela para continuar."
            appsOpen = true
            return
        }
        appsWarning = nil
        let browser = VRWebSession(app: app)
        let offset = webSessions.count % 3
        let newPanel = VRPanel(
            title: app.title, icon: app.symbol,
            text: app.description,
            x: 0,
            y: -0.02,
            depth: 1.2,
            kind: .web,
            webApp: app
        )
        webSessions[newPanel.id] = browser
        panels.append(newPanel)
        appsOpen = false
        themeMenuOpen = false
        dockExpanded = false
    }

    private func appsLauncher(size: CGSize) -> some View {
        VStack(spacing: 7) {
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
            HStack(spacing: 8) {
                Text("Tamanho das janelas")
                    .font(.system(size: 10))
                Slider(value: $webWindowZoom, in: 0.65...1.55, step: 0.05)
                    .tint(.cyan)
                Text("\(Int(webWindowZoom * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 35)
            }
            if let warning = appsWarning {
                Text(warning)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(VRWebApp.allCases) { app in
                Button { openWebApp(app) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(app.accent)
                            .frame(width: 29)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.title)
                                .font(.system(size: 12, weight: .bold))
                            Text(app.description)
                                .font(.system(size: 9))
                                .lineLimit(2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
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

    private func exitCinema() {
        cinema.exit()
        cinemaOpen = false
        runtime.setCinemaMode(false)
        dockExpanded = false
        lastPinch = false
    }

    private func activateDock(_ slot: Int) {
        switch slot {
        case 0:
            let count = panels.count + 1
            panels.append(VRPanel(
                title: "Janela \(count)", icon: "macwindow",
                text: "Janela ancorada com ARKit.\n"
                    + "Pegue a linha branca abaixo para mover em 3D.\n"
                    + "Use Cinema para assistir aos seus arquivos MP4.",
                x: CGFloat((count % 3) - 1) * 0.15,
                y: CGFloat(count % 2 == 0 ? -0.38 : -0.28),
                depth: 1.6))
        case 1:
            appsOpen.toggle()
            if appsOpen { themeMenuOpen = false }
        case 2:
            drag = nil
            webPinchGesture = nil
            appsOpen = false
            themeMenuOpen = false
            runtime.setCinemaMode(true)
            cinema.enter(camera: runtime.camera)
            cinemaOpen = true
        case 3:
            openUpdatesWindow()
            Task { await updates.check() }
        case 4:
            themeMenuOpen.toggle()
            if themeMenuOpen { appsOpen = false }
        default:
            for index in panels.indices {
                panels[index].x = 0
                panels[index].y = 0
                panels[index].anchor = nil
            }
        }
    }
}
