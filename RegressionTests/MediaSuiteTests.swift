import XCTest
import UIKit
import SceneKit

final class MediaSuiteTests: XCTestCase {
    func testCinemaToolbarHitTargets() {
        for size in [CGSize(width: 243, height: 236), CGSize(width: 304, height: 342)] {
            for slot in 0..<5 {
                let rect = VRCinemaToolbarGeometry.rect(slot, viewport: size)
                XCTAssertEqual(VRCinemaToolbarGeometry.slot(
                    at: CGPoint(x: rect.midX, y: rect.midY), viewport: size), slot)
            }
            XCTAssertNil(VRCinemaToolbarGeometry.slot(at: .zero, viewport: size))
        }
    }
    @MainActor
    func testImportRestartPreviewAndDeletePreserveOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.txt")
        try Data("Meu documento".utf8).write(to: source)
        let owned = folder.appendingPathComponent("owned")
        let store = VRMediaStore(folder: owned)
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.kind, .text)
        XCTAssertEqual(entry.title, "original.txt")
        let reopened = VRMediaStore(folder: owned)
        XCTAssertEqual(reopened.entries.count, 1)
        await reopened.open(entry)
        XCTAssertEqual(reopened.textPage, "Meu documento")
        try reopened.remove(entry)
        XCTAssertTrue(reopened.entries.isEmpty)
        XCTAssertNil(reopened.preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.url(for: entry).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testPhotoImportDecodeAndInvalidFormat() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let source = folder.appendingPathComponent("foto.png")
        try XCTUnwrap(image.pngData()).write(to: source)
        let store = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        await store.open(entry)
        XCTAssertNotNil(store.image)
        store.closePreview()
        XCTAssertNil(store.image)
        let unsupported = folder.appendingPathComponent("unsafe.exe")
        try Data([1, 2, 3]).write(to: unsupported)
        await store.importFile(unsupported)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(VRMediaStore.safeName("../escape"))
        XCTAssertFalse(VRMediaStore.safeName(".."))
    }

    @MainActor
    func testBrowserTabsPreserveURLsAndEnforceLimit() throws {
        let suite = "vros.tabs." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = VRWebSession(app: .browser, defaults: defaults)
        let first = browser.activeTabID
        browser.address = "https://example.com/first"
        browser.navigate()
        browser.newTab()
        let second = browser.activeTabID
        browser.address = "https://example.com/second"
        browser.navigate()
        browser.selectTab(first)
        XCTAssertEqual(browser.requestedURL.absoluteString, "https://example.com/first")
        browser.selectTab(second)
        XCTAssertEqual(browser.requestedURL.absoluteString, "https://example.com/second")
        for _ in 0..<12 { browser.newTab() }
        XCTAssertEqual(browser.tabs.count, 8)
        for _ in 0..<12 { browser.closeActiveTab() }
        XCTAssertEqual(browser.tabs.count, 1)
    }

    func testBrowserURLValidation() {
        XCTAssertEqual(VRBrowserURL.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertTrue(VRBrowserURL.resolve("filmes 3d")?.absoluteString.contains("google.com/search") == true)
        for value in ["javascript:alert(1)", "file:///secret", "http://example.com", "https://user:pass@example.com", ""] {
            XCTAssertNil(VRBrowserURL.resolve(value), value)
        }
    }

    @MainActor
    func testStereoConvergenceStaysInsideEachEyeAndAudioControlsClamp() throws {
        let cinema = CinemaModel()
        let previousVolume = cinema.movieVolume
        let previousLight = cinema.roomBrightness
        defer { cinema.setMovieVolume(previousVolume); cinema.setRoomBrightness(previousLight) }
        if cinema.swapEyes { cinema.toggleEyeOrder() }
        let screens = cinema.scene.rootNode.childNodes.filter {
            $0.geometry is SCNPlane && ($0.categoryBitMask == 2 || $0.categoryBitMask == 4)
        }.sorted { $0.categoryBitMask < $1.categoryBitMask }
        for value in [CGFloat(-0.02), 0, 0.02] {
            cinema.convergence = value
            cinema.selectMode(.sbs)
            let left = try XCTUnwrap(screens.first?.geometry?.firstMaterial).diffuse.contentsTransform
            let right = try XCTUnwrap(screens.last?.geometry?.firstMaterial).diffuse.contentsTransform
            XCTAssertGreaterThanOrEqual(left.m41, -0.00001)
            XCTAssertLessThanOrEqual(left.m41 + left.m11, 0.50001)
            XCTAssertGreaterThanOrEqual(right.m41, 0.49999)
            XCTAssertLessThanOrEqual(right.m41 + right.m11, 1.00001)
        }
        cinema.setMovieVolume(99)
        XCTAssertEqual(cinema.movieVolume, 1)
        cinema.setMovieVolume(.nan)
        XCTAssertEqual(cinema.movieVolume, 1)
        cinema.setRoomBrightness(-99)
        XCTAssertEqual(cinema.roomBrightness, 0.1, accuracy: 0.0001)
    }
}
