import SwiftUI
import MetalKit

@main
struct VROSApp: App {
    var body: some Scene {
        WindowGroup {
            VRRootView().preferredColorScheme(.dark)
        }
    }
}

@MainActor
private struct VRRootView: View {
    @StateObject private var session = AppLifecycleManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var calibrating = false
    @State private var configuringControllers = false
    @State private var controlsVisible = false

    var body: some View {
        ZStack {
            MetalHost(session: session).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { controlsVisible.toggle() }
            if controlsVisible {
                VStack {
                    DebugOverlay(metrics: session.metrics, trackingStatus: session.trackingStatus,
                                 error: session.renderError)
                    HStack {
                        Text("OLHO ESQUERDO").frame(maxWidth: .infinity)
                        Text("OLHO DIREITO").frame(maxWidth: .infinity)
                    }.font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    HStack(spacing: 18) {
                        Button("Centralizar Home") { session.spatial.recenter() }
                        Button("Calibrar lentes") { calibrating = true }
                        Button("Controles") { configuringControllers = true }
                        Button("Entrar no visor") { controlsVisible = false }
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Topo / Dynamic Island à esquerda • Toque na tela para mostrar os controles")
                        .font(.caption).foregroundStyle(.white)
                }
                .padding().background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $calibrating) { CalibrationView(manager: session.calibration) }
        .sheet(isPresented: $configuringControllers) {
            ControllerSettingsView(manager: session.spatial.controllers, preferences: session.spatial.preferences)
        }
        .onReceive(session.spatial.$exitRequests) { count in if count > 0 { controlsVisible = true } }
        .onAppear {
            session.spatial.interactionEnabled = !controlsVisible
            session.setActive(scenePhase == .active)
        }
        .onChange(of: controlsVisible) { _, visible in session.spatial.interactionEnabled = !visible }
        .onChange(of: scenePhase) { _, phase in session.setActive(phase == .active) }
        .onChange(of: calibrating) { _, presented in session.setPresentationPaused(presented || configuringControllers) }
        .onChange(of: configuringControllers) { _, presented in session.setPresentationPaused(presented || calibrating) }
        .onDisappear { session.setActive(false) }
    }
}

private struct MetalHost: UIViewControllerRepresentable {
    let session: AppLifecycleManager
    func makeUIViewController(context: Context) -> VRViewController { VRViewController(session: session) }
    func updateUIViewController(_ controller: VRViewController, context: Context) {}
}

@MainActor
private final class VRViewController: UIViewController {
    private let session: AppLifecycleManager
    private var renderer: VRRenderer?
    private var metalView: MTKView?

    init(session: AppLifecycleManager) { self.session = session; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(session:)") }

    override func loadView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            view = UIView(); view.backgroundColor = .black
            session.renderError = "Metal indisponível neste dispositivo."
            return
        }
        let metalView = MTKView(frame: .zero, device: device)
        metalView.backgroundColor = .black
        metalView.preferredFramesPerSecond = 60
        self.metalView = metalView
        view = metalView
        do {
            let renderer = try VRRenderer(view: metalView, tracking: session.tracking,
                                          calibration: session.calibration)
            renderer.onMetrics = { [weak session] metrics in session?.receive(metrics) }
            renderer.spatialFrameProvider = { [weak session] pose, time in
                guard let session else { return .empty }
                return session.spatial.update(headPose: pose, at: time, calibration: session.calibration)
            }
            self.renderer = renderer
            metalView.delegate = renderer
            session.attach(metalView)
        } catch {
            metalView.isPaused = true
            session.renderError = "Falha ao iniciar Metal: \(error.localizedDescription)"
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
