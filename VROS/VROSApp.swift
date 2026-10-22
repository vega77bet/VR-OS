import SwiftUI
import ARKit
import SceneKit

@main
struct VROSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

final class ARCoordinator: NSObject, ARSCNViewDelegate, ObservableObject {
    weak var sceneView: ARSCNView?
    @Published var status = "Aponte a câmera para o ambiente"

    func addWindow() {
        guard let view = sceneView,
              let frame = view.session.currentFrame else {
            status = "Aguarde o rastreamento iniciar"
            return
        }
        var transform = matrix_identity_float4x4
        transform.columns.3.z = -1.2
        let world = simd_mul(frame.camera.transform, transform)
        let anchor = ARAnchor(name: "VRWindow", transform: world)
        view.session.add(anchor: anchor)
        status = "Janela fixada no ambiente"
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor.name == "VRWindow" else { return SCNNode() }
        let root = SCNNode()
        let panel = SCNPlane(width: 0.8, height: 0.48)
        panel.cornerRadius = 0.025
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.06, green: 0.10, blue: 0.19, alpha: 0.94)
        material.isDoubleSided = true
        material.lightingModel = .constant
        panel.materials = [material]
        let panelNode = SCNNode(geometry: panel)
        root.addChildNode(panelNode)

        let title = SCNText(string: "VR OS 0.1", extrusionDepth: 0.001)
        title.font = UIFont.boldSystemFont(ofSize: 0.055)
        title.flatness = 0.002
        title.firstMaterial?.diffuse.contents = UIColor.white
        title.firstMaterial?.isDoubleSided = true
        let titleNode = SCNNode(geometry: title)
        titleNode.position = SCNVector3(-0.34, 0.13, 0.005)
        root.addChildNode(titleNode)

        let subtitle = SCNText(string: "Janela espacial", extrusionDepth: 0.001)
        subtitle.font = UIFont.systemFont(ofSize: 0.03)
        subtitle.firstMaterial?.diffuse.contents = UIColor.cyan
        subtitle.firstMaterial?.isDoubleSided = true
        let subtitleNode = SCNNode(geometry: subtitle)
        subtitleNode.position = SCNVector3(-0.34, 0.03, 0.005)
        root.addChildNode(subtitleNode)
        return root
    }
}

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var coordinator: ARCoordinator

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = coordinator
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = true
        coordinator.sceneView = view
        if ARWorldTrackingConfiguration.isSupported {
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravity
            view.session.run(config)
        } else {
            coordinator.status = "ARKit indisponível neste dispositivo"
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var ar = ARCoordinator()

    var body: some View {
        ZStack {
            ARCameraView(coordinator: ar)
                .ignoresSafeArea()
            VStack {
                Text("VR OS")
                    .font(.headline)
                    .padding(12)
                    .background(.black.opacity(0.65), in: Capsule())
                Spacer()
                Text(ar.status)
                    .font(.footnote)
                    .padding(10)
                    .background(.black.opacity(0.65), in: Capsule())
                Button {
                    ar.addWindow()
                } label: {
                    Label("Criar janela", systemImage: "plus.rectangle.on.rectangle")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
            }
            .padding()
        }
    }
}
