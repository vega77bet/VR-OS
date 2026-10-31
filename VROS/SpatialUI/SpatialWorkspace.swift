import Foundation
import simd

/// Input-independent spatial desktop. Its actual window/element geometry is also
/// the renderer's input; no parallel hit boxes or screen coordinates are maintained.
struct SpatialWorkspace {
    private(set) var windows: [SpatialWindow]
    private(set) var activeApp: AppDestination = .home
    private(set) var revision = 0
    private(set) var libraryPage = 0
    private(set) var panelDistance: Float = 2.4
    var focusedWindowID: String? { windows.first(where: { $0.isFocused && $0.isOpen })?.id }
    private var timeText = "--:--"
    private var dateText = "VR-OS 2.0"
    private var statusText = "Home espacial · 3DoF"
    private var batteryText = "Bateria indisponível"
    private var controlText = "Automático · mira da cabeça"
    private var opticalText = "Perfil de lentes provisório"
    private enum AppPanelMode { case destination, controls, calibration }
    private var appPanelMode = AppPanelMode.destination
    private var transitions: [String: WindowTransition] = [:]
    private var headingTransition: HeadingTransition?

    private struct WindowTransition {
        var startPosition: SIMD3<Float>
        var endPosition: SIMD3<Float>
        var startOrientation: simd_quatf
        var endOrientation: simd_quatf
        var startOpacity: Float
        var endOpacity: Float
        var start: TimeInterval
        var closeOnCompletion: Bool
    }
    private struct HeadingTransition {
        var start: TimeInterval
        var target: simd_quatf
        var previous = simd_quatf(real: 1, imag: .zero)
    }

    init() {
        windows = [
            SpatialWindow(id: "main", position: SIMD3(0, 1.86, -2.4), size: SIMD2(2.2, 1.2), title: "VR-OS"),
            SpatialWindow(id: "dock", position: SIMD3(0, 0.9, -2.2),
                          orientation: simd_quatf(angle: -0.25, axis: SIMD3(1, 0, 0)),
                          size: SIMD2(2.5, 0.34), cornerRadius: 0.10, title: ""),
            SpatialWindow(id: "library", position: SIMD3(0, 1.83, -2.1), size: SIMD2(2.18, 1.5),
                          title: "Aplicativos", isOpen: false, opacity: 0),
            SpatialWindow(id: "quick", position: SIMD3(0, 1.66, -1.72), size: SIMD2(1.55, 1.36),
                          title: "Acesso rápido", isOpen: false, opacity: 0),
            SpatialWindow(id: "app", position: SIMD3(0, 1.83, -2.25), size: SIMD2(2.15, 1.25),
                          title: "", isOpen: false, opacity: 0)
        ]
        focusWindow(id: "main")
        rebuildContent()
    }

    mutating func setSystemSummary(time: String, date: String, status: String, battery: String) {
        guard time != timeText || date != dateText || status != statusText || battery != batteryText else { return }
        timeText = time; dateText = date; statusText = status; batteryText = battery
        rebuildContent()
    }

    mutating func setControlSummary(_ text: String) {
        guard controlText != text else { return }
        controlText = text; rebuildContent()
    }

    mutating func setOpticalSummary(_ text: String) {
        guard opticalText != text else { return }
        opticalText = text; rebuildContent()
    }

