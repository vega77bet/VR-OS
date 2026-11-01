import Foundation
import simd

/// Parameters applied to one physical half of the SBS image. Offsets and
/// optical centers are normalized coordinates inside that eye's texture
/// (positive X is right, positive Y is down in the Metal texture).
struct EyeCalibration: Codable, Equatable {
    var horizontalOffset: Float
    var verticalOffset: Float
    var horizontalScale: Float
    var verticalScale: Float
    var rotationDegrees: Float
    var opticalCenterX: Float
    var opticalCenterY: Float
    var radialK1: Float
    var radialK2: Float
    var radialK3: Float
    var tangentialP1: Float
    var tangentialP2: Float
    var chromaticRedScale: Float
    var chromaticBlueScale: Float
    var distortionStrength: Float

    static let neutral = EyeCalibration(
        horizontalOffset: 0, verticalOffset: 0,
        horizontalScale: 1, verticalScale: 1, rotationDegrees: 0,
        opticalCenterX: 0.5, opticalCenterY: 0.5,
        radialK1: 0.18, radialK2: 0.04, radialK3: 0,
        tangentialP1: 0, tangentialP2: 0,
        chromaticRedScale: 1, chromaticBlueScale: 1,
        distortionStrength: 0)

    func validated() -> EyeCalibration {
        var result = self
        result.horizontalOffset = Self.clamp(horizontalOffset, -0.08...0.08, 0)
        result.verticalOffset = Self.clamp(verticalOffset, -0.08...0.08, 0)
        // Keep the range wide enough to read old VR-OS profiles (which allowed
        // a 1.30 scale), while the guided UI uses much smaller increments.
        result.horizontalScale = Self.clamp(horizontalScale, 0.85...1.30, 1)
        result.verticalScale = Self.clamp(verticalScale, 0.85...1.30, 1)
        result.rotationDegrees = Self.clamp(rotationDegrees, -3...3, 0)
        result.opticalCenterX = Self.clamp(opticalCenterX, 0.35...0.65, 0.5)
        result.opticalCenterY = Self.clamp(opticalCenterY, 0.35...0.65, 0.5)
        result.radialK1 = Self.clamp(radialK1, -0.5...0.5, 0.18)
        // A value below -0.5 is the sentinel produced by the legacy profile
        // validator for an invalid K2. Moderate negative values remain valid
        // for the new inverse-distortion model and are covered by tests.
        result.radialK2 = radialK2.isFinite && radialK2 < -0.5
            ? 0 : Self.clamp(radialK2, -0.25...0.25, 0.04)
        result.radialK3 = Self.clamp(radialK3, -0.1...0.1, 0)
        result.tangentialP1 = Self.clamp(tangentialP1, -0.05...0.05, 0)
        result.tangentialP2 = Self.clamp(tangentialP2, -0.05...0.05, 0)
        result.chromaticRedScale = Self.clamp(chromaticRedScale, 0.98...1.02, 1)
        result.chromaticBlueScale = Self.clamp(chromaticBlueScale, 0.98...1.02, 1)
        result.distortionStrength = Self.clamp(distortionStrength, 0...1, 0)
        return result
    }

