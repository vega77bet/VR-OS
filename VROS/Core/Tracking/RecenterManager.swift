import Foundation
import simd

/// Changes the world heading, never IPD or local eye offsets. Sensor motion stays unfiltered.
struct RecenterManager {
    private(set) var offset = MotionCoordinateConverter.identity
    private var startOffset = MotionCoordinateConverter.identity
    private var targetOffset = MotionCoordinateConverter.identity
    private var transitionStart: TimeInterval?
    static let transitionDuration: TimeInterval = 0.25

    mutating func recenter(absolutePose: simd_quatf, at time: TimeInterval, animated: Bool = true) {
        advance(at: time)
        guard let heading = MotionCoordinateConverter.heading(of: absolutePose) else { return }
        startOffset = offset
        targetOffset = simd_quatf(angle: -heading, axis: SIMD3(0, 1, 0))
        transitionStart = animated ? time : nil
        if !animated { offset = targetOffset }
    }

    /// A restarted Core Motion stream can choose a different arbitrary heading.
    /// Preserve the displayed heading, retaining the new gravity-derived pitch and roll.
    mutating func rebase(absolutePose: simd_quatf, preserving displayedPose: simd_quatf) {
        guard let newHeading = MotionCoordinateConverter.heading(of: absolutePose),
              let oldHeading = MotionCoordinateConverter.heading(of: displayedPose) else { return }
        offset = simd_quatf(angle: oldHeading - newHeading, axis: SIMD3(0, 1, 0))
        startOffset = offset
        targetOffset = offset
        transitionStart = nil
    }

    mutating func apply(to absolutePose: simd_quatf, at time: TimeInterval) -> simd_quatf {
        advance(at: time)
        return simd_normalize(offset * absolutePose)
    }

    private mutating func advance(at time: TimeInterval) {
        guard let start = transitionStart else { return }
        let t = Float(max(0, min((time - start) / Self.transitionDuration, 1)))
        let smooth = t * t * (3 - 2 * t)
        offset = simd_slerp(startOffset, targetOffset, smooth)
        if t >= 1 { transitionStart = nil }
    }
}
