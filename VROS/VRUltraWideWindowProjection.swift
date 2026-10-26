import CoreGraphics
import simd

/// Angular 3DoF panel projection for the 0.5x headset mode.
/// Anchors represent DIRECTIONS, not real-world metres/6DoF positions.
enum VRUltraWideWindowProjection {
    // Approximate display-space horizontal field of view; this is not a
    // calibrated optical FOV or ARKit camera intrinsic measurement.
    static let horizontalFieldOfView: Float = 82

    private static func focalLength(_ viewport: CGSize) -> Float {
        let radians = horizontalFieldOfView * .pi / 180
        return Float(viewport.width) / (2 * tan(radians / 2))
    }

    static func screenRay(at point: CGPoint, viewport: CGSize) -> SIMD3<Float> {
        guard viewport.width > 0, viewport.height > 0 else {
            return SIMD3<Float>(0, 0, -1)
        }
        let focal = focalLength(viewport)
        let x = Float(point.x - viewport.width / 2) / focal
        let y = -Float(point.y - viewport.height / 2) / focal
        return simd_normalize(SIMD3<Float>(x, y, -1))
    }

    /// Rotation is relative to the moment the ultra-wide mode was entered.
    /// The inverse turns a fixed bearing into the device's current view.
    static func project(_ anchoredDirection: SIMD3<Float>,
                        headRotation: simd_quatf,
                        viewport: CGSize) -> CGPoint? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let local = simd_inverse(headRotation).act(anchoredDirection)
        guard -local.z > 0.1 else { return nil }
        let focal = focalLength(viewport)
        let x = Float(viewport.width / 2) + local.x / -local.z * focal
        let y = Float(viewport.height / 2) - local.y / -local.z * focal
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    static func anchoredDirection(at point: CGPoint, viewport: CGSize,
                                  headRotation: simd_quatf) -> SIMD3<Float> {
        simd_normalize(headRotation.act(screenRay(at: point, viewport: viewport)))
    }
}
