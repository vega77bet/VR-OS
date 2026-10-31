import XCTest
@testable import VROS

final class CalibrationTests: XCTestCase {
    func testPreferencesRoundTrip() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let manager = VRCalibrationManager(defaults: defaults)
            manager.profile.ipdMeters = 0.071
            manager.profile.leftCenterX = 0.43
            manager.profile.rightCenterX = 0.57
            manager.profile.leftScale = 1.12
            manager.profile.rightScale = 0.92
            manager.profile.distortionStrength = 0.8
            manager.renderScale = 0.65
            let reopened = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(reopened.profile, manager.profile)
            XCTAssertEqual(reopened.renderScale, 0.65, accuracy: 0.0001)
        }
    }

    func testCorruptDataRestoresDefaults() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(Data("{invalid".utf8), forKey: VRCalibrationManager.persistenceKey)
            let manager = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(manager.profile, .genericVRBox)
            XCTAssertEqual(manager.renderScale, VRCalibrationManager.defaultRenderScale)
            XCTAssertNotEqual(defaults.data(forKey: VRCalibrationManager.persistenceKey), Data("{invalid".utf8))
        }
    }

    func testUnknownPersistenceVersionRestoresDefaults() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let encodedProfile = try! JSONEncoder().encode(VRLensProfile.genericVRBox)
            let profileObject = try! JSONSerialization.jsonObject(with: encodedProfile)
            let envelope: [String: Any] = ["version": 99, "profile": profileObject, "renderScale": 0.5]
            defaults.set(try! JSONSerialization.data(withJSONObject: envelope), forKey: VRCalibrationManager.persistenceKey)
            let manager = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(manager.renderScale, VRCalibrationManager.defaultRenderScale)
        }
    }

    func testRuntimeValuesAreClampedAndFinite() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let manager = VRCalibrationManager(defaults: defaults)
            manager.profile.ipdMeters = 2
            manager.profile.leftCenterX = -1
            manager.profile.rightScale = .infinity
            manager.profile.distortionK1 = .nan
            manager.renderScale = .nan
            XCTAssertEqual(manager.profile.ipdMeters, 0.075)
            XCTAssertEqual(manager.profile.leftCenterX, 0.35)
            XCTAssertEqual(manager.profile.rightScale, VRLensProfile.genericVRBox.rightScale)
            XCTAssertEqual(manager.profile.distortionK1, VRLensProfile.genericVRBox.distortionK1)
            XCTAssertEqual(manager.renderScale, VRCalibrationManager.defaultRenderScale)
            XCTAssertNotNil(defaults.data(forKey: VRCalibrationManager.persistenceKey))
            XCTAssertEqual(VRCalibrationManager(defaults: defaults).profile, manager.profile)
        }
    }

    func testStoredOutOfRangeValuesAreValidated() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            var profile = VRLensProfile.genericVRBox
            profile.verticalFOVDegrees = 400
            profile.rightCenterX = 0
            profile.leftScale = 100
            profile.distortionK2 = -1
            let encodedProfile = try! JSONEncoder().encode(profile)
            let profileObject = try! JSONSerialization.jsonObject(with: encodedProfile)
            let envelope: [String: Any] = ["version": 1, "profile": profileObject, "renderScale": 8]
            defaults.set(try! JSONSerialization.data(withJSONObject: envelope), forKey: VRCalibrationManager.persistenceKey)
            let manager = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(manager.profile.verticalFOVDegrees, 110)
            XCTAssertEqual(manager.profile.rightCenterX, 0.35)
            XCTAssertEqual(manager.profile.leftScale, 1.3)
            XCTAssertEqual(manager.profile.distortionK2, 0)
            XCTAssertEqual(manager.renderScale, 1)
        }
    }

    func testResetPersistsAllDefaults() async {
        await MainActor.run {
            let suite = "VRCalibrationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let manager = VRCalibrationManager(defaults: defaults)
            manager.profile.distortionStrength = 1
            manager.renderScale = 0.5
            manager.resetDefaults()
            let reopened = VRCalibrationManager(defaults: defaults)
            XCTAssertEqual(reopened.profile, .genericVRBox)
            XCTAssertEqual(reopened.renderScale, VRCalibrationManager.defaultRenderScale)
        }
    }
}
