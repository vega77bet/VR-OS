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

var ultraPinch = VRPinchDetector()
let thumb = CGPoint(x: 0.5, y: 0.5)
let closeTip = CGPoint(x: 0.53, y: 0.5)
let thresholdTip = CGPoint(x: 0.61, y: 0.5)
let openTip = CGPoint(x: 0.70, y: 0.5)
verify(!ultraPinch.update(thumb: thumb, index: closeTip, palmWidth: 0.20),
       "A single noisy Vision sample must not activate a pinch")
verify(ultraPinch.update(thumb: thumb, index: closeTip, palmWidth: 0.20),
       "Two consecutive closed-hand samples should activate a pinch")
verify(ultraPinch.update(thumb: thumb, index: thresholdTip, palmWidth: 0.20),
       "Mid-range pinch noise should stay latched due to hysteresis")
verify(ultraPinch.update(thumb: thumb, index: openTip, palmWidth: 0.20),
       "A single opening sample must not drop a pinch")
verify(!ultraPinch.update(thumb: thumb, index: openTip, palmWidth: 0.20),
       "Two opening samples should release a pinch")
_ = ultraPinch.update(thumb: thumb, index: closeTip, palmWidth: 0.20)
ultraPinch.reset()
verify(!ultraPinch.pinching,
       "Vision camera reset must clear the last held pinch")
print("PASS: ultrawide Vision pinch debouncing, release, hysteresis and reset")


// V20: optical centres measured on the supplied VR headset screenshot.
// Apertures are positioned against the FULL landscape screen, not 50/50 split.
let screenshotSize = CGSize(width: 1536, height: 735)
let reference = VRLensSettings().placement(in: screenshotSize)
verify(abs(reference.aperture.width - 438) < 2,
       "Reference lens width should match the example camera viewport")
verify(abs(reference.aperture.height - 441) < 2,
       "Reference lens height should match the example camera viewport")
verify(abs(reference.left.x - 538) < 2 &&
       abs(reference.right.x - 998) < 2,
       "Reference lenses must sit near 35% and 65% of whole screen width")
verify(abs(reference.left.y - 459) < 2,
       "Reference lens should sit about 63% down the screen")
verify(reference.gap >= 3, "Reference optical apertures must not overlap")

for screen in [CGSize(width: 852, height: 393),
               CGSize(width: 1536, height: 735),
               CGSize(width: 667, height: 375)] {
    for profile in VRLensProfile.allCases {
        for scale in [CGFloat(0.75), 1.0, 1.4] {
            for ipd in [CGFloat(-0.075), 0, 0.12] {
                var settings = VRLensSettings()
                settings.profile = profile
                settings.scale = scale
                settings.spacing = ipd
                let placement = settings.placement(in: screen)
                let size = placement.aperture
                verify(size.width > 0 && size.height > 0,
                       "A lens must be nonempty")
                verify(placement.left.x - size.width / 2 >= 0 &&
                       placement.right.x + size.width / 2 <= screen.width,
                       "Both apertures must remain horizontally on display")
                verify(placement.left.y - size.height / 2 >= 0 &&
                       placement.left.y + size.height / 2 <= screen.height,
                       "Both apertures must remain vertically on display")
                verify(placement.right.x - size.width / 2 >
                       placement.left.x + size.width / 2,
                       "No overlapping lenses even with extreme IPD/scale")
                verify(abs(placement.left.y - placement.right.y) < 0.0001,
                       "Left and right eyes must have aligned horizontal axes")

                let viewport = placement.aperture
                let menu = VRLensMenuGeometry.rect(in: viewport)
                let menuScale = menu.height / VRLensMenuGeometry.height
                let minus = CGPoint(x: menu.maxX - 77 * menuScale,
                                    y: menu.minY +
                                    (VRLensMenuGeometry.controlY + 12) * menuScale)
                let plus = CGPoint(x: menu.maxX - 20 * menuScale,
                                   y: menu.minY +
                                   (VRLensMenuGeometry.controlY + 12) * menuScale)
                verify(VRLensMenuGeometry.action(
                    at: minus, viewport: viewport) ==
                    .adjust(row: 0, direction: -1),
                    "The first lens settings minus button must match pinch")
                verify(VRLensMenuGeometry.action(
                    at: plus, viewport: viewport) ==
                    .adjust(row: 0, direction: 1),
                    "The first lens settings plus button must match pinch")
                let close = CGPoint(x: menu.maxX - 20 * menuScale,
                                    y: menu.minY + 20 * menuScale)
                verify(VRLensMenuGeometry.action(
                    at: close, viewport: viewport) == .close,
                    "The lens calibration X must match pinch")
            }
        }
    }
}
print("PASS: screenshot-matched dual optical apertures, IPD/size/height bounds")
print("      and visor calibration +/- pinch targets")

