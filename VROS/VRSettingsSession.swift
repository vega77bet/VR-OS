import SwiftUI
import UIKit

struct VRSettingsCommand: Identifiable {
    enum Kind { case recenterWindows, clearFavorites, restoreAll }
    let id = UUID()
    let kind: Kind
}

/// One shared, observable model for BOTH eyes. The last touched UIKit table
/// owns scrolling; its scroll offset drives the peer. Hand
/// gestures query the same UITableView rows instead of guessing row geometry.
@MainActor
final class VRSettingsSession: ObservableObject {
    @Published var page: VRSettingsPage = .home
    @Published var searchText: String = "" {
        didSet { if searchText != oldValue { resetScroll() } }
    }
    private let defaults: UserDefaults
    // High-frequency scroll updates must NOT publish into the whole
    // SwiftUI/ARKit headset tree. UIKit mirrors the peer table directly.
    private(set) var scrollOffset: CGFloat = 0
    @Published var focusSearchRequest = 0
    @Published var command: VRSettingsCommand?
    @Published private(set) var revision = 0
    @Published var notice: String?
    @Published var pendingConfirmation: String?

    @Published var lens = VRLensSettings() {
        didSet { lens.save(to: defaults) }
    }
    @Published var cameraUltra = false {
        didSet { defaults.set(cameraUltra, forKey: "vros.ultra.enabled.v1") }
    }
    @Published var fullCameraFrame = true {
        didSet { defaults.set(fullCameraFrame, forKey: "vros.ultra.fullFrame.v1") }
    }
    @Published var invertUltraMotion = false {
        didSet { defaults.set(invertUltraMotion, forKey: "vros.ultra.invertMotion.v1") }
    }
    @Published var themeIndex = 0 {
        didSet { defaults.set(themeIndex, forKey: "vros.selectedTheme.v1") }
    }
    @Published var webZoom: CGFloat = 1.0 {
        didSet { defaults.set(Double(webZoom), forKey: "vros.webZoom.v1") }
    }
    @Published var cinemaFOV: CGFloat = 88 {
        didSet { defaults.set(Double(cinemaFOV), forKey: "vros.cinema.fov.v1") }
    }
    @Published var cinemaInvert = false {
        didSet { defaults.set(cinemaInvert, forKey: "vros.cinema.invert.v1") }
    }
    @Published var cinemaImmersive = true {
        didSet { defaults.set(cinemaImmersive, forKey: "vros.cinema.immersive.v1") }
    }
    @Published var cinemaSwapEyes = false {
        didSet { defaults.set(cinemaSwapEyes, forKey: "vros.cinema.swapEyes.v1") }
    }
    @Published var cinemaAutoControls = true {
        didSet { defaults.set(cinemaAutoControls, forKey: "vros.cinema.autoControls.v1") }
    }

    @Published var showSkeleton: Bool = true {
        didSet { defaults.set(showSkeleton,
                                           forKey: "vros.settings.skeleton.v1") }
    }
    @Published var showCursor: Bool = true {
        didSet { defaults.set(showCursor,
                                           forKey: "vros.settings.cursor.v1") }
    }
    @Published var cursorSize: CGFloat = 1 {
        didSet { defaults.set(Double(cursorSize),
                                           forKey: "vros.settings.cursorSize.v1") }
    }
    @Published var pinchSensitivity: CGFloat = 0.5 {
        didSet { defaults.set(Double(pinchSensitivity),
                                           forKey: "vros.settings.pinch.v1") }
    }
    @Published var windowOpacity: CGFloat = 1 {
        didSet { defaults.set(Double(windowOpacity),
                                           forKey: "vros.settings.opacity.v1") }
    }
    @Published var defaultDepth: CGFloat = 1.6 {
        didSet { defaults.set(Double(defaultDepth),
                                           forKey: "vros.settings.defaultDepth.v1") }
    }
    @Published var reduceMotion = false {
        didSet { defaults.set(reduceMotion, forKey: "vros.reduceMotion.v1") }
    }
    @Published var largeText = false {
        didSet { defaults.set(largeText, forKey: "vros.largeText.v1") }
    }
    @Published var showHUD: Bool = true {
        didSet { defaults.set(showHUD,
                                           forKey: "vros.settings.hud.v1") }
    }

