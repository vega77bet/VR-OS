import SwiftUI

/// Slightly bowed four-sided headset aperture, approximating the optical
/// masks in the supplied dual-eye camera screenshot. The outer background
/// stays black. This is ONLY a display mask, not optical lens correction.
struct VRLensAperture: Shape {
    var curvature: CGFloat = 0.85

    var animatableData: CGFloat {
        get { curvature }
        set { curvature = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = max(0, min(1, curvature))
        if c < 0.001 { return Path(rect) }
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        let dx = w * 0.055 * c
        let dy = h * 0.057 * c
        let bulgeX = w * 0.06 * c
        let bulgeY = h * 0.06 * c

        var shape = Path()
        shape.move(to: CGPoint(x: x + dx, y: y + dy))
        shape.addQuadCurve(
            to: CGPoint(x: x + w - dx, y: y + dy),
            control: CGPoint(x: x + w / 2, y: y - bulgeY))
        shape.addQuadCurve(
            to: CGPoint(x: x + w - dx, y: y + h - dy),
            control: CGPoint(x: x + w + bulgeX, y: y + h / 2))
        shape.addQuadCurve(
            to: CGPoint(x: x + dx, y: y + h - dy),
            control: CGPoint(x: x + w / 2, y: y + h + bulgeY))
        shape.addQuadCurve(
            to: CGPoint(x: x + dx, y: y + dy),
            control: CGPoint(x: x - bulgeX, y: y + h / 2))
        shape.closeSubpath()
        return shape
    }
}