for screen in [CGSize(width: 243, height: 236),
               CGSize(width: 304, height: 342),
               CGSize(width: 426, height: 393)] {
    for warning in [false, true] {
        let count = 7
        let perPage = VRGestureGeometry.compactAppRows(
            viewport: screen, warning: warning, count: count)
        let pages = VRGestureGeometry.compactAppPageCount(
            viewport: screen, warning: warning, count: count)
        let menuHeight = VRGestureGeometry.compactAppMenuHeight(
            viewport: screen, warning: warning, count: count)
        verify(menuHeight <= screen.height * 0.94,
               "The 7-app launcher must never extend past an aperture")
        verify(pages * perPage >= count, "All web apps must stay reachable")
        let firstRowTop = (screen.height - menuHeight) / 2 + 10 +
            VRGestureGeometry.appHeaderHeight + VRGestureGeometry.appRowGap +
            VRGestureGeometry.appZoomHeight + VRGestureGeometry.appRowGap +
            (warning ? VRGestureGeometry.appWarningHeight +
                VRGestureGeometry.appRowGap : 0) +
            VRGestureGeometry.compactAppPagerHeight + VRGestureGeometry.appRowGap

        for page in 0..<pages {
            for row in 0..<perPage {
                let index = page * perPage + row
                guard index < count else { continue }
                let pointer = CGPoint(
                    x: screen.width / 2,
                    y: firstRowTop + CGFloat(row) *
                       (VRGestureGeometry.appRowHeight +
                        VRGestureGeometry.appRowGap) +
                       VRGestureGeometry.appRowHeight / 2)
                verify(VRGestureGeometry.compactAppRow(
                    at: pointer, viewport: screen, count: count,
                    warning: warning, page: page) == index,
                    "Paginated VR app \(index) must map to its actual row")
            }
        }
        let width = VRGestureGeometry.appMenuWidth(viewport: screen)
        let left = (screen.width - width) / 2
        let pagerY = (screen.height - menuHeight) / 2 + 10 +
            VRGestureGeometry.appHeaderHeight + VRGestureGeometry.appRowGap +
            VRGestureGeometry.appZoomHeight + VRGestureGeometry.appRowGap +
            (warning ? VRGestureGeometry.appWarningHeight +
                VRGestureGeometry.appRowGap : 0) +
            VRGestureGeometry.compactAppPagerHeight / 2
        verify(VRGestureGeometry.compactAppPageDelta(
            at: CGPoint(x: left + width / 6, y: pagerY),
            viewport: screen, count: count, warning: warning) == -1,
            "Previous-page VR pinch hit")
        verify(VRGestureGeometry.compactAppPageDelta(
            at: CGPoint(x: left + width * 5 / 6, y: pagerY),
            viewport: screen, count: count, warning: warning) == 1,
            "Next-page VR pinch hit")
        verify(VRGestureGeometry.compactAppPageDelta(
            at: CGPoint(x: left + width / 2, y: pagerY),
            viewport: screen, count: count, warning: warning) == nil,
            "Page indicator should not advance on pinch")
    }
}
print("PASS: small-aperture 7-app pagination, pinch controls, warnings")


// V21: real native Settings catalog navigation, search and stable actions.
let homeSections = VRSettingsCatalog.sections(for: .home)
let homeRows = homeSections.flatMap(\.rows)
verify(VRSettingsCatalog.categories.count == 9,
       "Settings should expose nine useful configuration categories")
verify(homeRows.filter {
    if case .navigate = $0.kind { return true }
    return false
}.count == 10, "Main settings must include a top account-style card and all categories")
for page in VRSettingsPage.allCases {
    let groups = VRSettingsCatalog.sections(for: page)
    let rows = groups.flatMap(\.rows)
    verify(!rows.isEmpty, "Settings page \(page.rawValue) must never be empty")
    let allIDs = rows.map(\.id)
    verify(Set(allIDs).count == allIDs.count,
           "Settings page \(page.rawValue) must not duplicate row identities")
    for row in rows {
        verify(!row.title.isEmpty, "Every Settings row needs a visible title")
        switch row.kind {
        case let .navigate(destination):
            verify(destination != .home, "Categories should enter a subpage")
            verify(!VRSettingsCatalog.sections(for: destination).isEmpty,
                   "Every navigation destination must have content")
        case .toggle, .stepper, .slider, .choice, .action, .information:
            verify(page != .home || row.kind == .information,
                   "Home is navigation-first rather than a flat settings form")
        }
    }
}
let searchOne = VRSettingsCatalog.sections(for: .home, search: "camera")
    .flatMap(\.rows)
verify(searchOne.contains(where: { $0.id == "open.camera" }),
       "Settings search must match labels without diacritics")
let searchTwo = VRSettingsCatalog.sections(for: .home, search: "PINCA")
    .flatMap(\.rows)
verify(searchTwo.contains(where: { $0.id == "open.hands" }),
       "Settings search must match child descriptions, case and accents")
let searchThree = VRSettingsCatalog.sections(for: .home, search: "IPD")
    .flatMap(\.rows)
verify(searchThree.contains(where: { $0.id == "open.visor" }),
       "Settings search must surface nested lens preferences")
let searchEmpty = VRSettingsCatalog.sections(for: .home,
                                               search: "xx_no_result_999")
    .flatMap(\.rows)
verify(searchEmpty.count == 1 && searchEmpty[0].id == "search.empty",
       "Unknown search must show clear empty results, never stale rows")
