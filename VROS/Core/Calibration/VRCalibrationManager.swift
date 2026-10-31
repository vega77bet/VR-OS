import Combine
import Foundation

@MainActor
final class VRCalibrationManager: ObservableObject {
    static let persistenceKey = "vr-os-2.optics.v1"
    static let defaultRenderScale: Float = 0.85

    @Published var profile: VRLensProfile {
        didSet {
            let safe = profile.validated()
            if profile != safe { profile = safe }
            persist()
        }
    }

    /// Fraction of native pixel dimensions, independent of per-eye optical scale.
    @Published var renderScale: Float {
        didSet {
            let safe = Self.validatedRenderScale(renderScale)
            if renderScale != safe { renderScale = safe }
            persist()
        }
    }

    private let defaults: UserDefaults

    private struct Preferences: Codable {
        var version: Int
        var profile: VRLensProfile
        var renderScale: Float
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.persistenceKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data),
           saved.version == 1 {
            profile = saved.profile.validated()
            renderScale = Self.validatedRenderScale(saved.renderScale)
        } else {
            profile = .genericVRBox
            renderScale = Self.defaultRenderScale
        }
        // Replace corrupt/out-of-range stored data with a complete valid envelope.
        persist()
    }

    func resetDefaults() {
        profile = .genericVRBox
        renderScale = Self.defaultRenderScale
    }

    private static func validatedRenderScale(_ value: Float) -> Float {
        VRLensProfile.clamp(value, to: 0.5...1, fallback: defaultRenderScale)
    }

    private func persist() {
        let preferences = Preferences(version: 1, profile: profile, renderScale: renderScale)
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }
}
