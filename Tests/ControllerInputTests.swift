import XCTest
import simd
@testable import VROS

final class ControllerInputTests: XCTestCase {
    private func descriptor(_ id: String, buttons: Set<ControllerButton> = [.a, .rightTrigger, .b],
                            left: Bool = true, right: Bool = true, motion: Bool = false) -> ControllerDescriptor {
        ControllerDescriptor(id: id, name: "Controle \(id)", availableButtons: buttons,
                             hasLeftStick: left, hasRightStick: right, hasMotion: motion, batteryLevel: nil)
    }

    func testConnectionAndDisconnectionClearTheActiveSource() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("left"))
        XCTAssertEqual(registry.activeID, "left")
        XCTAssertEqual(registry.devices.count, 1)
        registry.disconnect(id: "left")
        XCTAssertNil(registry.activeID)
        let stale = registry.filteredFrame(ControllerInputFrame(connected: true, controllerID: "left", buttons: [.a]))
        XCTAssertFalse(stale.connected)
        XCTAssertTrue(stale.buttons.isEmpty)
        XCTAssertEqual(stale.leftStick, .zero)
    }

    func testActiveDisconnectSelectsAnotherConnectedController() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("one")); registry.connect(descriptor("two"))
        registry.disconnect(id: "one")
        XCTAssertEqual(registry.activeID, "two")
        XCTAssertEqual(registry.devices.map(\.id), ["two"])
    }

    func testSwitchDoesNotFireAButtonAlreadyHeldOnTheNewController() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("one")); registry.connect(descriptor("two"))
        _ = registry.filteredFrame(ControllerInputFrame(connected: true, controllerID: "one"))
        registry.select(id: "two")
        var frame = ControllerInputFrame(connected: true, controllerID: "two", buttons: [.a])
        XCTAssertTrue(registry.filteredFrame(frame).buttons.isEmpty)
        XCTAssertTrue(registry.filteredFrame(frame).buttons.isEmpty)
        frame.buttons = []
        XCTAssertTrue(registry.filteredFrame(frame).buttons.isEmpty)
        frame.buttons = [.a]
        XCTAssertEqual(registry.filteredFrame(frame).buttons, [.a])
        registry.select(id: "missing")
        XCTAssertEqual(registry.activeID, "two")
    }

    func testUnavailableButtonsAxesAndMotionNeverLeakIntoTheFrame() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("micro", buttons: [.a], left: false, right: false))
        var frame = ControllerInputFrame(connected: true, controllerID: "micro")
        _ = registry.filteredFrame(frame)
        frame.buttons = [.a, .rightTrigger, .y]
        frame.leftStick = SIMD2(0.5, 0.9)
        frame.rightStick = SIMD2(-0.8, 0.2)
        frame.motionOrientation = simd_quatf(real: 1, imag: .zero)
        let actual = registry.filteredFrame(frame)
        XCTAssertEqual(actual.buttons, [.a])
        XCTAssertEqual(actual.leftStick, .zero)
        XCTAssertEqual(actual.rightStick, .zero)
        XCTAssertNil(actual.motionOrientation)
    }

    func testAvailableAxesRejectNonfiniteValuesAndClampBounds() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("pad"))
        _ = registry.filteredFrame(ControllerInputFrame(connected: true, controllerID: "pad"))
        let actual = registry.filteredFrame(ControllerInputFrame(
            connected: true, controllerID: "pad", leftStick: SIMD2(.nan, 4), rightStick: SIMD2(-5, .infinity)))
        XCTAssertEqual(actual.leftStick, SIMD2(0, 1))
        XCTAssertEqual(actual.rightStick, SIMD2(-1, 0))
    }

    func testMappingsDeduplicateAliasesAndFilterUnsupportedButtons() {
        let mapping = ControllerMapping.defaults
        let available: Set<ControllerButton> = [.a, .rightTrigger, .b]
        XCTAssertEqual(mapping.actions(for: [.a, .rightTrigger, .y], available: available), [.select])
        XCTAssertEqual(mapping.actions(for: [.b], available: available), [.back])
    }

    func testProfileCapabilityChangeRequiresReleaseBeforeNewSelection() {
        var registry = ControllerRegistry()
        registry.connect(descriptor("pad", buttons: [.a]))
        _ = registry.filteredFrame(ControllerInputFrame(connected: true, controllerID: "pad"))
        registry.connect(descriptor("pad", buttons: [.a, .rightTrigger]))
        var frame = ControllerInputFrame(connected: true, controllerID: "pad", buttons: [.rightTrigger])
        XCTAssertTrue(registry.filteredFrame(frame).buttons.isEmpty)
        frame.buttons = []
        _ = registry.filteredFrame(frame)
        frame.buttons = [.rightTrigger]
        XCTAssertEqual(registry.filteredFrame(frame).buttons, [.rightTrigger])
    }

    func testControllersWithoutZRReceiveAnAvailableSelectionFallback() {
        let effective = ControllerMapping.defaults.effectiveBindings(available: [.leftShoulder])
        XCTAssertEqual(effective, [.leftShoulder: .select])
        XCTAssertTrue(ControllerMapping.defaults.effectiveBindings(available: []).isEmpty)
    }

    func testCustomBindingsTakeEffectWithoutInventingUnavailableInputs() {
        let mapping = ControllerMapping(bindings: [.leftShoulder: .select, .a: .grab, .rightTrigger: .home])
        let effective = mapping.effectiveBindings(available: [.leftShoulder, .a])
        XCTAssertEqual(effective[.leftShoulder], .select)
        XCTAssertEqual(effective[.a], .grab)
        XCTAssertNil(effective[.rightTrigger])
    }

    func testPreferenceRoundTripIncludesMappingAndMotionCalibration() async {
        await MainActor.run {
            let name = "InteractionTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let preferences = InteractionPreferences(defaults: defaults)
            preferences.inputMode = .head; preferences.pointerMode = .motion
            preferences.motionInvertX = true; preferences.motionInvertY = true; preferences.motionSwapAxes = true
            preferences.dwellDuration = 1.4; preferences.sensitivity = 1.2; preferences.panelDistance = 2.8
            preferences.mapping = ControllerMapping(bindings: [.leftShoulder: .select, .rightShoulder: .grab])
            let reopened = InteractionPreferences(defaults: defaults)
            XCTAssertEqual(reopened.inputMode, .head)
            XCTAssertEqual(reopened.pointerMode, .motion)
            XCTAssertTrue(reopened.motionInvertX && reopened.motionInvertY && reopened.motionSwapAxes)
            XCTAssertEqual(reopened.dwellDuration, 1.4)
            XCTAssertEqual(reopened.sensitivity, 1.2)
            XCTAssertEqual(reopened.panelDistance, 2.8)
            XCTAssertEqual(reopened.mapping, preferences.mapping)
        }
    }

    func testPreferencesClampInvalidInputsAndRestoreDefaults() async {
        await MainActor.run {
            let name = "InteractionTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let preferences = InteractionPreferences(defaults: defaults)
            preferences.sensitivity = .nan; preferences.dwellDuration = .infinity; preferences.panelDistance = -10
            XCTAssertEqual(preferences.sensitivity, 0.9)
            XCTAssertEqual(preferences.dwellDuration, 1)
            XCTAssertEqual(preferences.panelDistance, 1.6)
            preferences.motionInvertX = true; preferences.inputMode = .controller
            preferences.resetDefaults()
            let reopened = InteractionPreferences(defaults: defaults)
            XCTAssertEqual(reopened.inputMode, .automatic)
            XCTAssertEqual(reopened.pointerMode, .analog)
            XCTAssertFalse(reopened.motionInvertX)
            XCTAssertEqual(reopened.mapping, .defaults)
            XCTAssertEqual(reopened.panelDistance, 2.3)
        }
    }

    func testCorruptPreferencesRecoverToSafeAnalogDefaults() async {
        await MainActor.run {
            let name = "InteractionTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(Data("broken json".utf8), forKey: InteractionPreferences.persistenceKey)
            let preferences = InteractionPreferences(defaults: defaults)
            XCTAssertEqual(preferences.pointerMode, .analog)
            XCTAssertEqual(preferences.inputMode, .automatic)
            XCTAssertEqual(preferences.mapping, .defaults)
        }
    }
}
