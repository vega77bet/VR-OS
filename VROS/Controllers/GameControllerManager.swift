import Combine
import Foundation
import GameController
import simd

/// Public GameController adapter. Pairing belongs to iOS Settings → Bluetooth.
/// A Joy-Con, pair or other controller is treated according to its actual profile.
@MainActor
final class GameControllerManager: ObservableObject {
    @Published private(set) var devices: [ControllerDescriptor] = []
    @Published private(set) var activeID: String?
    var activeDescriptor: ControllerDescriptor? { devices.first { $0.id == activeID } }
    var motionEnabled = false { didSet { configureMotion() } }
    private var registry = ControllerRegistry()
    private var live: [String: GCController] = [:]
    private struct CachedProfile {
        var identity: ObjectIdentifier
        var buttons: [ControllerButton: GCControllerButtonInput]
        var left: GCControllerDirectionPad?
        var right: GCControllerDirectionPad?
    }
    private var profiles: [String: CachedProfile] = [:]
    private var identifiers: [ObjectIdentifier: String] = [:]
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var selectedBeforeStop: String?
    private var lastMetadataRefresh = Date.distantPast

    func start() {
        guard !running else { return }
        running = true
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.running else { return }
                    self.refreshConnections()
                }
            })
        }
        refreshConnections()
        if let selectedBeforeStop { registry.select(id: selectedBeforeStop); publishRegistry() }
        configureMotion()
    }

    func stop() {
        guard running else { return }
        selectedBeforeStop = activeID
        running = false
        configureMotion()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        live.removeAll()
        profiles.removeAll()
        registry = ControllerRegistry()
        publishRegistry()
    }

    func select(id: String) {
        registry.select(id: id)
        publishRegistry()
        configureMotion()
    }

    func sample() -> ControllerInputFrame {
        guard running, let id = registry.activeID, let controller = live[id], let profile = profiles[id] else { return .disconnected }
        if Date().timeIntervalSince(lastMetadataRefresh) >= 1 { refreshMetadata() }
        let frame = ControllerInputFrame(
            connected: true, controllerID: id, name: controller.vendorName ?? "Controle GameController",
            buttons: Set(profile.buttons.compactMap { $0.value.isPressed ? $0.key : nil }),
            leftStick: SIMD2(profile.left?.xAxis.value ?? 0, profile.left?.yAxis.value ?? 0),
            rightStick: SIMD2(profile.right?.xAxis.value ?? 0, profile.right?.yAxis.value ?? 0),
            motionOrientation: attitude(from: controller))
        return registry.filteredFrame(frame)
    }

    private func refreshConnections() {
        var next: [String: GCController] = [:]
        let connected = GCController.controllers()
        let identities = Set(connected.map { ObjectIdentifier($0) })
        identifiers = identifiers.filter { identities.contains($0.key) }
        for controller in connected {
            let identity = ObjectIdentifier(controller)
            let id = identifiers[identity] ?? UUID().uuidString
            identifiers[identity] = id
            next[id] = controller
            let profile = controller.physicalInputProfile
            profiles[id] = CachedProfile(identity: ObjectIdentifier(profile), buttons: buttons(in: profile),
                                         left: profile.dpads[GCInputLeftThumbstick],
                                         right: profile.dpads[GCInputRightThumbstick])
            registry.connect(descriptor(controller, id: id))
        }
        for (id, previous) in live where next[id] == nil {
            if let motion = previous.motion, motion.sensorsRequireManualActivation { motion.sensorsActive = false }
            registry.disconnect(id: id)
            identifiers.removeValue(forKey: ObjectIdentifier(previous))
            profiles.removeValue(forKey: id)
        }
        live = next
        lastMetadataRefresh = Date()
        publishRegistry()
        configureMotion()
    }

    private func refreshMetadata() {
        for (id, controller) in live {
            let profile = controller.physicalInputProfile
            if profiles[id]?.identity != ObjectIdentifier(profile) {
                profiles[id] = CachedProfile(identity: ObjectIdentifier(profile), buttons: buttons(in: profile),
                                             left: profile.dpads[GCInputLeftThumbstick],
                                             right: profile.dpads[GCInputRightThumbstick])
                if id == registry.activeID { registry.resetHeldState() }
            }
            registry.connect(descriptor(controller, id: id))
        }
        lastMetadataRefresh = Date()
        publishRegistry()
    }

    private func publishRegistry() {
        if devices != registry.devices { devices = registry.devices }
        if activeID != registry.activeID { activeID = registry.activeID }
    }

    private func configureMotion() {
        for (id, controller) in live {
            if let motion = controller.motion, motion.sensorsRequireManualActivation {
                motion.sensorsActive = running && motionEnabled && id == registry.activeID
            }
        }
    }

    private func attitude(from controller: GCController) -> simd_quatf? {
        guard motionEnabled, let motion = controller.motion, motion.hasAttitude,
              !motion.sensorsRequireManualActivation || motion.sensorsActive else { return nil }
        let q = motion.attitude
        let vector = SIMD4<Float>(Float(q.x), Float(q.y), Float(q.z), Float(q.w))
        let length = simd_length_squared(vector)
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite,
              length.isFinite, length > 0.0001 else { return nil }
        // Keep public API semantics intact: this is not a headset/world transform.
        return simd_normalize(simd_quatf(vector: vector))
    }

    private func descriptor(_ controller: GCController, id: String) -> ControllerDescriptor {
        let profile = controller.physicalInputProfile
        var level: Float?
        if let battery = controller.battery, battery.batteryState != .unknown,
           battery.batteryLevel.isFinite, (0...1).contains(battery.batteryLevel) {
            level = battery.batteryLevel
        }
        return ControllerDescriptor(
            id: id, name: controller.vendorName ?? "Controle GameController",
            availableButtons: Set(buttons(in: profile).keys),
            hasLeftStick: profile.dpads[GCInputLeftThumbstick] != nil,
            hasRightStick: profile.dpads[GCInputRightThumbstick] != nil,
            hasMotion: controller.motion?.hasAttitude == true,
            batteryLevel: level)
    }

    private func buttons(in profile: GCPhysicalInputProfile) -> [ControllerButton: GCControllerButtonInput] {
        let names: [(ControllerButton, String)] = [
            (.a, GCInputButtonA), (.b, GCInputButtonB), (.x, GCInputButtonX), (.y, GCInputButtonY),
            (.leftTrigger, GCInputLeftTrigger), (.rightTrigger, GCInputRightTrigger),
            (.leftShoulder, GCInputLeftShoulder), (.rightShoulder, GCInputRightShoulder),
            (.menu, GCInputButtonMenu), (.options, GCInputButtonOptions), (.home, GCInputButtonHome),
            (.leftStickButton, GCInputLeftThumbstickButton), (.rightStickButton, GCInputRightThumbstickButton)
        ]
        var result: [ControllerButton: GCControllerButtonInput] = [:]
        for (button, name) in names { result[button] = profile.buttons[name] }
        if let dpad = profile.dpads[GCInputDirectionPad] {
            result[.dpadUp] = dpad.up; result[.dpadDown] = dpad.down
            result[.dpadLeft] = dpad.left; result[.dpadRight] = dpad.right
        }
        return result
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        for controller in live.values {
            if let motion = controller.motion, motion.sensorsRequireManualActivation { motion.sensorsActive = false }
        }
    }
}
