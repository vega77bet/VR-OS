import ARKit
import SwiftUI
import simd

/// Procedural 360-degree sky. Stars are directions on a unit sphere, not
/// screen-space particles: turning the headset reveals different stars.
/// Both eyes use the same star directions (infinite-distance background).
struct SpaceSkyView: View {
    let camera: ARCamera?
    let size: CGSize
    var headRotation: simd_quatf? = nil

    private struct Star {
        let direction: SIMD3<Float>
        let brightness: Double
        let radius: CGFloat
    }

    private static let stars: [Star] = {
        var seed: UInt64 = 0xC0FFEE_1234
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<1250).map { index in
            let y = Float(random() * 2 - 1)
            let a = Float(random() * .pi * 2)
            let r = sqrt(max(0, 1 - y * y))
            return Star(
                direction: SIMD3<Float>(r * cos(a), y, r * sin(a)),
                brightness: 0.35 + random() * 0.65,
                radius: index % 31 == 0 ? 1.9 : (index % 7 == 0 ? 1.2 : 0.65)
            )
        }
    }()

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(rect),
                         with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 0.025, green: 0.018, blue: 0.10),
                                Color(red: 0.005, green: 0.015, blue: 0.055),
                                Color(red: 0.035, green: 0.012, blue: 0.085)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                         ))

            let rotation: simd_float3x3
            if let headRotation = headRotation {
                rotation = simd_float3x3(headRotation)
            } else if let camera = camera {
                rotation = simd_float3x3(
                SIMD3<Float>(camera.transform.columns.0.x, camera.transform.columns.0.y, camera.transform.columns.0.z),
                SIMD3<Float>(camera.transform.columns.1.x, camera.transform.columns.1.y, camera.transform.columns.1.z),
                SIMD3<Float>(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
                )
            } else {
                rotation = matrix_identity_float3x3
            }
            let inverseRotation = rotation.transpose
            let focal = Float(min(canvasSize.width * 1.15, canvasSize.height * 1.25))
            let centerX = Float(canvasSize.width * 0.5)
            let centerY = Float(canvasSize.height * 0.5)

            for star in Self.stars {
                let local = inverseRotation * star.direction
                guard local.z < -0.12 else { continue }
                let x = centerX + local.x / -local.z * focal
                let y = centerY - local.y / -local.z * focal
                guard x >= -4, x <= Float(canvasSize.width) + 4,
                      y >= -4, y <= Float(canvasSize.height) + 4 else { continue }
                let point = CGRect(x: CGFloat(x) - star.radius,
                                   y: CGFloat(y) - star.radius,
                                   width: star.radius * 2,
                                   height: star.radius * 2)
                context.fill(Path(ellipseIn: point),
                             with: .color(.white.opacity(star.brightness)))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
