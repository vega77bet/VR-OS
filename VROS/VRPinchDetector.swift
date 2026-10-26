import CoreGraphics

/// Two-frame debounce and hysteresis for Vision fingertips. This is
/// platform-independent so CI can test pinches without camera hardware.
struct VRPinchDetector {
    private(set) var pinching = false
    private var confirmations = 0

    mutating func update(thumb: CGPoint, index: CGPoint,
                         palmWidth: CGFloat) -> Bool {
        let ratio = hypot(thumb.x - index.x, thumb.y - index.y) /
                    max(0.04, palmWidth)
        let candidate = pinching ? ratio < 0.64 : ratio < 0.43
        if candidate == pinching {
            confirmations = 0
        } else {
            confirmations += 1
            if confirmations >= 2 {
                pinching = candidate
                confirmations = 0
            }
        }
        return pinching
    }

    mutating func reset() {
        pinching = false
        confirmations = 0
    }
}
