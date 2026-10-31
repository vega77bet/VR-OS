import CoreMotion
import Foundation
import QuartzCore
import simd

struct HeadMotionSample {
    /// Core Motion attitude rotates reference vectors into the device frame.
    var referenceToDevice: simd_quatf
    var angularVelocity: SIMD3<Float>
    var timestamp: TimeInterval
}

@MainActor
protocol HeadMotionSource: AnyObject {
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var sample: HeadMotionSample? { get }
    func start()
    func stop()
}

/// Pull latest fused data immediately before rendering instead of queueing callbacks.
@MainActor
final class CoreMotionSource: HeadMotionSource {
    private let motion = CMMotionManager()
    var isAvailable: Bool { motion.isDeviceMotionAvailable }
    var isActive: Bool { motion.isDeviceMotionActive }
    var sample: HeadMotionSample? {
        guard let data = motion.deviceMotion else { return nil }
        let q = data.attitude.quaternion
        return HeadMotionSample(
            referenceToDevice: simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)),
            angularVelocity: SIMD3(Float(data.rotationRate.x), Float(data.rotationRate.y), Float(data.rotationRate.z)),
            timestamp: data.timestamp)
    }
    func start() {
        guard isAvailable, !isActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 120.0
        // No magnetometer heading corrections or camera dependency; yaw can drift.
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }
    func stop() { motion.stopDeviceMotionUpdates() }
    deinit { motion.stopDeviceMotionUpdates() }
}

@MainActor
final class HeadTrackingManager {
    private let source: HeadMotionSource
    private var recenterManager = RecenterManager()
    private var lastAbsolutePose = MotionCoordinateConverter.identity
    private var lastDisplayedPose = MotionCoordinateConverter.identity
    private var hasPose = false
    private var awaitingFirstSample = true
    private var wantsTracking = false
    private var streamStartTime: TimeInterval = 0
    private var previousTimestamp: TimeInterval?
    private var lastRestartTime: TimeInterval = 0
    private(set) var status = "Sensores parados"
    private(set) var isTracking = false
    static let staleSampleThreshold: TimeInterval = 0.25

    init(source: HeadMotionSource? = nil) {
        self.source = source ?? CoreMotionSource()
    }

    func start() { start(at: CACurrentMediaTime()) }
    func stop() {
        wantsTracking = false
        source.stop()
        isTracking = false
        awaitingFirstSample = true
        previousTimestamp = nil
        status = "Sensores parados"
    }

    /// Shared command endpoint for the test button and a future Bluetooth adapter.
    func recenter() { recenter(at: CACurrentMediaTime()) }
    func recenter(at time: TimeInterval) {
        guard hasPose, isTracking else { return }
        recenterManager.recenter(absolutePose: lastAbsolutePose, at: time)
    }

    func start(at time: TimeInterval) {
        guard !wantsTracking else { return }
        wantsTracking = true
        guard source.isAvailable else {
            status = "Core Motion indisponível — cena estática"
            return
        }
        beginStream(at: time)
    }

    func orientation(at time: TimeInterval) -> simd_quatf {
        guard wantsTracking, source.isAvailable else { return lastDisplayedPose }
        guard source.isActive else {
            isTracking = false
            status = "Rastreamento interrompido; retomando"
            restartIfNeeded(at: time)
            return lastDisplayedPose
        }
        guard let sample = source.sample,
              sample.timestamp.isFinite,
              sample.timestamp >= streamStartTime,
              sample.timestamp <= time + 0.01,
              time - sample.timestamp <= Self.staleSampleThreshold,
              MotionCoordinateConverter.isFiniteUnitCandidate(sample.referenceToDevice) else {
            isTracking = false
            status = "Aguardando amostra válida dos sensores"
            // A stale stream may require restarting after an OS interruption.
            if time - streamStartTime > 1 { restartIfNeeded(at: time) }
            return lastDisplayedPose
        }
        if let previous = previousTimestamp, sample.timestamp < previous {
            // Reject time rollback, and rebase the next fresh stream rather than jumping.
            isTracking = false
            restartIfNeeded(at: time)
            return lastDisplayedPose
        }
        previousTimestamp = sample.timestamp
        let absolute = MotionCoordinateConverter.predictedHeadPose(
            referenceToDevice: simd_normalize(sample.referenceToDevice),
            deviceAngularVelocity: sample.angularVelocity,
            sampleAge: time - sample.timestamp)
        if awaitingFirstSample {
            if hasPose {
                recenterManager.rebase(absolutePose: absolute, preserving: lastDisplayedPose)
            } else {
                recenterManager.recenter(absolutePose: absolute, at: time, animated: false)
            }
            awaitingFirstSample = false
        }
        lastAbsolutePose = absolute
        lastDisplayedPose = recenterManager.apply(to: absolute, at: time)
        hasPose = true
        isTracking = true
        status = "3DoF ativo"
        return lastDisplayedPose
    }

    private func beginStream(at time: TimeInterval) {
        streamStartTime = time
        lastRestartTime = time
        awaitingFirstSample = true
        previousTimestamp = nil
        source.start()
        status = "Aguardando sensores"
    }

    private func restartIfNeeded(at time: TimeInterval) {
        guard time - lastRestartTime >= 1 else { return }
        source.stop()
        beginStream(at: time)
    }
}
