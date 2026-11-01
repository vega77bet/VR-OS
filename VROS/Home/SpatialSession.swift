import UIKit
import Combine
import QuartzCore
import simd

/// One world state and one input decision per frame, shared by both eye renders.
@MainActor
final class SpatialSession: ObservableObject {
    let controllers = GameControllerManager()
    let preferences = InteractionPreferences()
    private(set) var workspace = SpatialWorkspace()
    private var interaction = SpatialInteractionSystem()
    @Published private(set) var exitRequests = 0
    @Published private(set) var inputStatus = "Mira da cabeça"
    private var lastHeadPose = simd_quatf(real: 1, imag: .zero)
    private var lastControllerFrame = ControllerInputFrame()
    private var lastSummary = -Double.infinity
    private var metrics = FrameMetrics()
    private var appliedDistance: Float = 0
    /// The spatial calibration panel and the native SwiftUI wizard share the
    /// same transactional model. Keeping the session here means that pointer
    /// and Joy-Con edits are applied to the live compositor and can still be
    /// cancelled or undone as one transaction.
    private var visionSession: VisionCalibrationSession?
    private let clockFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    private var active = false
    private var hasPresented = false
    var interactionEnabled = true {
        didSet {
            if interactionEnabled != oldValue {
                resetInput()
                workspace.setDockVisible(interactionEnabled, at: CACurrentMediaTime())
            }
            if !interactionEnabled { controllers.motionEnabled = false }
        }
    }

    init() {
        clockFormatter = DateFormatter(); clockFormatter.locale = Locale(identifier: "pt_BR")
        clockFormatter.dateFormat = "HH:mm"
        dateFormatter = DateFormatter(); dateFormatter.locale = Locale(identifier: "pt_BR")
        dateFormatter.dateFormat = "EEEE, d 'de' MMMM"
        workspace.setDockVisible(false, at: 0)
        workspace.update(at: 1)
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        UIDevice.current.isBatteryMonitoringEnabled = value
        if value { controllers.start() } else { controllers.stop() }
        resetInput()
    }

    func resetInput() { interaction.reset(); lastSummary = -.infinity }
    func receive(_ value: FrameMetrics) { metrics = value }

    func recenter(at time: Double = CACurrentMediaTime()) {
        workspace.perform(.recenter, headPose: lastHeadPose, at: time)
        interaction.recenterAim(headPose: lastHeadPose, motion: lastControllerFrame.motionOrientation)
    }

