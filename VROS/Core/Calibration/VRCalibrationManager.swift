import Combine
import Foundation

@MainActor
final class VRCalibrationManager: ObservableObject {
    static let persistenceKey = "vr-os-2.optics.v1"
    static let defaultRenderScale: Float = 1.0

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
           saved.version == 1 || saved.version == 2 {
            var stored = saved.profile
            // Version 1 shipped with a provisional 50% warp. Migrate only an
            // untouched generic profile; preserve profiles users calibrated.
            if saved.version == 1,
               stored.id == VRLensProfile.genericVRBox.id,
               abs(stored.distortionStrength - 0.5) < 0.0001 {
                stored.distortionStrength = VRLensProfile.genericVRBox.distortionStrength
            }
            profile = stored.validated()
            // Older default 0.85 was downsampling text and panel edges. Upgrade
            // untouched default only; preserve intentional user adjustments.
            renderScale = abs(saved.renderScale - 0.85) < 0.0001 ? 1.0 : Self.validatedRenderScale(saved.renderScale)
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
        let preferences = Preferences(version: 2, profile: profile, renderScale: renderScale)
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }
}
