import AVFoundation
import CoreImage
import SwiftUI

/// A true 0.5x camera feed: requests the physical rear ultra-wide lens.
/// ARKit must be paused while AVCaptureSession owns the rear camera.
final class VRUltraWideCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "Preparando câmera 0,5x…"
    @Published private(set) var active = false

    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "vros.ultrawide.capture", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "vros.ultrawide.frames", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var frameIndex = 0
    private var configured = false

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            DispatchQueue.main.async { self.status = "Permita o acesso à câmera nos Ajustes" }
            return
        }
        DispatchQueue.main.async { self.status = "Ligando lente ultrawide real…" }
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured && !self.configure() { return }
            if !self.capture.isRunning { self.capture.startRunning() }
            DispatchQueue.main.async {
                self.active = self.capture.isRunning
                self.status = self.active ? "0,5x REAL · ARKit pausado" :
                    "Não foi possível iniciar a câmera ultrawide"
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
                self.status = "Este iPhone não possui câmera ultrawide traseira"
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

    func stop(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            if self.capture.isRunning { self.capture.stopRunning() }
            DispatchQueue.main.async {
                self.active = false
                self.image = nil
                self.status = "Câmera 0,5x desligada"
                completion?()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameIndex += 1
        guard frameIndex % 2 == 0,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.active else { return }
            self.image = cgImage
        }
    }
}
