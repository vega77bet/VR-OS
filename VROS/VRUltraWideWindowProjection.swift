import CoreGraphics
import simd

/// Map the head's forward ray into a HUD pointer. The sign must agree with
/// the world projection: turning toward a target moves the pointer toward it
/// while an anchored window moves in the opposite direction on screen.
enum VRHeadPointerGeometry {
    static func normalizedPoint(rotation: simd_quatf, sensitivity: Double = 0.42) -> CGPoint {
        let forward = rotation.act(SIMD3<Float>(0, 0, -1))
        let yaw = Double(atan2(forward.x, -forward.z))
        let pitch = Double(asin(max(-1, min(1, forward.y))))
        guard yaw.isFinite, pitch.isFinite else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: max(0.06, min(0.94, 0.5 + yaw * sensitivity)),
                       y: max(0.06, min(0.94, 0.5 - pitch * sensitivity)))
    }
}

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
