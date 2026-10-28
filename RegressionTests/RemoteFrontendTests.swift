import XCTest
import SwiftUI

final class RemoteFrontendTests: XCTestCase {
    func testFallbackFrontendIsValidAndHasAllCoreActions() {
        let config = RemoteFrontendConfiguration.fallback
        XCTAssertTrue(config.validated)
        XCTAssertEqual(config.enabledTaskbar.count, 8)
        XCTAssertEqual(Set(config.enabledTaskbar.compactMap(\.resolvedAction)).count, 8)
    }

    func testRemoteFrontendDecodesAndReordersKnownActions() throws {
        let json = """
        {
          "schema": 1,
          "accentHex": "#123ABC",
          "surfaceHex": "#20242D",
          "taskbarOpacity": 0.91,
          "taskbar": [
            {"id":"settings","action":"settings","title":"Preferências","icon":"settings","enabled":true},
            {"id":"home","action":"home","title":"Início","icon":"home","enabled":true},
            {"id":"apps","action":"apps","title":"Apps","icon":"more","enabled":true},
            {"id":"cinema","action":"cinema","title":"Cinema","icon":"cinema","enabled":false}
          ]
        }
        """
        let config = try JSONDecoder().decode(RemoteFrontendConfiguration.self,
                                               from: Data(json.utf8))
        XCTAssertTrue(config.validated)
        XCTAssertEqual(config.enabledTaskbar.map(\.id), ["settings", "home", "apps"])
    }

    func testRemoteFrontendRejectsUnknownActionAndUnsafeIcon() throws {
        let json = """
        {
          "schema": 1,
          "accentHex": "#123ABC",
          "surfaceHex": "#20242D",
          "taskbarOpacity": 0.91,
          "taskbar": [
            {"id":"settings","action":"runCode","title":"Ajustes","icon":"settings","enabled":true},
            {"id":"home","action":"home","title":"Início","icon":"remote.svg","enabled":true},
            {"id":"apps","action":"apps","title":"Apps","icon":"more","enabled":true}
          ]
        }
        """
        let config = try JSONDecoder().decode(RemoteFrontendConfiguration.self,
                                               from: Data(json.utf8))
        XCTAssertFalse(config.validated)
    }

    func testTaskbarHitTestingFollowsRemoteOrder() {
        let items = [
            RemoteTaskbarItem(id: "settings", action: "settings", title: "Ajustes", icon: "settings", enabled: true),
            RemoteTaskbarItem(id: "home", action: "home", title: "Central", icon: "home", enabled: true),
            RemoteTaskbarItem(id: "apps", action: "apps", title: "Apps", icon: "more", enabled: true)
        ]
        let viewport = CGSize(width: 304, height: 342)
        let first = VRTaskbarGeometry.itemRect(0, viewport: viewport, count: 3).midX
        let y = VRTaskbarGeometry.itemRect(0, viewport: viewport, count: 3).midY
        XCTAssertEqual(
            VRTaskbarGeometry.action(at: CGPoint(x: first, y: y),
                                     viewport: viewport, items: items),
            .settings
        )
    }
}
