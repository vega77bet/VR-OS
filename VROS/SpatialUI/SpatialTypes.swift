import Foundation
import simd

enum AppDestination: String, CaseIterable, Codable {
    case home, applications, cinema, browser, files, photos, settings, library
    var title: String {
        switch self {
        case .home: return "Início"
        case .applications: return "Aplicativos"
        case .cinema: return "Cinema"
        case .browser: return "Navegador"
        case .files: return "Arquivos"
        case .photos: return "Fotos"
        case .settings: return "Ajustes"
        case .library: return "Biblioteca"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .applications: return "square.grid.2x2.fill"
        case .cinema: return "play.rectangle.fill"
        case .browser: return "globe"
        case .files: return "folder.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .settings: return "gearshape.fill"
        case .library: return "books.vertical.fill"
        }
    }
}

enum SpatialAction: Equatable {
    case open(AppDestination), back, quickMenu, recenter, controls, calibration, exitImmersive
    case close(String), recover(String), resetLayout, scroll(Int), setDistance(Float)
    case cycleInputMode, cyclePointerMode, nextController, recenterPointer
    case adjustDwell(Double), adjustSensitivity(Float), adjustOptics(OpticalAdjustment, Float), resetOptics
}

enum OpticalAdjustment: String { case ipd, distortion, renderScale, distance }

enum SpatialElementStyle: Equatable { case label, caption, button, appIcon }

struct SpatialElement {
    var id: String
    var windowID: String
    var center: SIMD2<Float>
    var size: SIMD2<Float>
    var cornerRadius: Float = 0.03
    var title: String
    var symbol: String? = nil
    var action: SpatialAction? = nil
    var style: SpatialElementStyle = .button
    var selected: Bool = false
}

/// Rigid window geometry shared verbatim by the mesh builder and raycaster.
struct SpatialWindow {
    var id: String
    var position: SIMD3<Float>
    var orientation: simd_quatf = simd_quatf(real: 1, imag: .zero)
    var size: SIMD2<Float>
    var cornerRadius: Float = 0.08
    var title: String
    var elements: [SpatialElement] = []
    var isOpen: Bool = true
    var opacity: Float = 1
}

struct SpatialRay {
    var origin: SIMD3<Float>
    var direction: SIMD3<Float>
}

struct SpatialHit: Equatable {
    var windowID: String
    var elementID: String?
    var distance: Float
    var point: SIMD3<Float>
}

struct SpatialPointerVisual {
    var ray: SpatialRay
    var end: SIMD3<Float>
    var isLaser: Bool
    var isHit: Bool
    var dwellProgress: Float
    var selectionPulse: Float
}

struct SpatialRenderFrame {
    var windows: [SpatialWindow]
    var focusedElementID: String?
    var grabbedWindowID: String?
    var pointer: SpatialPointerVisual
    var time: TimeInterval
    static let empty = SpatialRenderFrame(windows: [], focusedElementID: nil, grabbedWindowID: nil,
                                         pointer: SpatialPointerVisual(ray: SpatialRay(origin: .zero, direction: SIMD3(0, 0, -1)),
                                                                       end: SIMD3(0, 0, -3), isLaser: false, isHit: false,
                                                                       dwellProgress: 0, selectionPulse: 0), time: 0)
}
