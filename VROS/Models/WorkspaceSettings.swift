import SwiftUI

final class WorkspaceSettings: ObservableObject {
    private let storage = UserDefaults.standard

    @Published var accentRaw: String {
        didSet { storage.set(accentRaw, forKey: "vros.accent") }
    }
    @Published var distance: Double {
        didSet { storage.set(distance, forKey: "vros.distance") }
    }
    @Published var windowSize: Double {
        didSet { storage.set(windowSize, forKey: "vros.windowSize") }
    }
    @Published var panelOpacity: Double {
        didSet { storage.set(panelOpacity, forKey: "vros.opacity") }
    }
    @Published var showTracking: Bool {
        didSet { storage.set(showTracking, forKey: "vros.showTracking") }
    }
    @Published var haptics: Bool {
        didSet { storage.set(haptics, forKey: "vros.haptics") }
    }
    @Published var animations: Bool {
        didSet { storage.set(animations, forKey: "vros.animations") }
    }

    var accent: AccentStyle {
        get { AccentStyle(rawValue: accentRaw) ?? .ice }
        set { accentRaw = newValue.rawValue }
    }

    init() {
        accentRaw = storage.string(forKey: "vros.accent") ?? AccentStyle.ice.rawValue
        distance = storage.object(forKey: "vros.distance") as? Double ?? 1.25
        windowSize = storage.object(forKey: "vros.windowSize") as? Double ?? 1.0
        panelOpacity = storage.object(forKey: "vros.opacity") as? Double ?? 0.95
        showTracking = storage.object(forKey: "vros.showTracking") as? Bool ?? true
        haptics = storage.object(forKey: "vros.haptics") as? Bool ?? true
        animations = storage.object(forKey: "vros.animations") as? Bool ?? true
    }

    func restoreDefaults() {
        accent = .ice
        distance = 1.25
        windowSize = 1.0
        panelOpacity = 0.95
        showTracking = true
        haptics = true
        animations = true
    }
}
