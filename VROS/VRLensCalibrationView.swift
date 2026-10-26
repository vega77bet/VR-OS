import SwiftUI

/// Compact, fully binocular VR Box settings surface. Extracted into its own
/// View to avoid SwiftUI's giant type-checking expression in VRHomeView.
struct VRLensCalibrationView: View {
    @Binding var lens: VRLensSettings
    @Binding var isOpen: Bool
    let viewport: CGSize

    private var frame: CGRect { VRLensMenuGeometry.rect(in: viewport) }
    private var interfaceScale: CGFloat {
        max(0.01, frame.height / VRLensMenuGeometry.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            heading
            presets
            calibrationRows
            Text("Zoom digital: acima de 100% corta a câmera.")
                .font(.system(size: 8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, height: 14)
        }
        .padding(8)
        .frame(width: frame.width / interfaceScale,
               height: VRLensMenuGeometry.height)
        .foregroundStyle(.white)
        .background(Color(white: 0.065).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(.cyan.opacity(0.65), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 8)
        .scaleEffect(interfaceScale)
    }

    private var heading: some View {
        HStack {
            Image(systemName: "viewfinder")
            Text("AJUSTE DO VISOR").tracking(0.4)
            Spacer(minLength: 2)
            Button { isOpen = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 34, height: 24)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10, weight: .bold))
        .frame(height: 24)
    }

    private var presets: some View {
        HStack(spacing: 3) {
            ForEach(VRLensProfile.allCases, id: \.rawValue) { profile in
                Button { lens.choose(profile) } label: {
                    Text(profile.name)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(lens.profile == profile
                                    ? Color.cyan.opacity(0.32)
                                    : Color.white.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 24)
    }

    private var calibrationRows: some View {
        VStack(spacing: 3) {
            control("Tamanho", "\(Int(lens.scale * 100))%", row: 0)
            control("IPD", "\(Int(lens.spacing * 1000))", row: 1)
            control("Altura", "\(Int(lens.verticalOffset * 100))%", row: 2)
            control("Zoom", "\(Int(lens.cameraZoom * 100))%", row: 3)
            control("Curva", "\(Int(lens.curvature * 100))%", row: 4)
        }
    }

    private func adjust(_ row: Int, _ direction: Int) {
        var next = lens
        let step = CGFloat(direction)
        switch row {
        case 0: next.scale = max(0.75, min(1.40, next.scale + step * 0.05))
        case 1: next.spacing = max(-0.075, min(0.12,
                                             next.spacing + step * 0.012))
        case 2: next.verticalOffset = max(-0.16, min(0.16,
                                                   next.verticalOffset + step * 0.015))
        case 3: next.cameraZoom = max(0.80, min(1.30,
                                              next.cameraZoom + step * 0.05))
        case 4: next.curvature = max(0, min(1,
                                          next.curvature + step * 0.125))
        default: return
        }
        lens = next
    }

    private func control(_ title: String, _ value: String, row: Int) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { adjust(row, -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 25, height: 24)
                    .background(.white.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .frame(width: 32)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Button { adjust(row, 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 25, height: 24)
                    .background(.white.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 24)
    }
}