    func update(headPose: simd_quatf, at time: Double, calibration: VRCalibrationManager,
                headTrackingValid: Bool) -> SpatialRenderFrame {
        lastHeadPose = headPose
        workspace.update(at: time)
        if !hasPresented {
            hasPresented = true
            workspace.setDockVisible(interactionEnabled, at: time)
        }
        if appliedDistance != preferences.panelDistance {
            appliedDistance = preferences.panelDistance
            workspace.perform(.setDistance(appliedDistance), headPose: headPose, at: time)
        }
        if !interactionEnabled {
            let ray = SpatialRay(origin: StereoCamera.headPosition, direction: headPose.act(SIMD3(0, 0, -1)))
            return SpatialRenderFrame(windows: workspace.windows, focusedElementID: nil, grabbedWindowID: nil,
                                      pointer: SpatialPointerVisual(ray: ray, end: ray.origin + ray.direction * 3,
                                                                    isLaser: false, isHit: false, dwellProgress: 0,
                                                                    selectionPulse: 0), time: time)
        }
        let enableMotion = preferences.pointerMode == .motion && preferences.inputMode != .head
        if controllers.motionEnabled != enableMotion { controllers.motionEnabled = enableMotion }
        let frame = controllers.sample()
        lastControllerFrame = frame
        let descriptor = controllers.devices.first(where: { $0.id == frame.controllerID })
        let config = InteractionConfiguration(inputMode: preferences.inputMode,
                                               pointerMode: preferences.pointerMode,
                                               sensitivity: preferences.sensitivity,
                                               dwellDuration: preferences.dwellDuration,
                                               mapping: preferences.mapping,
                                               motionInvertX: preferences.motionInvertX,
                                               motionInvertY: preferences.motionInvertY,
                                               motionSwapAxes: preferences.motionSwapAxes)
        let update = interaction.update(frame: frame, available: descriptor?.availableButtons ?? [],
                                        hasLeftStick: descriptor?.hasLeftStick ?? false,
                                        hasRightStick: descriptor?.hasRightStick ?? false,
                                        configuration: config, headPose: headPose,
                                        windows: workspace.windows, at: time, headTrackingValid: headTrackingValid)
        if let drag = update.drag { workspace.moveWindow(id: drag.id, to: drag.position, headPose: headPose) }
        if let id = update.selectedWindowID ?? update.grabbedWindowID { workspace.focusWindow(id: id) }
        if let hit = update.activation, let action = workspace.action(for: hit) {
            perform(action, at: time, calibration: calibration)
        }
        for command in ControllerAction.allCases where update.commands.contains(command) {
            switch command {
            case .back: perform(.back, at: time, calibration: calibration)
            case .applications: perform(.open(.applications), at: time, calibration: calibration)
            case .recenter: recenter(at: time)
            case .quickMenu: perform(.quickMenu, at: time, calibration: calibration)
            case .home: perform(.open(.home), at: time, calibration: calibration)
            case .select, .grab: break
            }
        }
        if update.scroll != 0 { workspace.perform(.scroll(update.scroll), headPose: headPose, at: time) }
        if time - lastSummary >= 1 {
            lastSummary = time
            inputStatus = update.pointerDescription
            let now = Date()
            let level = UIDevice.current.batteryLevel
            let battery = level >= 0 ? "iPhone \(Int(level * 100))%" : "Bateria iPhone indisponível"
            var controllerStatus = frame.connected ? frame.name : "Sem controle • seleção por permanência"
            if let level = descriptor?.batteryLevel { controllerStatus += " • \(Int(level * 100))%" }
            workspace.setSystemSummary(time: clockFormatter.string(from: now),
                                       date: dateFormatter.string(from: now),
                                       status: headTrackingValid ? String(format: "3DoF • %.0f FPS", metrics.fps) : "Tracking indisponível",
                                       battery: battery)
            workspace.setControlSummary("\(controllerStatus)\n\(preferences.inputMode.title) • \(update.pointerDescription)\nPermanência \(String(format: "%.1f s", preferences.dwellDuration)) • Sensibilidade \(String(format: "%.1f", preferences.sensitivity))")
            workspace.setOpticalSummary(String(format: "IPD %.0f mm • Distorção %.0f%%\nResolução %.0f%% • Painel %.1f m", calibration.profile.ipdMeters * 1000,
                                              calibration.profile.distortionStrength * 100, calibration.renderScale * 100,
                                              preferences.panelDistance))
        }
        // Re-intersect after dragging/actions: the visible dot and actual presented surface agree.
        let visibleHit = SpatialGeometry.intersect(ray: update.ray, windows: workspace.windows)
        let pointer = SpatialPointerVisual(ray: update.ray,
                                           end: visibleHit?.point ?? update.ray.origin + update.ray.direction * 3.5,
                                           isLaser: update.source == .controller &&
                                            ((descriptor?.hasLeftStick ?? false) || (descriptor?.hasRightStick ?? false) ||
                                             (preferences.pointerMode == .motion && frame.motionOrientation != nil)),
                                           isHit: visibleHit != nil, dwellProgress: update.progress,
                                           selectionPulse: update.selectionPulse)
        return SpatialRenderFrame(windows: workspace.windows, focusedElementID: visibleHit?.elementID,
                                  grabbedWindowID: update.grabbedWindowID, pointer: pointer, time: time)
    }

