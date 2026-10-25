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
struct VRPanel: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var text: String
    var x: CGFloat = 0
    var y: CGFloat = 0
    var depth: Double = 1.5
    var anchor: SIMD3<Float>?
}

private struct WindowDrag {
    enum Mode { case move, depth }
    let panelID: UUID
    let mode: Mode
    let firstPointer: CGPoint
    let pointerOffset: CGSize
    let initialDepth: Double
    let initialHandDepth: Float?
}

struct VRHomeView: View {
    @StateObject private var runtime = VRRuntime()
    @State private var panels = [
        VRPanel(title: "Bem-vindo ao VR OS", icon: "square.stack.3d.up",
                text: "Janelas fixas no ambiente com ARKit.\n"
                    + "Pinça para pegar. Aproxime ou afaste a mão para mudar a distância.\n"
                    + "Ajuste o Z na barra inferior.", depth: 1.5)
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
        }
        .ignoresSafeArea()
        .onAppear { runtime.start() }
        .onDisappear { runtime.stop() }
    }

    private func eyeView(right: Bool, size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            if let frame = runtime.cameraImage {
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

            Color.black.opacity(0.10).allowsHitTesting(false)

            ForEach(panels) { panel in
                if let center = windowCenter(panel, size: size, right: right) {
                    let scale = windowScale(panel.depth)
                    panelView(panel, size: size)
                        .frame(width: panelWidth(size) * scale,
                               height: panelHeight(size) * scale)
                        .position(center)
                }
            }

            statusBar(size: size)
                .position(x: w / 2, y: 28)

            dock(size: size)
                .position(x: w / 2, y: h - 41)

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
                Text("VR OS 3.0 · ESPACIAL")
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
        .background(Color(white: 0.16).opacity(0.94), in: Capsule())
        .frame(maxWidth: size.width * 0.88)
    }

    private func dock(size: CGSize) -> some View {
        HStack(spacing: 8) {
            dockButton("plus.rectangle.on.rectangle", "Janela", slot: 0)
            dockButton("note.text", "Notas", slot: 1)
            dockButton("scope", "Centralizar", slot: 2)
        }
        .padding(7)
        .background(Color(white: 0.19).opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17)
            .stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func dockButton(_ symbol: String, _ label: String, slot: Int) -> some View {
        Button {
            activateDock(slot)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(label).font(.system(size: 9, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(width: 78, height: 42)
            .background(Color.white.opacity(0.09),
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

            Text(panel.text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(4)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10))
                Text("Z")
                    .font(.system(size: 10, weight: .semibold))
                Slider(value: Binding(
                    get: { panels.first(where: { $0.id == panel.id })?.depth ?? panel.depth },
                    set: { adjustDepth(panel.id, to: $0, size: size) }
                ), in: 0.65...4.0, step: 0.05)
                .tint(Color(white: 0.76))
                Text(String(format: "%.2f m", panel.depth))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: 49, alignment: .trailing)
            }
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.19).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.50), radius: 11, y: 5)
    }

    private func panelWidth(_ size: CGSize) -> CGFloat { min(350, size.width * 0.75) }
    private func panelHeight(_ size: CGSize) -> CGFloat { min(213, size.height * 0.54) }
    private func windowScale(_ depth: Double) -> CGFloat {
        min(1.45, max(0.65, CGFloat(1.5 / depth)))
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
            if drag.mode == .depth {
                let value = drag.initialDepth
                    + Double((pointer.x - drag.firstPointer.x) / size.width) * 3.35
                adjustDepth(drag.panelID, to: value, size: size)
            } else {
                var distance = drag.initialDepth
                if let start = drag.initialHandDepth, let current = hand.estimatedDepth {
                    // Forward/backward motion of the hand changes the window's Z.
                    // Relative displacement only: avoid snapping window to hand depth.
                    distance += Double(current - start)
                }
                distance = min(4.0, max(0.65, distance))
                let target = CGPoint(x: pointer.x + drag.pointerOffset.width,
                                     y: pointer.y + drag.pointerOffset.height)
                if let anchor = runtime.worldPoint(at: target, viewport: size,
                                                   depth: Float(distance)) {
                    panels[index].anchor = anchor
                    panels[index].depth = distance
                }
            }
        } else if !hand.pinching {
            drag = nil
        }
        lastPinch = hand.pinching
    }

    private func beganPinch(_ pointer: CGPoint, hand: TrackedHand, size: CGSize) {
        if pointer.y > size.height - 83 {
            if pointer.x < size.width * 0.36 { activateDock(0) }
            else if pointer.x < size.width * 0.65 { activateDock(1) }
            else { activateDock(2) }
            return
        }
        for panel in panels.reversed() {
            guard let center = windowCenter(panel, size: size, right: false) else { continue }
            let width = panelWidth(size) * windowScale(panel.depth)
            let height = panelHeight(size) * windowScale(panel.depth)
            let dx = pointer.x - center.x
            let dy = pointer.y - center.y
            guard abs(dx) < width / 2, abs(dy) < height / 2 else { continue }
            if dx > width / 2 - 40 && dy < -height / 2 + 40 {
                close(panel.id)
                return
            }
            let mode: WindowDrag.Mode = dy > height / 2 - 39 ? .depth : .move
            drag = WindowDrag(
                panelID: panel.id, mode: mode, firstPointer: pointer,
                pointerOffset: CGSize(width: center.x - pointer.x,
                                      height: center.y - pointer.y),
                initialDepth: panel.depth, initialHandDepth: hand.estimatedDepth
            )
            return
        }
    }

    private func adjustDepth(_ id: UUID, to rawValue: Double, size: CGSize) {
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
        let value = min(4.0, max(0.65, rawValue))
        let center = windowCenter(panels[index], size: size, right: false)
        panels[index].depth = value
        if let center = center,
           let anchor = runtime.worldPoint(at: center, viewport: size, depth: Float(value)) {
            panels[index].anchor = anchor
        }
    }

    private func close(_ id: UUID) {
        panels.removeAll { $0.id == id }
        if drag?.panelID == id { drag = nil }
    }

    private func activateDock(_ slot: Int) {
        switch slot {
        case 0:
            let count = panels.count + 1
            panels.append(VRPanel(
                title: "Janela \(count)", icon: "macwindow",
                text: "Fixada no espaço pelo ARKit.\n"
                    + "Pinça para arrastar · Z pela barra inferior.\n"
                    + "O Z da mão é aproximado, não medido.",
                x: CGFloat((count % 3) - 1) * 0.15,
                y: CGFloat(count % 2 == 0 ? -0.12 : 0.10),
                depth: 1.6))
        case 1:
            panels.append(VRPanel(
                title: "Notas", icon: "note.text",
                text: "• 21 pontos da mão\n• Profundidade monocular aproximada\n"
                    + "• Janelas no espaço até reiniciar\n• Duas imagens da mesma câmera",
                x: 0.14, y: -0.12, depth: 1.8))
        default:
            // Explicitly move all windows in front of the user's CURRENT pose.
            for index in panels.indices {
                let distance = panels[index].depth
                panels[index].x = 0
                panels[index].y = 0
                panels[index].anchor = nil
                // Pending windows are anchored on the next ARKit camera update.
                panels[index].depth = distance
            }
        }
    }
}