    weak var primaryTable: UITableView?
    weak var secondaryTable: UITableView?
    // Physical touches can scroll EITHER eye; the last user-dragged eye
    // temporarily becomes the source. Vision pinches always use left eye.
    private(set) var scrollOwnerRightEye = false

    func beginPhysicalScroll(rightEye: Bool) {
        scrollOwnerRightEye = rightEye
    }

    var sections: [VRSettingsSection] {
        VRSettingsCatalog.sections(for: page, search: searchText)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lens = VRLensSettings.load(from: defaults)
        let d = defaults
        func flag(_ key: String, otherwise: Bool) -> Bool {
            d.object(forKey: key) == nil ? otherwise : d.bool(forKey: key)
        }
        func decimal(_ key: String, otherwise: CGFloat,
                     min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            guard d.object(forKey: key) != nil else { return otherwise }
            let number = CGFloat(d.double(forKey: key))
            return number.isFinite ? max(lower, min(upper, number)) : otherwise
        }
        showSkeleton = flag("vros.settings.skeleton.v1", otherwise: true)
        showCursor = flag("vros.settings.cursor.v1", otherwise: true)
        cursorSize = decimal("vros.settings.cursorSize.v1", otherwise: 1,
                             min: 0.7, max: 1.6)
        pinchSensitivity = decimal("vros.settings.pinch.v1", otherwise: 0.5,
                                   min: 0, max: 1)
        windowOpacity = decimal("vros.settings.opacity.v1", otherwise: 1,
                                min: 0.42, max: 1)
        defaultDepth = decimal("vros.settings.defaultDepth.v1", otherwise: 1.6,
                               min: 0.75, max: 3.5)
        showHUD = flag("vros.settings.hud.v1", otherwise: true)
        reduceMotion = flag("vros.reduceMotion.v1", otherwise: false)
        largeText = flag("vros.largeText.v1", otherwise: false)
        webZoom = decimal("vros.webZoom.v1", otherwise: 1, min: 0.65, max: 1.55)
        let theme = d.integer(forKey: "vros.selectedTheme.v1")
        themeIndex = (0...3).contains(theme) ? theme : 0
        cameraUltra = flag("vros.ultra.enabled.v1", otherwise: false)
        fullCameraFrame = flag("vros.ultra.fullFrame.v1", otherwise: true)
        cinemaImmersive = flag("vros.cinema.immersive.v1", otherwise: true)
        cinemaSwapEyes = flag("vros.cinema.swapEyes.v1", otherwise: false)
        cinemaAutoControls = flag("vros.cinema.autoControls.v1", otherwise: true)
        invertUltraMotion = d.bool(forKey: "vros.ultra.invertMotion.v1")
        cinemaInvert = d.bool(forKey: "vros.cinema.invert.v1")
        let fov = d.double(forKey: "vros.cinema.fov.v1")
        if fov >= 55 && fov <= 115 { cinemaFOV = CGFloat(fov) }
    }

    func enter(_ next: VRSettingsPage) {
        page = next
        notice = nil
        pendingConfirmation = nil
        resetScroll()
    }

    func back() {
        if page != .home { enter(.home) }
    }

    func resetScroll() {
        scrollOwnerRightEye = false
        scrollOffset = 0
        primaryTable?.setContentOffset(.zero, animated: false)
        secondaryTable?.setContentOffset(.zero, animated: false)
    }

    private func mirrorScroll(_ position: CGFloat, into table: UITableView?) {
        guard let table = table, table.bounds.height > 0 else { return }
        let maximum = max(0, table.contentSize.height - table.bounds.height)
        let clamped = max(0, min(maximum, position))
        guard abs(table.contentOffset.y - clamped) > 0.6 else { return }
        table.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
    }

