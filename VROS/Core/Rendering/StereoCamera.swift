import simd

/// Right-handed world in metres; +Y up, camera looks along -Z. Column vectors.
struct StereoCamera {
    enum Eye: Int, CaseIterable { case left = 0, right = 1 }
    static let headPosition = SIMD3<Float>(0, 1.65, 0)

    static func eyePosition(_ eye: Eye, orientation: simd_quatf,
                            ipdMeters: Float) -> SIMD3<Float> {
        let offset: Float = eye == .left ? -0.5 : 0.5
        return headPosition + orientation.act(SIMD3(offset * ipdMeters, 0, 0))
    }

    static func viewMatrix(_ eye: Eye, orientation: simd_quatf,
                           ipdMeters: Float) -> simd_float4x4 {
        let rotation = simd_float4x4(orientation.inverse)
        let position = eyePosition(eye, orientation: orientation, ipdMeters: ipdMeters)
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(-position.x, -position.y, -position.z, 1)
        return rotation * translation
    }

    /// Off-axis projection; principal point is expressed in each eye's output UV.
    /// No toe-in: the two camera axes remain parallel, preventing vertical disparity.
    static func projection(verticalFOVDegrees: Float, aspect: Float,
                           centerX: Float, near: Float = 0.05,
                           far: Float = 80) -> simd_float4x4 {
        let y = 1 / tan(verticalFOVDegrees * .pi / 360)
        let x = y / aspect
        // NDC principal point = 2*centerX-1. Clip w = -camera z.
        return simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(1 - 2 * centerX, 0, far / (near - far), -1),
            SIMD4(0, 0, near * far / (near - far), 0)
        ))
    }

    /// Drawable pixels, never safe-area points. No padding is inserted between eyes.
    static func horizontalRange(_ eye: Eye, drawableWidth: Int) -> Range<Int> {
        let split = drawableWidth / 2
        return eye == .left ? 0..<split : split..<drawableWidth
    }
}
