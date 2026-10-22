import ARKit
import SceneKit
import SwiftUI
import UIKit

final class SpatialEngine: NSObject, ObservableObject, ARSCNViewDelegate {
    weak var view: ARSCNView?
    weak var settings: WorkspaceSettings?

    @Published private(set) var windows: [SpatialWindow] = []
    @Published private(set) var tracking = "Iniciando rastreamento"
    @Published private(set) var selectedID: UUID?
    @Published private(set) var available = ARWorldTrackingConfiguration.isSupported

    private var nodes: [UUID: SCNNode] = [:]
    private var movingID: UUID?
    private var lastDrag: CGPoint = .zero
    private var startingScale: Float = 1
    private let maxWindows = 12

    func configure(_ sceneView: ARSCNView) {
        view = sceneView
        sceneView.delegate = self
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(tap)
        sceneView.addGestureRecognizer(pan)
        sceneView.addGestureRecognizer(pinch)

        guard ARWorldTrackingConfiguration.isSupported else {
            available = false
            tracking = "ARKit indisponível"
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func add(_ kind: AppKind) {
        guard let view = view, let frame = view.session.currentFrame else {
            tracking = "Aguarde a câmera iniciar"
            return
        }
        guard windows.count < maxWindows else {
            tracking = "Limite de 12 janelas"
            return
        }

        let distance = Float(settings?.distance ?? 1.25)
        let count = windows.count
        let offsetX = Float((count % 3) - 1) * 0.22
        let offsetY = Float((count / 3) % 3 - 1) * 0.14
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(offsetX, offsetY, -distance, 1)
        let world = simd_mul(frame.camera.transform, translation)
        let anchor = ARAnchor(name: "vros.\(kind.rawValue)", transform: world)
        let model = SpatialWindow(id: UUID(), kind: kind, anchorID: anchor.identifier, scale: Float(settings?.windowSize ?? 1))
        windows.append(model)
        selectedID = model.id
        view.session.add(anchor: anchor)
        feedback()
    }

    func remove(_ id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        if let anchor = view?.session.currentFrame?.anchors.first(where: { $0.identifier == window.anchorID }) {
            view?.session.remove(anchor: anchor)
        }
        nodes.removeValue(forKey: window.anchorID)
        windows.removeAll { $0.id == id }
        if selectedID == id { selectedID = windows.last?.id }
    }

    func closeAll() {
        for id in windows.map(\.id) { remove(id) }
    }

    func recenter() {
        guard let view = view, let frame = view.session.currentFrame else { return }
        let existing = windows
        for model in existing {
            if let anchor = frame.anchors.first(where: { $0.identifier == model.anchorID }) {
                view.session.remove(anchor: anchor)
            }
        }
        nodes.removeAll()
        windows.removeAll()
        for model in existing { add(model.kind) }
        tracking = "Janelas recentralizadas"
    }

    func select(_ id: UUID) {
        guard windows.contains(where: { $0.id == id }) else { return }
        selectedID = id
        feedback()
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let model = windows.first(where: { $0.anchorID == anchor.identifier }) else { return nil }
        let root = SCNNode()
        root.name = anchor.identifier.uuidString
        root.scale = SCNVector3(model.scale, model.scale, model.scale)

        let plane = SCNPlane(width: 0.78, height: 0.49)
        plane.cornerRadius = 0.038
        let material = SCNMaterial()
        material.diffuse.contents = panelImage(for: model.kind)
        material.isDoubleSided = true
        material.lightingModel = .constant
        plane.materials = [material]
        let surface = SCNNode(geometry: plane)
        surface.name = "panel"
        root.addChildNode(surface)

        DispatchQueue.main.async { [weak self] in
            self?.nodes[anchor.identifier] = root
        }
        return root
    }

    private func panelImage(for kind: AppKind) -> UIImage {
        let size = CGSize(width: 1000, height: 630)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let opacity = CGFloat(settings?.panelOpacity ?? 0.95)
            UIColor(red: 0.095, green: 0.11, blue: 0.15, alpha: opacity).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 52).fill()

            let line = UIBezierPath()
            line.move(to: CGPoint(x: 50, y: 132))
            line.addLine(to: CGPoint(x: 950, y: 132))
            UIColor.white.withAlphaComponent(0.12).setStroke()
            line.lineWidth = 2
            line.stroke()

            let dot = UIBezierPath(ovalIn: CGRect(x: 54, y: 56, width: 22, height: 22))
            UIColor(red: 0.96, green: 0.59, blue: 0.57, alpha: 1).setFill()
            dot.fill()

            let title = kind.title as NSString
            title.draw(at: CGPoint(x: 105, y: 48), withAttributes: [
                .font: UIFont.systemFont(ofSize: 39, weight: .semibold),
                .foregroundColor: UIColor.white
            ])

            let subtitle = kind.subtitle as NSString
            subtitle.draw(at: CGPoint(x: 65, y: 170), withAttributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ])

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 115, weight: .light)
            if let icon = UIImage(systemName: kind.symbol, withConfiguration: symbolConfig) {
                UIColor(settings?.accent.color ?? .white).setFill()
                let iconRect = CGRect(x: 72, y: 265, width: 130, height: 130)
                icon.withTintColor(UIColor(settings?.accent.color ?? .white), renderingMode: .alwaysOriginal).draw(in: iconRect)
            }