    func updateScroll(_ offset: CGFloat, fromRightEye: Bool) {
        guard scrollOwnerRightEye == fromRightEye,
              abs(scrollOffset - offset) > 0.5 else { return }
        scrollOffset = max(0, offset)
        // Direct UIKit-to-UIKit update gives both lenses the SAME vertical
        // position without redrawing the entire SwiftUI camera scene.
        mirrorScroll(scrollOffset, into: fromRightEye
                     ? primaryTable : secondaryTable)
    }

    func scrollBy(_ delta: CGFloat) {
        guard let table = primaryTable else { return }
        scrollOwnerRightEye = false
        let maxOffset = max(0, table.contentSize.height - table.bounds.height)
        let next = max(0, min(maxOffset, scrollOffset + delta))
        scrollOffset = next
        mirrorScroll(next, into: primaryTable)
        mirrorScroll(next, into: secondaryTable)
    }

    func value(for id: String) -> String {
        switch id {
        case "visor.size": return "\(Int(lens.scale * 100))%"
        case "visor.ipd": return "\(Int(lens.spacing * 1000))"
        case "visor.height": return "\(Int(lens.verticalOffset * 100))%"
        case "visor.zoom": return "\(Int(lens.cameraZoom * 100))%"
        case "visor.curve": return "\(Int(lens.curvature * 100))%"
        case "hands.cursorSize": return "\(Int(cursorSize * 100))%"
        case "hands.sensitivity": return "\(Int(pinchSensitivity * 100))%"
        case "windows.opacity": return "\(Int(windowOpacity * 100))%"
        case "windows.depth": return String(format: "%.1f m", Double(defaultDepth))
        case "cinema.fov": return "\(Int(cinemaFOV))°"
        case "web.zoom": return "\(Int(webZoom * 100))%"
        default: return ""
        }
    }

    func toggled(_ id: String) -> Bool {
        switch id {
        case "camera.ultra": return cameraUltra
        case "camera.full": return fullCameraFrame
        case "camera.invert": return invertUltraMotion
        case "hands.skeleton": return showSkeleton
        case "hands.cursor": return showCursor
        case "appearance.hud": return showHUD
        case "appearance.motion": return reduceMotion
        case "appearance.text": return largeText
        case "cinema.invert": return cinemaInvert
        case "cinema.immersive": return cinemaImmersive
        case "cinema.eyes": return cinemaSwapEyes
        case "cinema.autoControls": return cinemaAutoControls
        default: return false
        }
    }

    func selected(_ id: String) -> Bool {
        switch id {
        case "visor.reference": return lens.profile == .reference
        case "visor.wide": return lens.profile == .wide
        case "visor.compact": return lens.profile == .compact
        case "theme.0": return themeIndex == 0
        case "theme.1": return themeIndex == 1
        case "theme.2": return themeIndex == 2
        case "theme.3": return themeIndex == 3
        default: return false
        }
    }

    func normalized(_ id: String) -> CGFloat {
        switch id {
        case "hands.sensitivity": return pinchSensitivity
        case "windows.opacity": return (windowOpacity - 0.42) / 0.58
        case "cinema.fov": return (cinemaFOV - 55) / 60
        case "web.zoom": return (webZoom - 0.65) / 0.90
        default: return 0
        }
    }

    func setNormalized(_ id: String, fraction: CGFloat) {
        let t = max(0, min(1, fraction.isFinite ? fraction : 0.5))
        pendingConfirmation = nil
        switch id {
        case "hands.sensitivity":
            pinchSensitivity = t
        case "windows.opacity":
            windowOpacity = 0.42 + t * 0.58
        case "cinema.fov":
            cinemaFOV = CGFloat(Int(55 + t * 60))
        case "web.zoom":
            webZoom = CGFloat(Int((0.65 + 0.90 * t) * 100)) / 100
        default: return
        }
        revision += 1
    }

