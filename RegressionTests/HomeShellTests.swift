import XCTest
import SwiftUI
import UIKit

final class HomeShellTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "vros.home.test." + UUID().uuidString))
    }

    @MainActor
    func testLibrarySearchFiltersAccentsAndSectionAndResetsPage() throws {
        let model = VRHomeLibrary(defaults: try defaults())
        model.page = 2
        model.query = "ATUALIZACOES"
        XCTAssertEqual(model.page, 0)
        XCTAssertEqual(model.entries.map(\.id), ["updates"])
        model.query = ""
        model.section = .web
        XCTAssertEqual(Set(model.entries.map(\.id)), ["browser", "youtube", "netflix", "wikipedia", "twitch"])
        model.section = .worlds
        XCTAssertEqual(model.entries.count, 4)
        XCTAssertTrue(model.entries.allSatisfy { $0.kind == .world })
        model.section = .windows
        XCTAssertTrue(model.entries.isEmpty)
    }

    @MainActor
    func testPinsAndRecentAppsPersistWithNoUnknownOrDuplicateIDs() throws {
        let storage = try defaults()
        storage.set(["cinema", "cinema", "https://untrusted.example", "world.0", "settings"], forKey: "vros.home.pins.v48")
        let model = VRHomeLibrary(defaults: storage)
        XCTAssertEqual(model.pinned, ["cinema", "settings"])
        model.opened("photos")
        model.opened("files")
        model.opened("photos")
        model.opened("missing")
        model.togglePin("browser")
        model.togglePin("files")
        model.togglePin("notes")
        XCTAssertEqual(model.pinned.count, 4)
        let restored = VRHomeLibrary(defaults: storage)
        XCTAssertEqual(restored.pinned, model.pinned)
        XCTAssertEqual(restored.recent, ["photos", "files"])
        XCTAssertEqual(restored.entries.first?.id, "photos")
        model.togglePin("cinema")
        XCTAssertFalse(model.pinned.contains("cinema"))
    }

    @MainActor
    func testVisibleTargetsUseTheSameTransformAtAllHeadsetSizes() throws {
        let model = VRHomeLibrary(defaults: try defaults())
        for size in [CGSize(width: 243, height: 236), CGSize(width: 304, height: 342), CGSize(width: 600, height: 300)] {
            let canvas = VRHomeCanvas(viewport: size)
            for target in VRHomeLayout.targets(model, windows: []) {
                let center = CGPoint(x: target.rect.midX, y: target.rect.midY)
                let point = canvas.screen(center)
                XCTAssertEqual(VRHomeLayout.hit(point, viewport: size, model: model, windows: []), target.action, target.id)
                let roundTrip = canvas.local(point)
                XCTAssertEqual(roundTrip.x, center.x, accuracy: 0.001)
                XCTAssertEqual(roundTrip.y, center.y, accuracy: 0.001)
            }
        }
        model.visible = false
        let size = CGSize(width: 304, height: 342)
        let point = VRHomeCanvas(viewport: size).screen(CGPoint(x: 320, y: 140))
        XCTAssertNil(VRHomeLayout.hit(point, viewport: size, model: model, windows: []))
        XCTAssertFalse(VRHomeLayout.blocks(point, viewport: size, model: model))
    }

    @MainActor
    func testMinimizedWindowRemainsAnExplicitRestorationTarget() throws {
        let model = VRHomeLibrary(defaults: try defaults())
        model.section = .windows
        let id = UUID()
        let windows = [VRHomeWindow(id: id, title: "Navegador", symbol: "globe", minimized: true)]
        let target = try XCTUnwrap(VRHomeLayout.targets(model, windows: windows).first { $0.action == .window(id) })
        XCTAssertTrue(target.detail.contains("restaurar"))
        model.turnPage(100, windowCount: windows.count)
        XCTAssertEqual(model.page, 0)
    }

    @MainActor
    func testKeyboardEditsTheActualDestinationWithABoundedBuffer() {
        let keyboard = VRSpatialKeyboardSession()
        let id = UUID()
        keyboard.open(.browser(id), title: "Endereço", text: "")
        for key in ["o", "i", "space", "shift", "a", "delete", "symbols", "@", "."] { keyboard.type(key) }
        XCTAssertEqual(keyboard.text, "oi @.")
        XCTAssertEqual(keyboard.destination, .browser(id))
        keyboard.type("clear")
        XCTAssertTrue(keyboard.text.isEmpty)
        keyboard.open(.library, title: "Busca", text: String(repeating: "a", count: 600))
        keyboard.type("b")
        XCTAssertEqual(keyboard.text.count, 512)
        for symbols in [false, true] {
            for key in VRKeyboardGeometry.keys(symbols: symbols, uppercase: false) {
                let size = CGSize(width: 243, height: 236)
                let point = VRHomeCanvas(viewport: size).screen(CGPoint(x: key.rect.midX, y: key.rect.midY))
                XCTAssertEqual(VRKeyboardGeometry.hit(point, viewport: size, symbols: symbols, uppercase: false), key.id)
            }
        }
    }

    func testWindowChromeOffersSixDistinctActionsInsideTheViewport() {
        let viewport = CGSize(width: 243, height: 236)
        let frame = VRWindowChromeGeometry.frame(center: CGPoint(x: 121, y: 120),
            dimensions: CGSize(width: 200, height: 140), viewport: viewport)
        XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(frame))
        for action in VRWindowAction.allCases {
            let button = VRWindowChromeGeometry.button(action, frame: frame)
            XCTAssertEqual(VRWindowChromeGeometry.hit(CGPoint(x: button.midX, y: button.midY), frame: frame), action)
        }
    }

    @MainActor
    func testNativeLibraryAndKeyboardPreviews() async throws {
        let model = VRHomeLibrary(defaults: try defaults())
        let size = CGSize(width: 960, height: 630)
        let library = ZStack {
            VRHomeBackdrop()
            VRHomeShell(library: model, viewport: size, windows: [], cameraEnabled: false,
                motionAvailable: false, dwellDelay: 1, onAction: { _ in })
        }.frame(width: size.width, height: size.height).preferredColorScheme(.dark)
        try await screenshot(library, size: size, name: "VR-OS-V48-Biblioteca")
        model.visible = false; model.quickSettings = true
        try await screenshot(library, size: size, name: "VR-OS-V48-Ajustes-rapidos")
        let keyboard = VRSpatialKeyboardSession()
        keyboard.open(.library, title: "Pesquisar na Biblioteca", text: "Cinema")
        try await screenshot(VRSpatialKeyboard(session: keyboard, viewport: size, onKey: { _ in })
            .preferredColorScheme(.dark), size: size, name: "VR-OS-V48-Teclado")
        model.quickSettings = false; model.visible = true
        let screen = CGSize(width: 1100, height: 540)
        let placement = VRLensSettings().placement(in: screen)
        let stereo = ZStack {
            Color.black
            ForEach(0..<2) { eye in
                ZStack {
                    VRHomeBackdrop()
                    VRHomeShell(library: model, viewport: placement.aperture, windows: [], cameraEnabled: false,
                        motionAvailable: false, dwellDelay: 1, onAction: { _ in })
                }.frame(width: placement.aperture.width, height: placement.aperture.height)
                    .clipShape(VRLensAperture(curvature: 0.85))
                    .position(eye == 0 ? placement.left : placement.right)
            }
        }.frame(width: screen.width, height: screen.height).preferredColorScheme(.dark)
        try await screenshot(stereo, size: screen, name: "VR-OS-V48-Binocular")
    }

    @MainActor
    private func screenshot<Content: View>(_ content: Content, size: CGSize, name: String) async throws {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 180_000_000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VR-OS-Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
    }
}
