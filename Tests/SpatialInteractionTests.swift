import XCTest
import simd
@testable import VROS

final class SpatialInteractionTests: XCTestCase {
    private let identity = simd_quatf(real: 1, imag: .zero)
    private let available = Set(ControllerButton.allCases)

    private var windows: [SpatialWindow] {
        [SpatialWindow(id: "panel", position: SIMD3(0, 1.65, -2), size: SIMD2(2, 1.5),
                       title: "Panel", elements: [
                        SpatialElement(id: "panel.button", windowID: "panel", center: .zero,
                                       size: SIMD2(1, 0.8), title: "Select", action: .open(.cinema))
                       ])]
    }

    private func controller(_ buttons: Set<ControllerButton> = [], id: String = "controller-1") -> ControllerInputFrame {
        ControllerInputFrame(connected: true, controllerID: id, name: "Simulated controller", buttons: buttons)
    }

    @discardableResult
    private func step(_ system: inout SpatialInteractionSystem, at time: Double,
                      frame: ControllerInputFrame = .disconnected,
                      configuration: InteractionConfiguration = InteractionConfiguration(),
                      head: simd_quatf? = nil, left: Bool = false, right: Bool = false,
                      buttons: Set<ControllerButton>? = nil) -> InteractionUpdate {
        system.update(frame: frame, available: buttons ?? available,
                      hasLeftStick: left, hasRightStick: right, configuration: configuration,
                      headPose: head ?? identity, windows: windows, at: time)
    }

    func testHeadDwellRequiresFullDurationAndShowsProgress() {
        var system = SpatialInteractionSystem()
        XCTAssertNil(step(&system, at: 0).activation)
        let almost = step(&system, at: 0.99)
        XCTAssertEqual(almost.progress, 0.99, accuracy: 0.0001)
        XCTAssertNil(almost.activation)
        let selected = step(&system, at: 1)
        XCTAssertEqual(selected.activation?.elementID, "panel.button")
        XCTAssertEqual(selected.selectionPulse, 1, accuracy: 0.0001)
    }

