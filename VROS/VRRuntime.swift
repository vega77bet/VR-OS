import AVFoundation
import CoreMotion
import SwiftUI
import Vision
import ImageIO

struct TrackedHand: Equatable {
    var point: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var visible = false
    var pinching = false
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
    private var filteredPoint: CGPoint?
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
            DispatchQueue.main.async { self.cameraStatus = "Procure sua mão em frente à câmera" }
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
        // Run Vision on alternating camera frames so preview stays responsive.
        guard frameNumber % 2 == 0 else { return }

        // The capture connection rotates the buffers to landscape-right.
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let index = try? observation.recognizedPoint(.indexTip),
                  let thumb = try? observation.recognizedPoint(.thumbTip),
                  index.confidence > 0.35, thumb.confidence > 0.35 else {
                noHand()
                return
            }
            missingFrames = 0
            let point = CGPoint(x: index.location.x, y: 1 - index.location.y)
            let smoothed: CGPoint
            if let old = filteredPoint {
                smoothed = CGPoint(x: old.x * 0.55 + point.x * 0.45,
                                   y: old.y * 0.55 + point.y * 0.45)
            } else {
                smoothed = point
            }
            filteredPoint = smoothed

            let distance = hypot(index.location.x - thumb.location.x,
                                 index.location.y - thumb.location.y)
            if pinchLatched {
                if distance > 0.095 { pinchFrames += 1 }
                else { pinchFrames = 0 }
                if pinchFrames >= 2 { pinchLatched = false; pinchFrames = 0 }
            } else {
                if distance < 0.065 { pinchFrames += 1 }
                else { pinchFrames = 0 }
                if pinchFrames >= 2 { pinchLatched = true; pinchFrames = 0 }
            }

            let latest = TrackedHand(point: smoothed, visible: true, pinching: pinchLatched)
            DispatchQueue.main.async { [weak self] in
                self?.hand = latest
                self?.cameraStatus = "Mão detectada · pinça para clicar"
            }
        } catch {
            noHand()
        }
    }

    private func noHand() {
        missingFrames += 1
        guard missingFrames >= 3 else { return }
        filteredPoint = nil
        pinchLatched = false
        pinchFrames = 0
        DispatchQueue.main.async { [weak self] in
            self?.hand = TrackedHand()
            self?.cameraStatus = "Mostre a mão à câmera traseira"
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
