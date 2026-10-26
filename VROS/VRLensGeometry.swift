import CoreGraphics
import Foundation

/// Positions two headset apertures using the COMPLETE landscape screen.
/// Unlike a 50/50 HStack, their optical centres are adjustable and may sit
/// closer to the middle, as on real mobile VR viewers.
enum VRLensProfile: Int, CaseIterable {
    case reference = 0
    case wide = 1
    case compact = 2

    var name: String {
        switch self {
        case .reference: return "Referência"
        case .wide: return "VR Box +"
        case .compact: return "Compacto"
        }
    }

    /// Fractions of the TOTAL screen, measured from the user's screenshot
    /// for reference: aperture ≈ 29% screen width, 60% screen height,
    /// centres ≈ 35% and 65% of screen width, Y ≈ 63% height.
    var fractions: (width: CGFloat, height: CGFloat,
                    separation: CGFloat, centreY: CGFloat) {
        switch self {
        case .reference: return (0.285, 0.60, 0.30, 0.625)
        case .wide: return (0.36, 0.87, 0.378, 0.50)
        case .compact: return (0.265, 0.66, 0.295, 0.54)
        }
    }
}

struct VRLensPlacement {
    let aperture: CGSize
    let left: CGPoint
    let right: CGPoint
    let gap: CGFloat
    let screen: CGSize
}

struct VRLensSettings: Equatable {
    var profile: VRLensProfile = .reference
    var scale: CGFloat = 1.0
    /// In units of total screen width. Positive increases optical separation.
    var spacing: CGFloat = 0
    /// In units of total screen height; negative moves apertures up.
    var verticalOffset: CGFloat = 0
    /// Digital passthrough zoom only, never changes the actual ultrawide lens.
    var cameraZoom: CGFloat = 1.0
    /// 0 = rectangular aperture, 1 = smoothly bowed lens-style aperture.
    var curvature: CGFloat = 0.85

    func placement(in screen: CGSize) -> VRLensPlacement {
        let w = max(1, screen.width)
        let h = max(1, screen.height)
        let p = profile.fractions
        // Clamp every adjustable parameter in this PURE layout calculation,
        // even if UserDefaults contains a corrupted/old setting.
        let effectiveScale = max(0.75, min(1.40, scale))
        let eyeW = min(w * 0.47, max(1, w * p.width * effectiveScale))
        let eyeH = min(h * 0.96, max(1, h * p.height * effectiveScale))
        let minimumGap = max(3, w * 0.005)
        let wantedSeparation = w * (p.separation +
            max(-0.075, min(0.12, spacing)))
        let separation = min(w - eyeW - 8,
                             max(eyeW + minimumGap, wantedSeparation))
        let centreY = max(eyeH / 2 + 2,
                          min(h - eyeH / 2 - 2,
                              h * (p.centreY +
                                   max(-0.16, min(0.16, verticalOffset)))))
        let left = CGPoint(x: w / 2 - separation / 2, y: centreY)
        let right = CGPoint(x: w / 2 + separation / 2, y: centreY)
        return VRLensPlacement(
            aperture: CGSize(width: eyeW, height: eyeH),
            left: left, right: right, gap: separation - eyeW,
            screen: screen)
    }

    mutating func choose(_ next: VRLensProfile) {
        profile = next
        scale = 1
        spacing = 0
        verticalOffset = 0
        cameraZoom = 1
        curvature = 0.85
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(profile.rawValue, forKey: "vros.lens.profile.v1")
        defaults.set(Double(scale), forKey: "vros.lens.size.v1")
        defaults.set(Double(spacing), forKey: "vros.lens.spacing.v1")
        defaults.set(Double(verticalOffset), forKey: "vros.lens.vertical.v1")
        defaults.set(Double(cameraZoom), forKey: "vros.lens.zoom.v1")
        defaults.set(Double(curvature), forKey: "vros.lens.curve.v1")
    }

    static func load() -> VRLensSettings {
        let defaults = UserDefaults.standard
        var value = VRLensSettings()
        if defaults.object(forKey: "vros.lens.profile.v1") != nil {
            value.profile = VRLensProfile(
                rawValue: defaults.integer(forKey: "vros.lens.profile.v1"))
                ?? .reference
        }
        if defaults.object(forKey: "vros.lens.size.v1") != nil {
            value.scale = CGFloat(defaults.double(forKey: "vros.lens.size.v1"))
        }
        if defaults.object(forKey: "vros.lens.spacing.v1") != nil {
            value.spacing = CGFloat(defaults.double(forKey: "vros.lens.spacing.v1"))
        }
        if defaults.object(forKey: "vros.lens.vertical.v1") != nil {
            value.verticalOffset = CGFloat(defaults.double(forKey: "vros.lens.vertical.v1"))
        }
        if defaults.object(forKey: "vros.lens.zoom.v1") != nil {
            value.cameraZoom = CGFloat(defaults.double(forKey: "vros.lens.zoom.v1"))
        }
        if defaults.object(forKey: "vros.lens.curve.v1") != nil {
            value.curvature = CGFloat(defaults.double(forKey: "vros.lens.curve.v1"))
        }
        value.scale = max(0.75, min(1.40, value.scale))
        value.spacing = max(-0.075, min(0.12, value.spacing))
        value.verticalOffset = max(-0.16, min(0.16, value.verticalOffset))
        value.cameraZoom = max(0.80, min(1.30, value.cameraZoom))
        value.curvature = max(0, min(1, value.curvature))
        return value
    }
}


/// Identical hit positions for the onscreen calibration controls and the
/// Vision pinch pointer (which never generates regular UIKit touch events).
enum VRLensMenuAction: Equatable {
    case close
    case profile(Int)
    case adjust(row: Int, direction: Int)
}

enum VRLensMenuGeometry {
    static let height: CGFloat = 219
    static let headerY: CGFloat = 8
    static let profileY: CGFloat = 35
    static let controlY: CGFloat = 62
    static let controlStep: CGFloat = 27
    static let controlCount = 5

    static func rect(in viewport: CGSize) -> CGRect {
        let width = min(viewport.width * 0.97, 320)
        let h = min(height, max(1, viewport.height - 4))
        return CGRect(x: (viewport.width - width) / 2,
                      y: (viewport.height - h) / 2,
                      width: width, height: h)
    }

    static func action(at point: CGPoint, viewport: CGSize)
        -> VRLensMenuAction? {
        let panel = rect(in: viewport)
        guard panel.contains(point) else { return .close }
        // On short eye viewports, scale the entire calibration panel down
        // without sacrificing a row. Convert the pinch back to design units.
        let scale = max(0.01, panel.height / height)
        let fullWidth = panel.width / scale
        let x = (point.x - panel.minX) / scale
        let y = (point.y - panel.minY) / scale

        if y >= headerY && y <= headerY + 24 {
            return x > fullWidth - 42 ? .close : nil
        }
        if y >= profileY && y <= profileY + 24 {
            let slot = Int((x - 8) / max(1, (fullWidth - 16) / 3))
            return .profile(max(0, min(2, slot)))
        }
        if y >= controlY {
            let row = Int((y - controlY) / controlStep)
            guard row >= 0, row < controlCount else { return nil }
            let rowOffset = y - (controlY + CGFloat(row) * controlStep)
            guard rowOffset <= 24 else { return nil }
            if x >= fullWidth - 90 && x < fullWidth - 65 {
                return .adjust(row: row, direction: -1)
            }
            if x >= fullWidth - 33 && x <= fullWidth - 8 {
                return .adjust(row: row, direction: 1)
            }
        }
        return nil
    }
}
