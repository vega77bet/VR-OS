import UIKit
import MetalKit
import Combine

/// Owns sensor/display lifetime. Inactive scenes and calibration pause both.
/// Future Bluetooth commands can call `tracking.recenter()` on the main actor.
@MainActor
final class AppLifecycleManager: ObservableObject {
    let tracking = HeadTrackingManager()
    let calibration = VRCalibrationManager()
    let spatial = SpatialSession()
    @Published private(set) var metrics = FrameMetrics()
    @Published private(set) var trackingStatus = "Aguardando sensores"
    @Published var renderError: String?
    private weak var metalView: MTKView?
    private var active = false
    private var presentationPaused = false

    func attach(_ view: MTKView) { metalView = view; applyState() }
    func setActive(_ value: Bool) { active = value; applyState() }
    func setPresentationPaused(_ value: Bool) { presentationPaused = value; applyState() }

    func receive(_ metrics: FrameMetrics) {
        self.metrics = metrics
        spatial.receive(metrics)
        trackingStatus = tracking.status
    }

    private func applyState() {
        let running = active && !presentationPaused && metalView != nil
        spatial.setActive(active)
        spatial.resetInput()
        metalView?.isPaused = !running
        UIApplication.shared.isIdleTimerDisabled = running
        if running { tracking.start() } else { tracking.stop() }
        trackingStatus = tracking.status
    }
}