    func testHeadDwellLatchesUntilGazeLeavesTarget() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0)
        XCTAssertNotNil(step(&system, at: 1).activation)
        XCTAssertNil(step(&system, at: 3).activation)
        XCTAssertEqual(step(&system, at: 4).progress, 0)
        let away = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        XCTAssertNil(step(&system, at: 4.1, head: away).hit)
        step(&system, at: 4.2)
        XCTAssertNil(step(&system, at: 5.19).activation)
        XCTAssertNotNil(step(&system, at: 5.21).activation)
    }

    func testLeavingBeforeDwellCompletionCancelsAccumulatedTime() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0)
        XCTAssertGreaterThan(step(&system, at: 0.7).progress, 0.6)
        let away = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(step(&system, at: 0.8, head: away).progress, 0)
        step(&system, at: 0.9)
        XCTAssertNil(step(&system, at: 1.8).activation)
        XCTAssertNotNil(step(&system, at: 1.91).activation)
    }

    func testControllerSourceNeverAlsoExecutesGazeDwell() {
        var system = SpatialInteractionSystem()
        let frame = controller()
        step(&system, at: 0, frame: frame)
        let idle = step(&system, at: 5, frame: frame)
        XCTAssertEqual(idle.source, .controller)
        XCTAssertNotNil(idle.hit)
        XCTAssertNil(idle.activation)
        XCTAssertEqual(idle.progress, 0)
    }

    func testSelectAliasesProduceOneEdgeAndDoNotRetriggerWhileEitherIsHeld() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        let selected = step(&system, at: 0.1, frame: controller([.a, .rightTrigger]))
        XCTAssertNotNil(selected.activation)
        XCTAssertFalse(selected.commands.contains(.select))
        XCTAssertNil(step(&system, at: 0.2, frame: controller([.a, .rightTrigger])).activation)
        XCTAssertNil(step(&system, at: 0.3, frame: controller([.rightTrigger])).activation)
        step(&system, at: 0.4, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.5, frame: controller([.rightTrigger])).activation)
    }

    func testExplicitHeadModeIgnoresControllerButtonsAndUsesDwell() {
        var system = SpatialInteractionSystem()
        var configuration = InteractionConfiguration()
        configuration.inputMode = .head
        step(&system, at: 0, frame: controller(), configuration: configuration)
        let pressed = step(&system, at: 0.1, frame: controller([.a, .x]), configuration: configuration)
        XCTAssertEqual(pressed.source, .head)
        XCTAssertNil(pressed.activation)
        XCTAssertTrue(pressed.commands.isEmpty)
        XCTAssertNotNil(step(&system, at: 1, frame: controller([.a]), configuration: configuration).activation)
    }

    func testHeldButtonOnConnectionMustBeReleasedBeforeSelecting() {
        var system = SpatialInteractionSystem()
        XCTAssertNil(step(&system, at: 0, frame: controller([.a])).activation)
        XCTAssertNil(step(&system, at: 2, frame: controller([.a])).activation)
        step(&system, at: 2.1, frame: controller())
        XCTAssertNotNil(step(&system, at: 2.2, frame: controller([.a])).activation)
    }

    func testSwitchingActiveControllerDoesNotInheritHeldSelection() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.1, frame: controller([.a])).activation)
        XCTAssertNil(step(&system, at: 0.2, frame: controller([.a], id: "controller-2")).activation)
        XCTAssertNil(step(&system, at: 1.2, frame: controller([.a], id: "controller-2")).activation)
        step(&system, at: 1.3, frame: controller(id: "controller-2"))
        XCTAssertNotNil(step(&system, at: 1.4, frame: controller([.a], id: "controller-2")).activation)
    }

    func testDisconnectFallsBackToHeadWithFreshDwellTimer() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        let disconnected = step(&system, at: 5)
        XCTAssertEqual(disconnected.source, .head)
        XCTAssertEqual(disconnected.progress, 0)
        XCTAssertNil(disconnected.activation)
        XCTAssertNil(step(&system, at: 5.9).activation)
        XCTAssertNotNil(step(&system, at: 6.01).activation)
    }

    func testModeSwitchResetsDwellAndQuarantinesHeldControllerButton() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.1, frame: controller([.a])).activation)
        var head = InteractionConfiguration()
        head.inputMode = .head
        XCTAssertNil(step(&system, at: 0.2, frame: controller([.a]), configuration: head).activation)
        XCTAssertNil(step(&system, at: 1.19, frame: controller([.a]), configuration: head).activation)
        XCTAssertNotNil(step(&system, at: 1.21, frame: controller([.a]), configuration: head).activation)
        XCTAssertNil(step(&system, at: 1.3, frame: controller([.a])).activation)
        step(&system, at: 1.4, frame: controller())
        XCTAssertNotNil(step(&system, at: 1.5, frame: controller([.a])).activation)
    }

    func testEmptySpaceDoesNotExecuteSelectionOrDwell() {
        var system = SpatialInteractionSystem()
        let away = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        step(&system, at: 0, frame: controller(), head: away)
        let selected = step(&system, at: 0.1, frame: controller([.a]), head: away)
        XCTAssertNil(selected.hit)
        XCTAssertNil(selected.activation)
        XCTAssertTrue(selected.commands.isEmpty)
        step(&system, at: 1, head: away)
        XCTAssertNil(step(&system, at: 10, head: away).activation)
    }

    func testGrabStartsWithoutJumpMovesAndReleasesWithoutSelecting() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        let grabbed = step(&system, at: 0.1, frame: controller([.leftTrigger, .rightTrigger]))
        XCTAssertEqual(grabbed.grabbedWindowID, "panel")
        XCTAssertNotNil(grabbed.drag)
        XCTAssertEqual(simd_distance(grabbed.drag!.position, windows[0].position), 0, accuracy: 0.00001)
        XCTAssertNil(grabbed.activation)
        let turned = simd_quatf(angle: 0.15, axis: SIMD3<Float>(0, 1, 0))
        let moved = step(&system, at: 0.2, frame: controller([.leftTrigger, .rightTrigger]), head: turned)
        XCTAssertGreaterThan(simd_distance(moved.drag!.position, grabbed.drag!.position), 0.1)
        XCTAssertNil(moved.activation)
        let released = step(&system, at: 0.3, frame: controller([.rightTrigger]), head: turned)
        XCTAssertNil(released.drag)
        XCTAssertNil(released.grabbedWindowID)
        XCTAssertNil(released.activation)
    }

    func testDisconnectAlwaysReleasesGrabAndStartsHeadDwellFromZero() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.1, frame: controller([.leftTrigger])).drag)
        let disconnected = step(&system, at: 0.2)
        XCTAssertEqual(disconnected.source, .head)
        XCTAssertNil(disconnected.drag)
        XCTAssertNil(disconnected.grabbedWindowID)
        XCTAssertNil(disconnected.activation)
        XCTAssertEqual(disconnected.progress, 0)
    }

    func testAnalogDeadzoneAndReleasedStickKeepPointerStable() {
        var system = SpatialInteractionSystem()
        let initial = step(&system, at: 0, frame: controller(), right: true)
        var drift = controller()
        drift.rightStick = SIMD2(0.1, 0.05)
        let deadzone = step(&system, at: 0.02, frame: drift, right: true)
        XCTAssertEqual(simd_distance(initial.ray.direction, deadzone.ray.direction), 0, accuracy: 0.000001)
        var pointing = controller()
        pointing.rightStick = SIMD2(1, 0)
        let moved = step(&system, at: 0.1, frame: pointing, right: true)
        XCTAssertGreaterThan(moved.ray.direction.x, initial.ray.direction.x)
        let stopped = step(&system, at: 0.2, frame: controller(), right: true)
        let later = step(&system, at: 2, frame: controller(), right: true)
        XCTAssertEqual(simd_distance(stopped.ray.direction, moved.ray.direction), 0, accuracy: 0.000001)
        XCTAssertEqual(simd_distance(later.ray.direction, moved.ray.direction), 0, accuracy: 0.000001)
    }

    func testAnalogIntegrationCapsDeltaTimeAcrossLongFrames() {
        var longFrame = SpatialInteractionSystem()
        var shortFrame = SpatialInteractionSystem()
        step(&longFrame, at: 0, frame: controller(), right: true)
        step(&shortFrame, at: 0, frame: controller(), right: true)
        var held = controller()
        held.rightStick = SIMD2(1, 0)
        let long = step(&longFrame, at: 100, frame: held, right: true)
        let short = step(&shortFrame, at: 0.05, frame: held, right: true)
        XCTAssertEqual(simd_distance(long.ray.direction, short.ray.direction), 0, accuracy: 0.000001)
        XCTAssertLessThan(abs(long.ray.direction.x), 0.06)
    }

    func testMotionUsesRelativeOrientationAndRecenterWithoutTrackingPosition() {
        var system = SpatialInteractionSystem()
        var configuration = InteractionConfiguration()
        configuration.pointerMode = .motion
        let neutral = simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0))
        var frame = controller()
        frame.motionOrientation = neutral
        let initial = step(&system, at: 0, frame: frame, configuration: configuration)
        let changed = neutral * simd_quatf(angle: 0.3, axis: SIMD3<Float>(1, 0, 0))
        frame.motionOrientation = changed
        let moved = step(&system, at: 0.05, frame: frame, configuration: configuration)
        XCTAssertGreaterThan(moved.ray.direction.y, initial.ray.direction.y + 0.1)
        XCTAssertEqual(simd_distance(moved.ray.origin, initial.ray.origin), 0, accuracy: 0.000001)
        system.recenterAim(headPose: identity, motion: changed)
        let recentered = step(&system, at: 0.1, frame: frame, configuration: configuration)
        XCTAssertEqual(simd_distance(recentered.ray.direction, initial.ray.direction), 0, accuracy: 0.00001)
        XCTAssertEqual(simd_distance(recentered.ray.origin, initial.ray.origin), 0, accuracy: 0.000001)
    }

    func testMissingMotionFallsBackToExposedAnalogOrHeadWithButtons() {
        var configuration = InteractionConfiguration()
        configuration.pointerMode = .motion
        var analog = SpatialInteractionSystem()
        step(&analog, at: 0, frame: controller(), configuration: configuration, right: true)
        var movedFrame = controller()
        movedFrame.rightStick = SIMD2(1, 0)
        let fallback = step(&analog, at: 0.05, frame: movedFrame, configuration: configuration, right: true)
        XCTAssertTrue(fallback.pointerDescription.contains("indisponível"))
        XCTAssertGreaterThan(fallback.ray.direction.x, 0)
        var buttonsOnly = SpatialInteractionSystem()
        let headFallback = step(&buttonsOnly, at: 0, frame: controller(), configuration: configuration)
        XCTAssertEqual(headFallback.pointerDescription, "Mira da cabeça + botões")
        XCTAssertEqual(simd_distance(headFallback.ray.direction, SIMD3(0, 0, -1)), 0, accuracy: 0.000001)
    }

    func testOnlyExposedSelectionFallbackExecutesWithoutInventingOtherActions() {
        var system = SpatialInteractionSystem()
        let available: Set<ControllerButton> = [.x]
        step(&system, at: 0, frame: controller(), buttons: available)
        let selected = step(&system, at: 0.1, frame: controller([.x, .y, .rightTrigger]), buttons: available)
        XCTAssertNotNil(selected.activation)
        XCTAssertTrue(selected.commands.isEmpty)
    }

    func testSingleStickPointsWhileDualStickScrollHasControlledRepeat() {
        var singleStick = SpatialInteractionSystem()
        step(&singleStick, at: 0, frame: controller(), left: true)
        var up = controller()
        up.leftStick = SIMD2(0, 1)
        XCTAssertEqual(step(&singleStick, at: 0.4, frame: up, left: true).scroll, 0)
        var dualStick = SpatialInteractionSystem()
        step(&dualStick, at: 0, frame: controller(), left: true, right: true)
        var down = controller()
        down.leftStick = SIMD2(0, -1)
        XCTAssertEqual(step(&dualStick, at: 0.35, frame: down, left: true, right: true).scroll, 1)
        XCTAssertEqual(step(&dualStick, at: 0.4, frame: down, left: true, right: true).scroll, 0)
        XCTAssertEqual(step(&dualStick, at: 0.7, frame: down, left: true, right: true).scroll, 1)
    }

    func testControllerWithoutSelectableInputsFallsBackToHeadInBothModes() {
        for mode in [InteractionInputMode.automatic, .controller] {
            var system = SpatialInteractionSystem()
            var configuration = InteractionConfiguration()
            configuration.inputMode = mode
            let initial = step(&system, at: 0, frame: controller(), configuration: configuration, buttons: [])
            XCTAssertEqual(initial.source, .head)
            XCTAssertNil(initial.activation)
            let selected = step(&system, at: 1, frame: controller(), configuration: configuration, buttons: [])
            XCTAssertEqual(selected.activation?.elementID, "panel.button")
        }
    }

    func testDpadSelectionFallbackDoesNotAlsoScroll() {
        var system = SpatialInteractionSystem()
        let onlyDpad: Set<ControllerButton> = [.dpadDown]
        step(&system, at: 0, frame: controller(), buttons: onlyDpad)
        let selected = step(&system, at: 0.35, frame: controller([.dpadDown]), buttons: onlyDpad)
        XCTAssertNotNil(selected.activation)
        XCTAssertEqual(selected.scroll, 0)
        XCTAssertTrue(selected.commands.isEmpty)
    }

    func testExplicitDpadMappingWinsOverImplicitScrolling() {
        var system = SpatialInteractionSystem()
        var configuration = InteractionConfiguration()
        configuration.mapping = ControllerMapping(bindings: [.a: .select, .dpadDown: .back])
        step(&system, at: 0, frame: controller(), configuration: configuration)
        let back = step(&system, at: 0.35, frame: controller([.dpadDown]), configuration: configuration)
        XCTAssertEqual(back.commands, [.back])
        XCTAssertNil(back.activation)
        XCTAssertEqual(back.scroll, 0)
    }

    func testInvalidMotionNeutralCanRecoverFromLaterValidAttitude() {
        var system = SpatialInteractionSystem()
        var configuration = InteractionConfiguration()
        configuration.pointerMode = .motion
        var frame = controller()
        frame.motionOrientation = simd_quatf(vector: .zero)
        step(&system, at: 0, frame: frame, configuration: configuration)
        frame.motionOrientation = identity
        let recovered = step(&system, at: 0.05, frame: frame, configuration: configuration)
        XCTAssertTrue(recovered.ray.direction.x.isFinite)
        XCTAssertTrue(recovered.ray.direction.y.isFinite)
        XCTAssertTrue(recovered.ray.direction.z.isFinite)
        XCTAssertEqual(simd_length(recovered.ray.direction), 1, accuracy: 0.00001)
        frame.motionOrientation = simd_quatf(angle: 0.3, axis: SIMD3<Float>(1, 0, 0))
        let moved = step(&system, at: 0.1, frame: frame, configuration: configuration)
        XCTAssertGreaterThan(moved.ray.direction.y, recovered.ray.direction.y + 0.1)
        system.recenterAim(headPose: identity, motion: simd_quatf(vector: .zero))
        let recalibrated = step(&system, at: 0.15, frame: frame, configuration: configuration)
        XCTAssertEqual(simd_distance(recalibrated.ray.direction, recovered.ray.direction), 0, accuracy: 0.00001)
    }

    func testRecenterAimPreservesCompletedHeadDwellLatch() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0)
        XCTAssertNotNil(step(&system, at: 1).activation)
        system.recenterAim(headPose: identity, motion: nil)
        XCTAssertNil(step(&system, at: 2).activation)
        XCTAssertNil(step(&system, at: 5).activation)
    }

    func testChangingControllerPointerPreferenceCannotRetriggerHeadDwell() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0)
        var configuration = InteractionConfiguration()
        configuration.pointerMode = .motion
        let partial = step(&system, at: 0.7, configuration: configuration)
        XCTAssertEqual(partial.progress, 0.7, accuracy: 0.0001)
        XCTAssertNotNil(step(&system, at: 1, configuration: configuration).activation)
        configuration.pointerMode = .analog
        XCTAssertNil(step(&system, at: 2.1, configuration: configuration).activation)
        configuration.pointerMode = .motion
        XCTAssertNil(step(&system, at: 4, configuration: configuration).activation)
    }

    func testNavigationCancelsGrabAndHeldGrabCannotMoveClosedOrReplacementWindow() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.1, frame: controller([.leftTrigger])).drag)
        let navigation = step(&system, at: 0.2, frame: controller([.leftTrigger, .b]))
        XCTAssertEqual(navigation.commands, [.back])
        XCTAssertNil(navigation.drag)
        XCTAssertNil(navigation.grabbedWindowID)
        XCTAssertNil(navigation.activation)

        // The coordinator closes a panel in response to Back. The interaction
        // system must not keep emitting moves for its previous captured ID.
        let closed = system.update(frame: controller([.leftTrigger]), available: available,
                                   hasLeftStick: false, hasRightStick: false,
                                   configuration: InteractionConfiguration(), headPose: identity,
                                   windows: [], at: 0.3)
        XCTAssertNil(closed.drag)
        XCTAssertNil(closed.grabbedWindowID)
        // Reopening a surface under the held ray also requires a new grab edge.
        XCTAssertNil(step(&system, at: 0.4, frame: controller([.leftTrigger])).drag)
        step(&system, at: 0.5, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.6, frame: controller([.leftTrigger])).drag)
    }

    func testBackAndSelectOnSameFrameNavigateWithoutActivatingPointedButton() {
        var system = SpatialInteractionSystem()
        step(&system, at: 0, frame: controller())
        let navigation = step(&system, at: 0.1, frame: controller([.a, .b]))
        XCTAssertEqual(navigation.commands, [.back])
        XCTAssertNil(navigation.activation)
        XCTAssertNil(navigation.drag)
        XCTAssertNil(step(&system, at: 0.2, frame: controller([.a])).activation)
        step(&system, at: 0.3, frame: controller())
        XCTAssertNotNil(step(&system, at: 0.4, frame: controller([.a])).activation)
    }
}
