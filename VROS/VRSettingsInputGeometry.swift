import Foundation
import CoreGraphics

/// One UI-independent map for header/back/search/close gestures in the
/// mirrored headset Settings surface. Touch and Vision use identical bounds.
enum VRSettingsHitZone: Equatable {
    case close
    case back
    case search
    case table
    case none
}

enum VRSettingsInputGeometry {
    static let toolbarHeight: CGFloat = 48
    static let searchHeight: CGFloat = 44
    static let scrollDeadZone: CGFloat = 11

    static func tableTop(page: VRSettingsPage) -> CGFloat {
        toolbarHeight + (page == .home ? searchHeight : 0)
    }

    static func classify(_ point: CGPoint, viewport: CGSize,
                         page: VRSettingsPage) -> VRSettingsHitZone {
        guard point.x.isFinite, point.y.isFinite,
              viewport.width > 0, viewport.height > 0,
              point.x >= 0, point.y >= 0,
              point.x <= viewport.width, point.y <= viewport.height
        else { return .none }
        if point.y < toolbarHeight {
            if point.x > viewport.width - 49 { return .close }
            if page != .home && point.x < viewport.width * 0.38 {
                return .back
            }
            return .none
        }
        if page == .home && point.y < toolbarHeight + searchHeight {
            return .search
        }
        return .table
    }

    static func isScroll(from initial: CGPoint, to current: CGPoint) -> Bool {
        hypot(initial.x - current.x, initial.y - current.y) >
            scrollDeadZone
    }
}
