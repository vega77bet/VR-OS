import XCTest
import CoreGraphics

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testMinimizeFocusResizeAndClose() {
        let workspace = VRWorkspace()
        let id = UUID()
        workspace.focus(id)
        XCTAssertEqual(workspace.focused, id)
        workspace.minimize(id)
        XCTAssertNil(workspace.focused)
        XCTAssertTrue(workspace.state(id).minimized)
        workspace.focus(id)
        XCTAssertFalse(workspace.state(id).minimized)
        workspace.resize(id, by: 100)
        XCTAssertEqual(workspace.state(id).scale, 1.4)
        workspace.resize(id, by: -100)
        XCTAssertEqual(workspace.state(id).scale, 0.65)
        workspace.resize(id, by: .nan)
        XCTAssertEqual(workspace.state(id).scale, 0.65)
        workspace.remove(id)
        XCTAssertNil(workspace.focused)
        XCTAssertTrue(workspace.windows.isEmpty)
    }

    func testVisionTargetsMatchSixCards() {
        for size in [CGSize(width: 243, height: 236), CGSize(width: 304, height: 342)] {
            for index in 0..<6 {
                let rect = VRWorkspaceGeometry.cell(index, in: size)
                XCTAssertTrue(VRWorkspaceGeometry.bounds(size).contains(rect))
                XCTAssertEqual(VRWorkspaceGeometry.item(
                    at: CGPoint(x: rect.midX, y: rect.midY), in: size), index)
            }
            XCTAssertNil(VRWorkspaceGeometry.item(at: .zero, in: size))
        }
    }
}
