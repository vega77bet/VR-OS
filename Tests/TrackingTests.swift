import XCTest
import simd
@testable import VROS

final class TrackingTests: XCTestCase {
    // Independent reference fixture: upright landscapeRight, screen +Y = device +X.
    // Hamilton quaternion Rz(-90°) Rx(-90°), with reference gravity down device -X.
    private let neutral = simd_quatf(ix: -0.5, iy: 0.5, iz: -0.5, r: 0.5)
    private let forward = SIMD3<Float>(0, 0, -1)
    private let up = SIMD3<Float>(0, 1, 0)

    func testNeutralLandscapeAndCoreMotionGravityConvention() {
        assertVector(neutral.act(SIMD3(0, 0, -1)), SIMD3(-1, 0, 0))
        let pose = MotionCoordinateConverter.headPose(referenceToDevice: neutral)
        assertVector(pose.act(forward), forward)
        assertVector(pose.act(up), up)
        assertVector(MotionCoordinateConverter.deviceFromHead.act(SIMD3(1, 0, 0)), SIMD3(0, -1, 0))
        assertVector(MotionCoordinateConverter.deviceFromHead.act(up), SIMD3(1, 0, 0))
    }

    func testPhysicalYawRightAndLeftDoNotInvert() {
        for sign: Float in [-1, 1] {
            // A right head turn is negative about screen +Y = device +X.
            // A reference->device attitude therefore gains the inverse, +X rotation.
            let sample = simd_quatf(angle: sign * .pi / 6, axis: SIMD3(1, 0, 0)) * neutral
            let gaze = MotionCoordinateConverter.headPose(referenceToDevice: sample).act(forward)
            XCTAssertEqual(gaze.x, sign * 0.5, accuracy: 0.00001)
            XCTAssertEqual(gaze.y, 0, accuracy: 0.00001)
            XCTAssertLessThan(gaze.z, 0)
        }
    }

    func testPhysicalPitchUpAndDownDoNotInvert() {
        for sign: Float in [-1, 1] {
            // Looking up rotates positively about head +X = -device Y.
            let sample = simd_quatf(angle: sign * .pi / 6, axis: SIMD3(0, 1, 0)) * neutral
            let gaze = MotionCoordinateConverter.headPose(referenceToDevice: sample).act(forward)
            XCTAssertEqual(gaze.y, sign * 0.5, accuracy: 0.00001)
            XCTAssertEqual(gaze.x, 0, accuracy: 0.00001)
        }
    }

    func testPhysicalRollRightAndLeftDoNotInvert() {
        for sign: Float in [-1, 1] {
            let sample = simd_quatf(angle: sign * .pi / 6, axis: SIMD3(0, 0, 1)) * neutral
            let pose = MotionCoordinateConverter.headPose(referenceToDevice: sample)
            XCTAssertEqual(pose.act(up).x, sign * 0.5, accuracy: 0.00001)
            assertVector(pose.act(forward), forward)
        }
    }

    func testPredictionMatchesBodyRateAndIsBounded() {
        // Device -X is a physical right turn in landscapeRight.
        let pose = MotionCoordinateConverter.predictedHeadPose(
            referenceToDevice: neutral, deviceAngularVelocity: SIMD3(-2, 0, 0), sampleAge: 0.01)
        XCTAssertEqual(pose.act(forward).x, sin(0.02), accuracy: 0.00001)
        let capped = MotionCoordinateConverter.predictedHeadPose(
            referenceToDevice: neutral, deviceAngularVelocity: SIMD3(-2, 0, 0), sampleAge: 8)
        XCTAssertEqual(capped.act(forward).x, sin(0.04), accuracy: 0.00001)
        let negativeAge = MotionCoordinateConverter.predictedHeadPose(
            referenceToDevice: neutral, deviceAngularVelocity: SIMD3(-2, 0, 0), sampleAge: -1)
        assertVector(negativeAge.act(forward), forward)
    }

    func testRecenterHasNoDiscontinuityAndPreservesTilt() {
        let yaw = simd_quatf(angle: -0.8, axis: SIMD3(0, 1, 0))
        let tilt = simd_quatf(angle: 0.2, axis: SIMD3(1, 0, 0)) *
                   simd_quatf(angle: -0.1, axis: SIMD3(0, 0, 1))
        let absolute = yaw * tilt
        var manager = RecenterManager()
        manager.recenter(absolutePose: absolute, at: 1)
        let first = manager.apply(to: absolute, at: 1)
        assertVector(first.act(forward), absolute.act(forward))
        let final = manager.apply(to: absolute, at: 1.25)
        XCTAssertEqual(MotionCoordinateConverter.heading(of: final)!, 0, accuracy: 0.00001)
        // A world-Y rotation cannot change any vector's vertical component.
        XCTAssertEqual(final.act(forward).y, absolute.act(forward).y, accuracy: 0.00001)
        XCTAssertEqual(final.act(up).y, absolute.act(up).y, accuracy: 0.00001)
        manager.recenter(absolutePose: absolute, at: 2)
        assertVector(manager.apply(to: absolute, at: 2.25).act(forward), final.act(forward))
    }

