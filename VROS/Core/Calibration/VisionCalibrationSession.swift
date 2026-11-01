import Combine
import Foundation

/// Transactional calibration state. Every edit is previewed by the real
/// compositor; cancel restores the exact profile that was active on entry.
@MainActor
final class VisionCalibrationSession: ObservableObject {
    struct Snapshot: Equatable {
        var profile: VRLensProfile
        var renderScale: Float
    }

    @Published private(set) var draft: VRLensProfile
    @Published private(set) var draftRenderScale: Float
    @Published var stage: VisionCalibrationStage
    @Published var selectedEye: VisionCalibrationEye
    @Published var compareBefore = false
    @Published private(set) var lastChange = "Nenhuma alteração"
    @Published private(set) var userAssessment = "Ainda não avaliado"
    private let manager: VRCalibrationManager
    private var original: Snapshot
    private var undoStack: [Snapshot] = []
    private var stageBaselines: [VisionCalibrationStage: Snapshot] = [:]

    init(manager: VRCalibrationManager) {
        self.manager = manager
        let initial = Snapshot(profile: manager.profile, renderScale: manager.renderScale)
        original = initial; draft = initial.profile; draftRenderScale = initial.renderScale
        stage = .preparation; selectedEye = .left
        stageBaselines[.preparation] = initial
    }

    var progressText: String {
        "Etapa \(stage.rawValue + 1) de \(VisionCalibrationStage.allCases.count)"
    }

    var canUndo: Bool { !undoStack.isEmpty }

    var eye: EyeCalibration { selectedEye == .left ? draft.leftEye : draft.rightEye }

    /// Starts a fresh transaction after the user changes the active named
    /// profile. The compositor is already showing the manager's selected
    /// profile, so the draft must follow it instead of editing stale values.
    func reloadFromManager() {
        let initial = Snapshot(profile: manager.profile, renderScale: manager.renderScale)
        original = initial
        draft = initial.profile
        draftRenderScale = initial.renderScale
        undoStack.removeAll(keepingCapacity: true)
        compareBefore = false
        stageBaselines = [.preparation: initial]
        stage = .preparation
        selectedEye = .left
        lastChange = "Perfil carregado"
    }

    func nextStage() {
        guard let next = VisionCalibrationStage(rawValue: min(stage.rawValue + 1,
                                                              VisionCalibrationStage.allCases.count - 1)) else { return }
        if next != stage { stageBaselines[next] = snapshot; stage = next }
        applyPreview()
    }

    func previousStage() {
        guard let previous = VisionCalibrationStage(rawValue: max(stage.rawValue - 1, 0)) else { return }
        stage = previous
        applyPreview()
    }

    func selectEye(_ eye: VisionCalibrationEye) { selectedEye = eye }

    func setAssessment(_ value: String) { userAssessment = value }

    func adjust(_ parameter: VisionCalibrationParameter, delta: Float,
                eye targetEye: VisionCalibrationEye? = nil) {
        pushUndo()
        let target = targetEye ?? selectedEye
        if parameter == .horizontalOffset || parameter == .verticalOffset ||
            parameter == .horizontalScale || parameter == .verticalScale ||
            parameter == .rotationDegrees || parameter == .opticalCenterX ||
            parameter == .opticalCenterY || parameter == .radialK1 ||
            parameter == .radialK2 || parameter == .radialK3 ||
            parameter == .tangentialP1 || parameter == .tangentialP2 ||
            parameter == .chromaticRedScale || parameter == .chromaticBlueScale ||
            parameter == .distortionStrength {
            mutateEye(target) { value in
                switch parameter {
                case .horizontalOffset: value.horizontalOffset += delta
                case .verticalOffset: value.verticalOffset += delta
                case .horizontalScale: value.horizontalScale += delta
                case .verticalScale: value.verticalScale += delta
                case .rotationDegrees: value.rotationDegrees += delta
                case .opticalCenterX: value.opticalCenterX += delta
                case .opticalCenterY: value.opticalCenterY += delta
                case .radialK1: value.radialK1 += delta
                case .radialK2: value.radialK2 += delta
                case .radialK3: value.radialK3 += delta
                case .tangentialP1: value.tangentialP1 += delta
                case .tangentialP2: value.tangentialP2 += delta
                case .chromaticRedScale: value.chromaticRedScale += delta
                case .chromaticBlueScale: value.chromaticBlueScale += delta
                case .distortionStrength: value.distortionStrength += delta
                }
            }
            lastChange = "\(parameter.title) \(delta >= 0 ? "+" : "−")"
        }
        applyPreview()
    }

    func adjustIPD(_ delta: Float) {
        pushUndo(); draft.ipdMeters += delta; lastChange = "IPD ajustado"; applyPreview()
    }

    func adjustProjectionCenter(eye targetEye: VisionCalibrationEye, delta: Float) {
        pushUndo()
        if targetEye == .left { draft.leftProjectionCenterX += delta }
        else { draft.rightProjectionCenterX += delta }
        lastChange = "Centro de projeção ajustado"; applyPreview()
    }

    func setRenderScale(_ value: Float) {
        pushUndo(); draftRenderScale = min(max(value, 0.5), 1); lastChange = "Resolução interna ajustada"; applyPreview()
    }

    func restoreStage() {
        guard let baseline = stageBaselines[stage] else { return }
        pushUndo(); restore(baseline); lastChange = "Etapa restaurada"; applyPreview()
    }

    func restoreSelectedEye() {
        pushUndo(); mutateEye(selectedEye) { $0 = .neutral }
        lastChange = "Olho restaurado"; applyPreview()
    }

    func restoreAll() {
        pushUndo(); draft = .genericVRBox; draftRenderScale = VRCalibrationManager.defaultRenderScale
        lastChange = "Padrão seguro restaurado"; applyPreview()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        restore(previous); lastChange = "Alteração desfeita"; applyPreview()
    }

    func toggleCompare() {
        compareBefore.toggle()
        if compareBefore { manager.preview(profile: original.profile, renderScale: original.renderScale) }
        else { applyPreview() }
    }

    func cancel() {
        compareBefore = false
        manager.preview(profile: original.profile, renderScale: original.renderScale)
    }

    func save() {
        compareBefore = false
        manager.commit(profile: draft, renderScale: draftRenderScale, completed: true)
    }

    func emergencyRestore() {
        draft = .genericVRBox; draftRenderScale = VRCalibrationManager.defaultRenderScale
        manager.resetDefaults(); compareBefore = false
    }

    private var snapshot: Snapshot { Snapshot(profile: draft, renderScale: draftRenderScale) }
    private func pushUndo() {
        undoStack.append(snapshot)
        if undoStack.count > 32 { undoStack.removeFirst() }
    }
    private func restore(_ value: Snapshot) { draft = value.profile; draftRenderScale = value.renderScale }
    private func applyPreview() {
        guard !compareBefore else { return }
        draft = draft.validated()
        manager.preview(profile: draft, renderScale: draftRenderScale)
    }
    private func mutateEye(_ target: VisionCalibrationEye, _ body: (inout EyeCalibration) -> Void) {
        if target == .left { body(&draft.leftEye) }
        else { body(&draft.rightEye) }
        draft = draft.validated()
    }
}
