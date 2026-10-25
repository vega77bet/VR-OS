import SwiftUI
import ARKit
import simd

/// Two distinct immersive backgrounds. The world rotation makes the horizon
/// react to the user's head motion; nothing here reads private camera pixels.
struct ThemeAtmosphereView: View {
    let isAurora: Bool
    let camera: ARCamera?
    let size: CGSize

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, canvas in
            let bounds = CGRect(origin: .zero, size: canvas)
            let yaw: Double
            let pitch: Double
            if let pose = camera {
                let forward = pose.transform.columns.2
                yaw = atan2(Double(forward.x), Double(forward.z))
                pitch = asin(Double(max(-1, min(1, forward.y))))
            } else {
                yaw = 0
                pitch = 0
            }
            let horizon = canvas.height * (0.55 + 0.25 * sin(pitch))
            if isAurora {
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.005, green: 0.025, blue: 0.07),
                        Color(red: 0.015, green: 0.13, blue: 0.15),
                        Color(red: 0.03, green: 0.06, blue: 0.12)
                    ]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: canvas.height)))
                for stripe in 0..<7 {
                    let index = Double(stripe)
                    var path = Path()
                    for step in 0...70 {
                        let x = CGFloat(step) / 70 * canvas.width
                        let phase = Double(x / max(canvas.width, 1)) * 7 + yaw + index * 0.32
                        let y = horizon * 0.65 + CGFloat(sin(phase) * 25 + index * 8)
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path,
                                   with: .color(Color(red: 0.18, green: 0.94,
                                                      blue: index.isMultiple(of: 2) ? 0.55 : 0.90)
                                    .opacity(0.45 - index * 0.04)),
                                   style: StrokeStyle(lineWidth: 18, lineCap: .round))
                }
            } else {
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.06, green: 0.015, blue: 0.16),
                        Color(red: 0.23, green: 0.025, blue: 0.22),
                        Color(red: 0.03, green: 0.012, blue: 0.08)
                    ]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: canvas.height)))
                let gridColor = Color(red: 1, green: 0.24, blue: 0.71)
                for i in -9...9 {
                    var line = Path()
                    let shift = CGFloat(sin(yaw) * 100)
                    line.move(to: CGPoint(x: canvas.width / 2 + CGFloat(i) * 6 + shift,
                                          y: horizon))
                    line.addLine(to: CGPoint(x: canvas.width / 2 + CGFloat(i) * 65 + shift,
                                             y: canvas.height))
                    context.stroke(line, with: .color(gridColor.opacity(0.58)), lineWidth: 1)
                }
                for i in 0..<12 {
                    let t = CGFloat(i + 1) / 12
                    let y = horizon + (canvas.height - horizon) * t * t
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: canvas.width, y: y))
                    context.stroke(line, with: .color(gridColor.opacity(0.48)), lineWidth: 1)
                }
                let sun = CGRect(x: canvas.width * 0.37, y: horizon - 75,
                                 width: canvas.width * 0.26, height: 65)
                context.fill(Path(ellipseIn: sun),
                             with: .color(Color(red: 1, green: 0.55, blue: 0.36).opacity(0.85)))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}
