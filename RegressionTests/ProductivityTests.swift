import XCTest
import SwiftUI
import PDFKit

final class ProductivityTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testSearchSortRenameFavoriteAndRestartPreserveSource() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Férias.txt")
        try Data("conteúdo original".utf8).write(to: source)
        let store = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        let ownedURL = store.url(for: entry)
        store.query = "FERIAS"; store.kindFilter = .text
        XCTAssertEqual(store.visibleEntries(photosOnly: false).map(\.id), [entry.id])
        XCTAssertTrue(store.visibleEntries(photosOnly: true).isEmpty)
        store.favoritesOnly = true
        XCTAssertTrue(store.visibleEntries(photosOnly: false).isEmpty)
        try store.toggleFavorite(entry.id)
        XCTAssertEqual(store.visibleEntries(photosOnly: false).count, 1)
        try store.rename(entry.id, to: "Leitura de viagem")
        XCTAssertTrue(store.visibleEntries(photosOnly: false).isEmpty)
        XCTAssertThrowsError(try store.rename(entry.id, to: "../fora"))
        let restored = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        let updated = try XCTUnwrap(restored.entries.first)
        XCTAssertEqual(updated.title, "Leitura de viagem")
        XCTAssertEqual(updated.favorite, true)
        XCTAssertEqual(restored.url(for: updated), ownedURL)
        XCTAssertEqual(try String(contentsOf: source), "conteúdo original")
        store.resetFilters()
        let other = folder.appendingPathComponent("A.txt")
        try Data("x".utf8).write(to: other); await store.importFile(other)
        store.sort = .name
        XCTAssertEqual(store.visibleEntries(photosOnly: false).first?.title, "A.txt")
        store.sort = .size
        XCTAssertEqual(store.visibleEntries(photosOnly: false).first?.id, entry.id)
    }

    @MainActor
    func testLegacyIndexWithoutNewMetadataLoads() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("old.txt")
        try Data("V36".utf8).write(to: source)
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [[
            "id": id.uuidString, "filename": "old.txt", "title": "Antigo",
            "kind": "text", "bytes": 3
        ]])
        try data.write(to: folder.appendingPathComponent("index.json"))
        let store = VRMediaStore(folder: folder)
        XCTAssertEqual(store.entries.first?.id, id)
        XCTAssertNil(store.entries.first?.favorite)
        XCTAssertNil(store.entries.first?.readingPosition)
    }

    @MainActor
    func testFailedMetadataWriteRollsBackRenameAndFavorite() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("original".utf8).write(to: source)
        let owned = folder.appendingPathComponent("owned")
        let store = VRMediaStore(folder: owned)
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        let index = owned.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.rename(entry.id, to: "Não salvo"))
        XCTAssertEqual(store.entries.first?.title, entry.title)
        XCTAssertThrowsError(try store.toggleFavorite(entry.id))
        XCTAssertNil(store.entries.first?.favorite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: entry).path))
    }

    @MainActor
    func testTextPagesKeepNewlinesUnicodeAndResumeAfterRestart() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = (0..<40).map { "Linha \($0) 👨‍👩‍👧‍👦 café\n" }.joined()
        let source = folder.appendingPathComponent("linhas.txt")
        try Data(original.utf8).write(to: source)
        let owned = folder.appendingPathComponent("owned")
        let store = VRMediaStore(folder: owned)
        store.configureReadingViewport(CGSize(width: 170, height: 85))
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        await store.open(entry)
        XCTAssertGreaterThan(store.pageCount, 3)
        var reconstructed = ""
        for _ in 0..<store.pageCount {
            reconstructed += store.textPage
            store.changePage(1)
        }
        XCTAssertEqual(reconstructed, original)
        store.changePage(Int.min)
        XCTAssertEqual(store.pdfPage, 0)
        store.changePage(2)
        store.adjustReaderSize(2)
        let savedText = store.textPage
        let savedSize = store.readerSize
        store.closePreview()
        let reopened = VRMediaStore(folder: owned)
        reopened.configureReadingViewport(CGSize(width: 170, height: 85))
        await reopened.open(try XCTUnwrap(reopened.entries.first))
        XCTAssertEqual(reopened.textPage, savedText)
        XCTAssertEqual(reopened.readerSize, savedSize)
        reopened.changePage(Int.max)
        XCTAssertEqual(reopened.pdfPage, reopened.pageCount - 1)
    }

    @MainActor
    func testPDFResumesPageAndPreviewButtonsNavigate() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("book.pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 200)).pdfData { context in
            for i in 1...3 {
                context.beginPage()
                ("Página \(i)" as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
            }
        }
        try data.write(to: source)
        let owned = folder.appendingPathComponent("owned")
        let store = VRMediaStore(folder: owned)
        await store.importFile(source)
        await store.open(try XCTUnwrap(store.entries.first))
        store.performPreview(.next); store.performPreview(.next)
        store.closePreview()
        let reopened = VRMediaStore(folder: owned)
        await reopened.open(try XCTUnwrap(reopened.entries.first))
        XCTAssertEqual(reopened.pdfPage, 2)
        reopened.performPreview(.rotate) // Início for documents.
        XCTAssertEqual(reopened.pdfPage, 0)
        reopened.performPreview(.close)
        XCTAssertNil(reopened.preview)
    }

    @MainActor
    func testGalleryZoomRotationAndCanonicalOwnedFile() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        for name in ["a.png", "b.png"] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { ctx in
                UIColor.cyan.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            }
            let url = folder.appendingPathComponent(name)
            try XCTUnwrap(image.pngData()).write(to: url); await store.importFile(url)
        }
        let first = store.entries[0]
        let second = store.entries[1]
        let ids = [first.id, second.id]
        await store.open(first, gallery: ids)
        store.setZoom(99); XCTAssertEqual(store.zoom, 4)
        store.setZoom(.nan); XCTAssertEqual(store.zoom, 4)
        store.moveImage(by: CGSize(width: 9999, height: -9999), viewport: CGSize(width: 100, height: 80))
        XCTAssertEqual(store.pan, CGSize(width: 150, height: -120))
        for _ in 0..<5 { store.rotateImage() }
        XCTAssertEqual(store.quarterTurns, 1)
        await store.browsePhoto(1)
        XCTAssertEqual(store.preview?.id, second.id)
        XCTAssertEqual(store.zoom, 1); XCTAssertEqual(store.quarterTurns, 0)
        XCTAssertEqual(store.galleryPosition, "2/2")
        // Stale/crafted metadata cannot substitute another file with the same id.
        let forged = VRMediaEntry(id: second.id, filename: "../a.png", title: "forged", kind: .text, bytes: 1)
        await store.open(forged)
        XCTAssertEqual(store.preview?.kind, .image)
        try store.remove(forged)
        XCTAssertNil(store.preview)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path))
        XCTAssertEqual(store.entries.count, 1)
    }

    @MainActor
    func testClosingWhileDecodingDoesNotReopenPreview() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("cancel.txt")
        try Data(String(repeating: "texto ", count: 1000).utf8).write(to: source)
        let store = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        await store.importFile(source)
        let entry = try XCTUnwrap(store.entries.first)
        var finished = false
        let task = Task { await store.open(entry); finished = true }
        for _ in 0..<1000 {
            if store.loadingPreview || finished { break }
            await Task.yield()
        }
        store.closePreview()
        await task.value
        XCTAssertNil(store.preview)
        XCTAssertNil(store.text)
        XCTAssertFalse(store.loadingPreview)
    }

    @MainActor
    func testTabsRestoreActiveURLAndReopenClosedWithoutCrossingApps() throws {
        let suite = "vros.productivity." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = VRWebSession(app: .browser, defaults: defaults)
        browser.address = "https://example.com/a"; browser.navigate()
        browser.newTab()
        browser.address = "https://example.com/b"; browser.navigate()
        let active = browser.activeTabID
        let restored = VRWebSession(app: .browser, defaults: defaults)
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.activeTabID, active)
        XCTAssertEqual(restored.requestedURL.absoluteString, "https://example.com/b")
        restored.closeActiveTab()
        XCTAssertEqual(restored.tabs.count, 1)
        restored.reopenClosedTab()
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.requestedURL.absoluteString, "https://example.com/b")
        let youtube = VRWebSession(app: .youtube, defaults: defaults)
        XCTAssertEqual(youtube.tabs.count, 1)
        XCTAssertEqual(youtube.requestedURL, VRWebApp.youtube.startURL)
    }

    @MainActor
    func testMalformedTabRestoreRejectsUnsafeURLsDuplicatesAndExcess() throws {
        let suite = "vros.productivity." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let valid = VRBrowserTab(url: URL(string: "https://example.com")!)
        let unsafe = VRBrowserTab(url: URL(string: "https://user:pass@example.com")!)
        var tabs = [unsafe, valid, valid]
        for i in 0..<12 { tabs.append(VRBrowserTab(url: URL(string: "https://example.com/\(i)")!)) }
        let data = try JSONEncoder().encode(VRBrowserSnapshot(tabs: tabs, active: unsafe.id))
        defaults.set(data, forKey: "vros.web.tabs.v1.browser")
        let restored = VRWebSession(app: .browser, defaults: defaults)
        XCTAssertEqual(restored.tabs.count, 8)
        XCTAssertEqual(Set(restored.tabs.map(\.id)).count, 8)
        XCTAssertTrue(restored.tabs.allSatisfy { VRBrowserURL.isAllowed($0.url) })
        XCTAssertEqual(restored.activeTabID, valid.id)
        restored.setPageZoom(.infinity)
        XCTAssertTrue(restored.pageZoom.isFinite)
    }

    @MainActor
    func testBackupRoundtripAppliesAndPersistsPreferencesWithoutClearingOtherData() throws {
        let suite = "vros.backup." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = VRSettingsSession(defaults: defaults)
        session.lens.choose(.wide); session.lens.spacing = 0.03
        session.cursorSize = 1.3; session.pinchSensitivity = 0.8
        session.showCursor = false; session.largeText = true; session.reduceMotion = true
        session.webZoom = 1.4; session.cinemaFOV = 100; session.themeIndex = 2
        let original = VRSettingsBackup(settings: session, scenery: 3)
        let encoded = try original.encoded()
        let decoded = try VRSettingsBackup.decode(encoded)
        session.cursorSize = 0.7; session.showCursor = true; session.themeIndex = 0
        defaults.set(["https://example.com"], forKey: "vros.web.history.v1")
        let scenery = try decoded.apply(to: session)
        let reopened = VRSettingsSession(defaults: defaults)
        XCTAssertEqual(try VRSettingsBackup(settings: reopened, scenery: scenery).encoded(), encoded)
        XCTAssertEqual(defaults.stringArray(forKey: "vros.web.history.v1"), ["https://example.com"])
        XCTAssertNil(session.command)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("history"))
    }

    @MainActor
    func testInvalidBackupsAreRejectedBeforeAnyPreferenceChanges() throws {
        let suite = "vros.backup." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = VRSettingsSession(defaults: defaults)
        let before = VRSettingsBackup(settings: session, scenery: 0)
        var invalid = before
        invalid.numbers["scale"] = 99
        XCTAssertThrowsError(try invalid.apply(to: session))
        XCTAssertEqual(session.lens.scale, 1)
        invalid = before; invalid.flags["hud"] = nil
        XCTAssertThrowsError(try invalid.apply(to: session))
        invalid = before; invalid.version = 2
        XCTAssertThrowsError(try invalid.apply(to: session))
        invalid = before; invalid.numbers["profile"] = 1.5
        XCTAssertThrowsError(try invalid.apply(to: session))
        XCTAssertThrowsError(try VRSettingsBackup.decode(Data(repeating: 32, count: 65_537)))
        XCTAssertEqual(try VRSettingsBackup(settings: session, scenery: 0).encoded(), try before.encoded())
    }

    func testPreviewTouchAndVisionBoundsDoNotOverlapContentOrEachOther() {
        for size in [CGSize(width: 242, height: 236), CGSize(width: 304, height: 342)] {
            let actions = VRMediaPreviewAction.allCases
            for action in actions {
                let rect = VRMediaPreviewGeometry.rect(action, in: size)
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect))
                XCTAssertEqual(VRMediaPreviewGeometry.action(at: CGPoint(x: rect.midX, y: rect.midY), in: size), action)
                XCTAssertFalse(rect.intersects(VRMediaPreviewGeometry.content(size)))
                for other in actions where other != action {
                    XCTAssertFalse(rect.intersects(VRMediaPreviewGeometry.rect(other, in: size)))
                }
            }
            XCTAssertNil(VRMediaPreviewGeometry.action(at: CGPoint(x: size.width / 2, y: size.height / 2), in: size))
        }
    }

    @MainActor
    func testPreviewRendersAtSmallAndLargeLensSizes() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("leitura.txt")
        try Data("Leitura binocular\n\nTexto com acentos e posição compartilhada entre os dois olhos.".utf8).write(to: source)
        let store = VRMediaStore(folder: folder.appendingPathComponent("owned"))
        await store.importFile(source); await store.open(try XCTUnwrap(store.entries.first))
        for size in [CGSize(width: 242, height: 236), CGSize(width: 304, height: 342)] {
            let controller = UIHostingController(rootView: VRMediaPreview(store: store))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller; window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "V37-43-preview-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1000)
            window.isHidden = true
        }
    }
}
