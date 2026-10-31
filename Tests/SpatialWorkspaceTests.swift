import XCTest
import simd
@testable import VROS

final class SpatialWorkspaceTests: XCTestCase {
    private let identity = simd_quatf(real: 1, imag: SIMD3<Float>.zero)

    func testInitialHomeAndDockAreRealWorldPanelsAtComfortableDistances() throws {
        let workspace = SpatialWorkspace()
        let main = try XCTUnwrap(workspace.windows.first(where: { $0.id == "main" }))
        let dock = try XCTUnwrap(workspace.windows.first(where: { $0.id == "dock" }))
        XCTAssertTrue(main.isOpen)
        XCTAssertTrue(dock.isOpen)
        XCTAssertEqual(main.position.z, -2.4, accuracy: 0.00001)
        XCTAssertLessThan(dock.position.y, main.position.y)
        XCTAssertEqual(dock.elements.count, 8)
        XCTAssertEqual(Set(workspace.windows.map(\.id)).count, workspace.windows.count)
        XCTAssertEqual(Set(dock.elements.map(\.id)).count, dock.elements.count)
        XCTAssertEqual(workspace.activeApp, .home)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "library" })!.isOpen)
    }

    func testEveryInteractiveElementFitsItsDisplayedWindowAndCanBeHit() {
        let workspace = SpatialWorkspace()
        for var window in workspace.windows {
            window.isOpen = true; window.opacity = 1
            for element in window.elements where element.action != nil {
                XCTAssertLessThanOrEqual(abs(element.center.x) + element.size.x / 2, window.size.x / 2 + 0.0001)
                XCTAssertLessThanOrEqual(abs(element.center.y) + element.size.y / 2, window.size.y / 2 + 0.0001)
                let local = SIMD3(element.center.x, element.center.y, SpatialGeometry.elementDepth)
                let point = SpatialGeometry.worldPoint(local: local, window: window)
                let origin = point + window.orientation.act(SIMD3(0, 0, 1))
                let ray = SpatialRay(origin: origin, direction: point - origin)
                let hit = SpatialGeometry.intersect(ray: ray, windows: [window])
                XCTAssertEqual(hit?.windowID, window.id)
                XCTAssertEqual(hit?.elementID, element.id)
                XCTAssertEqual(hit?.distance ?? 0, 1, accuracy: 0.00001)
            }
        }
    }

    func testRoundedCornersAndBackFacesDoNotSelectInvisibleSurfaces() {
        let window = SpatialWindow(id: "test", position: SIMD3(0, 1.65, -2),
                                   size: SIMD2(1, 1), cornerRadius: 0.2, title: "")
        let miss = SpatialRay(origin: SIMD3(0.49, 2.14, 0), direction: SIMD3(0, 0, -1))
        XCTAssertNil(SpatialGeometry.intersect(ray: miss, windows: [window]))
        let hit = SpatialRay(origin: SIMD3(0.40, 2.05, 0), direction: SIMD3(0, 0, -1))
        XCTAssertNotNil(SpatialGeometry.intersect(ray: hit, windows: [window]))
        let back = SpatialRay(origin: SIMD3(0, 1.65, -4), direction: SIMD3(0, 0, 1))
        XCTAssertNil(SpatialGeometry.intersect(ray: back, windows: [window]))
    }

    func testNearestBlankWindowOccludesFartherButton() {
        let element = SpatialElement(id: "far.button", windowID: "far", center: .zero,
                                     size: SIMD2(0.5, 0.3), title: "Open", action: .open(.cinema))
        let far = SpatialWindow(id: "far", position: SIMD3(0, 1.65, -3), size: SIMD2(2, 1),
                                title: "", elements: [element])
        let near = SpatialWindow(id: "near", position: SIMD3(0, 1.65, -2), size: SIMD2(2, 1), title: "")
        let ray = SpatialRay(origin: StereoCamera.headPosition, direction: SIMD3(0, 0, -1))
        let hit = SpatialGeometry.intersect(ray: ray, windows: [far, near])
        XCTAssertEqual(hit?.windowID, "near")
        XCTAssertNil(hit?.elementID)
        XCTAssertEqual(hit?.distance ?? 0, 2, accuracy: 0.00001)
    }

    func testRotatedWindowSharesPlaneAndElementTransform() throws {
        let rotation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(0, 1, 0))
        let element = SpatialElement(id: "turn.button", windowID: "turn", center: SIMD2(0.12, -0.08),
                                     size: SIMD2(0.4, 0.3), title: "Open", action: .open(.photos))
        let window = SpatialWindow(id: "turn", position: SIMD3(2, 1.8, -2), orientation: rotation,
                                   size: SIMD2(1.5, 1), title: "", elements: [element])
        let point = SpatialGeometry.worldPoint(local: SIMD3(0.12, -0.08, SpatialGeometry.elementDepth), window: window)
        let origin = point + rotation.act(SIMD3(0, 0, 1.3))
        let hit = try XCTUnwrap(SpatialGeometry.intersect(ray: SpatialRay(origin: origin, direction: point - origin), windows: [window]))
        XCTAssertEqual(hit.elementID, element.id)
        XCTAssertEqual(simd_length(hit.point - point), 0, accuracy: 0.00001)
    }

    func testLibraryPagingSelectionAndDevelopmentDestination() throws {
        var workspace = SpatialWorkspace()
        workspace.perform(.open(.applications), headPose: identity, at: 1)
        workspace.update(at: 1.3)
        var library = try XCTUnwrap(workspace.windows.first(where: { $0.id == "library" }))
        XCTAssertTrue(library.isOpen)
        XCTAssertEqual(library.elements.filter { $0.style == .appIcon }.count, 6)
        workspace.perform(.scroll(1), headPose: identity, at: 1.4)
        library = try XCTUnwrap(workspace.windows.first(where: { $0.id == "library" }))
        XCTAssertEqual(workspace.libraryPage, 1)
        XCTAssertEqual(library.elements.filter { $0.style == .appIcon }.count, 2)
        workspace.perform(.scroll(1), headPose: identity, at: 1.5)
        XCTAssertEqual(workspace.libraryPage, 1)
        workspace.perform(.open(.cinema), headPose: identity, at: 2)
        workspace.update(at: 2.3)
        XCTAssertEqual(workspace.activeApp, .cinema)
        let app = try XCTUnwrap(workspace.windows.first(where: { $0.id == "app" }))
        XCTAssertTrue(app.isOpen)
        XCTAssertTrue(app.elements.contains(where: { $0.title == "Recurso em desenvolvimento" }))
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "library" })!.isOpen)
        let dock = try XCTUnwrap(workspace.windows.first(where: { $0.id == "dock" }))
        XCTAssertEqual(dock.elements.filter(\.selected).map(\.id), ["dock.cinema"])
    }

    func testOpeningPanelCannotBeSelectedUntilVisible() {
        var workspace = SpatialWorkspace()
        workspace.perform(.open(.applications), headPose: identity, at: 1)
        var library = workspace.windows.first(where: { $0.id == "library" })!
        let origin = library.position + SIMD3<Float>(0, 0, 1)
        let ray = SpatialRay(origin: origin, direction: SIMD3(0, 0, -1))
        XCTAssertNil(SpatialGeometry.intersect(ray: ray, windows: [library]))
        workspace.update(at: 1.3)
        library = workspace.windows.first(where: { $0.id == "library" })!
        XCTAssertNotNil(SpatialGeometry.intersect(ray: ray, windows: [library]))
    }

    func testCloseRecoverAndHomeRestoreAvailableWithoutClosingDock() {
        var workspace = SpatialWorkspace()
        workspace.perform(.close("main"), headPose: identity, at: 1)
        workspace.update(at: 1.3)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "main" })!.isOpen)
        workspace.perform(.close("dock"), headPose: identity, at: 1.4)
        XCTAssertTrue(workspace.windows.first(where: { $0.id == "dock" })!.isOpen)
        workspace.perform(.open(.home), headPose: identity, at: 2)
        workspace.update(at: 2.3)
        XCTAssertTrue(workspace.windows.first(where: { $0.id == "main" })!.isOpen)
    }

    func testDragStaysInsideFrontHemisphereAndComfortLimits() throws {
        var workspace = SpatialWorkspace()
        let yaw = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        for proposed in [SIMD3<Float>(100, 100, 100), SIMD3(-20, -20, 20), StereoCamera.headPosition] {
            workspace.moveWindow(id: "main", to: proposed, headPose: yaw)
            let window = try XCTUnwrap(workspace.windows.first(where: { $0.id == "main" }))
            let local = yaw.inverse.act(window.position - StereoCamera.headPosition)
            let horizontal = simd_length(SIMD2(local.x, local.z))
            XCTAssertGreaterThanOrEqual(horizontal, 1.4 - 0.00001)
            XCTAssertLessThanOrEqual(horizontal, 4.00001)
            XCTAssertLessThan(local.z, 0)
            XCTAssertGreaterThanOrEqual(window.position.y, 0.65 - 0.00001)
            XCTAssertLessThanOrEqual(window.position.y, 2.70001)
            let towardHead = normalize(StereoCamera.headPosition - window.position)
            XCTAssertGreaterThan(simd_dot(window.orientation.act(SIMD3(0, 0, 1)), towardHead), 0.4)
        }
    }

    func testRecenterMovesInterfaceAsRigidGroupWithoutMovingCameraOrAbruptFirstFrame() throws {
        var workspace = SpatialWorkspace()
        let mainBefore = workspace.windows.first(where: { $0.id == "main" })!
        let dockBefore = workspace.windows.first(where: { $0.id == "dock" })!
        let separation = simd_length(mainBefore.position - dockBefore.position)
        let yaw = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        workspace.perform(.recenter, headPose: yaw, at: 1)
        let first = workspace.windows.first(where: { $0.id == "main" })!
        XCTAssertEqual(simd_length(first.position - mainBefore.position), 0, accuracy: 0.00001)
        for time in [1.08, 1.16, 1.24, 1.4] {
            workspace.update(at: time)
            let main = workspace.windows.first(where: { $0.id == "main" })!
            let dock = workspace.windows.first(where: { $0.id == "dock" })!
            XCTAssertEqual(simd_length(main.position - dock.position), separation, accuracy: 0.00002)
        }
        let mainAfter = try XCTUnwrap(workspace.windows.first(where: { $0.id == "main" }))
        var bearing = mainAfter.position - StereoCamera.headPosition; bearing.y = 0
        XCTAssertGreaterThan(simd_dot(normalize(bearing), yaw.act(SIMD3(0, 0, -1))), 0.999)
        XCTAssertEqual(StereoCamera.headPosition, SIMD3<Float>(0, 1.65, 0))
    }

    func testSpatialPanelHasGenuineBinocularDisparity() {
        let workspace = SpatialWorkspace()
        let panel = workspace.windows.first(where: { $0.id == "main" })!
        let projection = StereoCamera.projection(verticalFOVDegrees: 90, aspect: 1.08, centerX: 0.5)
        func projected(_ eye: StereoCamera.Eye) -> SIMD2<Float> {
            let m = projection * StereoCamera.viewMatrix(eye, orientation: identity, ipdMeters: 0.064)
            let p = m * SIMD4<Float>(panel.position, 1)
            return SIMD2(p.x / p.w, p.y / p.w)
        }
        let left = projected(.left), right = projected(.right)
        XCTAssertGreaterThan(left.x, right.x)
        XCTAssertEqual(left.y, right.y, accuracy: 0.00001)
    }

    func testSystemSummaryUpdatesVisibleContentAndIgnoresIdenticalValues() {
        var workspace = SpatialWorkspace()
        workspace.setSystemSummary(time: "12:34", date: "31 de outubro", status: "59 FPS", battery: "80%")
        let revision = workspace.revision
        XCTAssertTrue(workspace.windows.first(where: { $0.id == "main" })!.elements.contains(where: { $0.title == "12:34" }))
        workspace.setSystemSummary(time: "12:34", date: "31 de outubro", status: "59 FPS", battery: "80%")
        XCTAssertEqual(workspace.revision, revision)
    }

    func testControlsAndCalibrationAreActionableSpatialPanels() throws {
        var workspace = SpatialWorkspace()
        workspace.setControlSummary("Joy-Con (R) · Analógico · 1,0 s")
        workspace.setOpticalSummary("IPD 64 mm · Resolução 85%")
        for (index, entry) in [(SpatialAction.controls, "Controles"), (.calibration, "Calibração")].enumerated() {
            let (action, title) = entry
            let time = 1 + Double(index)
            workspace.perform(action, headPose: identity, at: time)
            workspace.update(at: time + 0.3)
            let panel = try XCTUnwrap(workspace.windows.first(where: { $0.id == "app" }))
            XCTAssertEqual(panel.title, title)
            XCTAssertTrue(panel.isOpen)
            XCTAssertEqual(workspace.activeApp, .settings)
            for element in panel.elements where element.action != nil {
                XCTAssertLessThanOrEqual(abs(element.center.x) + element.size.x / 2, panel.size.x / 2)
                XCTAssertLessThanOrEqual(abs(element.center.y) + element.size.y / 2, panel.size.y / 2)
                let target = SpatialGeometry.worldPoint(local: SIMD3(element.center, SpatialGeometry.elementDepth), window: panel)
                let hit = try XCTUnwrap(SpatialGeometry.intersect(
                    ray: SpatialRay(origin: StereoCamera.headPosition, direction: target - StereoCamera.headPosition),
                    windows: [panel]))
                XCTAssertEqual(workspace.action(for: hit), element.action)
            }
        }
    }

    func testPersistedDistanceDoesNotOpenHiddenWindowsAndRetainsDepthOrder() {
        var workspace = SpatialWorkspace()
        workspace.perform(.setDistance(3), headPose: identity, at: 1)
        workspace.update(at: 1.3)
        let main = workspace.windows.first(where: { $0.id == "main" })!
        let app = workspace.windows.first(where: { $0.id == "app" })!
        let library = workspace.windows.first(where: { $0.id == "library" })!
        XCTAssertTrue(main.isOpen)
        XCTAssertFalse(app.isOpen)
        XCTAssertFalse(library.isOpen)
        XCTAssertEqual(main.position.z, -3, accuracy: 0.00001)
        XCTAssertEqual(app.position.z, -2.85, accuracy: 0.00001)
        XCTAssertEqual(library.position.z, -2.7, accuracy: 0.00001)
        XCTAssertEqual(app.opacity, 0)
        XCTAssertEqual(library.opacity, 0)
    }

    func testLibraryFromAnAppIsNotOccludedAndBackRestoresHome() throws {
        var workspace = SpatialWorkspace()
        workspace.perform(.open(.cinema), headPose: identity, at: 1)
        workspace.update(at: 1.3)
        workspace.perform(.setDistance(2), headPose: identity, at: 1.4)
        workspace.update(at: 1.7)
        workspace.perform(.open(.applications), headPose: identity, at: 2)
        workspace.update(at: 2.3)
        let library = try XCTUnwrap(workspace.windows.first(where: { $0.id == "library" }))
        let button = try XCTUnwrap(library.elements.first(where: { $0.id == "library.cinema" }))
        let target = SpatialGeometry.worldPoint(local: SIMD3(button.center, SpatialGeometry.elementDepth), window: library)
        let hit = SpatialGeometry.intersect(ray: SpatialRay(origin: StereoCamera.headPosition,
                                                            direction: target - StereoCamera.headPosition),
                                            windows: workspace.windows)
        XCTAssertEqual(hit?.windowID, "library")
        XCTAssertEqual(hit?.elementID, button.id)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "app" })!.isOpen)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "main" })!.isOpen)
        workspace.perform(.back, headPose: identity, at: 3)
        workspace.update(at: 3.3)
        XCTAssertEqual(workspace.activeApp, .home)
        XCTAssertTrue(workspace.windows.first(where: { $0.id == "main" })!.isOpen)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "library" })!.isOpen)
    }

    func testHeadRayCanReachQuickMenuFromHomeAndEveryQuickAction() throws {
        var workspace = SpatialWorkspace()
        let main = try XCTUnwrap(workspace.windows.first(where: { $0.id == "main" }))
        let button = try XCTUnwrap(main.elements.first(where: { $0.action == .quickMenu }))
        let target = SpatialGeometry.worldPoint(local: SIMD3(button.center, SpatialGeometry.elementDepth), window: main)
        let hit = try XCTUnwrap(SpatialGeometry.intersect(
            ray: SpatialRay(origin: StereoCamera.headPosition, direction: target - StereoCamera.headPosition),
            windows: workspace.windows))
        XCTAssertEqual(workspace.action(for: hit), .quickMenu)
        workspace.perform(.quickMenu, headPose: identity, at: 1)
        workspace.update(at: 1.3)
        let quick = try XCTUnwrap(workspace.windows.first(where: { $0.id == "quick" }))
        for element in quick.elements where element.action != nil {
            let target = SpatialGeometry.worldPoint(local: SIMD3(element.center, SpatialGeometry.elementDepth), window: quick)
            let hit = try XCTUnwrap(SpatialGeometry.intersect(
                ray: SpatialRay(origin: StereoCamera.headPosition, direction: target - StereoCamera.headPosition),
                windows: workspace.windows))
            XCTAssertEqual(hit.windowID, "quick")
            XCTAssertEqual(workspace.action(for: hit), element.action)
        }
    }

    func testWindowFocusIsExclusiveAndLeavesTransformsUnchanged() {
        var workspace = SpatialWorkspace()
        let positions = workspace.windows.map(\.position)
        let rotations = workspace.windows.map { $0.orientation.vector }
        XCTAssertEqual(workspace.focusedWindowID, "main")
        workspace.focusWindow(id: "dock")
        XCTAssertEqual(workspace.focusedWindowID, "dock")
        XCTAssertEqual(workspace.windows.filter(\.isFocused).count, 1)
        XCTAssertEqual(workspace.windows.map(\.position), positions)
        XCTAssertEqual(workspace.windows.map { $0.orientation.vector }, rotations)
    }

    func testClosedAndClosingWindowsCannotTakeFocus() {
        var workspace = SpatialWorkspace()
        workspace.focusWindow(id: "library")
        XCTAssertEqual(workspace.focusedWindowID, "main")
        workspace.perform(.close("main"), headPose: identity, at: 1)
        workspace.focusWindow(id: "main")
        XCTAssertEqual(workspace.focusedWindowID, "dock")
        let closingPosition = workspace.windows.first(where: { $0.id == "main" })!.position
        workspace.moveWindow(id: "main", to: SIMD3(1, 2, -2), headPose: identity)
        XCTAssertEqual(workspace.windows.first(where: { $0.id == "main" })!.position, closingPosition)
        workspace.update(at: 1.3)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == "main" })!.isFocused)
        XCTAssertEqual(workspace.windows.filter(\.isFocused).count, 1)
    }

    func testNavigationFocusFollowsTheVisibleDestinationAndRecovery() {
        var workspace = SpatialWorkspace()
        workspace.perform(.open(.cinema), headPose: identity, at: 1)
        XCTAssertEqual(workspace.focusedWindowID, "app")
        workspace.perform(.open(.applications), headPose: identity, at: 2)
        XCTAssertEqual(workspace.focusedWindowID, "library")
        workspace.perform(.back, headPose: identity, at: 3)
        XCTAssertEqual(workspace.focusedWindowID, "main")
        workspace.perform(.controls, headPose: identity, at: 4)
        XCTAssertEqual(workspace.focusedWindowID, "app")
        workspace.perform(.quickMenu, headPose: identity, at: 5)
        XCTAssertEqual(workspace.focusedWindowID, "quick")
        workspace.perform(.back, headPose: identity, at: 6)
        XCTAssertEqual(workspace.focusedWindowID, "app")
        workspace.perform(.recover("main"), headPose: identity, at: 7)
        XCTAssertEqual(workspace.focusedWindowID, "main")
        XCTAssertEqual(workspace.windows.filter(\.isFocused).count, 1)
    }
}