    private func perform(_ action: SpatialAction, at time: Double, calibration: VRCalibrationManager) {
        if case .calibration = action, visionSession == nil {
            visionSession = VisionCalibrationSession(manager: calibration)
            syncVisionWorkspace()
        }
        switch action {
        case .recenter: recenter(at: time); return
        case .recenterPointer:
            interaction.recenterAim(headPose: lastHeadPose, motion: lastControllerFrame.motionOrientation)
        case .cycleInputMode:
            let modes: [InteractionInputMode] = [.automatic, .head, .controller]
            preferences.inputMode = modes[((modes.firstIndex(of: preferences.inputMode) ?? 0) + 1) % modes.count]
        case .cyclePointerMode: preferences.pointerMode = preferences.pointerMode == .analog ? .motion : .analog
        case .nextController:
            let devices = controllers.devices
            if !devices.isEmpty {
                let index = devices.firstIndex(where: { $0.id == controllers.activeID }) ?? -1
                controllers.select(id: devices[(index + 1) % devices.count].id)
            }
        case .adjustDwell(let delta): preferences.dwellDuration += delta
        case .adjustSensitivity(let delta): preferences.sensitivity += delta
        case .setDistance(let distance):
            preferences.panelDistance = distance
            appliedDistance = preferences.panelDistance
        case .resetLayout:
            preferences.panelDistance = 2.4
            appliedDistance = preferences.panelDistance
        case .adjustOptics(let setting, let delta):
            switch setting {
            case .ipd: calibration.profile.ipdMeters += delta
            case .distortion: calibration.profile.distortionStrength += delta
            case .renderScale: calibration.renderScale += delta
            case .distance: preferences.panelDistance += delta
            }
        case .resetOptics: calibration.resetDefaults()
        case .exitImmersive: exitRequests += 1
        case .visionEye(let eye):
            visionSession?.selectEye(eye)
            syncVisionWorkspace()
        case .visionStage(let raw):
            if let stage = VisionCalibrationStage(rawValue: raw) {
                visionSession?.stage = stage
                if stage == .leftAlignment { visionSession?.selectEye(.left) }
                if stage == .rightAlignment { visionSession?.selectEye(.right) }
                syncVisionWorkspace()
            }
        case .visionAdjust(let eye, let parameter, let delta):
            ensureVisionSession(calibration).adjust(parameter, delta: delta, eye: eye)
            syncVisionWorkspace()
        case .visionIPD(let delta):
            ensureVisionSession(calibration).adjustIPD(delta)
            syncVisionWorkspace()
        case .visionProjectionCenter(let eye, let delta):
            ensureVisionSession(calibration).adjustProjectionCenter(eye: eye, delta: delta)
            syncVisionWorkspace()
        case .visionUndo:
            ensureVisionSession(calibration).undo()
            syncVisionWorkspace()
        case .visionRestoreStage:
            ensureVisionSession(calibration).restoreStage()
            syncVisionWorkspace()
        case .visionRestoreAll:
            ensureVisionSession(calibration).restoreAll()
            syncVisionWorkspace()
        case .visionCompare:
            ensureVisionSession(calibration).toggleCompare()
            syncVisionWorkspace()
        case .visionSave:
            ensureVisionSession(calibration).save()
            workspace.perform(.back, headPose: lastHeadPose, at: time)
            visionSession = nil
        case .visionCancel:
            ensureVisionSession(calibration).cancel()
            workspace.perform(.back, headPose: lastHeadPose, at: time)
            visionSession = nil
        default: break
        }
        workspace.perform(action, headPose: lastHeadPose, at: time)
        if case .calibration = action { syncVisionWorkspace() }
        lastSummary = -.infinity
    }

    private func ensureVisionSession(_ calibration: VRCalibrationManager) -> VisionCalibrationSession {
        if let visionSession { return visionSession }
        let session = VisionCalibrationSession(manager: calibration)
        visionSession = session
        return session
    }

    private func syncVisionWorkspace() {
        guard let session = visionSession else { return }
        workspace.setVisionState(stage: session.stage, eye: session.selectedEye,
                                 change: session.lastChange)
    }
}
