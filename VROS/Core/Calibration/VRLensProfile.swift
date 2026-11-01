import Foundation

/// Optical and binocular configuration consumed by both the stereo camera and
/// the per-eye Metal compositor. Legacy scalar accessors remain as aliases for
/// profiles created by earlier VR-OS builds.
struct VRLensProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var schemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var displayIdentifier: String?
    var calibrationCompleted: Bool
    var ipdMeters: Float
    var verticalFOVDegrees: Float
    var leftProjectionCenterX: Float
    var rightProjectionCenterX: Float
    var leftEye: EyeCalibration
    var rightEye: EyeCalibration

    var leftCenterX: Float {
        get { leftProjectionCenterX }
        set { leftProjectionCenterX = newValue; leftEye.opticalCenterX = newValue }
    }
    var rightCenterX: Float {
        get { rightProjectionCenterX }
        set { rightProjectionCenterX = newValue; rightEye.opticalCenterX = newValue }
    }
    var leftScale: Float {
        get { leftEye.horizontalScale }
        set { leftEye.horizontalScale = newValue; leftEye.verticalScale = newValue }
    }
    var rightScale: Float {
        get { rightEye.horizontalScale }
        set { rightEye.horizontalScale = newValue; rightEye.verticalScale = newValue }
    }
    var distortionK1: Float {
        get { (leftEye.radialK1 + rightEye.radialK1) * 0.5 }
        set { leftEye.radialK1 = newValue; rightEye.radialK1 = newValue }
    }
    var distortionK2: Float {
        get { (leftEye.radialK2 + rightEye.radialK2) * 0.5 }
        set { leftEye.radialK2 = newValue; rightEye.radialK2 = newValue }
    }
    var distortionStrength: Float {
        get { (leftEye.distortionStrength + rightEye.distortionStrength) * 0.5 }
        set { leftEye.distortionStrength = newValue; rightEye.distortionStrength = newValue }
    }

    static let genericVRBox: VRLensProfile = {
        let now = Date()
        return VRLensProfile(id: "generic-vr-box-v1", name: "VR Box — provisório",
                             schemaVersion: VisionCalibrationProfile.currentSchemaVersion,
                             createdAt: now, updatedAt: now, displayIdentifier: nil,
                             calibrationCompleted: false, ipdMeters: 0.064,
                             verticalFOVDegrees: 90, leftProjectionCenterX: 0.5,
                             rightProjectionCenterX: 0.5, leftEye: .neutral,
                             rightEye: .neutral)
    }()

    static let presets = [genericVRBox]

    func validated() -> VRLensProfile {
        var result = self
        let fallback = Self.genericVRBox
        if result.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.id = fallback.id }
        if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.name = fallback.name }
        result.schemaVersion = VisionCalibrationProfile.currentSchemaVersion
        result.ipdMeters = Self.clamp(ipdMeters, to: 0.05...0.075, fallback: fallback.ipdMeters)
        result.verticalFOVDegrees = Self.clamp(verticalFOVDegrees, to: 60...110, fallback: fallback.verticalFOVDegrees)
        result.leftProjectionCenterX = Self.clamp(leftProjectionCenterX, to: 0.35...0.65, fallback: 0.5)
        result.rightProjectionCenterX = Self.clamp(rightProjectionCenterX, to: 0.35...0.65, fallback: 0.5)
        result.leftEye = leftEye.validated()
        result.rightEye = rightEye.validated()
        return result
    }

    init(id: String, name: String, schemaVersion: Int = VisionCalibrationProfile.currentSchemaVersion,
         createdAt: Date = Date(), updatedAt: Date = Date(), displayIdentifier: String? = nil,
         calibrationCompleted: Bool = false, ipdMeters: Float, verticalFOVDegrees: Float,
         leftProjectionCenterX: Float, rightProjectionCenterX: Float,
         leftEye: EyeCalibration, rightEye: EyeCalibration) {
        self.id = id; self.name = name; self.schemaVersion = schemaVersion
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.displayIdentifier = displayIdentifier; self.calibrationCompleted = calibrationCompleted
        self.ipdMeters = ipdMeters; self.verticalFOVDegrees = verticalFOVDegrees
        self.leftProjectionCenterX = leftProjectionCenterX
        self.rightProjectionCenterX = rightProjectionCenterX
        self.leftEye = leftEye; self.rightEye = rightEye
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, schemaVersion, createdAt, updatedAt, displayIdentifier, calibrationCompleted
        case ipdMeters, verticalFOVDegrees, leftCenterX, rightCenterX, leftScale, rightScale
        case distortionK1, distortionK2, distortionStrength, leftProjectionCenterX, rightProjectionCenterX
        case leftEye, rightEye
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let oldLeftCenter = try c.decodeIfPresent(Float.self, forKey: .leftCenterX) ??
            (try c.decodeIfPresent(Float.self, forKey: .leftProjectionCenterX) ?? 0.5)
        let oldRightCenter = try c.decodeIfPresent(Float.self, forKey: .rightCenterX) ??
            (try c.decodeIfPresent(Float.self, forKey: .rightProjectionCenterX) ?? 0.5)
        let oldLeftScale = try c.decodeIfPresent(Float.self, forKey: .leftScale) ?? 1
        let oldRightScale = try c.decodeIfPresent(Float.self, forKey: .rightScale) ?? 1
        let oldK1 = try c.decodeIfPresent(Float.self, forKey: .distortionK1) ?? 0.18
        let oldK2 = try c.decodeIfPresent(Float.self, forKey: .distortionK2) ?? 0.04
        let oldStrength = try c.decodeIfPresent(Float.self, forKey: .distortionStrength) ?? 0
        let leftFallback = EyeCalibration(horizontalOffset: 0, verticalOffset: 0,
                                          horizontalScale: oldLeftScale, verticalScale: oldLeftScale,
                                          rotationDegrees: 0, opticalCenterX: oldLeftCenter, opticalCenterY: 0.5,
                                          radialK1: oldK1, radialK2: oldK2, radialK3: 0,
                                          tangentialP1: 0, tangentialP2: 0,
                                          chromaticRedScale: 1, chromaticBlueScale: 1,
                                          distortionStrength: oldStrength)
        let rightFallback = EyeCalibration(horizontalOffset: 0, verticalOffset: 0,
                                           horizontalScale: oldRightScale, verticalScale: oldRightScale,
                                           rotationDegrees: 0, opticalCenterX: oldRightCenter, opticalCenterY: 0.5,
                                           radialK1: oldK1, radialK2: oldK2, radialK3: 0,
                                           tangentialP1: 0, tangentialP2: 0,
                                           chromaticRedScale: 1, chromaticBlueScale: 1,
                                           distortionStrength: oldStrength)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Self.genericVRBox.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? Self.genericVRBox.name
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        displayIdentifier = try c.decodeIfPresent(String.self, forKey: .displayIdentifier)
        calibrationCompleted = try c.decodeIfPresent(Bool.self, forKey: .calibrationCompleted) ?? false
        ipdMeters = try c.decodeIfPresent(Float.self, forKey: .ipdMeters) ?? 0.064
        verticalFOVDegrees = try c.decodeIfPresent(Float.self, forKey: .verticalFOVDegrees) ?? 90
        leftProjectionCenterX = oldLeftCenter
        rightProjectionCenterX = oldRightCenter
        leftEye = try c.decodeIfPresent(EyeCalibration.self, forKey: .leftEye) ?? leftFallback
        rightEye = try c.decodeIfPresent(EyeCalibration.self, forKey: .rightEye) ?? rightFallback
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(createdAt, forKey: .createdAt); try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(displayIdentifier, forKey: .displayIdentifier)
        try c.encode(calibrationCompleted, forKey: .calibrationCompleted)
        try c.encode(ipdMeters, forKey: .ipdMeters); try c.encode(verticalFOVDegrees, forKey: .verticalFOVDegrees)
        try c.encode(leftProjectionCenterX, forKey: .leftCenterX)
        try c.encode(rightProjectionCenterX, forKey: .rightCenterX)
        try c.encode(leftEye.horizontalScale, forKey: .leftScale)
        try c.encode(rightEye.horizontalScale, forKey: .rightScale)
        try c.encode(distortionK1, forKey: .distortionK1)
        try c.encode(distortionK2, forKey: .distortionK2)
        try c.encode(distortionStrength, forKey: .distortionStrength)
        try c.encode(leftProjectionCenterX, forKey: .leftProjectionCenterX)
        try c.encode(rightProjectionCenterX, forKey: .rightProjectionCenterX)
        try c.encode(leftEye, forKey: .leftEye); try c.encode(rightEye, forKey: .rightEye)
    }

    static func clamp(_ value: Float, to range: ClosedRange<Float>, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