    func perform(_ row: VRSettingsRow, direction: Int = 0) {
        switch row.kind {
        case let .navigate(next):
            enter(next)
            return
        case .information:
            return
        case .slider:
            if direction != 0 {
                setNormalized(row.id, fraction: normalized(row.id) +
                              CGFloat(direction) * 0.08)
            }
            return
        case .stepper:
            guard direction != 0 else { return }
            step(row.id, direction)
        case .toggle:
            flip(row.id)
        case .choice:
            choose(row.id)
        case .action:
            execute(row.id)
        }
        if row.kind != .action { pendingConfirmation = nil }
        revision += 1
    }

    private func step(_ id: String, _ direction: Int) {
        var next = lens
        let step = CGFloat(direction)
        switch id {
        case "visor.size":
            next.scale = max(0.75, min(1.40, next.scale + step * 0.05))
        case "visor.ipd":
            next.spacing = max(-0.075, min(0.12, next.spacing + step * 0.012))
        case "visor.height":
            next.verticalOffset = max(-0.16,
                                       min(0.16, next.verticalOffset + step * 0.015))
        case "visor.zoom":
            next.cameraZoom = max(0.8,
                                  min(1.3, next.cameraZoom + step * 0.05))
        case "visor.curve":
            next.curvature = max(0, min(1, next.curvature + step * 0.125))
        case "hands.cursorSize":
            cursorSize = max(0.7, min(1.6, cursorSize + step * 0.1))
        case "windows.depth":
            defaultDepth = max(0.75, min(3.5, defaultDepth + step * 0.15))
        default: break
        }
        if id.hasPrefix("visor.") { lens = next }
    }

    private func flip(_ id: String) {
        switch id {
        case "camera.ultra": cameraUltra.toggle()
        case "camera.full": fullCameraFrame.toggle()
        case "camera.invert": invertUltraMotion.toggle()
        case "hands.skeleton": showSkeleton.toggle()
        case "hands.cursor": showCursor.toggle()
        case "appearance.hud": showHUD.toggle()
        case "appearance.motion": reduceMotion.toggle()
        case "appearance.text": largeText.toggle()
        case "cinema.invert": cinemaInvert.toggle()
        case "cinema.immersive": cinemaImmersive.toggle()
        case "cinema.eyes": cinemaSwapEyes.toggle()
        case "cinema.autoControls": cinemaAutoControls.toggle()
        default: break
        }
    }

    private func choose(_ id: String) {
        switch id {
        case "visor.reference": lens.choose(.reference)
        case "visor.wide": lens.choose(.wide)
        case "visor.compact": lens.choose(.compact)
        case "theme.0": themeIndex = 0
        case "theme.1": themeIndex = 1
        case "theme.2": themeIndex = 2
        case "theme.3": themeIndex = 3
        default: break
        }
    }

    private func execute(_ id: String) {
        switch id {
        case "windows.center":
            command = VRSettingsCommand(kind: .recenterWindows)
            notice = "Janelas centralizadas"
        case "visor.reset":
            lens.choose(.reference)
            notice = "Visor restaurado"
        case "web.clear", "general.reset":
            guard pendingConfirmation == id else {
                pendingConfirmation = id
                notice = "Toque novamente para confirmar"
                return
            }
            pendingConfirmation = nil
            if id == "web.clear" {
                command = VRSettingsCommand(kind: .clearFavorites)
                notice = "Favoritos removidos"
            } else {
                resetPreferences()
                command = VRSettingsCommand(kind: .restoreAll)
                notice = "Preferências restauradas"
            }
        default: break
        }
    }

    private func resetPreferences() {
        lens.choose(.reference)
        showSkeleton = true
        showCursor = true
        cursorSize = 1
        pinchSensitivity = 0.5
        windowOpacity = 1
        defaultDepth = 1.6
        showHUD = true
        reduceMotion = false
        largeText = false
        themeIndex = 0
        fullCameraFrame = true
        invertUltraMotion = false
        webZoom = 1
        cinemaFOV = 88
        cinemaInvert = false
        cinemaImmersive = true
        cinemaSwapEyes = false
        cinemaAutoControls = true
        cameraUltra = false
    }