    mutating func perform(_ action: SpatialAction, headPose: simd_quatf, at time: TimeInterval) {
        update(at: time)
        let previousFocus = focusedWindowID
        switch action {
        case .open(let destination):
            appPanelMode = .destination
            activeApp = destination
            switch destination {
            case .home:
                setOpen("main", true, at: time)
                setOpen("app", false, at: time)
                setOpen("library", false, at: time)
                setOpen("quick", false, at: time)
            case .applications, .library:
                setOpen("quick", false, at: time)
                setOpen("main", false, at: time)
                setOpen("app", false, at: time)
                setOpen("library", true, at: time)
            default:
                setOpen("main", false, at: time)
                setOpen("library", false, at: time)
                setOpen("quick", false, at: time)
                setOpen("app", true, at: time)
            }
        case .back:
            if isVisible("quick") { setOpen("quick", false, at: time) }
            else if isVisible("library") {
                activeApp = .home
                setOpen("library", false, at: time)
                setOpen("main", true, at: time)
            }
            else if appPanelMode != .destination { appPanelMode = .destination }
            else { activeApp = .home; setOpen("app", false, at: time); setOpen("main", true, at: time) }
        case .quickMenu:
            if isVisible("quick") { setOpen("quick", false, at: time) }
            else { recoverWindow("quick", headPose: headPose, at: time) }
        case .recenter:
            recenter(headPose: headPose, at: time)
        case .close(let id):
            if id != "dock" { setOpen(id, false, at: time) }
            if id == "library" || id == "app" {
                activeApp = .home
                setOpen("main", true, at: time)
            }
        case .recover(let id):
            recoverWindow(id, headPose: headPose, at: time)
        case .resetLayout:
            resetLayout(headPose: headPose, at: time)
        case .scroll(let delta):
            guard isVisible("library"), delta != 0 else { break }
            libraryPage = max(0, min(1, libraryPage + (delta > 0 ? 1 : -1)))
        case .setDistance(let distance):
            guard distance.isFinite else { break }
            panelDistance = max(1.6, min(3.5, distance))
            for id in ["main", "app", "library"] {
                guard let index = index(id) else { continue }
                var p = windows[index].position
                let delta = p - StereoCamera.headPosition
                let horizontal = SIMD3(delta.x, 0, delta.z)
                let norm = simd_length(horizontal)
                let offset: Float = id == "app" ? -0.15 : (id == "library" ? -0.3 : 0)
                let depth = max(1.4, panelDistance + offset)
                if norm > 0.001 { p = StereoCamera.headPosition + horizontal / norm * depth; p.y = windows[index].position.y }
                if windows[index].isOpen {
                    if var closing = transitions[id], closing.closeOnCompletion {
                        closing.startPosition = windows[index].position
                        closing.endPosition = p
                        closing.startOpacity = windows[index].opacity
                        closing.start = time
                        transitions[id] = closing
                    } else { animatePosition(id, to: p, orientation: windows[index].orientation, at: time) }
                } else {
                    // Updating a persisted distance must not open hidden app/library panels.
                    windows[index].position = p
                }
            }
        case .controls, .calibration:
            activeApp = .settings
            appPanelMode = action == .controls ? .controls : .calibration
            setOpen("main", false, at: time)
            setOpen("library", false, at: time)
            setOpen("quick", false, at: time)
            setOpen("app", true, at: time)
        case .exitImmersive, .cycleInputMode, .cyclePointerMode, .nextController, .recenterPointer,
             .adjustDwell, .adjustSensitivity, .adjustOptics, .resetOptics:
            // Routed by the native app coordinator; do not pretend an external
            // system settings or Bluetooth operation happened in this model.
            break
        }
        switch action {
        case .open(let destination):
            focusWindow(id: destination == .home ? "main" :
                (destination == .applications || destination == .library ? "library" : "app"))
        case .controls, .calibration:
            focusWindow(id: "app")
        case .recover(let id):
            focusWindow(id: id)
        case .quickMenu, .back, .resetLayout:
            focusFallback()
        case .close(let id):
            if previousFocus == id || focusedWindowID == nil { focusFallback() }
        default: break
        }
        rebuildContent()
    }

    /// Focus is exclusive and never changes transforms or depth ordering.
    mutating func focusWindow(id: String) {
        guard isVisible(id), focusedWindowID != id else { return }
        for index in windows.indices { windows[index].isFocused = windows[index].id == id }
        revision &+= 1
    }

    private mutating func focusFallback() {
        if let id = ["quick", "library", "app", "main", "dock"].first(where: { isVisible($0) }) {
            focusWindow(id: id)
        }
    }