            let hint = "Toque para abrir • Arraste para mover • Pinça para ajustar" as NSString
            hint.draw(at: CGPoint(x: 65, y: 550), withAttributes: [
                .font: UIFont.systemFont(ofSize: 21, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ])
            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            context.cgContext.setLineWidth(3)
            context.cgContext.stroke(UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 50).cgPath)
        }
    }

    private func model(at point: CGPoint) -> SpatialWindow? {
        guard let view = view else { return nil }
        for hit in view.hitTest(point, options: [SCNHitTestOption.firstFoundOnly: false]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let anchorID = UUID(uuidString: current.name ?? ""),
                   let model = windows.first(where: { $0.anchorID == anchorID }) {
                    return model
                }
                node = current.parent
            }
        }
        return nil
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view, gesture.state == .ended else { return }
        guard let model = model(at: gesture.location(in: view)) else { return }
        select(model.id)
        NotificationCenter.default.post(name: .vrosOpenApp, object: model.kind.rawValue)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = view else { return }
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began:
            movingID = model(at: point)?.id
            lastDrag = point
            if let movingID = movingID { select(movingID) }
        case .changed:
            guard let id = movingID,
                  let model = windows.first(where: { $0.id == id }),
                  let node = nodes[model.anchorID],
                  let frame = view.session.currentFrame else { return }
            let dx = Float(point.x - lastDrag.x) * 0.0016
            let dy = Float(point.y - lastDrag.y) * -0.0016
            let rotation = simd_float3x3(frame.camera.transform)
            let right = rotation.columns.0
            let up = rotation.columns.1
            let movement = right * dx + up * dy
            node.simdWorldPosition += movement
            lastDrag = point
        case .ended, .cancelled, .failed:
            // Commit the moved node's world position to a new AR anchor.
            if let id = movingID,
               let model = windows.first(where: { $0.id == id }),
               let node = nodes[model.anchorID],
               let frame = view.session.currentFrame,
               let old = frame.anchors.first(where: { $0.identifier == model.anchorID }) {
                var transform = node.simdWorldTransform
                transform.columns.0 = simd_normalize(transform.columns.0)
                transform.columns.1 = simd_normalize(transform.columns.1)
                transform.columns.2 = simd_normalize(transform.columns.2)
                let replacement = ARAnchor(name: "vros.\(model.kind.rawValue)", transform: transform)
                view.session.remove(anchor: old)
                nodes.removeValue(forKey: model.anchorID)
                if let index = windows.firstIndex(where: { $0.id == id }) {
                    windows[index] = SpatialWindow(id: model.id, kind: model.kind, anchorID: replacement.identifier, scale: model.scale)
                }
                view.session.add(anchor: replacement)
            }
            movingID = nil
        default: break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = view else { return }
        let center = gesture.location(in: view)
        switch gesture.state {
        case .began:
            if let model = model(at: center) {
                selectedID = model.id
                startingScale = model.scale
            }
        case .changed, .ended:
            guard let id = selectedID, let index = windows.firstIndex(where: { $0.id == id }) else { return }
            let value = min(max(startingScale * Float(gesture.scale), 0.55), 1.85)
            windows[index].scale = value
            nodes[windows[index].anchorID]?.scale = SCNVector3(value, value, value)
        default: break
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let value: String
        switch camera.trackingState {
        case .normal: value = "Rastreamento ativo"
        case .notAvailable: value = "Rastreamento indisponível"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: value = "Mova o iPhone mais devagar"
            case .insufficientFeatures: value = "Aponte para um ambiente com detalhes"
            case .initializing: value = "Mapeando ambiente"
            case .relocalizing: value = "Relocalizando"
            @unknown default: value = "Rastreamento limitado"
            }
        }
        DispatchQueue.main.async { [weak self] in self?.tracking = value }
    }

    private func feedback() {
        guard settings?.haptics ?? true else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension Notification.Name {
    static let vrosOpenApp = Notification.Name("vros.openApp")
}

struct ARSurface: UIViewRepresentable {
    @ObservedObject var engine: SpatialEngine

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        engine.configure(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
