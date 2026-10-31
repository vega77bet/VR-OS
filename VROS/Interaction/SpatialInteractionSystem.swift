import Foundation
import simd

enum ActiveInputSource: String { case head, controller }

struct InteractionConfiguration {
    var inputMode: InteractionInputMode = .automatic
    var pointerMode: ControllerPointerMode = .analog
    var sensitivity: Float = 0.9
    var dwellDuration: Double = 1
    var mapping = ControllerMapping.defaults
    var motionInvertX = false
    var motionInvertY = false
    var motionSwapAxes = false
}

struct InteractionUpdate {
    var ray: SpatialRay
    var hit: SpatialHit?
    var activation: SpatialHit?
    var commands: Set<ControllerAction>
    var drag: (id: String, position: SIMD3<Float>)?
    var grabbedWindowID: String?
    var scroll: Int
    var source: ActiveInputSource
    var pointerDescription: String
    var progress: Float
    var selectionPulse: Float
}

/// Input-independent hit testing, single action-edge arbitration, dwell and drag.
/// Controller positions are synthetic body offsets, never tracked physical positions.
struct SpatialInteractionSystem {
    private var previousTime: Double?
    private var previousActions: Set<ControllerAction> = []
    private var identity: String?
    private var previousPointerMode: ControllerPointerMode?
    private var quarantine: Set<ControllerButton> = []
    private var dwellTarget: String?
    private var dwellStarted: Double = 0
    private var dwellLatched = false
    private var yaw: Float = 0
    private var pitch: Float = 0.12
    private var anchorYaw: Float = 0
    private var motionNeutral: simd_quatf?
    private var filteredRelative = simd_quatf(real: 1, imag: .zero)
    private var grabbedID: String?
    private var grabDistance: Float = 2
    private var grabOffset = SIMD3<Float>.zero
    private var grabBlockedUntilRelease = false
    private var lastScrollTime = -Double.infinity
    private var lastSelectionTime = -Double.infinity

    mutating func reset() {
        previousTime = nil; identity = nil; previousActions.removeAll()
        quarantine.removeAll(); grabbedID = nil; clearDwell()
        motionNeutral = nil; previousPointerMode = nil
        grabBlockedUntilRelease = false
    }

    mutating func recenterAim(headPose: simd_quatf, motion: simd_quatf?) {
        anchorYaw = Self.horizontalHeading(headPose)
        yaw = 0; pitch = 0.12
        motionNeutral = Self.valid(motion) ? simd_normalize(motion!) : nil
        filteredRelative = simd_quatf(real: 1, imag: .zero)
        grabbedID = nil
    }

