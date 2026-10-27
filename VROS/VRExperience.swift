import SwiftUI
import ARKit

enum VRScenery: Int, CaseIterable {
    case original, ocean, forest, nebula, cyberpunk
    var title: String { ["Tema original", "Oceano", "Floresta", "Nebulosa", "Cyberpunk"][rawValue] }
}

struct VRSceneryView: View {
    let scenery: VRScenery
    let camera: ARCamera?
    var body: some View {
        Canvas { context, size in
            let yaw = Double(camera?.eulerAngles.y ?? 0)
            let pitch = Double(camera?.eulerAngles.x ?? 0)
            let colors: [Color] = scenery == .forest ? [.black, .green.opacity(0.4)] :
                scenery == .ocean ? [.blue.opacity(0.25), .cyan.opacity(0.6)] :
                scenery == .nebula ? [.black, .purple.opacity(0.6)] : [.black, .pink.opacity(0.4)]
            context.fill(Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)))
            let horizon = size.height * (0.5 + CGFloat(sin(pitch)) * 0.2)
            for index in 0..<48 {
                let phase = Double(index) * 2.399963 + yaw
                let x = (CGFloat(sin(phase)) * 0.6 + 0.5) * size.width
                switch scenery {
                case .forest:
                    var tree = Path()
                    let height = CGFloat(35 + index % 7 * 13)
                    tree.move(to: CGPoint(x: x, y: horizon - height))
                    tree.addLine(to: CGPoint(x: x - height * 0.3, y: size.height))
                    tree.addLine(to: CGPoint(x: x + height * 0.3, y: size.height))
                    tree.closeSubpath()
                    context.fill(tree, with: .color(.green.opacity(0.10 + Double(index % 5) * 0.08)))
                case .ocean:
                    var wave = Path()
                    let y = horizon + CGFloat(index) * 6
                    for step in 0...32 {
                        let px = CGFloat(step) / 32 * size.width
                        let py = y + CGFloat(sin(Double(step) * 0.4 + phase)) * 3
                        if step == 0 { wave.move(to: CGPoint(x: px, y: py)) }
                        else { wave.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    context.stroke(wave, with: .color(.cyan.opacity(0.2)), lineWidth: 1)
                case .nebula:
                    let y = CGFloat((sin(phase * 1.7) + 1) / 2) * size.height
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                                 with: .color(.white.opacity(0.7)))
                case .cyberpunk:
                    let height = CGFloat(20 + index % 9 * 11)
                    let rect = CGRect(x: x, y: horizon - height, width: 14, height: size.height)
                    context.fill(Path(rect), with: .color(.black.opacity(0.65)))
                    context.stroke(Path(rect), with: .color(.pink.opacity(0.5)), lineWidth: 1)
                case .original: break
                }
            }
        }.allowsHitTesting(false)
    }
}

struct VRPrecisionCursor: View {
    let pinching: Bool
    let size: CGFloat
    let reduceMotion: Bool
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.45))
            Circle().stroke(pinching ? Color.cyan : .white, lineWidth: pinching ? 3 : 1.5)
            Circle().fill(pinching ? Color.cyan : .white).frame(width: 5, height: 5)
            if pinching {
                Circle().stroke(.cyan.opacity(0.3), lineWidth: 1).padding(-5)
            }
        }
        .frame(width: pinching ? 27 : 21, height: pinching ? 27 : 21)
        .scaleEffect(size)
        .shadow(color: .black.opacity(0.7), radius: 3)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pinching)
        .allowsHitTesting(false)
    }
}
