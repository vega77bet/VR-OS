import MetalKit

/// One draw per eye, each sampling its own texture. UVs can never cross the eye boundary.
final class LensDistortionRenderer {
    private let pipeline: MTLRenderPipelineState

    private struct Uniforms {
        var center: SIMD2<Float>
        var scale: Float
        var aspect: Float
        var k1: Float
        var k2: Float
        var strength: Float
        var padding: Float = 0
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
        var uniforms = Uniforms(center: SIMD2(eye == .left ? profile.leftCenterX : profile.rightCenterX, 0.5),
                                scale: eye == .left ? profile.leftScale : profile.rightScale,
                                aspect: Float(range.count) / Float(drawableSize.height),
                                k1: profile.distortionK1, k2: profile.distortionK2,
                                strength: profile.distortionStrength)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