    private static func clamp(_ value: Float, _ range: ClosedRange<Float>, _ fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum VisionCalibrationEye: String, CaseIterable, Codable, Equatable {
    case left, right
    var title: String { self == .left ? "Olho esquerdo" : "Olho direito" }
}

enum VisionCalibrationParameter: String, CaseIterable, Codable, Equatable {
    case horizontalOffset, verticalOffset, horizontalScale, verticalScale
    case rotationDegrees, opticalCenterX, opticalCenterY
    case radialK1, radialK2, radialK3, tangentialP1, tangentialP2
    case chromaticRedScale, chromaticBlueScale, distortionStrength

    var title: String {
        switch self {
        case .horizontalOffset: return "Posição horizontal"
        case .verticalOffset: return "Posição vertical"
        case .horizontalScale: return "Escala horizontal"
        case .verticalScale: return "Escala vertical"
        case .rotationDegrees: return "Rotação"
        case .opticalCenterX: return "Centro óptico X"
        case .opticalCenterY: return "Centro óptico Y"
        case .radialK1: return "Distorção radial K1"
        case .radialK2: return "Distorção radial K2"
        case .radialK3: return "Distorção radial K3"
        case .tangentialP1: return "Distorção tangencial P1"
        case .tangentialP2: return "Distorção tangencial P2"
        case .chromaticRedScale: return "Cromática vermelho"
        case .chromaticBlueScale: return "Cromática azul"
        case .distortionStrength: return "Intensidade da lente"
        }
    }
}

enum VisionCalibrationStage: Int, CaseIterable, Codable, Equatable {
    case preparation, leftAlignment, rightAlignment, fusion, scale
    case opticalCenter, distortion, chromatic, readability, validation
    var title: String {
        switch self {
        case .preparation: return "Preparar visão"
        case .leftAlignment: return "Alinhar olho esquerdo"
        case .rightAlignment: return "Alinhar olho direito"
        case .fusion: return "Fusão binocular"
        case .scale: return "Escala e rotação"
        case .opticalCenter: return "Centro óptico"
        case .distortion: return "Grade e distorção"
        case .chromatic: return "Cores nas bordas"
        case .readability: return "Teste de legibilidade"
        case .validation: return "Validar e salvar"
        }
    }
}

/// A persistent named calibration profile. It contains no biometric claim:
/// completion means only that the user accepted the visual result manually.
struct VisionCalibrationProfile: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1
    var id: String
    var name: String
    var schemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var displayIdentifier: String?
    var calibrationCompleted: Bool
    var leftEye: EyeCalibration
    var rightEye: EyeCalibration
    var ipdMeters: Float
    var verticalFOVDegrees: Float
    var leftProjectionCenterX: Float
    var rightProjectionCenterX: Float
    var renderScale: Float

    static func generic() -> VisionCalibrationProfile {
        let now = Date()
        return VisionCalibrationProfile(id: "generic-vr-box-v1", name: "VR Box — padrão seguro",
                                        schemaVersion: currentSchemaVersion, createdAt: now,
                                        updatedAt: now, displayIdentifier: nil,
                                        calibrationCompleted: false,
                                        leftEye: .neutral, rightEye: .neutral,
                                        ipdMeters: 0.064, verticalFOVDegrees: 90,
                                        leftProjectionCenterX: 0.5, rightProjectionCenterX: 0.5,
                                        renderScale: 1)
    }

    func validated() -> VisionCalibrationProfile {
        var result = self
        let fallback = Self.generic()
        if result.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.id = fallback.id }
        if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.name = fallback.name }
        result.schemaVersion = Self.currentSchemaVersion
        result.leftEye = leftEye.validated()
        result.rightEye = rightEye.validated()
        result.ipdMeters = Self.clamp(ipdMeters, 0.05...0.075, fallback.ipdMeters)
        result.verticalFOVDegrees = Self.clamp(verticalFOVDegrees, 60...110, fallback.verticalFOVDegrees)
        result.leftProjectionCenterX = Self.clamp(leftProjectionCenterX, 0.35...0.65, 0.5)
        result.rightProjectionCenterX = Self.clamp(rightProjectionCenterX, 0.35...0.65, 0.5)
        result.renderScale = Self.clamp(renderScale, 0.5...1, 1)
        return result
    }

    private static func clamp(_ value: Float, _ range: ClosedRange<Float>, _ fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// CPU reference implementation used by tests and documentation. The Metal
/// compositor follows this exact inverse mapping for each destination pixel.
enum VisionCalibrationMath {
    struct Sample: Equatable {
        var uv: SIMD2<Float>
        var valid: Bool
    }

    static func sourceUV(destinationUV: SIMD2<Float>, aspect: Float,
                         eye: EyeCalibration, channelScale: Float = 1) -> Sample {
        let safeAspect = (aspect.isFinite && aspect > 0.0001) ? aspect : 1
        let safeEye = eye.validated()
        let safeChannelScale = channelScale.isFinite ? min(max(channelScale, 0.5), 1.5) : 1
        let center = SIMD2(safeEye.opticalCenterX, safeEye.opticalCenterY)
        guard destinationUV.x.isFinite, destinationUV.y.isFinite else {
            return Sample(uv: .zero, valid: false)
        }

        // Image placement is inverted because this function maps destination
        // pixels back into the source texture.
        var p = destinationUV - center - SIMD2(safeEye.horizontalOffset, safeEye.verticalOffset)
        let c = cos(-safeEye.rotationDegrees * .pi / 180)
        let s = sin(-safeEye.rotationDegrees * .pi / 180)
        p = SIMD2(c * p.x - s * p.y, s * p.x + c * p.y)
        var n = SIMD2(2 * p.x * safeAspect, 2 * p.y)
        let r2 = simd_dot(n, n)
        let radial = 1 + safeEye.distortionStrength *
            (safeEye.radialK1 * r2 + safeEye.radialK2 * r2 * r2 + safeEye.radialK3 * r2 * r2 * r2)
        let x = n.x
        let y = n.y
        let tangentialX = 2 * safeEye.tangentialP1 * x * y + safeEye.tangentialP2 * (r2 + 2 * x * x)
        let tangentialY = safeEye.tangentialP1 * (r2 + 2 * y * y) + 2 * safeEye.tangentialP2 * x * y
        n = SIMD2((x * radial + tangentialX) * safeChannelScale,
                  (y * radial + tangentialY) * safeChannelScale)
        // Image scale is applied after the optical warp. This is the ordering
        // used by the original compositor and keeps saved profiles backward
        // compatible while preserving inverse sampling.
        let corrected = center + SIMD2(n.x / (2 * safeAspect), n.y / 2)
        let uv = center + (corrected - center) /
            SIMD2(max(safeEye.horizontalScale, 0.001), max(safeEye.verticalScale, 0.001))
        return Sample(uv: uv, valid: uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1)
    }

    static func isNeutral(_ eye: EyeCalibration) -> Bool {
        eye.horizontalOffset == 0 && eye.verticalOffset == 0 &&
        eye.horizontalScale == 1 && eye.verticalScale == 1 &&
        abs(eye.rotationDegrees) < 0.00001 && eye.opticalCenterX == 0.5 && eye.opticalCenterY == 0.5 &&
        eye.distortionStrength == 0 && eye.tangentialP1 == 0 && eye.tangentialP2 == 0 &&
        eye.chromaticRedScale == 1 && eye.chromaticBlueScale == 1
    }
}
