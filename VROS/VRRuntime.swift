import ARKit
import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import Vision

/// Every landmark is camera-image normalized (origin at top left).
/// estimatedDepth is a monocular guess in metres, NOT a depth-sensor reading.
struct TrackedHand: Equatable {
    var point = CGPoint(x: 0.5, y: 0.5)
    var visible = false
    var pinching = false
    var joints: [CGPoint?] = Array(repeating: nil, count: 21)
    var estimatedDepth: Float?
    var worldPoint: SIMD3<Float>?
}

enum HandSkeleton {
    static let names: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    static let bones: [(Int, Int)] = [
        (0,1),(1,2),(2,3),(3,4),
        (0,5),(5,6),(6,7),(7,8),
        (0,9),(9,10),(10,11),(11,12),
        (0,13),(13,14),(14,15),(15,16),
        (0,17),(17,18),(18,19),(19,20),
        (5,9),(9,13),(13,17)
    ]
}

/// ARKit owns the rear camera. Both stereo halves consume one shared CGImage.
/// Running a separate AVCaptureSession alongside ARWorldTracking would contend
/// for the same camera, so Vision runs directly on ARFrame.capturedImage.
final class VRRuntime: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()

    @Published private(set) var cameraImage: CGImage?
    @Published private(set) var camera: ARCamera?
    @Published private(set) var hand = TrackedHand()
    @Published private(set) var cameraStatus = "Iniciando ARKit…"
    @Published private(set) var spatialTracking = false

    private let frameQueue = DispatchQueue(label: "vros.arkit.frames", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "vros.vision.hand", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let request = VNDetectHumanHandPoseRequest()

    // Only touched from frameQueue, except the Vision filters (visionQueue only).
    private var frameNumber = 0
    private var visionBusy = false
    // Owned exclusively by frameQueue, which is also ARSession's delegate queue.
    private var cinemaMode = false
    private var cameraPreviewEnabled = true

    private var filteredJoints: [CGPoint?] = Array(repeating: nil, count: 21)
    private var filteredDepth: Float?
    private var pinchLatched = false
    private var pinchFrames = 0
    private var missingFrames = 0

    override init() {
        super.init()
        request.maximumHandCount = 1
        session.delegate = self
        session.delegateQueue = frameQueue
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            cameraStatus = "Este aparelho não suporta ARKit World Tracking"
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied &&
              AVCaptureDevice.authorizationStatus(for: .video) != .restricted else {
            cameraStatus = "Libere a câmera nos Ajustes do iPhone"
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.runSession() }
                    else { self?.cameraStatus = "Permita o acesso à câmera" }
                }
            }
        } else {
            runSession()
        }
    }

    private func runSession(resuming: Bool = false) {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        // A resumed session should NOT erase all existing world anchors.
        let options: ARSession.RunOptions = resuming
            ? [] : [.resetTracking, .removeExistingAnchors]
        session.run(config, options: options)
        cameraStatus = resuming
            ? "ARKit: restaurando rastreamento…"
            : "ARKit: procurando o ambiente…"
    }

    func resume() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            start()
            return
        }
        runSession(resuming: true)
    }

    func stop() {
        session.pause()
    }

    /// Cinema renders its own stereo SceneKit scene. Avoid the expensive
    /// AR camera pixel-buffer to CGImage conversion behind the cinema.
    /// Continue publishing AR pose (fallback) and hand tracking (pinch).
    func setCinemaMode(_ enabled: Bool) {
        frameQueue.async { [weak self] in
            self?.cinemaMode = enabled
        }
        if enabled {
            // Cinema shows its own 3D room; keep only the AR pose and Vision.
            cameraImage = nil
        }
    }

    func setCameraPreviewEnabled(_ enabled: Bool) {
        frameQueue.async { [weak self] in
            self?.cameraPreviewEnabled = enabled
        }
        if !enabled { cameraImage = nil }
    }

    /// Recenter means put the panels in front of the current camera pose.
    /// It does not reset the ARKit world origin.
    func worldPoint(at screenPoint: CGPoint, viewport: CGSize, depth: Float,
                    using pose: ARCamera? = nil) -> SIMD3<Float>? {
        guard let pose = pose ?? camera, viewport.width > 0, viewport.height > 0 else { return nil }
        let resolution = pose.imageResolution
        let sourceW = max(resolution.width, 1)
        let sourceH = max(resolution.height, 1)
        let scale = max(viewport.width / sourceW, viewport.height / sourceH)
        let sourceX = (screenPoint.x + (sourceW * scale - viewport.width) * 0.5) / scale
        let sourceY = (screenPoint.y + (sourceH * scale - viewport.height) * 0.5) / scale
        let intrinsics = pose.intrinsics
        let fx = max(intrinsics.columns.0.x, 1)
        let fy = max(intrinsics.columns.1.y, 1)
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        let local = SIMD4<Float>(
            Float((sourceX - CGFloat(cx)) / CGFloat(fx)) * depth,
            -Float((sourceY - CGFloat(cy)) / CGFloat(fy)) * depth,
            -depth, 1
        )
        let world = pose.transform * local
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    func projectedPoint(_ world: SIMD3<Float>, viewport: CGSize,
                        rightEye: Bool) -> CGPoint? {
        guard let pose = camera else { return nil }
        let view = simd_inverse(pose.transform) * SIMD4<Float>(world.x, world.y, world.z, 1)
        guard view.z < -0.1 else { return nil }
        let point = pose.projectPoint(world, orientation: .landscapeRight, viewportSize: viewport)
        guard point.x.isFinite, point.y.isFinite else { return nil }

        // Approximate stereo window disparity from a virtual 64-mm interpupillary distance.
        // Camera passthrough remains monocular; this is NOT stereo camera reconstruction.
        let effectiveFocal = CGFloat(pose.intrinsics.columns.0.x) *
            max(viewport.width / max(pose.imageResolution.width, 1),
                viewport.height / max(pose.imageResolution.height, 1))
        let disparity = min(32, effectiveFocal * 0.032 / CGFloat(-view.z))
        return CGPoint(x: point.x + (rightEye ? -disparity : disparity), y: point.y)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameNumber += 1
        let frameIndex = frameNumber
        let pose = frame.camera
        let reliable: Bool
        if case .normal = pose.trackingState { reliable = true }
        else { reliable = false }

        // Only graphite Home displays the camera pixels. Themes and Cinema
        // need camera pose for motion, not costly CGImage creation.
        let pixelsRequired = cameraPreviewEnabled && !cinemaMode
        let displayStride = pixelsRequired ? 3 : 6
        if frameIndex % displayStride == 0 {
            let output: CGImage?
            if !pixelsRequired {
                output = nil
            } else {
                let image = CIImage(cvPixelBuffer: frame.capturedImage)
                output = ciContext.createCGImage(image, from: image.extent)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let output = output { self.cameraImage = output }
                self.camera = pose
                self.spatialTracking = reliable
                if !reliable {
                    self.cameraStatus = "ARKit: mova o iPhone devagar para localizar o ambiente"
                }
            }
        }

        // Hand detection ~15 fps in Home, ~10 in Cinema, without queue buildup.
        let handStride = cinemaMode ? 6 : 4
        if frameIndex % handStride == 0 && !visionBusy {
            visionBusy = true
            visionQueue.async { [weak self] in
                self?.detectHand(in: frame)
                self?.frameQueue.async { [weak self] in self?.visionBusy = false }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.cameraStatus = "Erro ARKit: \(error.localizedDescription)"
        }
    }

    private func detectHand(in frame: ARFrame) {
        // ARKit captures landscape-right sensor images; Vision and display share
        // this unrotated buffer so their 2D coordinates use the same origin.
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                noHand()
                return
            }
            let points = try observation.recognizedPoints(.all)
            var next: [CGPoint?] = Array(repeating: nil, count: HandSkeleton.names.count)
            for (i, name) in HandSkeleton.names.enumerated() {
                guard let joint = points[name], joint.confidence >= 0.28 else {
                    filteredJoints[i] = nil
                    continue
                }
                let raw = CGPoint(x: joint.location.x, y: 1 - joint.location.y)
                if let old = filteredJoints[i] {
                    let value = CGPoint(x: old.x * 0.56 + raw.x * 0.44,
                                        y: old.y * 0.56 + raw.y * 0.44)
                    next[i] = value
                } else {
                    next[i] = raw
                }
                filteredJoints[i] = next[i]
            }
            guard let index = next[8], let thumb = next[4] else {
                noHand()
                return
            }

            missingFrames = 0
            let palm = palmSpan(next)
            let pinchSize = max(palm, 0.04)
            let pinchRatio = hypot(index.x - thumb.x, index.y - thumb.y) / pinchSize
            let target = pinchLatched ? pinchRatio < 0.63 : pinchRatio < 0.42
            if target == pinchLatched {
                pinchFrames = 0
            } else {
                pinchFrames += 1
                if pinchFrames >= 2 {
                    pinchLatched = target
                    pinchFrames = 0
                }
            }

            let depth = estimateDepth(joints: next, camera: frame.camera)
            let world: SIMD3<Float>? = depth.flatMap { d in
                let viewport = frame.camera.imageResolution
                return worldPoint(at: CGPoint(x: index.x * viewport.width,
                                              y: index.y * viewport.height),
                                  viewport: viewport, depth: d, using: frame.camera)
            }
            let state = TrackedHand(point: index, visible: true, pinching: pinchLatched,
                                    joints: next, estimatedDepth: depth, worldPoint: world)
            let count = next.compactMap { $0 }.count
            let message = depth.map { "Mão \(count)/21 · Z ≈ \(String(format: "%.2f", $0)) m" }
                ?? "Mão \(count)/21 · Z não estimado"
            DispatchQueue.main.async { [weak self] in
                self?.hand = state
                self?.cameraStatus = message
            }
        } catch {
            noHand()
        }
    }

    private func palmSpan(_ joints: [CGPoint?]) -> CGFloat {
        guard let indexBase = joints[5], let littleBase = joints[17] else { return 0 }
        return hypot(indexBase.x - littleBase.x, indexBase.y - littleBase.y)
    }

    /// Monocular pinhole estimate: distance ~= focal_length_px * palm_width_m / palm_width_px.
    /// Palm width is assumed (8.5 cm); foreshortening, finger pose, and hand size
    /// change the apparent width, so this MUST NOT be treated as measured depth.
    private func estimateDepth(joints: [CGPoint?], camera: ARCamera) -> Float? {
        guard let indexBase = joints[5], let littleBase = joints[17] else {
            return filteredDepth
        }
        let imageW = Float(camera.imageResolution.width)
        let imageH = Float(camera.imageResolution.height)
        let dx = Float(indexBase.x - littleBase.x) * imageW
        let dy = Float(indexBase.y - littleBase.y) * imageH
        let apparent = hypot(dx, dy)
        guard apparent > 7 else { return filteredDepth }
        let fx = camera.intrinsics.columns.0.x
        let raw = max(0.30, min(3.5, fx * 0.085 / apparent))
        let value = filteredDepth.map { 0.78 * $0 + 0.22 * raw } ?? raw
        filteredDepth = value
        return value
    }

    private func noHand() {
        missingFrames += 1
        guard missingFrames >= 3 else { return }
        filteredJoints = Array(repeating: nil, count: 21)
        filteredDepth = nil
        pinchLatched = false
        pinchFrames = 0
        DispatchQueue.main.async { [weak self] in
            self?.hand = TrackedHand()
            self?.cameraStatus = "Mostre palma e dedos à câmera traseira"
        }
    }
}