    mutating func update(at time: TimeInterval) {
        var changed = false
        for (id, transition) in Array(transitions) {
            guard let index = index(id) else { transitions.removeValue(forKey: id); continue }
            let progress = Self.smooth(Float((time - transition.start) / 0.24))
            windows[index].position = transition.startPosition + (transition.endPosition - transition.startPosition) * progress
            windows[index].orientation = simd_slerp(transition.startOrientation, transition.endOrientation, progress)
            windows[index].opacity = transition.startOpacity + (transition.endOpacity - transition.startOpacity) * progress
            changed = true
            if time - transition.start >= 0.24 {
                if transition.closeOnCompletion { windows[index].isOpen = false }
                transitions.removeValue(forKey: id)
            }
        }
        if var heading = headingTransition {
            let progress = Self.smooth(Float((time - heading.start) / 0.32))
            let current = simd_slerp(simd_quatf(real: 1, imag: .zero), heading.target, progress)
            let delta = current * heading.previous.inverse
            for index in windows.indices {
                windows[index].position = Self.rotate(windows[index].position, by: delta)
                windows[index].orientation = simd_normalize(delta * windows[index].orientation)
            }
            for id in Array(transitions.keys) {
                guard var transition = transitions[id] else { continue }
                transition.startPosition = Self.rotate(transition.startPosition, by: delta)
                transition.endPosition = Self.rotate(transition.endPosition, by: delta)
                transition.startOrientation = delta * transition.startOrientation
                transition.endOrientation = delta * transition.endOrientation
                transitions[id] = transition
            }
            heading.previous = current
            headingTransition = time - heading.start >= 0.32 ? nil : heading
            changed = true
        }
        if changed { revision &+= 1 }
    }

    mutating func moveWindow(id: String, to proposed: SIMD3<Float>, headPose: simd_quatf) {
        guard let index = index(id), isVisible(id) else { return }
        let position = SpatialGeometry.comfortablePosition(proposed, headPose: headPose)
        windows[index].position = position
        let towardViewer = StereoCamera.headPosition - position
        let yaw = atan2(towardViewer.x, towardViewer.z)
        // Upright windows avoid accumulating roll while a stick/controller is used.
        windows[index].orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        transitions.removeValue(forKey: id)
        headingTransition = nil
        focusWindow(id: id)
        revision &+= 1
    }

    func action(for hit: SpatialHit) -> SpatialAction? {
        guard let window = windows.first(where: { $0.id == hit.windowID && $0.isOpen && $0.opacity >= 0.8 }),
              let id = hit.elementID else { return nil }
        return window.elements.first(where: { $0.id == id })?.action
    }

    private func index(_ id: String) -> Int? { windows.firstIndex(where: { $0.id == id }) }
    private func isVisible(_ id: String) -> Bool {
        guard let index = index(id), windows[index].isOpen else { return false }
        return transitions[id]?.closeOnCompletion != true
    }
    private static func smooth(_ value: Float) -> Float {
        let t = max(0, min(1, value)); return t * t * (3 - 2 * t)
    }
    private static func rotate(_ position: SIMD3<Float>, by rotation: simd_quatf) -> SIMD3<Float> {
        StereoCamera.headPosition + rotation.act(position - StereoCamera.headPosition)
    }

    private mutating func setOpen(_ id: String, _ open: Bool, at time: TimeInterval) {
        guard let index = index(id), isVisible(id) != open else { return }
        let window = windows[index]
        windows[index].isOpen = true
        if !open { windows[index].isFocused = false }
        transitions[id] = WindowTransition(startPosition: window.position,
                                           endPosition: window.position,
                                           startOrientation: window.orientation,
                                           endOrientation: window.orientation,
                                           startOpacity: window.opacity, endOpacity: open ? 1 : 0,
                                           start: time, closeOnCompletion: !open)
    }

    private mutating func animatePosition(_ id: String, to position: SIMD3<Float>, orientation: simd_quatf,
                                         at time: TimeInterval) {
        guard let index = index(id) else { return }
        let window = windows[index]
        windows[index].isOpen = true
        transitions[id] = WindowTransition(startPosition: window.position, endPosition: position,
                                           startOrientation: window.orientation, endOrientation: orientation,
                                           startOpacity: window.opacity, endOpacity: 1,
                                           start: time, closeOnCompletion: false)
    }

    private mutating func recoverWindow(_ id: String, headPose: simd_quatf, at time: TimeInterval) {
        guard index(id) != nil else { return }
        let yaw = SpatialGeometry.horizontalOrientation(of: headPose) ?? simd_quatf(real: 1, imag: .zero)
        let local: SIMD3<Float>
        if id == "dock" { local = SIMD3(0, -0.75, -2.2) }
        else if id == "quick" { local = SIMD3(0, 0.05, -1.72) }
        else { local = SIMD3(0, 0.18, -panelDistance) }
        let orientation = id == "dock" ? yaw * simd_quatf(angle: -0.25, axis: SIMD3(1, 0, 0)) : yaw
        animatePosition(id, to: StereoCamera.headPosition + yaw.act(local), orientation: orientation, at: time)
    }