let lensSettings = VRSettingsCatalog.sections(for: .visor).flatMap(\.rows)
verify(lensSettings.filter {
    if case .stepper = $0.kind { return true }
    return false
}.count == 5, "Visor must expose five real numerical controls")
let cinemaSettings = VRSettingsCatalog.sections(for: .cinema)
    .flatMap(\.rows)
verify(cinemaSettings.contains(where: { $0.id == "cinema.fov" &&
    $0.kind == .slider }), "Cinema FOV must have a real slider row")
verify(VRSettingsCatalog.sections(for: .internet)
    .flatMap(\.rows).contains(where: { $0.id == "web.clear" &&
        $0.kind == .action }), "Favorites cleanup should be explicit")
print("PASS: Apple-inspired native Settings navigation, nested searchable")
print("      categories, stable row IDs, toggles, sliders and actions")


for size in [CGSize(width: 243, height: 236),
             CGSize(width: 308, height: 345),
             CGSize(width: 426, height: 393)] {
    for page in VRSettingsPage.allCases {
        let leftHeader = CGPoint(x: 15, y: 20)
        let rightHeader = CGPoint(x: size.width - 12, y: 20)
        verify(VRSettingsInputGeometry.classify(
            rightHeader, viewport: size, page: page) == .close,
            "Settings close X must stay pinch-reachable in every eye size")
        verify(VRSettingsInputGeometry.classify(
            leftHeader, viewport: size, page: page) ==
               (page == .home ? .none : .back),
            "Settings back must only exist on category pages")
        let belowHeader = CGPoint(
            x: size.width / 2,
            y: VRSettingsInputGeometry.toolbarHeight + 12)
        verify(VRSettingsInputGeometry.classify(
            belowHeader, viewport: size, page: page) ==
               (page == .home ? .search : .table),
            "Search should only intercept the main Settings screen")
        let rowPoint = CGPoint(
            x: size.width / 2,
            y: VRSettingsInputGeometry.tableTop(page: page) + 30)
        verify(VRSettingsInputGeometry.classify(
            rowPoint, viewport: size, page: page) == .table,
            "A valid table row must not be mistaken for the toolbar")
    }
    verify(VRSettingsInputGeometry.classify(
        CGPoint(x: -1, y: 30), viewport: size,
        page: .home) == .none,
        "A finger outside the visor must never activate controls")
}
let pinchOrigin = CGPoint(x: 100, y: 130)
verify(!VRSettingsInputGeometry.isScroll(
    from: pinchOrigin, to: CGPoint(x: 105, y: 134)),
    "A jittery short pinch should be treated as a click")
verify(VRSettingsInputGeometry.isScroll(
    from: pinchOrigin, to: CGPoint(x: 100, y: 146)),
    "A real 16px hand drag should scroll the Settings list")
print("PASS: Settings Vision/physical search, back/close, table and scroll")
print("      hit targets across small/medium/wide headset viewports")


// V21 regression: Settings actually adjusts the Vision detector's activation
// thresholds without losing two-frame debouncing or latching hysteresis.
let middleThumb = CGPoint(x: 0.5, y: 0.5)
let borderlineIndex = CGPoint(x: 0.595, y: 0.5) // ratio 0.475 for palm=0.20
var lowSensitivity = VRPinchDetector()
var highSensitivity = VRPinchDetector()
for _ in 0..<4 {
    verify(!lowSensitivity.update(thumb: middleThumb,
                                  index: borderlineIndex,
                                  palmWidth: 0.2, sensitivity: 0),
           "Very low sensitivity must reject borderline finger separation")
}
verify(!highSensitivity.update(thumb: middleThumb,
                                index: borderlineIndex,
                                palmWidth: 0.2, sensitivity: 1),
       "Very high sensitivity still requires two consecutive pinch frames")
verify(highSensitivity.update(thumb: middleThumb,
                              index: borderlineIndex,
                              palmWidth: 0.2, sensitivity: 1),
       "High sensitivity must recognize a wider finger gap after debounce")
let hysteresisIndex = CGPoint(x: 0.635, y: 0.5) // ratio 0.675
verify(highSensitivity.update(thumb: middleThumb,
                              index: hysteresisIndex,
                              palmWidth: 0.2, sensitivity: 1),
       "High sensitivity pinch should stay latched in release hysteresis band")
let releaseIndex = CGPoint(x: 0.67, y: 0.5) // ratio 0.85
verify(highSensitivity.update(thumb: middleThumb,
                              index: releaseIndex,
                              palmWidth: 0.2, sensitivity: 1),
       "First open-hand frame must not unpinch")
verify(!highSensitivity.update(thumb: middleThumb,
                               index: releaseIndex,
                               palmWidth: 0.2, sensitivity: 1),
       "Two open-hand frames must release even at high sensitivity")
highSensitivity.reset()
verify(!highSensitivity.pinching,
       "Settings Vision detector reset must clear held hand gesture")
print("PASS: Settings pinch sensitivity extreme thresholds, debounce and")
print("      hysteresis without accidental click or stuck pinch")
