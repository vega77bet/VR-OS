import CoreGraphics

/// Two-frame debounce and hysteresis for Vision fingertips. This is
/// platform-independent so CI can test pinches without camera hardware.
struct VRPinchDetector {
    private(set) var pinching = false
    private var confirmations = 0

    mutating func update(thumb: CGPoint, index: CGPoint,
                         palmWidth: CGFloat,
                         sensitivity: CGFloat = 0.5) -> Bool {
        guard thumb.x.isFinite, thumb.y.isFinite,
              index.x.isFinite, index.y.isFinite, palmWidth.isFinite else {
            reset()
            return false
        }
        let ratio = hypot(thumb.x - index.x, thumb.y - index.y) /
                    max(0.04, palmWidth)
        let tuned = sensitivity.isFinite ? max(0, min(1, sensitivity)) : 0.5
        // Higher sensitivity accepts slightly wider finger gaps. Retain
        // hysteresis and two-frame debounce so noise cannot spam clicks.
        let engage = 0.43 + (tuned - 0.5) * 0.18
        let release = 0.64 + (tuned - 0.5) * 0.16
        let candidate = pinching ? ratio < release : ratio < engage
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