    mutating func update(frame: ControllerInputFrame, available: Set<ControllerButton>,
                         hasLeftStick: Bool, hasRightStick: Bool,
                         configuration: InteractionConfiguration, headPose: simd_quatf,
                         windows: [SpatialWindow], at time: Double) -> InteractionUpdate {
        let dt = Float(min(max(time - (previousTime ?? time), 0), 0.05))
        previousTime = time
        let bindings = configuration.mapping.effectiveBindings(available: available)
        let usableController = frame.connected && bindings.values.contains(.select)
        let source: ActiveInputSource = configuration.inputMode != .head && usableController ? .controller : .head
        let nextIdentity = source == .controller ? "controller:\(frame.controllerID ?? "unknown")" : "head"
        let changed = identity != nextIdentity ||
            (source == .controller && previousPointerMode != configuration.pointerMode)
        if changed {
            identity = nextIdentity
            previousPointerMode = configuration.pointerMode
            quarantine = frame.buttons
            previousActions.removeAll()
            recenterAim(headPose: headPose, motion: frame.motionOrientation)
            clearDwell()
            lastScrollTime = time
        }
        quarantine.formIntersection(frame.buttons)
        let buttons = frame.buttons.subtracting(quarantine)
        let actions = source == .controller
            ? configuration.mapping.actions(for: buttons, available: available) : []
        let edges = actions.subtracting(previousActions)
        previousActions = actions
        let navigating = !edges.subtracting([.select, .grab]).isEmpty
        if !actions.contains(.grab) { grabBlockedUntilRelease = false }
        if navigating {
            grabbedID = nil
            if actions.contains(.grab) { grabBlockedUntilRelease = true }
        }

        let headOrigin = StereoCamera.headPosition
        let headForward = headPose.act(SIMD3<Float>(0, 0, -1))
        var ray = SpatialRay(origin: headOrigin, direction: headForward)
        var pointerDescription = "Mira da cabeça"
        if source == .controller {
            let stick = Self.deadzone(hasRightStick ? frame.rightStick : (hasLeftStick ? frame.leftStick : .zero))
            let usingMotion = configuration.pointerMode == .motion && Self.valid(frame.motionOrientation)
            if usingMotion, let motion = frame.motionOrientation {
                if motionNeutral == nil { motionNeutral = motion }
                let relative = simd_normalize(motionNeutral!.inverse * motion)
                let blend = 1 - exp(-dt * 35)
                filteredRelative = simd_slerp(filteredRelative, relative, blend)
                let forward = filteredRelative.act(SIMD3<Float>(0, 0, -1))
                var x = atan2(forward.x, -forward.z)
                var y = asin(min(max(forward.y, -1), 1))
                if configuration.motionSwapAxes { swap(&x, &y) }
                yaw = min(max(x * (configuration.motionInvertX ? -1 : 1), -1.05), 1.05)
                pitch = min(max(y * (configuration.motionInvertY ? -1 : 1) + 0.12, -0.65), 0.65)
                pointerDescription = "Movimento relativo • experimental"
            } else if hasRightStick || hasLeftStick {
                yaw = min(max(yaw + stick.x * configuration.sensitivity * dt, -1.05), 1.05)
                pitch = min(max(pitch + stick.y * configuration.sensitivity * dt, -0.65), 0.65)
                pointerDescription = configuration.pointerMode == .motion
                    ? "Analógico • movimento indisponível" : "Analógico"
            } else {
                pointerDescription = "Mira da cabeça + botões"
            }
            if usingMotion || hasRightStick || hasLeftStick {
                let anchor = simd_quatf(angle: anchorYaw, axis: SIMD3(0, 1, 0))
                let aim = anchor * simd_quatf(angle: -yaw, axis: SIMD3(0, 1, 0)) *
                    simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
                let body = simd_quatf(angle: Self.horizontalHeading(headPose), axis: SIMD3(0, 1, 0))
                ray = SpatialRay(origin: headOrigin + body.act(SIMD3(0.22, -0.20, -0.12)),
                                 direction: aim.act(SIMD3(0, 0, -1)))
            }
        }
        let hit = SpatialGeometry.intersect(ray: ray, windows: windows)
        let actionable = hit.flatMap { candidate -> SpatialHit? in
            guard let id = candidate.elementID,
                  windows.first(where: { $0.id == candidate.windowID })?.elements
                    .contains(where: { $0.id == id && $0.action != nil }) == true else { return nil }
            return candidate
        }
        var activation: SpatialHit?
        var drag: (id: String, position: SIMD3<Float>)?
        if source == .controller && actions.contains(.grab) && !grabBlockedUntilRelease {
            clearDwell()
            if edges.contains(.grab), let hit,
               let window = windows.first(where: { $0.id == hit.windowID && $0.isOpen }) {
                grabbedID = hit.windowID
                grabDistance = min(max(hit.distance, 1.4), 4)
                grabOffset = window.position - hit.point
            }
            if let id = grabbedID {
                if hasLeftStick && hasRightStick {
                    grabDistance = min(max(grabDistance + Self.deadzone(frame.leftStick).y * dt, 1.4), 4)
                }
                drag = (id, ray.origin + ray.direction * grabDistance + grabOffset)
            }
        } else {
            grabbedID = nil
            if source == .head {
                if let target = actionable?.elementID {
                    if dwellTarget != target {
                        dwellTarget = target; dwellStarted = time; dwellLatched = false
                    }
                    if !dwellLatched && time - dwellStarted >= max(configuration.dwellDuration, 0.6) {
                        activation = actionable; dwellLatched = true
                    }
                } else { clearDwell() }
            } else {
                clearDwell()
                if edges.contains(.select) && !navigating { activation = actionable }
            }
        }
        if activation != nil { lastSelectionTime = time }
        var scroll = 0
        if source == .controller && grabbedID == nil {
            let vertical = hasLeftStick && hasRightStick ? frame.leftStick.y : 0
            let down = buttons.contains(.dpadDown) && bindings[.dpadDown] == nil
            let up = buttons.contains(.dpadUp) && bindings[.dpadUp] == nil
            let direction = down || vertical < -0.55 ? 1 : (up || vertical > 0.55 ? -1 : 0)
            if direction != 0 && time - lastScrollTime >= 0.3 {
                scroll = direction; lastScrollTime = time
            } else if direction == 0 { lastScrollTime = time - 0.3 }
        }
        let progress = source == .head && dwellTarget != nil && !dwellLatched
            ? Float(min(max((time - dwellStarted) / max(configuration.dwellDuration, 0.6), 0), 1)) : 0
        return InteractionUpdate(ray: ray, hit: hit, activation: activation,
                                 commands: edges.subtracting([.select, .grab]), drag: drag,
                                 grabbedWindowID: grabbedID, scroll: scroll, source: source,
                                 pointerDescription: pointerDescription, progress: progress,
                                 selectionPulse: Float(max(0, 1 - (time - lastSelectionTime) / 0.22)))
    }

    private mutating func clearDwell() { dwellTarget = nil; dwellLatched = false; dwellStarted = 0 }

    static func horizontalHeading(_ pose: simd_quatf) -> Float {
        let forward = pose.act(SIMD3<Float>(0, 0, -1))
        return forward.x * forward.x + forward.z * forward.z > 0.0001 ? atan2(-forward.x, -forward.z) : 0
    }

    private static func deadzone(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        guard stick.x.isFinite, stick.y.isFinite else { return .zero }
        let length = simd_length(stick)
        guard length > 0.14 else { return .zero }
        let amount = min((length - 0.14) / 0.86, 1)
        return stick / length * amount * amount
    }

    private static func valid(_ q: simd_quatf?) -> Bool {
        guard let q else { return false }
        let length = simd_length_squared(q.vector)
        return length.isFinite && length > 0.001 && q.vector.x.isFinite &&
            q.vector.y.isFinite && q.vector.z.isFinite && q.vector.w.isFinite
    }
}
