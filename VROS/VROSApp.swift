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

private struct WindowDrag {
    enum Mode { case move, depth }
    let panelID: UUID
    let mode: Mode
    let firstPointer: CGPoint
    let pointerOffset: CGSize
    let initialDepth: Double
    let initialHandDepth: Float?
    let fixedScreenCenter: CGPoint
    let initialAnchor: SIMD3<Float>?
    var movementStarted = false
    var filteredPointer: CGPoint
    var lastAppliedPointer: CGPoint
    var activationFrames = 0
    var movementFrames = 0
    let depthTrackStart: CGFloat
    let depthTrackLength: CGFloat
}

struct VRHomeView: View {
    @StateObject private var runtime = VRRuntime()
    @StateObject private var updates = LiveUpdateManager()
    @State private var nextRemoteTemplateIndex = 0
    @State private var selectedTheme: VRTheme = .graphite
    @State private var themeMenuOpen = false
    @State private var panels = [
        VRPanel(title: "Bem-vindo ao VR OS", icon: "square.stack.3d.up",
                text: "Janelas fixas no ambiente com ARKit.\n"
                    + "Segure a pinça para selecionar; mova a mão para arrastar.\n"
                    + "Use a linha Z abaixo de cada janela.", y: -0.34, depth: 1.5)
    ]
    @State private var lastPinch = false
    @State private var drag: WindowDrag?