    func testRecenterWhileLookingStraightUpRetainsHeading() {
        var manager = RecenterManager()
        let old = simd_quatf(angle: 0.7, axis: SIMD3(0, 1, 0))
        manager.recenter(absolutePose: old, at: 0, animated: false)
        let original = manager.offset
        manager.recenter(absolutePose: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)), at: 1)
        _ = manager.apply(to: old, at: 2)
        assertVector(manager.offset.act(forward), original.act(forward))
    }

    private func assertVector(_ a: SIMD3<Float>, _ b: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 0.00001, file: file, line: line)
    }
}

#if os(iOS)
@MainActor
final class TrackingLifecycleTests: XCTestCase {
    private final class Source: HeadMotionSource {
        var isAvailable = true
        var isActive = false
        var sample: HeadMotionSample?
        var starts = 0
        var stops = 0
        func start() { starts += 1; isActive = true }
        func stop() { stops += 1; isActive = false; sample = nil }
    }
    private func sample(yaw: Float, at time: TimeInterval) -> HeadMotionSample {
        let neutral = simd_quatf(ix: -0.5, iy: 0.5, iz: -0.5, r: 0.5)
        return HeadMotionSample(referenceToDevice: simd_quatf(angle: yaw, axis: SIMD3(1, 0, 0)) * neutral,
                                angularVelocity: .zero, timestamp: time)
    }

    func testStopResumeRebasesArbitraryHeadingAndStartIsIdempotent() {
        let source = Source()
        let tracker = HeadTrackingManager(source: source)
        tracker.start(at: 1)
        tracker.start(at: 1)
        XCTAssertEqual(source.starts, 1)
        source.sample = sample(yaw: 0, at: 1.01)
        _ = tracker.orientation(at: 1.02)
        source.sample = sample(yaw: 0.5, at: 1.03)
        let before = tracker.orientation(at: 1.04).act(SIMD3<Float>(0, 0, -1))
        tracker.stop()
        XCTAssertFalse(source.isActive)
        XCTAssertFalse(tracker.isTracking)
        tracker.start(at: 2)
        source.sample = sample(yaw: -0.9, at: 2.01)
        let after = tracker.orientation(at: 2.02).act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(after.x, before.x, accuracy: 0.00001)
        XCTAssertEqual(after.z, before.z, accuracy: 0.00001)
        XCTAssertTrue(tracker.isTracking)
    }

    func testStaleSampleFreezesThenRecoversPhysicalHeading() {
        let source = Source()
        let tracker = HeadTrackingManager(source: source)
        tracker.start(at: 1)
        source.sample = sample(yaw: 0, at: 1.01)
        let initial = tracker.orientation(at: 1.02)
        let stale = tracker.orientation(at: 1.5)
        XCTAssertFalse(tracker.isTracking)
        XCTAssertEqual(abs(simd_dot(initial.vector, stale.vector)), 1, accuracy: 0.00001)
        source.sample = sample(yaw: 0.6, at: 1.51)
        let recovered = tracker.orientation(at: 1.52)
        XCTAssertTrue(tracker.isTracking)
        XCTAssertEqual(recovered.act(SIMD3(0, 0, -1)).x, sin(0.6), accuracy: 0.00001)
    }

    func testInterruptedMotionStreamIsRestartedWithoutBusyLoop() {
        let source = Source()
        let tracker = HeadTrackingManager(source: source)
        tracker.start(at: 1)
        source.isActive = false
        _ = tracker.orientation(at: 1.1)
        XCTAssertEqual(source.starts, 1)
        _ = tracker.orientation(at: 2.1)
        XCTAssertEqual(source.starts, 2)
        source.sample = sample(yaw: 0, at: 2.11)
        _ = tracker.orientation(at: 2.12)
        XCTAssertTrue(tracker.isTracking)
    }

    func testUnavailableSensorAndInvalidQuaternionAreReported() {
        let source = Source()
        source.isAvailable = false
        let tracker = HeadTrackingManager(source: source)
        tracker.start(at: 1)
        XCTAssertEqual(source.starts, 0)
        XCTAssertFalse(tracker.isTracking)
        tracker.stop()
        source.isAvailable = true
        tracker.start(at: 2)
        source.sample = HeadMotionSample(referenceToDevice: simd_quatf(vector: SIMD4(repeating: 0)),
                                         angularVelocity: .zero, timestamp: 2.01)
        _ = tracker.orientation(at: 2.02)
        XCTAssertFalse(tracker.isTracking)
    }
}
#endif
