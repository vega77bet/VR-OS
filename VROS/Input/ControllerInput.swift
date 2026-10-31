import Foundation
import simd

enum InteractionInputMode: String, Codable, CaseIterable {
    case automatic, controller, head
    var title: String {
        switch self { case .automatic: return "Automático"; case .controller: return "Controle"; case .head: return "Cabeça" }
    }
}

enum ControllerPointerMode: String, Codable, CaseIterable {
    case analog, motion
    var title: String { self == .analog ? "Analógico" : "Movimento experimental" }
}

/// Names refer to Apple's logical gamepad layout, not guaranteed Nintendo legends.
enum ControllerButton: String, Codable, CaseIterable, Hashable {
    case a, b, x, y, leftTrigger, rightTrigger, leftShoulder, rightShoulder
    case menu, options, home, dpadUp, dpadDown, dpadLeft, dpadRight
    case leftStickButton, rightStickButton

    var title: String {
        switch self {
        case .a: return "A lógico · inferior"
        case .b: return "B lógico · direito"
        case .x: return "X lógico · esquerdo"
        case .y: return "Y lógico · superior"
        case .leftTrigger: return "Gatilho esquerdo · ZL equivalente"
        case .rightTrigger: return "Gatilho direito · ZR equivalente"
        case .leftShoulder: return "Ombro esquerdo"
        case .rightShoulder: return "Ombro direito"
        case .menu: return "Menu · + equivalente"
        case .options: return "Opções · − equivalente"
        case .home: return "Home do controle"
        case .dpadUp: return "Direcional acima"
        case .dpadDown: return "Direcional abaixo"
        case .dpadLeft: return "Direcional esquerdo"
        case .dpadRight: return "Direcional direito"
        case .leftStickButton: return "Clique do analógico E"
        case .rightStickButton: return "Clique do analógico D"
        }
    }
}

enum ControllerAction: String, Codable, CaseIterable, Hashable {
    case select, grab, back, applications, recenter, quickMenu, home
    var title: String {
        switch self {
        case .select: return "Selecionar"
        case .grab: return "Agarrar janela"
        case .back: return "Voltar"
        case .applications: return "Aplicativos"
        case .recenter: return "Recentralizar"
        case .quickMenu: return "Menu rápido"
        case .home: return "Início"
        }
    }
}

struct ControllerMapping: Codable, Equatable {
    var bindings: [ControllerButton: ControllerAction]
    static let defaults = ControllerMapping(bindings: [
        .rightTrigger: .select, .a: .select, .leftTrigger: .grab,
        .b: .back, .x: .applications, .y: .recenter, .menu: .quickMenu, .options: .home
    ])

    /// Keep real available inputs only. A controller without ZR/A gets an explicit
    /// selection fallback, rather than an unclickable cursor. Never invent axes/buttons.
    func effectiveBindings(available: Set<ControllerButton>) -> [ControllerButton: ControllerAction] {
        var result = bindings.filter { available.contains($0.key) }
        if !result.values.contains(.select) {
            let priority: [ControllerButton] = [.a, .rightTrigger, .x, .rightShoulder, .leftShoulder,
                                                .b, .y, .leftTrigger, .leftStickButton, .rightStickButton,
                                                .menu, .options, .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .home]
            if let fallback = priority.first(where: { available.contains($0) }) { result[fallback] = .select }
        }
        return result
    }

    /// Multiple aliases (e.g. A and ZR) produce one virtual action.
    func actions(for pressed: Set<ControllerButton>, available: Set<ControllerButton>) -> Set<ControllerAction> {
        let effective = effectiveBindings(available: available)
        return Set(pressed.compactMap { effective[$0] })
    }
}

struct ControllerDescriptor: Equatable, Identifiable {
    var id: String
    var name: String
    var availableButtons: Set<ControllerButton>
    var hasLeftStick: Bool
    var hasRightStick: Bool
    var hasMotion: Bool
    /// 0...1 only when the public API reports a known battery level.
    var batteryLevel: Float?
}

struct ControllerInputFrame {
    var connected: Bool = false
    var controllerID: String? = nil
    var name: String = "Sem controle"
    var buttons: Set<ControllerButton> = []
    var leftStick: SIMD2<Float> = .zero
    var rightStick: SIMD2<Float> = .zero
    /// Raw GCMotion body attitude. This is a relative controller reference, not
    /// the headset world, hand position or a guarantee of Nintendo sensor support.
    var motionOrientation: simd_quatf? = nil
    static let disconnected = ControllerInputFrame()
}

/// Hardware-independent connection policy, also used by the real adapter.
struct ControllerRegistry {
    private(set) var devices: [ControllerDescriptor] = []
    private(set) var activeID: String?
    private var waitingForFirstFrame = true
    private var blockedButtons: Set<ControllerButton> = []

    mutating func connect(_ descriptor: ControllerDescriptor) {
        if let index = devices.firstIndex(where: { $0.id == descriptor.id }) {
            let old = devices[index]
            if activeID == descriptor.id,
               old.availableButtons != descriptor.availableButtons || old.hasLeftStick != descriptor.hasLeftStick ||
               old.hasRightStick != descriptor.hasRightStick || old.hasMotion != descriptor.hasMotion {
                resetHeldState()
            }
            devices[index] = descriptor
        } else { devices.append(descriptor) }
        if activeID == nil { select(id: descriptor.id) }
    }

    mutating func disconnect(id: String) {
        devices.removeAll { $0.id == id }
        if activeID == id {
            activeID = nil
            resetHeldState()
            if let next = devices.first { select(id: next.id) }
        }
    }

    mutating func select(id: String) {
        guard devices.contains(where: { $0.id == id }), activeID != id else { return }
        activeID = id
        resetHeldState()
    }

    mutating func resetHeldState() {
        waitingForFirstFrame = true
        blockedButtons = []
    }

    mutating func filteredFrame(_ source: ControllerInputFrame) -> ControllerInputFrame {
        guard source.connected, source.controllerID == activeID,
              let descriptor = devices.first(where: { $0.id == activeID }) else { return .disconnected }
        var result = source
        result.buttons.formIntersection(descriptor.availableButtons)
        if waitingForFirstFrame {
            blockedButtons = result.buttons
            waitingForFirstFrame = false
            result.leftStick = .zero
            result.rightStick = .zero
        } else {
            result.leftStick = descriptor.hasLeftStick ? Self.validated(result.leftStick) : .zero
            result.rightStick = descriptor.hasRightStick ? Self.validated(result.rightStick) : .zero
        }
        blockedButtons.formIntersection(result.buttons)
        result.buttons.subtract(blockedButtons)
        if !descriptor.hasMotion { result.motionOrientation = nil }
        return result
    }

    private static func validated(_ axes: SIMD2<Float>) -> SIMD2<Float> {
        func value(_ input: Float) -> Float { input.isFinite ? min(max(input, -1), 1) : 0 }
        return SIMD2(value(axes.x), value(axes.y))
    }
}
