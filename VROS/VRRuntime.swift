import AVFoundation
import CoreMotion
import SwiftUI
import Vision
import ImageIO

struct TrackedHand: Equatable {
    var point: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var visible = false
    var pinching = false
    // Vision provides 21 2D joints: wrist, thumb, index, middle, ring and little fingers.
    var joints: [CGPoint?] = Array(repeating: nil, count: 21)
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

final class VRRuntime: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var hand = TrackedHand()
    @Published var cameraStatus = "Iniciando câmera…"
    @Published var headYaw: Double = 0
    @Published var headPitch: Double = 0

    private let cameraQueue = DispatchQueue(label: "vros.camera.setup")
    private let videoQueue = DispatchQueue(label: "vros.hand.vision", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    private let motion = CMMotionManager()
    private var configured = false
    private var frameNumber = 0
    private var filteredJoints: [CGPoint?] = Array(repeating: nil, count: 21)
    private var pinchLatched = false
    private var pinchFrames = 0
    private var missingFrames = 0
    private var initialYaw: Double?

    override init() {
        super.init()
        request.maximumHandCount = 1
    }

    func start() {
        startMotion()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupCamera() }
                else { DispatchQueue.main.async { self?.cameraStatus = "Permita a câmera nos Ajustes" } }
            }
        default:
            cameraStatus = "Câmera bloqueada: Ajustes > Privacidade > Câmera"
        }
    }

    private func setupCamera() {
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.cameraStatus = "Câmera traseira indisponível" }
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.cameraStatus = "Não foi possível iniciar Vision" }
                    return
                }
                self.session.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.cameraStatus = "Mostre a mão inteira à câmera" }
        }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let self = self, let attitude = reading?.attitude else { return }
            if self.initialYaw == nil { self.initialYaw = attitude.yaw }
            var delta = attitude.yaw - (self.initialYaw ?? 0)
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            self.headYaw = delta
            self.headPitch = attitude.pitch
        }
    }

    func recenter() {
        initialYaw = motion.deviceMotion?.attitude.yaw
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameNumber += 1
        guard frameNumber % 2 == 0 else { return }
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
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
                    let smooth = CGPoint(x: old.x * 0.58 + raw.x * 0.42,
                                         y: old.y * 0.58 + raw.y * 0.42)
                    next[i] = smooth
                    filteredJoints[i] = smooth
                } else {
                    next[i] = raw
                    filteredJoints[i] = raw
                }
            }
            guard let index = next[8], let thumb = next[4] else {
                noHand()
                return
            }
            missingFrames = 0
            // Normalize pinch threshold by palm size to reduce distance sensitivity.
            let palmSize: CGFloat
            if let wrist = next[0], let middle = next[9] {
                palmSize = max(0.045, hypot(wrist.x - middle.x, wrist.y - middle.y))
            } else {
                palmSize = 0.12
            }
            let pinchRatio = hypot(index.x - thumb.x, index.y - thumb.y) / palmSize
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
            let count = next.compactMap { $0 }.count
            let latest = TrackedHand(point: index, visible: true, pinching: pinchLatched, joints: next)
            DispatchQueue.main.async { [weak self] in
                self?.hand = latest
                self?.cameraStatus = "Mão: \(count)/21 pontos · pinça para clicar"
            }
        } catch {
            noHand()
        }
    }

    private func noHand() {
        missingFrames += 1
        guard missingFrames >= 3 else { return }
        filteredJoints = Array(repeating: nil, count: 21)
        pinchLatched = false
        pinchFrames = 0
        DispatchQueue.main.async { [weak self] in
            self?.hand = TrackedHand()
            self?.cameraStatus = "Mostre a palma e os dedos à câmera"
        }
    }
}

final class VRPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var cameraLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct VRPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VRPreviewUIView {
        let view = VRPreviewUIView()
        view.backgroundColor = .black
        view.cameraLayer.videoGravity = .resizeAspectFill
        view.cameraLayer.session = session
        if let connection = view.cameraLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
        return view
    }

    func updateUIView(_ uiView: VRPreviewUIView, context: Context) {
        if uiView.cameraLayer.session !== session {
            uiView.cameraLayer.session = session
        }
    }
}