    private mutating func recenter(headPose: simd_quatf, at time: TimeInterval) {
        guard let target = SpatialGeometry.horizontalOrientation(of: headPose), let main = index("main") else { return }
        let direction = windows[main].position - StereoCamera.headPosition
        guard direction.x * direction.x + direction.z * direction.z > 0.0001 else { return }
        let current = simd_quatf(angle: atan2(-direction.x, -direction.z), axis: SIMD3(0, 1, 0))
        headingTransition = HeadingTransition(start: time, target: simd_normalize(target * current.inverse))
    }

    private mutating func resetLayout(headPose: simd_quatf, at time: TimeInterval) {
        let previous = windows
        let yaw = SpatialGeometry.horizontalOrientation(of: headPose) ?? simd_quatf(real: 1, imag: .zero)
        let defaults = SpatialWorkspace()
        windows = defaults.windows
        activeApp = .home; libraryPage = 0; panelDistance = defaults.panelDistance
        appPanelMode = .destination
        transitions.removeAll(); headingTransition = nil
        for index in windows.indices {
            let destination = Self.rotate(windows[index].position, by: yaw)
            let orientation = yaw * windows[index].orientation
            if windows[index].isOpen, let old = previous.first(where: { $0.id == windows[index].id }) {
                windows[index].position = old.position
                windows[index].orientation = old.orientation
                windows[index].opacity = old.opacity
                animatePosition(windows[index].id, to: destination, orientation: orientation, at: time)
            } else { windows[index].position = destination; windows[index].orientation = orientation }
        }
    }

    private mutating func rebuildContent() {
        for index in windows.indices {
            let id = windows[index].id
            switch id {
            case "main": windows[index].elements = mainElements()
            case "dock": windows[index].elements = dockElements()
            case "library": windows[index].elements = libraryElements()
            case "quick": windows[index].elements = quickElements()
            case "app":
                switch appPanelMode {
                case .destination: windows[index].title = activeApp.title; windows[index].size = SIMD2(2.15, 1.25)
                case .controls: windows[index].title = "Controles"; windows[index].size = SIMD2(2.15, 1.8)
                case .calibration: windows[index].title = "Calibração"; windows[index].size = SIMD2(2.15, 1.75)
                }
                windows[index].elements = appElements()
            default: break
            }
        }
        revision &+= 1
    }

    private func element(_ id: String, window: String, x: Float, y: Float, w: Float, h: Float,
                         title: String, symbol: String? = nil, action: SpatialAction? = nil,
                         style: SpatialElementStyle = .button, selected: Bool = false) -> SpatialElement {
        SpatialElement(id: "\(window).\(id)", windowID: window, center: SIMD2(x, y), size: SIMD2(w, h),
                       cornerRadius: min(0.035, h * 0.18), title: title, symbol: symbol,
                       action: action, style: style, selected: selected)
    }
    private func controls(_ id: String, width: Float, height: Float) -> [SpatialElement] {
        [element("recover", window: id, x: width / 2 - 0.31, y: height / 2 - 0.14, w: 0.16, h: 0.16,
                 title: "", symbol: "scope", action: .recover(id)),
         element("close", window: id, x: width / 2 - 0.12, y: height / 2 - 0.14, w: 0.16, h: 0.16,
                 title: "", symbol: "xmark", action: .close(id))]
    }