    /// Pinch coordinates use the same UITableView indexes as physical
    /// touchscreen touches; scrolling is always driven by the primary eye.
    func row(at viewportPoint: CGPoint, topInset: CGFloat) -> VRSettingsRow? {
        guard let table = primaryTable else { return nil }
        // Navigation/search publishes before SwiftUI has reloaded UIKit.
        // Ignore a Vision frame against the previous page's row geometry.
        if let source = table.dataSource as? VRSettingsTable.Coordinator {
            guard source.page == page, source.search == searchText else { return nil }
        }
        let localY = viewportPoint.y - topInset
        guard localY >= 0, localY < table.bounds.height else { return nil }
        let localX = viewportPoint.x
        guard localX >= 0, localX <= table.bounds.width else { return nil }
        let contentPoint = CGPoint(x: localX,
                                   y: localY + table.contentOffset.y)
        guard let indexPath = table.indexPathForRow(at: contentPoint) else {
            return nil
        }
        let sections = self.sections
        guard indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].rows.count else {
            return nil
        }
        return sections[indexPath.section].rows[indexPath.row]
    }

    func isSliderHit(at point: CGPoint, topInset: CGFloat) -> Bool {
        guard let table = primaryTable,
              let row = row(at: point, topInset: topInset),
              row.kind == .slider else { return false }
        let contentPoint = CGPoint(
            x: point.x, y: point.y - topInset + table.contentOffset.y)
        guard let path = table.indexPathForRow(at: contentPoint),
              let cell = table.cellForRow(at: path)
                  as? VRSettingsTableCell else { return false }
        let rect = cell.slider.convert(cell.slider.bounds, to: table)
        return point.x >= rect.minX - 3 && point.x <= rect.maxX + 3 &&
               contentPoint.y >= rect.minY - 7 &&
               contentPoint.y <= rect.maxY + 7
    }

    func handlePinchTap(at point: CGPoint, viewport: CGSize,
                        topInset: CGFloat) -> Bool {
        guard let row = row(at: point, topInset: topInset) else { return false }
        if row.kind == .information { return true }
        if row.kind == .stepper {
            guard let direction = stepperDirection(at: point,
                                                   topInset: topInset) else {
                // Pinching the label does NOT adjust a value.
                return false
            }
            perform(row, direction: direction)
        } else if row.kind == .slider {
            guard isSliderHit(at: point, topInset: topInset) else {
                return false
            }
            setNormalized(row.id, fraction: sliderFraction(
                x: point.x, width: viewport.width,
                localY: point.y - topInset))
        } else {
            perform(row)
        }
        return true
    }

    func stepperDirection(at point: CGPoint, topInset: CGFloat) -> Int? {
        guard let table = primaryTable else { return nil }
        let inTable = CGPoint(x: point.x,
                              y: point.y - topInset +
                                 table.contentOffset.y)
        guard let path = table.indexPathForRow(at: inTable),
              let cell = table.cellForRow(at: path)
                  as? VRSettingsTableCell else { return nil }
        return cell.stepperDirection(at: inTable, in: table)
    }

    func sliderFraction(x: CGFloat, width: CGFloat,
                        localY: CGFloat? = nil) -> CGFloat {
        // Hit the UISlider's REAL visible track, including grouped cell
        // margins; do not assume that cell.width == headset viewport.width.
        if let y = localY, let table = primaryTable {
            let contentY = y + table.contentOffset.y
            if let indexPath = table.indexPathForRow(
                at: CGPoint(x: x, y: contentY)),
               let cell = table.cellForRow(at: indexPath)
                   as? VRSettingsTableCell {
                let rect = cell.slider.convert(cell.slider.bounds, to: table)
                let start = rect.minX + 11
                let length = max(1, rect.width - 22)
                return max(0, min(1, (x - start) / length))
            }
        }
        // Fallback while UIKit is still mounting the primary eye.
        return max(0, min(1, (x - (width - 114)) / 92))
    }
}

