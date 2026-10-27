import XCTest
import CoreGraphics

final class WorkspaceTests: XCTestCase {
    func testLibraryFavoritesAndHistorySurviveRestart() throws {
        let suite = "vros.library.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = CinemaLibrary.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data([0]).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            defaults.removePersistentDomain(forName: suite)
        }
        let library = CinemaLibrary(defaults: defaults)
        library.record(url: url, title: "Teste")
        let id = try XCTUnwrap(library.entries.first?.id)
        library.toggleFavorite(id)
        library.saveMode("H-SBS", for: url)
        library.saveProgress(45, convergence: 0.01, for: url)
        library.saveProgress(.nan, convergence: 0.02, for: url)
        library.record(url: url, title: "Teste")
        let restored = CinemaLibrary(defaults: defaults)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.id, id)
        XCTAssertTrue(try XCTUnwrap(restored.entries.first).favorite)
        XCTAssertEqual(restored.entries.first?.mode, "H-SBS")
        XCTAssertEqual(restored.entries.first?.seconds, 45)
        XCTAssertEqual(restored.entries.first?.convergence, 0.01)
        XCTAssertEqual(restored.url(for: try XCTUnwrap(restored.entries.first)), url)
    }

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