    var body: some View {
        GeometryReader { geometry in
            let eyeSize = CGSize(width: geometry.size.width / 2, height: geometry.size.height)
            HStack(spacing: 0) {
                eyeView(right: false, size: eyeSize)
                eyeView(right: true, size: eyeSize)
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
            runtime.start()
            Task { await updates.check() }
        }
        .onDisappear { runtime.stop() }
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
                if let center = windowCenter(panel, size: size, right: right) {
                    let scale = windowScale(panel)
                    panelView(panel, size: size)
                        .frame(width: panelWidth(size) * scale,
                               height: panelHeight(size) * scale)
                        .position(center)
                    depthBar(panel, size: size)
                        .position(x: center.x, y: center.y + panelHeight(size) * scale / 2 + 25)
                }
            }

            statusBar(size: size)
                .position(x: w / 2, y: 28)

            if themeMenuOpen {
                themePicker(size: size).position(x: w / 2, y: h / 2)
            }

            dock(size: size)
                .position(x: w / 2, y: dockCenterY(size))

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
    private func dockCenterY(_ size: CGSize) -> CGFloat { size.height * 0.74 }

    private func dock(size: CGSize) -> some View {
        HStack(spacing: 5) {
            dockButton("plus.rectangle.on.rectangle", "Janela", slot: 0, size: size)
            dockButton("square.grid.2x2", "Apps", slot: 1, size: size)
            dockButton("arrow.down.circle", "Atualizar", slot: 2, size: size)
            dockButton("paintpalette.fill", "Temas", slot: 3, size: size)
            dockButton("scope", "Centro", slot: 4, size: size)
        }
        .padding(5)
        .background(selectedTheme.surface.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17)
            .stroke(Color.white.opacity(0.15), lineWidth: 1))
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
            .frame(width: max(26, (size.width - 50) / 5), height: 48)
            .background(selectedTheme.accent.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func panelView(_ panel: VRPanel, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: panel.icon)
                    .foregroundStyle(.white.opacity(0.75))
                Text(panel.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
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

            if panel.kind == .updates {
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

            Spacer(minLength: 0)
            Text("Pinça para mover · linha Z abaixo para profundidade")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
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

    // Independent, hand-draggable depth control BELOW each window.
    private func depthBarWidth(_ size: CGSize) -> CGFloat {
        max(100, min(size.width * 0.82, 180))
    }

    private func depthBar(_ panel: VRPanel, size: CGSize) -> some View {
        let width = depthBarWidth(size)
        let track = width - 24
        let fraction = CGFloat((panel.depth - 0.65) / 3.35)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("PERTO")
                Spacer(minLength: 1)
                Text(String(format: "Z %.2f m", panel.depth))
                    .fontWeight(.semibold)
                Spacer(minLength: 1)
                Text("LONGE")
            }
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.88))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(width: track, height: 4)
                Capsule().fill(selectedTheme.accent)
                    .frame(width: max(3, track * fraction), height: 4)
                Circle().fill(.white)
                    .frame(width: 12, height: 12)
                    .offset(x: track * fraction - 6)
            }
            .frame(width: track, height: 14, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(width: width, height: 40)
        .background(selectedTheme.surface.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selectedTheme.accent.opacity(0.52), lineWidth: 1))
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
            return min(2.5, max(0.3, CGFloat(1.5 / panel.depth)))
        }
        let position = camera.transform.columns.3
        let distance = simd_distance(anchor, SIMD3<Float>(position.x, position.y, position.z))
        return min(2.5, max(0.3, CGFloat(1.5 / max(distance, 0.1))))
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
        guard hand.visible else {
            lastPinch = false
            drag = nil
            return
        }
        let pointer = mappedPoint(hand.point, size: size)
        if hand.pinching && !lastPinch {
            beganPinch(pointer, hand: hand, size: size)
        } else if hand.pinching, let drag = drag,
                  let index = panels.firstIndex(where: { $0.id == drag.panelID }) {
            // Smooth the fingertip before applying any interaction.
            // The Vision landmark can drift while a real hand stays still.
            let alpha: CGFloat = 0.24
            let filtered = CGPoint(
                x: drag.filteredPointer.x + (pointer.x - drag.filteredPointer.x) * alpha,
                y: drag.filteredPointer.y + (pointer.y - drag.filteredPointer.y) * alpha
            )
            self.drag?.filteredPointer = filtered

            let displacement = hypot(filtered.x - drag.firstPointer.x,
                                     filtered.y - drag.firstPointer.y)
            let threshold: CGFloat = drag.mode == .depth ? 4 : 28
            if !drag.movementStarted {
                // A single landmark jump must never start dragging.
                self.drag?.activationFrames = displacement >= threshold
                    ? drag.activationFrames + 1 : 0
                guard (self.drag?.activationFrames ?? 0) >= 3 else {
                    lastPinch = true
                    return
                }
                self.drag?.movementStarted = true
            }

            let sinceCommit = hypot(filtered.x - drag.lastAppliedPointer.x,
                                    filtered.y - drag.lastAppliedPointer.y)
            let step: CGFloat = drag.mode == .depth ? 3 : 12
            // Require two successive samples outside the motion gate.
            // In a stationary pinch, the window anchor is never rewritten.
            self.drag?.movementFrames = sinceCommit >= step
                ? drag.movementFrames + 1 : 0
            guard (self.drag?.movementFrames ?? 0) >= 2 else {
                lastPinch = true
                return
            }
            self.drag?.movementFrames = 0
            self.drag?.lastAppliedPointer = filtered

            // Consume the initial dead zone so the panel does not jump when
            // the deliberate movement is first recognized.
            let effective = max(0, displacement - threshold)
            let ratio = displacement > 0 ? effective / displacement : 0
            let deltaX = (filtered.x - drag.firstPointer.x) * ratio
            let deltaY = (filtered.y - drag.firstPointer.y) * ratio

            if drag.mode == .depth {
                let fraction = (filtered.x - drag.depthTrackStart)
                    / max(drag.depthTrackLength, 1)
                let value = 0.65 + Double(fraction) * 3.35
                adjustDepth(drag.panelID, to: value, size: size,
                            lockedCenter: drag.fixedScreenCenter)
            } else if runtime.spatialTracking, let origin = drag.initialAnchor,
                      let baseRay = runtime.worldPoint(
                        at: drag.fixedScreenCenter, viewport: size,
                        depth: Float(drag.initialDepth)),
                      let movedRay = runtime.worldPoint(
                        at: CGPoint(x: drag.fixedScreenCenter.x + deltaX,
                                   y: drag.fixedScreenCenter.y + deltaY),
                        viewport: size, depth: Float(drag.initialDepth)) {
                // Apply only the relative world displacement to the original
                // anchor. Reconstructing an absolute anchor every Vision frame
                // caused stationary pinches to walk sideways with camera pose.
                panels[index].anchor = origin + movedRay - baseRay
            }
        } else if !hand.pinching {
            drag = nil
        }
        lastPinch = hand.pinching
    }

    private func beganPinch(_ pointer: CGPoint, hand: TrackedHand, size: CGSize) {
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
        // Dock selection is based on 2D fingertip position, not hand depth.
        let dockWidth = max(26, (size.width - 50) / 5) * 5 + 4 * 5 + 10
        let dockLeft = (size.width - dockWidth) / 2
        if abs(pointer.y - dockCenterY(size)) <= 37 &&
           pointer.x >= dockLeft - 8 &&
           pointer.x <= dockLeft + dockWidth + 8 {
            let cell = max(26, (size.width - 50) / 5) + 5
            let slot = min(4, max(0, Int((pointer.x - dockLeft - 5) / cell)))
            activateDock(slot)
            return
        }

        // Hit-test external Z bars BEFORE the panels themselves.
        for panel in panels.reversed() {
            guard let center = windowCenter(panel, size: size, right: false) else { continue }
            let scale = windowScale(panel)
            let barCenter = CGPoint(x: center.x,
                                    y: center.y + panelHeight(size) * scale / 2 + 25)
            let barWidth = depthBarWidth(size)
            guard abs(pointer.x - barCenter.x) <= barWidth / 2 + 6,
                  abs(pointer.y - barCenter.y) <= 25 else { continue }
            let start = barCenter.x - barWidth / 2 + 12
            let length = barWidth - 24
            let fraction = min(1, max(0, (pointer.x - start) / length))
            drag = WindowDrag(
                panelID: panel.id, mode: .depth, firstPointer: pointer,
                pointerOffset: .zero, initialDepth: panel.depth,
                initialHandDepth: hand.estimatedDepth, fixedScreenCenter: center,
                initialAnchor: panel.anchor, filteredPointer: pointer,
                lastAppliedPointer: pointer, depthTrackStart: start,
                depthTrackLength: length
            )
            adjustDepth(panel.id, to: 0.65 + Double(fraction) * 3.35,
                        size: size, lockedCenter: center)
            return
        }
        for panel in panels.reversed() {
            guard let center = windowCenter(panel, size: size, right: false) else { continue }
            let width = panelWidth(size) * windowScale(panel)
            let height = panelHeight(size) * windowScale(panel)
            let dx = pointer.x - center.x
            let dy = pointer.y - center.y
            guard abs(dx) < width / 2, abs(dy) < height / 2 else { continue }
            if dx > width / 2 - 40 && dy < -height / 2 + 40 {
                close(panel.id)
                return
            }
            if panel.kind == .updates && dy > -height / 2 + 40 &&
                dy < height / 2 - 35 {
                Task { await updates.check() }
                return
            }
            let mode: WindowDrag.Mode = .move
            drag = WindowDrag(
                panelID: panel.id, mode: mode, firstPointer: pointer,
                pointerOffset: CGSize(width: center.x - pointer.x,
                                      height: center.y - pointer.y),
                initialDepth: panel.depth, initialHandDepth: hand.estimatedDepth,
                fixedScreenCenter: center, initialAnchor: panel.anchor,
                filteredPointer: pointer, lastAppliedPointer: pointer,
                depthTrackStart: 0, depthTrackLength: 1
            )
            return
        }
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
        if drag?.panelID == id { drag = nil }
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

    private func activateDock(_ slot: Int) {
        switch slot {
        case 0:
            let count = panels.count + 1
            panels.append(VRPanel(
                title: "Janela \(count)", icon: "macwindow",
                text: "Janela ancorada com ARKit.\n"
                    + "Pinça para arrastar · Z na linha abaixo.\n"
                    + "Use Apps para abrir conteúdo online.",
                x: CGFloat((count % 3) - 1) * 0.15,
                y: CGFloat(count % 2 == 0 ? -0.38 : -0.28),
                depth: 1.6))
        case 1:
            openRemoteWindow()
        case 2:
            openUpdatesWindow()
            Task { await updates.check() }
        case 3:
            themeMenuOpen.toggle()
        default:
            for index in panels.indices {
                panels[index].x = 0
                panels[index].y = 0
                panels[index].anchor = nil
            }
        }
    }
}
