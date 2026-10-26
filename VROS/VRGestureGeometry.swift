import CoreGraphics

/// Shared hit targets for the hand cursor and the matching SwiftUI menus.
/// Keeping the arithmetic separate lets macOS CI test the edges and prevents
/// app-count changes from silently opening the wrong button.
enum VRGestureGeometry {
    static let appRowHeight: CGFloat = 49
    static let appRowGap: CGFloat = 7
    static let appHeaderHeight: CGFloat = 17
    static let appZoomHeight: CGFloat = 26
    static let appWarningHeight: CGFloat = 24

    static func appMenuWidth(viewport: CGSize) -> CGFloat {
        min(viewport.width * 0.89, 330)
    }

    static func appMenuHeight(count: Int, warning: Bool) -> CGFloat {
        let n = CGFloat(max(0, count))
        let warningGap: CGFloat = warning ? appRowGap : 0
        return 20 + appHeaderHeight + appZoomHeight +
               appRowHeight * n + appRowGap * (n + 1) +
               (warning ? appWarningHeight : 0) + warningGap
    }

    static func appRow(at point: CGPoint, viewport: CGSize, count: Int,
                       warning: Bool) -> Int? {
        guard count > 0 else { return nil }
        let width = appMenuWidth(viewport: viewport)
        let left = (viewport.width - width) / 2
        let menuTop = (viewport.height - appMenuHeight(
            count: count, warning: warning)) / 2
        let warningSpace: CGFloat = warning ? appWarningHeight + appRowGap : 0
        let firstRowTop = menuTop + 10 + appHeaderHeight + appRowGap +
                          appZoomHeight + appRowGap + warningSpace
        guard point.x >= left, point.x <= left + width else { return nil }
        let localY = point.y - firstRowTop
        guard localY >= 0 else { return nil }
        let slot = Int(localY / (appRowHeight + appRowGap))
        guard slot >= 0, slot < count else { return nil }
        let insideRow = localY - CGFloat(slot) * (appRowHeight + appRowGap)
        return insideRow <= appRowHeight ? slot : nil
    }

    static func appZoomFraction(at point: CGPoint, viewport: CGSize,
                                count: Int, warning: Bool) -> CGFloat? {
        let width = appMenuWidth(viewport: viewport)
        let left = (viewport.width - width) / 2
        let menuTop = (viewport.height - appMenuHeight(
            count: count, warning: warning)) / 2
        let top = menuTop + 10 + appHeaderHeight + appRowGap
        let x = point.x - left
        guard x >= 0, x <= width, point.y >= top,
              point.y <= top + appZoomHeight else { return nil }
        return max(0, min(1, (x - 110) / max(1, width - 157)))
    }

    static func webToolbarSlot(localX: CGFloat, width: CGFloat,
                               count: Int = 7) -> Int {
        guard count > 0 else { return 0 }
        let cellWidth = max(1, (width - 24) / CGFloat(count))
        return max(0, min(count - 1, Int((localX - 12) / cellWidth)))
    }

    static func webFavoriteSlot(localX: CGFloat, width: CGFloat,
                                count: Int) -> Int? {
        guard count > 0, localX >= 28 else { return nil }
        let cellWidth = max(1, (width - 40) / CGFloat(count))
        let slot = Int((localX - 28) / cellWidth)
        return (0..<count).contains(slot) ? slot : nil
    }

    static func webContentTop(hasFavorites: Bool) -> CGFloat {
        150 + (hasFavorites ? 29 : 0)
    }

    static func visiblePanelSize(original: CGSize, scale: CGFloat,
                                 viewport: CGSize, isWeb: Bool,
                                 isFocused: Bool) -> CGSize {
        if isFocused {
            return CGSize(width: viewport.width * 0.995,
                          height: viewport.height * 0.99)
        }
        let maxWidth = viewport.width * (isWeb ? 0.99 : 0.94)
        let maxHeight = viewport.height * (isWeb ? 0.80 : 0.75)
        return CGSize(width: min(maxWidth, original.width * scale),
                      height: min(maxHeight, original.height * scale))
    }
}
