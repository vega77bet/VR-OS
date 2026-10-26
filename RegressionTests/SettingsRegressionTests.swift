import XCTest
import SwiftUI
import UIKit
import SceneKit
import AVFoundation

final class SettingsRegressionTests: XCTestCase {
    @MainActor
    func testDemoMovieImportsAsHalfSBS() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "VR-OS-demo-H-SBS", withExtension: "mp4"))
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let cinema = CinemaModel()
        cinema.loadMovie(url)
        for _ in 0..<30 {
            if cinema.movieTitle == "VR-OS-demo-H-SBS" { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(cinema.movieTitle, "VR-OS-demo-H-SBS")
        XCTAssertEqual(cinema.selectedMode, .halfSBS)
        XCTAssertNil(cinema.errorMessage)
        cinema.exit()
        XCTAssertFalse(cinema.playing)
    }

    @MainActor
    func testMountedStereoTablesFollowSearchAndNavigation() async throws {
        let session = VRSettingsSession()
        let root = HStack(spacing: 0) {
            VRSettingsScreen(session: session, rightEye: false, onClose: {})
            VRSettingsScreen(session: session, rightEye: true, onClose: {})
        }.frame(width: 600, height: 300)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let left = try XCTUnwrap(session.primaryTable)
        let right = try XCTUnwrap(session.secondaryTable)
        session.searchText = "PINCA"
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(left.numberOfSections, right.numberOfSections)
        XCTAssertEqual(left.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(right.numberOfRows(inSection: 0), 1)
        let row = try XCTUnwrap(session.sections.first?.rows.first)
        session.perform(row)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(session.page, .hands)
        XCTAssertEqual(left.numberOfSections, right.numberOfSections)
        for section in 0..<left.numberOfSections {
            XCTAssertEqual(left.numberOfRows(inSection: section),
                           right.numberOfRows(inSection: section))
        }
        session.back()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(session.page, .home)
        XCTAssertEqual(left.contentOffset.y, right.contentOffset.y, accuracy: 0.01)
    }

    @MainActor
    func testCinemaCropsUseSeparateEyeHalvesAndCanSwap() throws {
        let cinema = CinemaModel()
        let screens = cinema.scene.rootNode.childNodes.filter {
            $0.geometry is SCNPlane && ($0.categoryBitMask == 2 || $0.categoryBitMask == 4)
        }.sorted { $0.categoryBitMask < $1.categoryBitMask }
        XCTAssertEqual(screens.count, 2)
        let left = try XCTUnwrap(screens.first?.geometry?.firstMaterial)
        let right = try XCTUnwrap(screens.last?.geometry?.firstMaterial)
        cinema.selectMode(.sbs)
        XCTAssertEqual(left.diffuse.contentsTransform.m11, 0.5)
        XCTAssertEqual(right.diffuse.contentsTransform.m41 - left.diffuse.contentsTransform.m41,
                       cinema.swapEyes ? -0.5 : 0.5, accuracy: 0.0001)
        cinema.toggleEyeOrder()
        XCTAssertEqual(right.diffuse.contentsTransform.m41 - left.diffuse.contentsTransform.m41,
                       cinema.swapEyes ? -0.5 : 0.5, accuracy: 0.0001)
        cinema.selectMode(.overUnder)
        XCTAssertEqual(left.diffuse.contentsTransform.m22, 0.5)
        XCTAssertEqual(abs(right.diffuse.contentsTransform.m42 - left.diffuse.contentsTransform.m42),
                       0.5, accuracy: 0.0001)
        cinema.selectMode(.twoD)
        XCTAssertEqual(left.diffuse.contentsTransform.m11, 1)
        XCTAssertEqual(right.diffuse.contentsTransform.m41, 0)
    }

    @MainActor
    func testLateMovieImportCannotAutoplayAfterExit() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try Data([0, 1, 2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let cinema = CinemaModel()
        cinema.loadMovie(url)
        cinema.exit()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(cinema.playing)
        XCTAssertTrue(cinema.controlsVisible)
        let photoToken = cinema.beginPhotoImport()
        cinema.exit()
        XCTAssertFalse(cinema.acceptsPhotoImport(photoToken))
    }
    @MainActor
    func testEveryControlPersistsAcrossNewSession() throws {
        let name = "vros.regression." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = VRSettingsSession(defaults: defaults)
        for page in VRSettingsPage.allCases {
            for row in VRSettingsCatalog.sections(for: page).flatMap(\.rows) {
                switch row.kind {
                case .toggle, .choice: session.perform(row)
                case .stepper: session.perform(row, direction: 1)
                case .slider: session.setNormalized(row.id, fraction: 0.8)
                default: break
                }
            }
        }
        let reopened = VRSettingsSession(defaults: defaults)
        for page in VRSettingsPage.allCases {
            for row in VRSettingsCatalog.sections(for: page).flatMap(\.rows) {
                XCTAssertEqual(reopened.value(for: row.id), session.value(for: row.id), row.id)
                XCTAssertEqual(reopened.toggled(row.id), session.toggled(row.id), row.id)
                XCTAssertEqual(reopened.selected(row.id), session.selected(row.id), row.id)
            }
        }
        XCTAssertEqual(reopened.lens, session.lens)
    }

    @MainActor
    func testResetRequiresConfirmationAndPersistsDefaults() throws {
        let name = "vros.regression." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = VRSettingsSession(defaults: defaults)
        session.cameraUltra = true
        session.fullCameraFrame = false
        session.themeIndex = 3
        session.cinemaImmersive = false
        session.cinemaSwapEyes = true
        session.cinemaAutoControls = false
        session.setNormalized("windows.opacity", fraction: 0)
        let reset = try XCTUnwrap(VRSettingsCatalog.sections(for: .general)
            .flatMap(\.rows).first { $0.id == "general.reset" })
        session.perform(reset)
        XCTAssertNil(session.command)
        XCTAssertEqual(session.themeIndex, 3)
        session.perform(reset)
        XCTAssertNotNil(session.command)
        let reopened = VRSettingsSession(defaults: defaults)
        XCTAssertFalse(reopened.cameraUltra)
        XCTAssertTrue(reopened.fullCameraFrame)
        XCTAssertEqual(reopened.themeIndex, 0)
        XCTAssertTrue(reopened.cinemaImmersive)
        XCTAssertFalse(reopened.cinemaSwapEyes)
        XCTAssertTrue(reopened.cinemaAutoControls)
        XCTAssertEqual(reopened.windowOpacity, 1)
    }

    @MainActor
    func testInvalidStoredNumbersHaveSafeDefaults() throws {
        let name = "vros.regression." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Double.nan, forKey: "vros.lens.size.v1")
        defaults.set(Double.infinity, forKey: "vros.lens.zoom.v1")
        defaults.set(Double.nan, forKey: "vros.webZoom.v1")
        defaults.set(999, forKey: "vros.selectedTheme.v1")
        let session = VRSettingsSession(defaults: defaults)
        XCTAssertEqual(session.lens.scale, 1)
        XCTAssertEqual(session.lens.cameraZoom, 1)
        XCTAssertEqual(session.webZoom, 1)
        XCTAssertEqual(session.themeIndex, 0)
        session.setNormalized("cinema.fov", fraction: .nan)
        XCTAssertEqual(session.cinemaFOV, 85)
    }

    @MainActor
    func testStepperLabelDoesNotIncrement() throws {
        let row = try XCTUnwrap(VRSettingsCatalog.sections(for: .hands)
            .flatMap(\.rows).first { $0.id == "hands.cursorSize" })
        let name = "vros.regression." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = VRSettingsSession(defaults: defaults)
        session.perform(row)
        XCTAssertEqual(session.cursorSize, 1)
        session.perform(row, direction: 1)
        XCTAssertEqual(session.cursorSize, 1.1, accuracy: 0.001)
        session.perform(row, direction: -1)
        XCTAssertEqual(session.cursorSize, 1, accuracy: 0.001)
    }

    @MainActor
    func testSearchAndNavigationResetBothScrollOffsets() {
        let session = VRSettingsSession()
        let left = UITableView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let right = UITableView(frame: left.frame)
        session.primaryTable = left
        session.secondaryTable = right
        for table in [left, right] { table.contentSize = CGSize(width: 300, height: 1000) }
        session.beginPhysicalScroll(rightEye: true)
        right.contentOffset.y = 180
        session.updateScroll(180, fromRightEye: true)
        XCTAssertEqual(left.contentOffset.y, 180, accuracy: 0.01)
        session.searchText = "camera"
        XCTAssertEqual(session.scrollOffset, 0)
        XCTAssertEqual(left.contentOffset.y, 0)
        XCTAssertEqual(right.contentOffset.y, 0)
        session.enter(.visor)
        session.scrollBy(70)
        XCTAssertEqual(right.contentOffset.y, left.contentOffset.y, accuracy: 0.01)
        session.back()
        XCTAssertEqual(session.page, .home)
        XCTAssertEqual(session.scrollOffset, 0)
    }

    @MainActor
    func testUIKitControlsChangeSharedSession() throws {
        let name = "vros.regression." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = VRSettingsSession(defaults: defaults)
        let toggleRow = try XCTUnwrap(VRSettingsCatalog.sections(for: .hands)
            .flatMap(\.rows).first { $0.id == "hands.cursor" })
        let left = VRSettingsTableCell(style: .default, reuseIdentifier: nil)
        let right = VRSettingsTableCell(style: .default, reuseIdentifier: nil)
        left.configure(row: toggleRow, session: session, enabled: true)
        let control = try XCTUnwrap(left.contentView.subviews.compactMap { $0 as? UISwitch }.first)
        control.isOn = false
        control.sendActions(for: .valueChanged)
        XCTAssertFalse(session.showCursor)
        right.configure(row: toggleRow, session: session, enabled: true)
        XCTAssertFalse(try XCTUnwrap(right.contentView.subviews.compactMap { $0 as? UISwitch }.first).isOn)
        let sliderRow = try XCTUnwrap(VRSettingsCatalog.sections(for: .cinema)
            .flatMap(\.rows).first { $0.id == "cinema.fov" })
        left.configure(row: sliderRow, session: session, enabled: true)
        left.slider.value = 1
        left.slider.sendActions(for: .valueChanged)
        right.configure(row: sliderRow, session: session, enabled: true)
        XCTAssertEqual(session.cinemaFOV, 115)
        XCTAssertEqual(right.slider.value, 1)
    }

    func testInvalidVisionSampleCancelsHeldPinch() {
        var detector = VRPinchDetector()
        for _ in 0..<2 {
            _ = detector.update(thumb: .zero, index: .zero, palmWidth: 0.2)
        }
        XCTAssertTrue(detector.pinching)
        XCTAssertFalse(detector.update(thumb: CGPoint(x: CGFloat.nan, y: 0),
                                      index: .zero, palmWidth: 0.2))
    }
}
