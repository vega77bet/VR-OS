import XCTest
import simd
@testable import VROS

final class StereoTests: XCTestCase {
    private let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    func testEyeSeparationRotatesWithHeadAndKeepsIPD() {
        for pose in [identity,
                     simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0)),
                     simd_quatf(angle: .pi / 3, axis: normalize(SIMD3<Float>(1, 2, 3)))] {
            let left = StereoCamera.eyePosition(.left, orientation: pose, ipdMeters: 0.064)
            let right = StereoCamera.eyePosition(.right, orientation: pose, ipdMeters: 0.064)
            XCTAssertEqual(simd_length(right - left), 0.064, accuracy: 0.000001)
            XCTAssertEqual(simd_length((left + right) * 0.5 - StereoCamera.headPosition), 0, accuracy: 0.000001)
            XCTAssertGreaterThan(simd_dot(right - left, pose.act(SIMD3(1, 0, 0))), 0)
        }
    }

    func testCameraViewInvertsTheCorrectEyeWorldTransform() {
        let pose = simd_quatf(angle: 0.8, axis: normalize(SIMD3<Float>(1, 3, 2)))
        for eye in StereoCamera.Eye.allCases {
            let origin = StereoCamera.eyePosition(eye, orientation: pose, ipdMeters: 0.067)
            let view = StereoCamera.viewMatrix(eye, orientation: pose, ipdMeters: 0.067)
            let cameraOrigin = view * SIMD4(origin.x, origin.y, origin.z, 1)
            XCTAssertEqual(simd_length(cameraOrigin - SIMD4(0, 0, 0, 1)), 0, accuracy: 0.00001)
            let forward = origin + pose.act(SIMD3(0, 0, -1))
            let inCamera = view * SIMD4(forward.x, forward.y, forward.z, 1)
            XCTAssertEqual(inCamera.z, -1, accuracy: 0.00001)
            XCTAssertEqual(inCamera.x, 0, accuracy: 0.00001)
        }
    }

    func testRealBinocularDisparityHasCorrectSignAndDepthDependence() {
        let projection = StereoCamera.projection(verticalFOVDegrees: 90, aspect: 1.08, centerX: 0.5)
        func projectedX(_ eye: StereoCamera.Eye, depth: Float) -> Float {
            let camera = projection * StereoCamera.viewMatrix(eye, orientation: identity, ipdMeters: 0.064)
            let clip = camera * SIMD4(0, 1.65, -depth, 1)
            return clip.x / clip.w
        }
        // A central near object appears right of center to the left eye, left to the right eye.
        let nearLeft = projectedX(.left, depth: 1)
        let nearRight = projectedX(.right, depth: 1)
        XCTAssertGreaterThan(nearLeft, 0)
        XCTAssertLessThan(nearRight, 0)
        XCTAssertEqual(nearLeft, -nearRight, accuracy: 0.000001)
        let farDisparity = projectedX(.left, depth: 4) - projectedX(.right, depth: 4)
        XCTAssertEqual(nearLeft - nearRight, farDisparity * 4, accuracy: 0.000001)
    }

    func testMetalProjectionMapsNearFarAndOpticalPrincipalPoint() {
        let projection = StereoCamera.projection(verticalFOVDegrees: 90, aspect: 1.08, centerX: 0.57)
        let depthSamples: [(Float, Float)] = [(0.05, 0), (80, 1)]
        for (depth, expectedZ) in depthSamples {
            let clip = projection * SIMD4(0, 0, -depth, 1)
            XCTAssertEqual(clip.z / clip.w, expectedZ, accuracy: 0.00001)
            XCTAssertEqual(clip.x / clip.w, 0.14, accuracy: 0.00001)
        }
    }

    func testPhysicalEyeHalvesNeverSwapAndCoverOddWidthWithoutGap() {
        let left = StereoCamera.horizontalRange(.left, drawableWidth: 2557)
        let right = StereoCamera.horizontalRange(.right, drawableWidth: 2557)
        XCTAssertEqual(left.lowerBound, 0)
        XCTAssertEqual(left.upperBound, right.lowerBound)
        XCTAssertEqual(right.upperBound, 2557)
        XCTAssertEqual(left.count + right.count, 2557)
    }

    func testSceneContainsRealThreeDimensionalGeometry() {
        let vertices = VRTestScene.vertices()
        XCTAssertGreaterThan(vertices.count, 1000)
        XCTAssertEqual(vertices.count % 3, 0)
        let positions = vertices.map(\.position)
        XCTAssertLessThan(positions.map(\.x).min()!, -2)
        XCTAssertGreaterThan(positions.map(\.x).max()!, 2)
        XCTAssertLessThan(positions.map(\.z).min()!, -4)
        XCTAssertGreaterThan(positions.map(\.y).max()!, 2)
        XCTAssertEqual(MemoryLayout<SceneVertex>.stride, 32)
    }
}
