import Combine
import Foundation

@MainActor
final class InteractionPreferences: ObservableObject {
    static let persistenceKey = "vr-os-2.interaction.v1"
    @Published var inputMode: InteractionInputMode { didSet { persist() } }
    @Published var pointerMode: ControllerPointerMode { didSet { persist() } }
    @Published var motionInvertX: Bool { didSet { persist() } }
    @Published var motionInvertY: Bool { didSet { persist() } }
    @Published var motionSwapAxes: Bool { didSet { persist() } }
    @Published var sensitivity: Float {
        didSet { sensitivity = Self.safe(sensitivity, within: 0.2...2.5, fallback: 0.9); persist() }
    }
    @Published var dwellDuration: Double {
        didSet {
            dwellDuration = dwellDuration.isFinite ? min(max(dwellDuration, 0.6), 2) : 1
            persist()
        }
    }
    @Published var panelDistance: Float {
        didSet { panelDistance = Self.safe(panelDistance, within: 1.6...3.5, fallback: 2.3); persist() }
    }
    @Published var mapping: ControllerMapping { didSet { persist() } }
    private let defaults: UserDefaults
    private struct Stored: Codable {
        var version = 1
        var inputMode: InteractionInputMode = .automatic
        var pointerMode: ControllerPointerMode = .analog
        var motionInvertX = false
        var motionInvertY = false
        var motionSwapAxes = false
        var sensitivity: Float = 0.9
        var dwellDuration: Double = 1
        var panelDistance: Float = 2.3
        var mapping: ControllerMapping = .defaults
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.persistenceKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        let saved = decoded?.version == 1 ? decoded! : Stored()
        inputMode = saved.inputMode
        pointerMode = saved.pointerMode
        motionInvertX = saved.motionInvertX
        motionInvertY = saved.motionInvertY
        motionSwapAxes = saved.motionSwapAxes
        sensitivity = Self.safe(saved.sensitivity, within: 0.2...2.5, fallback: 0.9)
        dwellDuration = saved.dwellDuration.isFinite ? min(max(saved.dwellDuration, 0.6), 2) : 1
        panelDistance = Self.safe(saved.panelDistance, within: 1.6...3.5, fallback: 2.3)
        mapping = saved.mapping
        persist()
    }

    func resetDefaults() {
        inputMode = .automatic; pointerMode = .analog; sensitivity = 0.9
        motionInvertX = false; motionInvertY = false; motionSwapAxes = false
        dwellDuration = 1; panelDistance = 2.3; mapping = .defaults
    }

    private static func safe(_ value: Float, within range: ClosedRange<Float>, fallback: Float) -> Float {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    private func persist() {
        let saved = Stored(inputMode: inputMode, pointerMode: pointerMode,
                           motionInvertX: motionInvertX, motionInvertY: motionInvertY, motionSwapAxes: motionSwapAxes,
                           sensitivity: sensitivity,
                           dwellDuration: dwellDuration, panelDistance: panelDistance, mapping: mapping)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.persistenceKey) }
    }
}
