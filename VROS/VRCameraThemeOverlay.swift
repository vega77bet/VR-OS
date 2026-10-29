import SwiftUI

/// Lightweight HUD layer that keeps the real camera visible while giving the
/// mixed-reality view a recognizable VR-OS identity.
struct VRCameraThemeOverlay: View {
    let accent: Color
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(0.58),
                    .clear,
                    .black.opacity(0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.32)

            RadialGradient(
                colors: [
                    accent.opacity(0.12),
                    .clear
                ],
                center: .center,
                startRadius: 12,
                endRadius: max(size.width, size.height) * 0.72
            )

            Canvas { context, canvas in
                let edge = min(canvas.width, canvas.height)
                let margin = edge * 0.065
                let length = edge * 0.13

                for index in 0...11 {
                    let y = CGFloat(index) / 11 * canvas.height
                    var scanline = Path()
                    scanline.move(to: CGPoint(x: 0, y: y))
                    scanline.addLine(to: CGPoint(x: canvas.width, y: y))
                    context.stroke(
                        scanline,
                        with: .color(accent.opacity(index % 3 == 0 ? 0.075 : 0.035)),
                        lineWidth: 0.6
                    )
                }

                let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (margin, margin, 1, 1),
                    (canvas.width - margin, margin, -1, 1),
                    (margin, canvas.height - margin, 1, -1),
                    (canvas.width - margin, canvas.height - margin, -1, -1)
                ]

                for (x, y, horizontal, vertical) in corners {
                    var corner = Path()
                    corner.move(to: CGPoint(x: x + horizontal * length, y: y))
                    corner.addLine(to: CGPoint(x: x, y: y))
                    corner.addLine(to: CGPoint(x: x, y: y + vertical * length))
                    context.stroke(
                        corner,
                        with: .color(accent.opacity(0.78)),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                }

                var horizon = Path()
                horizon.move(to: CGPoint(x: canvas.width * 0.12, y: canvas.height * 0.78))
                horizon.addLine(to: CGPoint(x: canvas.width * 0.88, y: canvas.height * 0.78))
                context.stroke(
                    horizon,
                    with: .color(accent.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 8])
                )
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: accent, radius: 5)
                    Text("VR-OS")
                        .tracking(1.4)
                    Text("LIVE")
                        .foregroundStyle(accent)
                        .tracking(1)
                    Spacer()
                    Text("CÂMERA ATIVA")
                        .foregroundStyle(.white.opacity(0.72))
                        .tracking(0.8)
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.36), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.36), lineWidth: 0.7))

                Spacer()

                HStack {
                    Text("REALIDADE MISTA")
                    Spacer()
                    Text("AMBIENTE \(String(format: "%02d", Int(size.width)))")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
