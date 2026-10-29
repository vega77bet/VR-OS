import Combine
import CoreGraphics
import GameController
import SwiftUI
import simd

/// Physical Joy-Con input for the VR Box interface.
///
/// The controller orientation becomes a 2D pointing ray. It deliberately
/// does not pretend to provide 6DoF position: the iPhone remains the display
/// and the Joy-Con supplies orientation plus a physical trigger.
@MainActor
final class VRJoyConController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var connectedCount = 0
    @Published private(set) var status = "Conecte os dois Joy-Cons pelo Bluetooth"
    @Published private(set) var primaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var secondaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var triggerPointNormalized = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var triggerPulse = 0
    @Published private(set) var motionRevision = 0
    @Published var invertMotion = false

    private var controllers: [ObjectIdentifier: GCController] = [:]
    private var references: [ObjectIdentifier: simd_quatf] = [:]
    private var lastTriggerState: [ObjectIdentifier: Bool] = [:]
    private var lastMenuState: [ObjectIdentifier: Bool] = [:]
    private var observerTokens: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: Notification.Name.GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.attach(controller)
            }
        )
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: Notification.Name.GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.detach(controller)
            }
        )
        GCController.controllers().forEach { attach($0) }
        refreshStatus()
    }

    func stop() {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observerTokens.removeAll()
        for controller in controllers.values {
            controller.motion?.valueChangedHandler = nil
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        controllers.removeAll()
        references.removeAll()
        lastTriggerState.removeAll()
        lastMenuState.removeAll()
        started = false
        connectedCount = 0
        isConnected = false
        primaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
        secondaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
        triggerPointNormalized = CGPoint(x: 0.5, y: 0.5)
        status = "Conecte os dois Joy-Cons pelo Bluetooth"
        motionRevision &+= 1
    }

    func recenter() {
        for controller in controllers.values {
            let id = ObjectIdentifier(controller)
            if let attitude = controller.motion?.attitude {
                references[id] = Self.quaternion(from: attitude)
            } else {
                references[id] = nil
            }
        }
        primaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
        secondaryPointNormalized = CGPoint(x: 0.5, y: 0.5)
        triggerPointNormalized = CGPoint(x: 0.5, y: 0.5)
        motionRevision &+= 1
        status = connectedCount == 2
            ? "Dois Joy-Cons ativos · mira recentralizada"
            : "Joy-Con ativo · mira recentralizada"
    }

    func primaryPoint(in viewport: CGSize) -> CGPoint {
        Self.point(primaryPointNormalized, in: viewport)
    }

    func secondaryPoint(in viewport: CGSize) -> CGPoint {
        Self.point(secondaryPointNormalized, in: viewport)
    }

    func triggerPoint(in viewport: CGSize) -> CGPoint {
        Self.point(triggerPointNormalized, in: viewport)
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard controllers[id] == nil else { return }
        controllers[id] = controller
        references[id] = nil

        controller.motion?.valueChangedHandler = { [weak self, weak controller] motion in
            guard let controller else { return }
            Task { @MainActor [weak self] in
                self?.consume(motion, from: controller)
            }
        }

        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] gamepad, _ in
            guard let controller else { return }
            let trigger = gamepad.rightTrigger.isPressed
            let menu = gamepad.buttonMenu.isPressed
            Task { @MainActor [weak self] in
                self?.consumeButtons(trigger: trigger, menu: menu, from: controller)
            }
        }

        refreshStatus()
    }

    private func detach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        controllers.removeValue(forKey: id)
        references.removeValue(forKey: id)
        lastTriggerState.removeValue(forKey: id)
        lastMenuState.removeValue(forKey: id)
        refreshStatus()
    }

    private func consume(_ motion: GCMotion, from controller: GCController) {
        let id = ObjectIdentifier(controller)
        let current = Self.quaternion(from: motion.attitude)
        guard let reference = references[id] else {
            references[id] = current
            return
        }

        var delta = simd_normalize(simd_inverse(reference) * current)
        if invertMotion { delta = simd_inverse(delta) }

        let point = VRHeadPointerGeometry.normalizedPoint(
            rotation: delta,
            sensitivity: 1.18
        )

        if isPrimary(controller) {
            primaryPointNormalized = point
        } else {
            secondaryPointNormalized = point
        }
        motionRevision &+= 1
    }

    private func consumeButtons(trigger: Bool, menu: Bool, from controller: GCController) {
        let id = ObjectIdentifier(controller)
        let oldTrigger = lastTriggerState[id] ?? false
        let oldMenu = lastMenuState[id] ?? false

        if trigger && !oldTrigger {
            triggerPointNormalized = isPrimary(controller)
                ? primaryPointNormalized
                : secondaryPointNormalized
            triggerPulse &+= 1
        }
        if menu && !oldMenu {
            recenter()
        }

        lastTriggerState[id] = trigger
        lastMenuState[id] = menu
    }

    private func isPrimary(_ controller: GCController) -> Bool {
        guard let first = controllers.values.first else { return true }
        return controller === first
    }

    private func refreshStatus() {
        connectedCount = controllers.count
        isConnected = !controllers.isEmpty
        if connectedCount == 0 {
            status = "Conecte os dois Joy-Cons pelo Bluetooth"
        } else if connectedCount == 1 {
            status = "1 Joy-Con ativo · conecte o outro para usar os dois"
        } else {
            status = "2 Joy-Cons ativos · raio e ZR prontos"
        }
    }

    private static func quaternion(from attitude: GCQuaternion) -> simd_quatf {
        simd_normalize(simd_quatf(
            ix: Float(attitude.x),
            iy: Float(attitude.y),
            iz: Float(attitude.z),
            r: Float(attitude.w)
        ))
    }

    private static func point(_ normalized: CGPoint, in viewport: CGSize) -> CGPoint {
        CGPoint(
            x: normalized.x * max(1, viewport.width),
            y: normalized.y * max(1, viewport.height)
        )
    }
}

/// A bright, layered pointer ray drawn over one VR eye.
struct VRJoyConRay: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        ZStack {
            Canvas { context, _ in
                var beam = Path()
                beam.move(to: start)
                beam.addLine(to: end)
                context.stroke(beam, with: .color(color.opacity(0.18)), lineWidth: 18)
                context.stroke(beam, with: .color(color.opacity(0.42)), lineWidth: 8)
                context.stroke(beam, with: .color(color.opacity(0.94)), lineWidth: 3)
                context.stroke(beam, with: .color(.white.opacity(0.92)), lineWidth: 1)
            }
            Circle()
                .fill(color.opacity(0.20))
                .overlay(Circle().stroke(color, lineWidth: 2))
                .overlay(Circle().fill(.white).frame(width: 4, height: 4))
                .frame(width: 20, height: 20)
                .position(end)
                .shadow(color: color, radius: 8)
        }
        .allowsHitTesting(false)
    }
}
