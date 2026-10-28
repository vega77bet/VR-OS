import CoreGraphics
import CoreMotion
import Combine
import Foundation
import UIKit
import simd

/// Camera-independent pointer for VR Box use.
///
/// The pointer is driven by relative head/device motion. A target remains
/// stable until the user recentres it, so a broken or unavailable camera does
/// not prevent navigation through the native interface.
final class VRDwellController: ObservableObject {
    @Published private(set) var normalizedPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var active = false
    @Published private(set) var motionAvailable = false
    @Published private(set) var pulse = 0
    @Published private(set) var headRotation = simd_quatf()

    private let motion = CMMotionManager()
    private let callbackQueue = OperationQueue.main
    private var referenceYaw: Double?
    private var referencePitch: Double?
    private var targetKey: String?
    private var targetStarted: Date?
    private var targetFired = false
    private var delay: TimeInterval = 1.0
    private var heartbeat: Timer?
    private var referenceRotation: simd_quatf?
    private var displayOrientation: UIInterfaceOrientation?

    /// Lower values make the target move more slowly with head rotation.
    private let sensitivity = 0.42

    func start() {
        guard !active else { return }
        active = true
        resetTarget()
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                         repeats: true) { [weak self] _ in
            self?.pulse += 1
        }
        if motion.isDeviceMotionAvailable {
            motionAvailable = true
            motion.deviceMotionUpdateInterval = 1.0 / 30.0
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: callbackQueue) { [weak self] reading, error in
                guard let self = self, let reading = reading, error == nil else {
                    self?.motionAvailable = false
                    return
                }
                self.consume(reading.attitude)
            }
        } else {
            // A centered target still permits a basic click on devices without
            // a motion sensor; the app remains usable instead of going black.
            motionAvailable = false
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        heartbeat?.invalidate()
        heartbeat = nil
        active = false
        motionAvailable = false
        referenceYaw = nil
        referencePitch = nil
        referenceRotation = nil
        headRotation = simd_quatf()
        resetTarget()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    func setDelay(_ seconds: CGFloat) {
        let value = seconds.isFinite ? seconds : 1.0
        delay = TimeInterval(max(0.5, min(2.0, value)))
        resetTarget()
    }

    func recenter() {
        if let attitude = motion.deviceMotion?.attitude {
            referenceYaw = attitude.yaw
            referencePitch = attitude.pitch
            let q = attitude.quaternion
            referenceRotation = simd_normalize(simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)))
        } else {
            referenceYaw = nil
            referencePitch = nil
            referenceRotation = nil
        }
        headRotation = simd_quatf()
        normalizedPoint = CGPoint(x: 0.5, y: 0.5)
        resetTarget()
    }

    func point(in viewport: CGSize) -> CGPoint {
        CGPoint(x: normalizedPoint.x * max(1, viewport.width),
                y: normalizedPoint.y * max(1, viewport.height))
    }

    /// Returns true once when the same interactive target has been held for
    /// the configured dwell duration.
    @discardableResult
    func updateTarget(_ key: String?, now: Date = Date()) -> Bool {
        guard active, let key = key else {
            resetTarget()
            return false
        }
        if targetKey != key {
            targetKey = key
            targetStarted = now
            targetFired = false
            progress = 0
            return false
        }
        guard !targetFired, let started = targetStarted else { return false }
        let elapsed = max(0, now.timeIntervalSince(started))
        progress = CGFloat(max(0, min(1, elapsed / delay)))
        guard elapsed >= delay else { return false }
        targetFired = true
        progress = 1
        return true
    }

    private func resetTarget() {
        targetKey = nil
        targetStarted = nil
        targetFired = false
        progress = 0
    }

    private func consume(_ attitude: CMAttitude) {
        guard active else { return }
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation ?? .landscapeRight
        let q = attitude.quaternion
        let current = simd_normalize(simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)))
        if referenceRotation == nil || displayOrientation != orientation {
            referenceRotation = current
            displayOrientation = orientation
        }
        guard let reference = referenceRotation else { return }
        let basis = simd_quatf(angle: orientation == .landscapeLeft ? -.pi / 2 : .pi / 2,
                              axis: SIMD3<Float>(0, 0, 1))
        headRotation = simd_normalize(simd_inverse(basis) * simd_inverse(reference) * current * basis)
        let forward = headRotation.act(SIMD3<Float>(0, 0, -1))
        let yaw = Double(atan2(-forward.x, -forward.z))
        let pitch = Double(asin(max(-1, min(1, forward.y))))
        let x = 0.5 + yaw * sensitivity
        let y = 0.5 - pitch * sensitivity
        normalizedPoint = CGPoint(
            x: max(0.06, min(0.94, x)),
            y: max(0.06, min(0.94, y))
        )
    }

    private func wrappedAngle(_ value: Double) -> Double {
        var result = value
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }
}
