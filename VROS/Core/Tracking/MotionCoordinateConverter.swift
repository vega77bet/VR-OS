import Foundation
import simd

/// All quaternions act on column vectors. See Docs/Coordinates.md for the derivation.
enum MotionCoordinateConverter {
    static let identity = simd_quatf(real: 1, imag: .zero)
    /// Core Motion reference: +Z up. Engine: +Y up, camera forward -Z.
    static let worldFromReference = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
    /// UIInterfaceOrientation.landscapeRight: USB/Home at right, Dynamic Island at left.
    /// Head +X = -device Y; head +Y = device X; head +Z = device Z.
    static let deviceFromHead = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1))

    static func headPose(referenceToDevice attitude: simd_quatf) -> simd_quatf {
        simd_normalize(worldFromReference * attitude.inverse * deviceFromHead)
    }

    /// Integrate the measured body angular velocity over sample age, capped at 20 ms.
    /// This compensates sample age only; it does not guess display scan-out time.
    static func predictedHeadPose(referenceToDevice attitude: simd_quatf,
                                  deviceAngularVelocity: SIMD3<Float>,
                                  sampleAge: TimeInterval) -> simd_quatf {
        let pose = headPose(referenceToDevice: attitude)
        let omega = deviceFromHead.inverse.act(deviceAngularVelocity)
        let speed = simd_length(omega)
        guard speed.isFinite, speed > 0.00001, sampleAge.isFinite else { return pose }
        let dt = Float(max(0, min(sampleAge, 0.020)))
        return simd_normalize(pose * simd_quatf(angle: speed * dt, axis: omega / speed))
    }

    /// Heading about world +Y. A vertical gaze has no heading; retain the old value.
    static func heading(of pose: simd_quatf) -> Float? {
        let forward = pose.act(SIMD3<Float>(0, 0, -1))
        guard forward.x * forward.x + forward.z * forward.z > 0.0001 else { return nil }
        return atan2(-forward.x, -forward.z)
    }

    static func isFiniteUnitCandidate(_ q: simd_quatf) -> Bool {
        q.vector.x.isFinite && q.vector.y.isFinite && q.vector.z.isFinite &&
        q.vector.w.isFinite && simd_length_squared(q.vector) > 0.0001
    }
}
