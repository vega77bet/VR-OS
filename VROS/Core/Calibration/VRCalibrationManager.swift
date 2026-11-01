import Combine
import Foundation

@MainActor
final class VRCalibrationManager: ObservableObject {
    static let persistenceKey = "vr-os-2.optics.v1"
    /// Full native resolution is the safe default for legibility. Users can
    /// lower it in the wizard when thermal or frame-time measurements require.
    static let defaultRenderScale: Float = 1
    static let currentPersistenceVersion = 3

    @Published var profile: VRLensProfile {
        didSet {
            let safe = profile.validated()
            if profile != safe { profile = safe; return }
            guard !restoring else { return }
            syncActiveProfile()
            persist()
        }
    }

    /// Fraction of native pixel dimensions, independent of per-eye optical scale.
    @Published var renderScale: Float {
        didSet {
            let safe = Self.validatedRenderScale(renderScale)
            if renderScale != safe { renderScale = safe; return }
            guard !restoring else { return }
            syncActiveProfile()
            persist()
        }
    }

    @Published private(set) var profiles: [VisionCalibrationProfile]
    @Published private(set) var activeProfileID: String
    private let defaults: UserDefaults
    private var restoring = false

    private struct Stored: Codable {
        var version: Int
        var profile: VRLensProfile
        var renderScale: Float
        var profiles: [VisionCalibrationProfile]?
        var activeProfileID: String?

        init(version: Int, profile: VRLensProfile, renderScale: Float,
             profiles: [VisionCalibrationProfile]?, activeProfileID: String?) {
            self.version = version; self.profile = profile; self.renderScale = renderScale
            self.profiles = profiles; self.activeProfileID = activeProfileID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
            profile = try c.decode(VRLensProfile.self, forKey: .profile)
            renderScale = try c.decodeIfPresent(Float.self, forKey: .renderScale) ?? 1
            profiles = try c.decodeIfPresent([VisionCalibrationProfile].self, forKey: .profiles)
            activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
        }

        private enum CodingKeys: String, CodingKey { case version, profile, renderScale, profiles, activeProfileID }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loadedProfile = VRLensProfile.genericVRBox
        var loadedScale = Self.defaultRenderScale
        var loadedProfiles: [VisionCalibrationProfile] = []
        var loadedActiveID = loadedProfile.id
        if let data = defaults.data(forKey: Self.persistenceKey),
           let saved = try? JSONDecoder().decode(Stored.self, from: data),
           (1...Self.currentPersistenceVersion).contains(saved.version) {
            loadedProfile = Self.migrate(saved.profile, sourceVersion: saved.version).validated()
            // The pre-profiles builds used 0.85 as their untouched default,
            // which made small atlas text shimmer after upscaling. Migrate
            // only that legacy envelope; v3 preserves an explicit user value.
            loadedScale = saved.version <= 2 && abs(saved.renderScale - 0.85) < 0.0001
                ? Self.defaultRenderScale : Self.validatedRenderScale(saved.renderScale)
            loadedProfiles = (saved.profiles ?? []).map { $0.validated() }
            loadedActiveID = saved.activeProfileID ?? loadedProfile.id
        }
        if loadedProfiles.isEmpty {
            loadedProfiles = [Self.vision(from: loadedProfile, renderScale: loadedScale)]
        }
        if !loadedProfiles.contains(where: { $0.id == loadedActiveID }) {
            loadedActiveID = loadedProfiles.first?.id ?? VRLensProfile.genericVRBox.id
        }
        self.profiles = loadedProfiles
        self.activeProfileID = loadedActiveID
        self.restoring = true
        self.profile = loadedProfile
        self.renderScale = loadedScale
        self.restoring = false
        persist()
    }

    func resetDefaults() {
        restoring = true
        profile = .genericVRBox
        renderScale = Self.defaultRenderScale
        restoring = false
        activeProfileID = VRLensProfile.genericVRBox.id
        let generic = Self.vision(from: profile, renderScale: renderScale)
        if let index = profiles.firstIndex(where: { $0.id == generic.id }) { profiles[index] = generic }
        else { profiles.insert(generic, at: 0) }
        persist()
    }

    /// Applies a draft immediately to the real compositor. A wizard can call
    /// this every time the user changes a control without recreating pipelines.
    func preview(profile draft: VRLensProfile, renderScale scale: Float? = nil) {
        restoring = true
        profile = draft.validated()
        if let scale { renderScale = Self.validatedRenderScale(scale) }
        restoring = false
    }