    private func mainElements() -> [SpatialElement] {
        controls("main", width: 2.2, height: 1.2) + [
            element("greeting", window: "main", x: -0.34, y: 0.27, w: 1.25, h: 0.14,
                    title: "Seu espaço, suas possibilidades", style: .label),
            element("quickMenu", window: "main", x: 0.71, y: 0.25, w: 0.52, h: 0.18,
                    title: "Menu", symbol: "ellipsis", action: .quickMenu),
            element("clock", window: "main", x: -0.67, y: 0.03, w: 0.65, h: 0.28, title: timeText, style: .label),
            element("date", window: "main", x: -0.60, y: -0.16, w: 0.8, h: 0.1, title: dateText, style: .caption),
            element("status", window: "main", x: 0.40, y: 0.05, w: 1.02, h: 0.13, title: statusText, style: .caption),
            element("battery", window: "main", x: 0.40, y: -0.12, w: 1.02, h: 0.10, title: batteryText, style: .caption),
            element("apps", window: "main", x: -0.68, y: -0.40, w: 0.59, h: 0.22,
                    title: "Aplicativos", symbol: AppDestination.applications.symbol, action: .open(.applications)),
            element("recenter", window: "main", x: 0, y: -0.40, w: 0.59, h: 0.22,
                    title: "Centralizar", symbol: "scope", action: .recenter),
            element("settings", window: "main", x: 0.68, y: -0.40, w: 0.59, h: 0.22,
                    title: "Ajustes", symbol: AppDestination.settings.symbol, action: .open(.settings))
        ]
    }
    private func dockElements() -> [SpatialElement] {
        AppDestination.allCases.enumerated().map { index, app in
            element(app.rawValue, window: "dock", x: (Float(index) - 3.5) * 0.30, y: 0,
                    w: 0.28, h: 0.28, title: app.title, symbol: app.symbol,
                    action: .open(app), style: .appIcon, selected: activeApp == app)
        }
    }
    private func libraryElements() -> [SpatialElement] {
        var elements = controls("library", width: 2.18, height: 1.5)
        let apps = Array(AppDestination.allCases.dropFirst(libraryPage * 6).prefix(6))
        for (index, app) in apps.enumerated() {
            elements.append(element(app.rawValue, window: "library", x: Float(index % 3 - 1) * 0.65,
                                    y: index < 3 ? 0.22 : -0.22, w: 0.57, h: 0.34,
                                    title: app.title, symbol: app.symbol, action: .open(app),
                                    style: .appIcon, selected: activeApp == app))
        }
        elements.append(element("previous", window: "library", x: -0.74, y: -0.57, w: 0.30, h: 0.18,
                                title: "", symbol: "chevron.up", action: .scroll(-1)))
        elements.append(element("page", window: "library", x: 0, y: -0.57, w: 0.9, h: 0.12,
                                title: "Página \(libraryPage + 1) / 2", style: .caption))
        elements.append(element("next", window: "library", x: 0.74, y: -0.57, w: 0.30, h: 0.18,
                                title: "", symbol: "chevron.down", action: .scroll(1)))
        return elements
    }
    private func quickElements() -> [SpatialElement] {
        var elements = controls("quick", width: 1.55, height: 1.36)
        let actions: [(String, String, String, SpatialAction)] = [
            ("home", "Início", "house.fill", .open(.home)),
            ("apps", "Aplicativos", "square.grid.2x2.fill", .open(.applications)),
            ("recenter", "Centralizar", "scope", .recenter),
            ("controllers", "Controles", "gamecontroller.fill", .controls),
            ("calibrate", "Calibração", "eye.fill", .calibration),
            ("exit", "Sair do visor", "rectangle.portrait.and.arrow.right", .exitImmersive)
        ]
        for (index, entry) in actions.enumerated() {
            elements.append(element(entry.0, window: "quick", x: index % 2 == 0 ? -0.35 : 0.35,
                                    y: 0.28 - Float(index / 2) * 0.25, w: 0.62, h: 0.21,
                                    title: entry.1, symbol: entry.2, action: entry.3))
        }
        elements.append(element("status", window: "quick", x: 0, y: -0.39, w: 1.3, h: 0.09,
                                title: "\(timeText) · \(batteryText)", style: .caption))
        elements.append(element("metrics", window: "quick", x: 0, y: -0.53, w: 1.3, h: 0.09,
                                title: statusText, style: .caption))
        return elements
    }
    private func appElements() -> [SpatialElement] {
        if appPanelMode == .controls { return controllerElements() }
        if appPanelMode == .calibration { return calibrationElements() }
        var elements = controls("app", width: 2.15, height: 1.25)
        if activeApp == .settings {
            elements += [
                element("controllers", window: "app", x: -0.49, y: 0.24, w: 0.87, h: 0.22,
                        title: "Controles", symbol: "gamecontroller.fill", action: .controls),
                element("calibration", window: "app", x: 0.49, y: 0.24, w: 0.87, h: 0.22,
                        title: "Calibração", symbol: "eye.fill", action: .calibration),
                element("nearer", window: "app", x: -0.49, y: -0.08, w: 0.87, h: 0.22,
                        title: "Aproximar painel", symbol: "minus.magnifyingglass", action: .setDistance(panelDistance - 0.25)),
                element("farther", window: "app", x: 0.49, y: -0.08, w: 0.87, h: 0.22,
                        title: "Afastar painel", symbol: "plus.magnifyingglass", action: .setDistance(panelDistance + 0.25)),
                element("layout", window: "app", x: 0, y: -0.41, w: 1.0, h: 0.22,
                        title: "Restaurar layout", symbol: "arrow.counterclockwise", action: .resetLayout)
            ]
        } else {
            elements += [
                element("symbol", window: "app", x: 0, y: 0.20, w: 0.28, h: 0.28,
                        title: "", symbol: activeApp.symbol, style: .label),
                element("message", window: "app", x: 0, y: -0.05, w: 1.7, h: 0.17,
                        title: "Recurso em desenvolvimento", style: .label),
                element("detail", window: "app", x: 0, y: -0.25, w: 1.8, h: 0.12,
                        title: "Este destino ainda não oferece seu conteúdo interno.", style: .caption),
                element("home", window: "app", x: 0, y: -0.45, w: 0.75, h: 0.20,
                        title: "Voltar ao Início", symbol: "house.fill", action: .open(.home))
            ]
        }
        return elements
    }

