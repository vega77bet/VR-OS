import XCTest
@testable import VROS

final class VisionCalibrationTests: XCTestCase {
    func testNeutralMappingIsIdentity() {
        let eye = EyeCalibration.neutral
        let sample = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.27, 0.73),
                                                    aspect: 1.4, eye: eye)
        XCTAssertTrue(sample.valid)
        XCTAssertEqual(sample.uv.x, 0.27, accuracy: 0.00001)
        XCTAssertEqual(sample.uv.y, 0.73, accuracy: 0.00001)
    }

    func testOffsetsUseInverseDestinationMapping() {
        var eye = EyeCalibration.neutral
        eye.horizontalOffset = 0.02
        eye.verticalOffset = -0.03
        let sample = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.5, 0.5),
                                                    aspect: 1, eye: eye)
        XCTAssertEqual(sample.uv.x, 0.48, accuracy: 0.00001)
        XCTAssertEqual(sample.uv.y, 0.53, accuracy: 0.00001)
    }

    func testScaleAndRotationAreIndependent() {
        var scaled = EyeCalibration.neutral
        scaled.horizontalScale = 1.1
        let scaledSample = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.6, 0.5),
                                                          aspect: 1, eye: scaled)
        XCTAssertEqual(scaledSample.uv.x, 0.5909091, accuracy: 0.0001)

        var rotated = EyeCalibration.neutral
        rotated.rotationDegrees = 2
        let rotatedSample = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.6, 0.5),
                                                           aspect: 1, eye: rotated)
        XCTAssertEqual(rotatedSample.uv.x, 0.5999391, accuracy: 0.0001)
        XCTAssertEqual(rotatedSample.uv.y, 0.4982550, accuracy: 0.0001)
    }

    func testOpticalCenterAndChromaticChannelMapping() {
        var eye = EyeCalibration.neutral
        eye.opticalCenterX = 0.6
        let centered = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.6, 0.5),
                                                      aspect: 1, eye: eye)
        XCTAssertEqual(centered.uv.x, 0.6, accuracy: 0.00001)

        let red = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.75, 0.5),
                                                 aspect: 1, eye: eye, channelScale: 1.01)
        let blue = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.75, 0.5),
                                                  aspect: 1, eye: eye, channelScale: 0.99)
        XCTAssertGreaterThan(red.uv.x, blue.uv.x)
    }

    func testRadialAndTangentialSignsArePreserved() {
        var positive = EyeCalibration.neutral
        positive.distortionStrength = 1
        positive.radialK1 = 0.1
        let outward = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.75, 0.5),
                                                     aspect: 1, eye: positive)
        XCTAssertGreaterThan(outward.uv.x, 0.75)

        positive.radialK1 = -0.1
        let inward = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.75, 0.5),
                                                    aspect: 1, eye: positive)
        XCTAssertLessThan(inward.uv.x, 0.75)

        positive.radialK1 = 0
        positive.tangentialP1 = 0.02
        let tangential = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.75, 0.55),
                                                        aspect: 1, eye: positive)
        XCTAssertGreaterThan(abs(tangential.uv.y - 0.55), 0.00001)
    }

    func testInvalidValuesAreSafeAndClamped() {
        var eye = EyeCalibration.neutral
        eye.horizontalScale = 0
        eye.verticalScale = .infinity
        eye.opticalCenterX = .nan
        eye.radialK1 = .infinity
        let sample = VisionCalibrationMath.sourceUV(destinationUV: SIMD2(0.5, 0.5),
                                                    aspect: .nan, eye: eye)
        XCTAssertTrue(sample.uv.x.isFinite)
        XCTAssertTrue(sample.uv.y.isFinite)
        XCTAssertTrue(EyeCalibration(horizontalOffset: .infinity, verticalOffset: .nan,
                                     horizontalScale: 0, verticalScale: .infinity,
                                     rotationDegrees: .nan, opticalCenterX: .nan,
                                     opticalCenterY: .infinity, radialK1: .infinity,
                                     radialK2: -.infinity, radialK3: .nan,
                                     tangentialP1: .nan, tangentialP2: .infinity,
                                     chromaticRedScale: 0, chromaticBlueScale: .infinity,
                                     distortionStrength: .nan).validated().horizontalScale > 0)
    }

    func testLegacyProfileKeysMigrateToIndependentEyes() throws {
        let object: [String: Any] = [
            "id": "legacy", "name": "Legacy", "schemaVersion": 1,
            "ipdMeters": 0.064, "verticalFOVDegrees": 90,
            "leftCenterX": 0.43, "rightCenterX": 0.57,
            "leftScale": 1.08, "rightScale": 0.92,
            "distortionK1": 0.22, "distortionK2": 0.03,
            "distortionStrength": 0.4
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let profile = try JSONDecoder().decode(VRLensProfile.self, from: data)
        XCTAssertEqual(profile.leftProjectionCenterX, 0.43, accuracy: 0.0001)
        XCTAssertEqual(profile.rightProjectionCenterX, 0.57, accuracy: 0.0001)
        XCTAssertEqual(profile.leftEye.horizontalScale, 1.08, accuracy: 0.0001)
        XCTAssertEqual(profile.rightEye.verticalScale, 0.92, accuracy: 0.0001)
        XCTAssertEqual(profile.distortionK1, 0.22, accuracy: 0.0001)
    }

    func testSessionPreviewCancelCommitAndUndo() async {
        await MainActor.run {
            let suite = "VisionCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let manager = VRCalibrationManager(defaults: defaults)
            let original = manager.profile
            let session = VisionCalibrationSession(manager: manager)
            session.adjust(.horizontalOffset, delta: 0.02)
            XCTAssertGreaterThan(abs(manager.profile.leftEye.horizontalOffset - original.leftEye.horizontalOffset), 0.0001)
            XCTAssertTrue(session.canUndo)
            session.undo()
            XCTAssertEqual(manager.profile, original)
            session.adjust(.horizontalOffset, delta: 0.01)
            session.save()
            let reopened = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(reopened.profile.leftEye.horizontalOffset, 0.01, accuracy: 0.0001)
            let cancelled = VisionCalibrationSession(manager: reopened)
            cancelled.adjust(.verticalOffset, delta: 0.02)
            cancelled.cancel()
            XCTAssertEqual(reopened.profile.rightEye.verticalOffset, 0, accuracy: 0.0001)
        }
    }

    func testProfilesKeepRecoveryEntry() async {
        await MainActor.run {
            let suite = "VisionCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let manager = VRCalibrationManager(defaults: defaults)
            let id = manager.createProfile(name: "Teste")
            XCTAssertTrue(manager.profiles.contains { $0.id == id })
            manager.selectProfile(id: id)
            manager.deleteProfile(id: VRLensProfile.genericVRBox.id)
            XCTAssertTrue(manager.profiles.contains { $0.id == VRLensProfile.genericVRBox.id })
            manager.resetDefaults()
            XCTAssertEqual(manager.profile, .genericVRBox)
        }
    }
}
