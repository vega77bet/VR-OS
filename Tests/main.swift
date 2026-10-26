import Foundation
import CoreGraphics
import simd

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let viewport = CGSize(width: 426, height: 393)

for count in [3, 5, 7] {
    for warning in [false, true] {
        let menuHeight = VRGestureGeometry.appMenuHeight(
            count: count, warning: warning)
        let menuWidth = VRGestureGeometry.appMenuWidth(viewport: viewport)
        let menuTop = (viewport.height - menuHeight) / 2
        let firstRow = menuTop + 10 + VRGestureGeometry.appHeaderHeight +
            VRGestureGeometry.appRowGap + VRGestureGeometry.appZoomHeight +
            VRGestureGeometry.appRowGap +
            (warning ? VRGestureGeometry.appWarningHeight +
                VRGestureGeometry.appRowGap : 0)
        for index in 0..<count {
            let inside = CGPoint(
                x: viewport.width / 2,
                y: firstRow + CGFloat(index) *
                   (VRGestureGeometry.appRowHeight + VRGestureGeometry.appRowGap) +
                   VRGestureGeometry.appRowHeight / 2
            )
            verify(VRGestureGeometry.appRow(
                at: inside, viewport: viewport, count: count,
                warning: warning) == index,
                "App row \(index) with count \(count), warning \(warning)")
        }
        let gap = CGPoint(x: viewport.width / 2,
            y: firstRow + VRGestureGeometry.appRowHeight + 3)
        verify(VRGestureGeometry.appRow(
            at: gap, viewport: viewport, count: count,
            warning: warning) == nil, "App row gap must not activate another app")
        verify(VRGestureGeometry.appRow(
            at: CGPoint(x: 0, y: firstRow + 20), viewport: viewport,
            count: count, warning: warning) == nil,
            "Outside menu should not select an app")

        let zoomY = menuTop + 10 + VRGestureGeometry.appHeaderHeight +
            VRGestureGeometry.appRowGap + VRGestureGeometry.appZoomHeight / 2
        let middleZoom = VRGestureGeometry.appZoomFraction(
            at: CGPoint(x: (viewport.width - menuWidth) / 2 +
                          menuWidth * 0.66, y: zoomY),
            viewport: viewport, count: count, warning: warning)
        verify(middleZoom != nil && middleZoom! >= 0 && middleZoom! <= 1,
            "Zoom slider hit must map inside [0,1]")
    }
}

for column in 0..<7 {
    let width: CGFloat = 416
    let x: CGFloat = 12 + (CGFloat(column) + 0.5) * (width - 24) / 7
    verify(VRGestureGeometry.webToolbarSlot(localX: x, width: width)
           == column, "Web nav icon \(column) click map")
}
for count in [1, 2, 4] {
    for index in 0..<count {
        let width: CGFloat = 416
        let x: CGFloat = 28 + (CGFloat(index) + 0.5) * (width - 40) /
                         CGFloat(count)
        verify(VRGestureGeometry.webFavoriteSlot(
            localX: x, width: width, count: count) == index,
            "Favorite \(index) click map with \(count) bookmarks")
    }
}
verify(VRGestureGeometry.webContentTop(hasFavorites: false) == 150,
       "Web page starts after two control bars")
verify(VRGestureGeometry.webContentTop(hasFavorites: true) == 179,
       "Favorites need another visible row")

let large = VRGestureGeometry.visiblePanelSize(
    original: CGSize(width: 500, height: 500), scale: 2.5,
    viewport: viewport, isWeb: true, isFocused: false)
verify(large.width <= viewport.width && large.height <= viewport.height,
       "Large web window should remain inside eye viewport")
let focus = VRGestureGeometry.visiblePanelSize(
    original: CGSize(width: 100, height: 100), scale: 0.5,
    viewport: viewport, isWeb: true, isFocused: true)
verify(focus.width > viewport.width * 0.99,
       "Focus mode should expand almost completely")

print("PASS: dynamic 3/5/7-app launcher, zoom targets, 7 web actions,")
print("      favorites, scroll layout and clamped/focused VR windows")

var checkedSeatCount = 0
for row in 0..<6 {
    for sideIndex in 0..<2 {
        let side: Float = sideIndex == 0 ? -1 : 1
        for column in 0..<6 {
            let eye = SIMD3<Float>(
                side * (2.45 + Float(column) * 2.08),
                Float(row) * 0.33 + 1.70,
                Float(row) * 4.2 - 11.7 - 0.13
            )
            let rotation = VRCinemaGeometry.lookRotation(from: eye)
            let rotatedForward = simd_normalize(
                rotation.act(VRCinemaGeometry.cameraForward))
            let expectedForward = simd_normalize(
                VRCinemaGeometry.screenCentre - eye)
            let alignment = simd_dot(rotatedForward, expectedForward)
            verify(alignment > 0.9999,
                   "Seat \(checkedSeatCount) needs a direct screen-centre aim")
            let pitch = VRCinemaGeometry.pitchDegrees(from: eye)
            let yaw = VRCinemaGeometry.yawDegrees(from: eye)
            verify(pitch >= 0 && pitch <= 55,
                   "Seat \(checkedSeatCount) pitch must be physically plausible")
            verify(abs(yaw) <= 80,
                   "Seat \(checkedSeatCount) yaw must face the screen")
            checkedSeatCount += 1
        }
    }
}
verify(checkedSeatCount == 72, "Every cinema seat must be checked")
print("PASS: all 72 cinema chairs point at the screen centre to 0.01%")

let ultraViewport = CGSize(width: 196, height: 390)
let centre = CGPoint(x: ultraViewport.width / 2,
                     y: ultraViewport.height / 2)
let identity = simd_quatf()
let centreRay = VRUltraWideWindowProjection.screenRay(
    at: centre, viewport: ultraViewport)
verify(simd_distance(centreRay, SIMD3<Float>(0, 0, -1)) < 0.00001,
       "0.5x virtual forward ray must be centred")
for degrees in [-50.0, -20.0, 0.0, 20.0, 50.0] {
    let rotation = simd_quatf(
        angle: Float(degrees * .pi / 180),
        axis: SIMD3<Float>(0, 1, 0))
    for point in [centre, CGPoint(x: 40, y: 90),
                  CGPoint(x: 156, y: 310)] {
        let anchored = VRUltraWideWindowProjection.anchoredDirection(
            at: point, viewport: ultraViewport, headRotation: rotation)
        guard let back = VRUltraWideWindowProjection.project(
            anchored, headRotation: rotation, viewport: ultraViewport) else {
            verify(false, "3DoF projection must remain visible for a matching bearing")
            continue
        }
        verify(hypot(back.x - point.x, back.y - point.y) < 0.05,
               "3DoF round trip drifted from its camera-relative input")
    }
}
let fixedRay = VRUltraWideWindowProjection.screenRay(
    at: centre, viewport: ultraViewport)
let yaw = simd_quatf(angle: Float.pi / 6, axis: SIMD3<Float>(0, 1, 0))
let shifted = VRUltraWideWindowProjection.project(
    fixedRay, headRotation: yaw, viewport: ultraViewport)
verify(shifted != nil && abs(shifted!.x - centre.x) > 15,
       "A fixed 3DoF panel should move on screen when the headset turns")
let behind = VRUltraWideWindowProjection.project(
    SIMD3<Float>(0, 0, 1), headRotation: identity,
    viewport: ultraViewport)
verify(behind == nil, "A 3DoF panel behind the user must not be displayed")
print("PASS: 0.5x headset 3DoF projection/drag round trips and rotation")
