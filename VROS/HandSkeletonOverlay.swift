import SwiftUI

/// Draws the 21 Vision landmarks and 23 bones of the tracked hand in each eye.
/// Coordinates are camera-normalized; mapping applies the same crop as the pointer.
struct HandSkeletonOverlay: View {
    let hand: TrackedHand
    let map: (CGPoint) -> CGPoint

    var body: some View {
        Canvas { context, _ in
            for (a, b) in HandSkeleton.bones {
                guard let p1 = hand.joints[a], let p2 = hand.joints[b] else { continue }
                var path = Path()
                path.move(to: map(p1))
                path.addLine(to: map(p2))
                context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 2.5)
            }
            for (index, joint) in hand.joints.enumerated() {
                guard let joint = joint else { continue }
                let point = map(joint)
                let diameter: CGFloat = index == 0 ? 9 : (index % 4 == 0 ? 8 : 5)
                let rect = CGRect(x: point.x - diameter / 2,
                                  y: point.y - diameter / 2,
                                  width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect),
                             with: .color(hand.pinching ? .green : .white))
            }
        }
    }
}
