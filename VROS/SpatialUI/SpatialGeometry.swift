import Foundation
import simd

/// Rendering and interaction use metres and the same rounded rectangles.
enum SpatialGeometry {
    static let elementDepth: Float = 0.008
    static let maximumReach: Float = 12

    static func worldPoint(local: SIMD3<Float>, window: SpatialWindow) -> SIMD3<Float> {
        window.position + window.orientation.act(local)
    }

    static func roundedContains(point: SIMD2<Float>, size: SIMD2<Float>, radius: Float) -> Bool {
        guard point.x.isFinite, point.y.isFinite, size.x > 0, size.y > 0 else { return false }
        let half = size * 0.5
        let r = max(0, min(radius, min(half.x, half.y)))
        let p = SIMD2<Float>(abs(point.x), abs(point.y))
        guard p.x <= half.x, p.y <= half.y else { return false }
        let corner = SIMD2<Float>(max(p.x - half.x + r, 0), max(p.y - half.y + r, 0))
        return simd_length_squared(corner) <= r * r + 0.0000001
    }

    /// A nearer window blocks every farther window, including on blank surfaces.
    /// Back faces and opening/closing panels are not actionable.
    static func intersect(ray: SpatialRay, windows: [SpatialWindow]) -> SpatialHit? {
        let norm = simd_length(ray.direction)
        guard norm.isFinite, norm > 0.00001,
              ray.origin.x.isFinite, ray.origin.y.isFinite, ray.origin.z.isFinite else { return nil }
        let direction = ray.direction / norm
        var nearest: SpatialHit?
        for window in windows where window.isOpen && window.opacity >= 0.8 {
            let inverse = window.orientation.inverse
            let origin = inverse.act(ray.origin - window.position)
            let localDirection = inverse.act(direction)
            guard localDirection.z < -0.00001 else { continue }
            let surfaceDistance = -origin.z / localDirection.z
            guard surfaceDistance > 0, surfaceDistance <= maximumReach else { continue }
            let point = origin + localDirection * surfaceDistance
            guard roundedContains(point: SIMD2(point.x, point.y), size: window.size,
                                  radius: window.cornerRadius) else { continue }

            var elementID: String?
            var hitDistance = surfaceDistance
            let elementDistance = (elementDepth - origin.z) / localDirection.z
            if elementDistance > 0 {
                let elementPoint = origin + localDirection * elementDistance
                // Last visible actionable element wins in the rare case of overlap,
                // matching mesh submission order within a window.
                for element in window.elements where element.action != nil {
                    let p = SIMD2(elementPoint.x, elementPoint.y) - element.center
                    if roundedContains(point: p, size: element.size, radius: element.cornerRadius) {
                        elementID = element.id
                        hitDistance = elementDistance
                    }
                }
            }
            if nearest == nil || hitDistance < nearest!.distance {
                nearest = SpatialHit(windowID: window.id, elementID: elementID,
                                     distance: hitDistance, point: ray.origin + direction * hitDistance)
            }
        }
        return nearest
    }

    static func horizontalOrientation(of head: simd_quatf) -> simd_quatf? {
        let forward = head.act(SIMD3<Float>(0, 0, -1))
        guard forward.x * forward.x + forward.z * forward.z > 0.0001 else { return nil }
        return simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3(0, 1, 0))
    }

    /// Synthetic controller/window manipulation stays in front of the current user.
    static func comfortablePosition(_ proposed: SIMD3<Float>, headPose: simd_quatf) -> SIMD3<Float> {
        let head = StereoCamera.headPosition
        let yaw = horizontalOrientation(of: headPose) ?? simd_quatf(real: 1, imag: .zero)
        var local = yaw.inverse.act(proposed - head)
        if !local.x.isFinite || !local.y.isFinite || !local.z.isFinite { local = SIMD3(0, 0, -2.4) }
        let horizontal = simd_length(SIMD2(local.x, local.z))
        let heading = horizontal > 0.0001 ? atan2(local.x, -local.z) : 0
        // The widest panel is 2.5 m: at the 1.4 m minimum, a ±45°
        // centre cone also keeps its corners ahead of the viewer.
        let bearing = max(-Float.pi / 4, min(Float.pi / 4, heading))
        let distance = max(1.4, min(4, horizontal))
        local.x = sin(bearing) * distance
        local.z = -cos(bearing) * distance
        local.y = max(0.65 - head.y, min(2.7 - head.y, local.y))
        return head + yaw.act(local)
    }
}
