import XCTest
@testable import VROSRegressionTests

final class DwellControlTests: XCTestCase {
    func testDwellFiresOnlyAfterHoldingTheSameTarget() {
        let controller = VRDwellController()
        controller.start()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(controller.updateTarget("settings.row.hands.dwell", now: start))
        XCTAssertFalse(controller.updateTarget(
            "settings.row.hands.dwell",
            now: start.addingTimeInterval(0.99)))
        XCTAssertTrue(controller.updateTarget(
            "settings.row.hands.dwell",
            now: start.addingTimeInterval(1.0)))
        XCTAssertFalse(controller.updateTarget(
            "settings.row.hands.dwell",
            now: start.addingTimeInterval(2.0)))

        controller.stop()
    }

    func testMovingToAnotherTargetCancelsThePreviousDwell() {
        let controller = VRDwellController()
        controller.start()
        let start = Date(timeIntervalSince1970: 2_000)

        XCTAssertFalse(controller.updateTarget("taskbar.settings", now: start))
        XCTAssertFalse(controller.updateTarget(
            "taskbar.settings", now: start.addingTimeInterval(0.8)))
        XCTAssertFalse(controller.updateTarget(
            "taskbar.apps", now: start.addingTimeInterval(1.4)))
        XCTAssertTrue(controller.updateTarget(
            "taskbar.apps", now: start.addingTimeInterval(2.4)))

        controller.stop()
    }

    func testDelayCanBeChangedAndIsClamped() {
        let controller = VRDwellController()
        controller.start()
        controller.setDelay(1.5)
        let start = Date(timeIntervalSince1970: 3_000)

        XCTAssertFalse(controller.updateTarget("settings.close", now: start))
        XCTAssertFalse(controller.updateTarget(
            "settings.close", now: start.addingTimeInterval(1.49)))
        XCTAssertTrue(controller.updateTarget(
            "settings.close", now: start.addingTimeInterval(1.5)))

        controller.stop()
    }
}
