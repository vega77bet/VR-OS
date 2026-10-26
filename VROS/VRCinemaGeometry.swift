import simd

/// Pure math shared by the Cinema renderer and macOS regression tests.
/// SceneKit cameras face local -Z; every seat needs its own 3D rotation
/// towards the centre of the film screen (not a hardcoded downward pitch).
enum VRCinemaGeometry {
    static let screenCentre = SIMD3<Float>(0, 7.05, -15.66)
    static let cameraForward = SIMD3<Float>(0, 0, -1)

    static func lookRotation(from eye: SIMD3<Float>,
                             to target: SIMD3<Float> = screenCentre) -> simd_quatf {
        let vector = target - eye
        guard simd_length_squared(vector) > 0.00001 else {
            return simd_quatf()
        }
        return simd_normalize(simd_quatf(
            from: cameraForward,
            to: simd_normalize(vector)
        ))
    }

    static func pitchDegrees(from eye: SIMD3<Float>,
                             to target: SIMD3<Float> = screenCentre) -> Float {
        let vector = simd_normalize(target - eye)
        return atan2(vector.y, hypot(vector.x, vector.z)) * 180 / .pi
    }

    static func yawDegrees(from eye: SIMD3<Float>,
                           to target: SIMD3<Float> = screenCentre) -> Float {
        let vector = simd_normalize(target - eye)
        return atan2(-vector.x, -vector.z) * 180 / .pi
    }
}
