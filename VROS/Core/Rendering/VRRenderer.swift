import MetalKit
import QuartzCore
import simd

@MainActor
final class VRRenderer: NSObject, MTKViewDelegate {
    enum RenderError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case .unavailable(let detail): return "Metal indisponível: \(detail)" }
        }
    }

    private struct SceneUniforms { var viewProjection: simd_float4x4 }
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let scenePipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let distortion: LensDistortionRenderer
    private let spatialUI: SpatialUIRenderer
    private let vertexBuffer: MTLBuffer
    private let vertexCount: Int
    private let tracking: HeadTrackingManager
    private let calibration: VRCalibrationManager
    private let inFlight = DispatchSemaphore(value: 2)
    private var eyeTextures: [MTLTexture] = []
    private var eyeDepthTextures: [MTLTexture] = []
    private var targetWidth = 0
    private var targetHeight = 0
    private var targetScale: Float = 0
    private var metricWindowStart: TimeInterval = 0
    private var metricFrames = 0
    private var lastMetricPublish: TimeInterval = 0
    private var lastGPUTime: Double?
    private var cpuAverage: Double = 0
    private var thermalCap: Float = 1
    private var lastThermalReduction: TimeInterval = 0
    private(set) var metrics = FrameMetrics()
    var onMetrics: ((FrameMetrics) -> Void)?
    /// Interaction advances once from the shared late head sample, before either eye.
    var spatialFrameProvider: ((simd_quatf, TimeInterval) -> SpatialRenderFrame)?

    init(view: MTKView, tracking: HeadTrackingManager,
         calibration: VRCalibrationManager) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw RenderError.unavailable("device, fila ou biblioteca de shaders ausente")
        }
        self.device = device
        commandQueue = queue
        self.tracking = tracking
        self.calibration = calibration
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VR scene geometry"
        descriptor.vertexFunction = library.makeFunction(name: "sceneVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "sceneFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        scenePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RenderError.unavailable("estado de profundidade")
        }
        depthState = depth
        distortion = try LensDistortionRenderer(device: device, library: library,
                                                pixelFormat: view.colorPixelFormat)
        spatialUI = try SpatialUIRenderer(device: device, library: library, pixelFormat: view.colorPixelFormat)
        let vertices = HomeEnvironment.vertices()
        vertexCount = vertices.count
        guard let buffer = vertices.withUnsafeBufferPointer({ pointer in
            device.makeBuffer(bytes: pointer.baseAddress!,
                              length: pointer.count * MemoryLayout<SceneVertex>.stride,
                              options: .storageModeShared)
        }) else { throw RenderError.unavailable("buffer da cena") }
        vertexBuffer = buffer
        vertexBuffer.label = "Immutable 360-degree Home environment"
        super.init()
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Targets are recreated lazily on the next rendered frame. Command buffers retain
        // the previous generation until completion, so resizing cannot invalidate GPU use.
        targetWidth = 0
    }

    func draw(in view: MTKView) {
        let cpuStart = CACurrentMediaTime()
        guard !view.isPaused, view.drawableSize.width >= 2, view.drawableSize.height >= 1 else { return }
        // Never queue an unbounded chain of stale head poses or block the main thread.
        guard inFlight.wait(timeout: .now()) == .success else {
            metrics.droppedFrames += 1
            return
        }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        guard prepareTargets(size: view.drawableSize, scale: effectiveScale(at: cpuStart)),
              let drawable = view.currentDrawable,
              let output = view.currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer() else { return }
        command.label = "VR binocular frame"
        output.colorAttachments[0].loadAction = .clear
        output.colorAttachments[0].storeAction = .store

        // Late sample exactly once; both eyes see the same instant and calibration snapshot.
        let pose = tracking.orientation(at: CACurrentMediaTime())
        let profile = calibration.profile
        let spatialFrame = spatialFrameProvider?(pose, CACurrentMediaTime())
        if let spatialFrame { spatialUI.prepare(spatialFrame) }
        for eye in StereoCamera.Eye.allCases {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = eyeTextures[eye.rawValue]
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.025, 0.035, 0.055, 1)
            pass.depthAttachment.texture = eyeDepthTextures[eye.rawValue]
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 1
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = eye == .left ? "Left-eye geometry" : "Right-eye geometry"
            encoder.setRenderPipelineState(scenePipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            let range = StereoCamera.horizontalRange(eye, drawableWidth: Int(view.drawableSize.width))
            let projection = StereoCamera.projection(
                verticalFOVDegrees: profile.verticalFOVDegrees,
                aspect: Float(range.count) / Float(view.drawableSize.height),
                centerX: eye == .left ? profile.leftCenterX : profile.rightCenterX)
            var camera = SceneUniforms(viewProjection: projection * StereoCamera.viewMatrix(
                eye, orientation: pose, ipdMeters: profile.ipdMeters))
            encoder.setVertexBytes(&camera, length: MemoryLayout<SceneUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            if spatialFrame != nil { spatialUI.encode(encoder: encoder, viewProjection: camera.viewProjection) }
            encoder.endEncoding()
        }
        guard let compositor = command.makeRenderCommandEncoder(descriptor: output) else { return }
        compositor.label = "Physical SBS + calibrated lens prewarp"
        for eye in StereoCamera.Eye.allCases {
            distortion.encode(encoder: compositor, eye: eye, texture: eyeTextures[eye.rawValue],
                              drawableSize: view.drawableSize, profile: profile)
        }
        compositor.endEncoding()
        command.present(drawable)
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] completed in
            semaphore.signal()
            let gpu = completed.gpuEndTime > completed.gpuStartTime && completed.gpuStartTime > 0
                ? (completed.gpuEndTime - completed.gpuStartTime) * 1000 : nil
            DispatchQueue.main.async { [weak self] in self?.lastGPUTime = gpu }
        }
        command.commit()
        submitted = true
        updateMetrics(now: cpuStart, cpuMilliseconds: (CACurrentMediaTime() - cpuStart) * 1000)
    }

    private func effectiveScale(at now: TimeInterval) -> Float {
        let requestedCap: Float
        switch ProcessInfo.processInfo.thermalState {
        case .serious: requestedCap = 0.7
        case .critical: requestedCap = 0.5
        default: requestedCap = 1
        }
        if requestedCap < thermalCap {
            thermalCap = requestedCap
            lastThermalReduction = now
        } else if requestedCap > thermalCap && now - lastThermalReduction >= 20 {
            // Delayed recovery avoids rapid target reallocation near a thermal boundary.
            thermalCap = requestedCap
        } else if requestedCap == thermalCap && thermalCap < 1 {
            lastThermalReduction = now
        }
        return min(calibration.renderScale, thermalCap)
    }

    private func prepareTargets(size: CGSize, scale: Float) -> Bool {
        let width = Int(size.width)
        let height = Int(size.height)
        let boundedScale = min(max(scale, 0.5), 1)
        if width == targetWidth && height == targetHeight && boundedScale == targetScale { return true }
        var colors: [MTLTexture] = []
        var depths: [MTLTexture] = []
        for eye in StereoCamera.Eye.allCases {
            let eyeWidth = StereoCamera.horizontalRange(eye, drawableWidth: width).count
            let renderWidth = max(1, Int(Float(eyeWidth) * boundedScale))
            let renderHeight = max(1, Int(Float(height) * boundedScale))
            let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: renderWidth, height: renderHeight, mipmapped: false)
            colorDescriptor.storageMode = .private
            colorDescriptor.usage = [.renderTarget, .shaderRead]
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: renderWidth, height: renderHeight, mipmapped: false)
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = .renderTarget
            guard let color = device.makeTexture(descriptor: colorDescriptor),
                  let depth = device.makeTexture(descriptor: depthDescriptor) else { return false }
            colors.append(color)
            depths.append(depth)
        }
        eyeTextures = colors
        eyeDepthTextures = depths
        targetWidth = width
        targetHeight = height
        targetScale = boundedScale
        return true
    }

    private func updateMetrics(now: TimeInterval, cpuMilliseconds: Double) {
        if metricWindowStart == 0 || now - metricWindowStart > 2 {
            // Reset after foreground resume, rather than reporting background time as low FPS.
            metricWindowStart = now
            metricFrames = 0
        }
        metricFrames += 1
        cpuAverage = cpuAverage == 0 ? cpuMilliseconds : cpuAverage * 0.9 + cpuMilliseconds * 0.1
        let elapsed = now - metricWindowStart
        if elapsed >= 1 {
            metrics.fps = Double(metricFrames - 1) / elapsed
            metricFrames = 1
            metricWindowStart = now
        }
        metrics.cpuMilliseconds = cpuAverage
        metrics.gpuMilliseconds = lastGPUTime
        metrics.renderScale = targetScale
        if now - lastMetricPublish >= 0.25 {
            lastMetricPublish = now
            onMetrics?(metrics)
        }
    }
}
