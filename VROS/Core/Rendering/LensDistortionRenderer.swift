import MetalKit

/// One draw per eye, each sampling its own texture. UVs can never cross the eye boundary.
final class LensDistortionRenderer {
    private let pipeline: MTLRenderPipelineState

    /// Keep this layout in lockstep with LensDistortion.metal. Every field is
    /// expressed in normalized per-eye texture coordinates except the angle.
    struct Uniforms {
        var center: SIMD2<Float>
        var imageOffset: SIMD2<Float>
        var imageScale: SIMD2<Float>
        var tangential: SIMD2<Float>
        var rotationRadians: Float
        var aspect: Float
        var radialK1: Float
        var radialK2: Float
        var radialK3: Float
        var distortionStrength: Float
        var chromaticRedScale: Float
        var chromaticBlueScale: Float
    }

    init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Per-eye lens correction"
        descriptor.vertexFunction = library.makeFunction(name: "lensVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "lensFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func encode(encoder: MTLRenderCommandEncoder, eye: StereoCamera.Eye,
                texture: MTLTexture, drawableSize: CGSize, profile: VRLensProfile) {
        let range = StereoCamera.horizontalRange(eye, drawableWidth: Int(drawableSize.width))
        encoder.setViewport(MTLViewport(originX: Double(range.lowerBound), originY: 0,
                                        width: Double(range.count), height: Double(drawableSize.height),
                                        znear: 0, zfar: 1))
        encoder.setScissorRect(MTLScissorRect(x: range.lowerBound, y: 0,
                                            width: range.count, height: Int(drawableSize.height)))
        let calibration = eye == .left ? profile.leftEye : profile.rightEye
        var uniforms = Uniforms(center: SIMD2(calibration.opticalCenterX, calibration.opticalCenterY),
                                imageOffset: SIMD2(calibration.horizontalOffset, calibration.verticalOffset),
                                imageScale: SIMD2(calibration.horizontalScale, calibration.verticalScale),
                                tangential: SIMD2(calibration.tangentialP1, calibration.tangentialP2),
                                rotationRadians: calibration.rotationDegrees * .pi / 180,
                                aspect: Float(range.count) / Float(drawableSize.height),
                                radialK1: calibration.radialK1, radialK2: calibration.radialK2,
                                radialK3: calibration.radialK3,
                                distortionStrength: calibration.distortionStrength,
                                chromaticRedScale: calibration.chromaticRedScale,
                                chromaticBlueScale: calibration.chromaticBlueScale)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