    func commit(profile draft: VRLensProfile, renderScale scale: Float? = nil,
                completed: Bool = true) {
        var value = draft.validated()
        value.calibrationCompleted = completed
        value.updatedAt = Date()
        restoring = true
        profile = value
        if let scale { renderScale = Self.validatedRenderScale(scale) }
        restoring = false
        syncActiveProfile()
        persist()
    }

    func update(_ mutate: (inout VRLensProfile) -> Void) {
        var value = profile
        mutate(&value)
        preview(profile: value)
        syncActiveProfile(); persist()
    }

    func selectProfile(id: String) {
        guard let selected = profiles.first(where: { $0.id == id }) else { return }
        restoring = true
        activeProfileID = selected.id
        profile = Self.lens(from: selected)
        renderScale = Self.validatedRenderScale(selected.renderScale)
        restoring = false
        persist()
    }

    @discardableResult
    func createProfile(name: String, from source: VRLensProfile? = nil) -> String {
        let now = Date()
        let id = "vision-\(UUID().uuidString.lowercased())"
        var value = source ?? profile
        value.id = id; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Minha calibração" : name
        value.createdAt = now; value.updatedAt = now; value.calibrationCompleted = false
        let entry = Self.vision(from: value, renderScale: renderScale)
        profiles.append(entry); activeProfileID = id
        restoring = true; profile = value; restoring = false
        persist()
        return id
    }

    @discardableResult
    func duplicateActiveProfile(name: String? = nil) -> String {
        createProfile(name: name ?? "Cópia de \(profile.name)", from: profile)
    }

    func renameActiveProfile(_ name: String) {
        guard activeProfileID != "generic-vr-box-v1", !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        profile.name = name
        profile.updatedAt = Date()
        syncActiveProfile(); persist()
    }

    func deleteProfile(id: String) {
        guard id != VRLensProfile.genericVRBox.id, profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { selectProfile(id: profiles.first!.id) }
        persist()
    }

    func restoreActiveProfile() {
        guard let stored = profiles.first(where: { $0.id == activeProfileID }) else { resetDefaults(); return }
        selectProfile(id: stored.id)
    }

    private func syncActiveProfile() {
        guard !restoring else { return }
        let entry = Self.vision(from: profile, renderScale: renderScale)
        if let index = profiles.firstIndex(where: { $0.id == activeProfileID }) { profiles[index] = entry }
        else { profiles.append(entry); activeProfileID = entry.id }
    }

    private static func vision(from profile: VRLensProfile, renderScale: Float) -> VisionCalibrationProfile {
        VisionCalibrationProfile(id: profile.id, name: profile.name, schemaVersion: VisionCalibrationProfile.currentSchemaVersion,
                                 createdAt: profile.createdAt, updatedAt: profile.updatedAt,
                                 displayIdentifier: profile.displayIdentifier,
                                 calibrationCompleted: profile.calibrationCompleted,
                                 leftEye: profile.leftEye, rightEye: profile.rightEye,
                                 ipdMeters: profile.ipdMeters, verticalFOVDegrees: profile.verticalFOVDegrees,
                                 leftProjectionCenterX: profile.leftProjectionCenterX,
                                 rightProjectionCenterX: profile.rightProjectionCenterX,
                                 renderScale: renderScale).validated()
    }

    private static func lens(from vision: VisionCalibrationProfile) -> VRLensProfile {
        VRLensProfile(id: vision.id, name: vision.name, schemaVersion: vision.schemaVersion,
                      createdAt: vision.createdAt, updatedAt: vision.updatedAt,
                      displayIdentifier: vision.displayIdentifier,
                      calibrationCompleted: vision.calibrationCompleted,
                      ipdMeters: vision.ipdMeters, verticalFOVDegrees: vision.verticalFOVDegrees,
                      leftProjectionCenterX: vision.leftProjectionCenterX,
                      rightProjectionCenterX: vision.rightProjectionCenterX,
                      leftEye: vision.leftEye, rightEye: vision.rightEye).validated()
    }

    private static func migrate(_ value: VRLensProfile, sourceVersion: Int) -> VRLensProfile {
        var result = value
        if sourceVersion <= 2, result.id == VRLensProfile.genericVRBox.id,
           abs(result.distortionStrength - 0.5) < 0.0001 {
            result.distortionStrength = VRLensProfile.genericVRBox.distortionStrength
        }
        return result
    }

    private static func validatedRenderScale(_ value: Float) -> Float {
        VRLensProfile.clamp(value, to: 0.5...1, fallback: defaultRenderScale)
    }

    private func persist() {
        let saved = Stored(version: Self.currentPersistenceVersion, profile: profile,
                           renderScale: renderScale, profiles: profiles,
                           activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }
}
