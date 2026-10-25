import SwiftUI
import AVFoundation

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

struct VRPanel: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var text: String
    // Normalized offsets from the center of each eye (-1 ... 1).
    var x: CGFloat = 0
    var y: CGFloat = 0
}

struct VRHomeView: View {
    @StateObject private var runtime = VRRuntime()
    @State private var panels: [VRPanel] = [
        VRPanel(title: "VR OS 2.0", icon: "square.stack.3d.up",
                text: "Bem-vindo! Mostre sua mão à câmera.\nJunte indicador e polegar para clicar.\nSegure a pinça sobre a janela para mover.")
    ]
    @State private var lastPinch = false
    @State private var draggingID: UUID?

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
                Rectangle().fill(Color.black).frame(width: 3)
                    .allowsHitTesting(false)
            }
            .onReceive(runtime.$hand) { value in
                processGesture(value, size: eyeSize)
            }
        }
        .ignoresSafeArea()
        .onAppear { runtime.start() }
        .onDisappear { runtime.stop() }
    }

    private func eyeView(right: Bool, size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let parallax: CGFloat = right ? -7 : 7
        let yawOffset = CGFloat(max(-0.7, min(0.7, runtime.headYaw))) * w * 0.13

        return ZStack {
            VRPreview(session: runtime.session)
                .frame(width: w, height: h)
                .clipped()

            Color.black.opacity(0.18).allowsHitTesting(false)

            ForEach(panels) { panel in
                panelView(panel, size: size)
                    .frame(width: panelWidth(size), height: panelHeight(size))
                    .position(
                        x: w / 2 + panel.x * (w / 2) + parallax - yawOffset,
                        y: h / 2 + panel.y * (h / 2)
                    )
            }

            VStack(spacing: 4) {
                Text("VR OS 2.0  •  HAND TRACKING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                Text(runtime.cameraStatus)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .position(x: w / 2, y: 30)

            HStack(spacing: 10) {
                dockButton("plus.rectangle.on.rectangle", "Janela", slot: 0)
                dockButton("note.text", "Notas", slot: 1)
                dockButton("scope", "Centro", slot: 2)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
            .position(x: w / 2, y: h - 45)

            if runtime.hand.visible {
                let cursor = mappedPoint(runtime.hand.point, size: size)
                ZStack {
                    Circle()
                        .stroke(runtime.hand.pinching ? Color.green : Color.cyan, lineWidth: 3)
                        .frame(width: runtime.hand.pinching ? 36 : 25,
                               height: runtime.hand.pinching ? 36 : 25)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }
                .shadow(color: .black.opacity(0.8), radius: 3)
                .position(x: cursor.x, y: cursor.y)
                .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .clipped()
        .background(.black)
    }

    private func panelView(_ panel: VRPanel, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: panel.icon)
                    .foregroundStyle(.cyan)
                Text(panel.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.75))
                    .font(.system(size: 17))
            }
            .padding(.bottom, 3)

            Rectangle()
                .fill(Color.cyan.opacity(0.5))
                .frame(height: 1)

            Text(panel.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: false)
                .lineSpacing(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            HStack {
                Circle().fill(runtime.hand.visible ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(runtime.hand.visible ? "Mão conectada" : "Aguardando mão")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 10))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.055, green: 0.09, blue: 0.16).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.38), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
    }

    private func dockButton(_ symbol: String, _ label: String, slot: Int) -> some View {
        Button {
            activateDock(slot)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 43)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func panelWidth(_ size: CGSize) -> CGFloat { min(330, size.width * 0.68) }
    private func panelHeight(_ size: CGSize) -> CGFloat { min(184, size.height * 0.48) }

    // The camera frame is 16:9; each eye is narrower and uses aspect-fill.
    // Convert Vision's full-frame coordinates to the actually visible center crop.
    private func mappedPoint(_ raw: CGPoint, size: CGSize) -> CGPoint {
        let imageAspect: CGFloat = 16.0 / 9.0
        let viewAspect = size.width / max(size.height, 1)
        let visibleFraction = min(1, viewAspect / imageAspect)
        let crop = (1 - visibleFraction) / 2
        let x = (raw.x - crop) / visibleFraction
        return CGPoint(x: x * size.width, y: raw.y * size.height)
    }

    private func processGesture(_ hand: TrackedHand, size: CGSize) {
        if !hand.visible {
            draggingID = nil
            lastPinch = false
            return
        }
        let point = mappedPoint(hand.point, size: size)
        if hand.pinching && !lastPinch {
            beganPinch(at: point, size: size)
        } else if hand.pinching, let id = draggingID,
                  let index = panels.firstIndex(where: { $0.id == id }) {
            let dx = (point.x - size.width / 2) / (size.width / 2)
            let dy = (point.y - size.height / 2) / (size.height / 2)
            panels[index].x = max(-0.42, min(0.42, dx))
            panels[index].y = max(-0.38, min(0.24, dy))
        } else if !hand.pinching {
            draggingID = nil
        }
        lastPinch = hand.pinching
    }

    private func beganPinch(at p: CGPoint, size: CGSize) {
        // Bottom dock is also reachable without touching the screen.
        if p.y > size.height - 94 {
            if p.x < size.width * 0.38 { activateDock(0) }
            else if p.x < size.width * 0.64 { activateDock(1) }
            else { activateDock(2) }
            return
        }

        let w = panelWidth(size)
        let h = panelHeight(size)
        for index in panels.indices.reversed() {
            let panel = panels[index]
            let cx = size.width / 2 + panel.x * (size.width / 2)
            let cy = size.height / 2 + panel.y * (size.height / 2)
            let localX = p.x - cx
            let localY = p.y - cy
            guard abs(localX) < w / 2, abs(localY) < h / 2 else { continue }

            // The X in the top-right corner closes the panel.
            if localX > w / 2 - 48 && localY < -h / 2 + 48 {
                panels.remove(at: index)
            } else {
                draggingID = panel.id
            }
            return
        }
    }

    private func activateDock(_ slot: Int) {
        switch slot {
        case 0:
            let number = panels.count + 1
            panels.append(VRPanel(
                title: "Janela \(number)", icon: "rectangle.on.rectangle",
                text: "Janela virtual independente.\nFaça pinça e arraste para mover.\nPinça no X para fechar.",
                x: CGFloat((number % 3) - 1) * 0.18,
                y: CGFloat((number % 2) == 0 ? -0.20 : 0.12)
            ))
        case 1:
            panels.append(VRPanel(
                title: "Notas", icon: "note.text",
                text: "VR OS 2.0 — versão experimental\n• Duas imagens para VR Box\n• Mãos via Apple Vision\n• Pinça, mover e fechar janelas",
                x: 0.16, y: -0.10
            ))
        default:
            runtime.recenter()
            for i in panels.indices {
                panels[i].x = 0
                panels[i].y = 0
            }
        }
    }
}
