import Foundation

/// Eye centers use normalized coordinates in each eye's half of the screen.
/// These are calibration controls, not measured physical properties of a VR Box.
struct VRLensProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var ipdMeters: Float
    var verticalFOVDegrees: Float
    var leftCenterX: Float
    var rightCenterX: Float
    var leftScale: Float
    var rightScale: Float
    var distortionK1: Float
    var distortionK2: Float
    var distortionStrength: Float

    static let genericVRBox = VRLensProfile(
        id: "generic-vr-box-v1", name: "VR Box — provisório",
        ipdMeters: 0.064, verticalFOVDegrees: 90,
        leftCenterX: 0.5, rightCenterX: 0.5,
        leftScale: 1, rightScale: 1,
        distortionK1: 0.18, distortionK2: 0.04, distortionStrength: 0.5
    )

    /// New measured presets can be added here without changing the renderer.
    static let presets = [genericVRBox]

    func validated() -> VRLensProfile {
        var result = self
        let fallback = Self.genericVRBox
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.id = fallback.id }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.name = fallback.name }
        result.ipdMeters = Self.clamp(ipdMeters, to: 0.05...0.075, fallback: fallback.ipdMeters)
        result.verticalFOVDegrees = Self.clamp(verticalFOVDegrees, to: 60...110, fallback: fallback.verticalFOVDegrees)
        result.leftCenterX = Self.clamp(leftCenterX, to: 0.35...0.65, fallback: fallback.leftCenterX)
        result.rightCenterX = Self.clamp(rightCenterX, to: 0.35...0.65, fallback: fallback.rightCenterX)
        result.leftScale = Self.clamp(leftScale, to: 0.7...1.3, fallback: fallback.leftScale)
        result.rightScale = Self.clamp(rightScale, to: 0.7...1.3, fallback: fallback.rightScale)
        result.distortionK1 = Self.clamp(distortionK1, to: 0...0.5, fallback: fallback.distortionK1)
        result.distortionK2 = Self.clamp(distortionK2, to: 0...0.25, fallback: fallback.distortionK2)
        result.distortionStrength = Self.clamp(distortionStrength, to: 0...1, fallback: fallback.distortionStrength)
        return result
    }

    static func clamp(_ value: Float, to range: ClosedRange<Float>, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
