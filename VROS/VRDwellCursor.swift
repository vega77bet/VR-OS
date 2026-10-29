import SwiftUI

struct VRDwellCursor: View {
    let progress: CGFloat
    let reduceMotion: Bool

    private let diameter: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.48))
                .frame(width: diameter, height: diameter)
            Circle()
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
                .frame(width: diameter, height: diameter)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    progress >= 1 ? VRDS.Color.success : VRDS.Color.primary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter - 4, height: diameter - 4)
                .animation(reduceMotion ? nil : .linear(duration: 0.06),
                           value: progress)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            Circle()
                .stroke(VRDS.Color.primary.opacity(0.75), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
        .shadow(color: .black.opacity(0.82), radius: 5)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
