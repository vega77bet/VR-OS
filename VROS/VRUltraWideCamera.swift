import AVFoundation
import CoreImage
import CoreMotion
import SwiftUI
import UIKit
import Vision
import simd

/// True rear 0.5x ultrawide camera, PLUS independent Vision hand/pinch and
/// CoreMotion 3DoF orientation tracking. ARKit/6DoF remains paused while
/// AVCapture owns the physical lens; no world tracking is claimed here.
final class VRUltraWideCamera: NSObject, ObservableObject,
                               AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "Preparando câmera 0,5x…"
    @Published private(set) var active = false
    @Published private(set) var hand = TrackedHand()
    @Published private(set) var motionDelta = simd_quatf()
    @Published private(set) var motionAvailable = false

    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "vros.ultrawide.capture", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "vros.ultrawide.frames", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "vros.ultrawide.vision", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let request = VNDetectHumanHandPoseRequest()
    private let motion = CMMotionManager()
    private var reference: simd_quatf?
    // frameIndex and visionBusy are owned exclusively by outputQueue.
    private var frameIndex = 0
    private var visionBusy = false
    // Vision filter state is owned exclusively by visionQueue.
    private var filteredJoints: [CGPoint?] = Array(repeating: nil, count: 21)
    private var pinchDetector = VRPinchDetector()
    private var missingFrames = 0
    private var configured = false

    override init() {
        super.init()
        request.maximumHandCount = 1
    }

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = "Permita o acesso à câmera nos Ajustes"
            return
        }
        status = "Ligando lente 0,5x e sensores…"
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured && !self.configure() { return }
            if !self.capture.isRunning { self.capture.startRunning() }
            let running = self.capture.isRunning
            DispatchQueue.main.async {
                self.active = running
                self.status = running
                    ? "0,5x real · mãos (Vision) + cabeça (3DoF)"
                    : "Não foi possível iniciar a câmera ultrawide"
                if running { self.startHeadMotion() }
            }
        }
    }

    private func configure() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first else {
            DispatchQueue.main.async {
                self.status = "Este iPhone não possui lente ultrawide traseira"
            }
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            capture.beginConfiguration()
            capture.sessionPreset = .high
            guard capture.canAddInput(input) else {
                capture.commitConfiguration()
                DispatchQueue.main.async { self.status = "Falha ao acessar lente 0,5x" }
                return false
            }
            capture.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: outputQueue)
            guard capture.canAddOutput(output) else {
                capture.commitConfiguration()
                DispatchQueue.main.async { self.status = "Falha ao receber vídeo 0,5x" }
                return false
            }
            capture.addOutput(output)
            if let connection = output.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            capture.commitConfiguration()
            configured = true
            return true
        } catch {
            DispatchQueue.main.async {
                self.status = "Erro da câmera: \(error.localizedDescription)"
            }
            return false
        }
    }

    /// Safe to call on the main thread; completion happens only after
    /// AVCaptureSession has released the camera, before ARKit resumes.
    func stop(completion: (() -> Void)? = nil) {
        motion.stopDeviceMotionUpdates()
        reference = nil
        motionDelta = simd_quatf()
        motionAvailable = false
        active = false
        hand = TrackedHand()
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            if self.capture.isRunning { self.capture.stopRunning() }
            DispatchQueue.main.async {
                self.image = nil
                self.status = "Câmera 0,5x desligada"
                completion?()
            }
        }
    }

    /// Gyroscope+accelerometer orientation is independent of camera capture.
    /// This supplies rotation only, never positional ARKit/6DoF tracking.
    private func startHeadMotion() {
        guard motion.isDeviceMotionAvailable else {
            motionAvailable = false
            status = "0,5x real · mão ativa · sensor de cabeça indisponível"
            return
        }
        reference = nil
        motionDelta = simd_quatf()
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryZVertical)
            ? .xArbitraryZVertical : .xArbitraryCorrectedZVertical
        motion.startDeviceMotionUpdates(using: frame, to: .main) {
            [weak self] reading, error in
            guard let self = self, self.active else { return }
            guard let reading = reading, error == nil else {
                self.motionAvailable = false
                return
            }
            self.motionAvailable = true
            let q = reading.attitude.quaternion
            let current = simd_normalize(simd_quatf(
                ix: Float(q.x), iy: Float(q.y),
                iz: Float(q.z), r: Float(q.w)))
            if self.reference == nil { self.reference = current }
            guard let reference = self.reference else { return }

            // Express delta in the actual landscape display axes, matching
            // Cinema's existing relative-head orientation convention.
            let deltaDevice = simd_inverse(reference) * current
            let basis = self.screenToDeviceRotation()
            self.motionDelta = simd_normalize(
                simd_inverse(basis) * deltaDevice * basis)
        }
    }

    private func screenToDeviceRotation() -> simd_quatf {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .landscapeRight
        let turn: Float = orientation == .landscapeLeft ? -.pi / 2 : .pi / 2
        return simd_quatf(angle: turn, axis: SIMD3<Float>(0, 0, 1))
    }

    func recenterMotion() {
        guard let q = motion.deviceMotion?.attitude.quaternion else { return }
        reference = simd_normalize(simd_quatf(
            ix: Float(q.x), iy: Float(q.y),
            iz: Float(q.z), r: Float(q.w)))
        motionDelta = simd_quatf()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameIndex += 1
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if frameIndex % 2 == 0 {
            let image = CIImage(cvPixelBuffer: buffer)
            if let cgImage = context.createCGImage(image, from: image.extent) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.active else { return }
                    self.image = cgImage
                }
            }
        }
        // Vision at ~10fps on a separate queue, avoiding a backlog of
        // hand requests and keeping the camera preview responsive.
        if frameIndex % 3 == 0 && !visionBusy {
            visionBusy = true
            visionQueue.async { [weak self] in
                self?.detectHand(in: buffer)
                self?.outputQueue.async { [weak self] in self?.visionBusy = false }
            }
        }
    }

    private func detectHand(in buffer: CVPixelBuffer) {
        // AVCaptureVideoDataOutput is rotated to LandscapeRight above.
        // Vision's top-left normalized coordinates match the preview CGImage.
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                noHand()
                return
            }
            let points = try observation.recognizedPoints(.all)
            var joints: [CGPoint?] = Array(repeating: nil, count: 21)
            for (index, name) in HandSkeleton.names.enumerated() {
                guard let p = points[name], p.confidence >= 0.28 else {
                    filteredJoints[index] = nil
                    continue
                }
                let raw = CGPoint(x: p.location.x, y: 1 - p.location.y)
                if let previous = filteredJoints[index] {
                    joints[index] = CGPoint(x: previous.x * 0.55 + raw.x * 0.45,
                                            y: previous.y * 0.55 + raw.y * 0.45)
                } else {
                    joints[index] = raw
                }
                filteredJoints[index] = joints[index]
            }
            guard let thumb = joints[4], let fingertip = joints[8] else {
                noHand()
                return
            }
            missingFrames = 0
            let palm: CGFloat
            if let indexBase = joints[5], let littleBase = joints[17] {
                palm = hypot(indexBase.x - littleBase.x,
                             indexBase.y - littleBase.y)
            } else {
                palm = 0.04
            }
            let pinching = pinchDetector.update(
                thumb: thumb, index: fingertip, palmWidth: palm)
            let state = TrackedHand(point: fingertip, visible: true,
                                    pinching: pinching, joints: joints,
                                    estimatedDepth: nil, worldPoint: nil)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.active else { return }
                self.hand = state
            }
        } catch {
            noHand()
        }
    }

    private func noHand() {
        missingFrames += 1
        guard missingFrames >= 3 else { return }
        filteredJoints = Array(repeating: nil, count: 21)
        pinchDetector.reset()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.active else { return }
            self.hand = TrackedHand()
        }
    }
}