    private func controllerElements() -> [SpatialElement] {
        var elements = controls("app", width: 2.15, height: 1.8)
        elements.append(element("controllerSummary", window: "app", x: 0, y: 0.47, w: 1.85, h: 0.30,
                                title: controlText, style: .caption))
        let actions: [(String, String, String, SpatialAction)] = [
            ("inputMode", "Modo de entrada", "cursorarrow.rays", .cycleInputMode),
            ("pointerMode", "Modo do ponteiro", "scope", .cyclePointerMode),
            ("controller", "Próximo controle", "gamecontroller.fill", .nextController),
            ("pointerCenter", "Centralizar laser", "viewfinder", .recenterPointer),
            ("dwellDown", "Permanência −", "minus", .adjustDwell(-0.2)),
            ("dwellUp", "Permanência +", "plus", .adjustDwell(0.2)),
            ("speedDown", "Sensibilidade −", "minus", .adjustSensitivity(-0.2)),
            ("speedUp", "Sensibilidade +", "plus", .adjustSensitivity(0.2))
        ]
        for (index, entry) in actions.enumerated() {
            elements.append(element(entry.0, window: "app", x: index % 2 == 0 ? -0.49 : 0.49,
                                    y: 0.14 - Float(index / 2) * 0.26, w: 0.88, h: 0.22,
                                    title: entry.1, symbol: entry.2, action: entry.3))
        }
        return elements
    }

    private func calibrationElements() -> [SpatialElement] {
        var elements = controls("app", width: 2.15, height: 1.75)
        elements.append(element("opticalSummary", window: "app", x: 0, y: 0.54, w: 1.85, h: 0.13,
                                title: opticalText, style: .caption))
        let adjustments: [(String, String, OpticalAdjustment, Float)] = [
            ("ipdDown", "IPD −", .ipd, -0.001), ("ipdUp", "IPD +", .ipd, 0.001),
            ("distortionDown", "Distorção −", .distortion, -0.1), ("distortionUp", "Distorção +", .distortion, 0.1),
            ("resolutionDown", "Resolução −", .renderScale, -0.1), ("resolutionUp", "Resolução +", .renderScale, 0.1),
            ("distanceDown", "Distância −", .distance, -0.2), ("distanceUp", "Distância +", .distance, 0.2)
        ]
        for (index, entry) in adjustments.enumerated() {
            elements.append(element(entry.0, window: "app", x: index % 2 == 0 ? -0.49 : 0.49,
                                    y: 0.33 - Float(index / 2) * 0.27, w: 0.88, h: 0.22,
                                    title: entry.1, symbol: index % 2 == 0 ? "minus" : "plus",
                                    action: .adjustOptics(entry.2, entry.3)))
        }
        elements.append(element("restoreOptics", window: "app", x: 0, y: -0.73, w: 1.1, h: 0.18,
                                title: "Restaurar lentes", symbol: "arrow.counterclockwise", action: .resetOptics))
        return elements
    }
}
