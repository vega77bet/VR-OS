import ARKit
import AVFoundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

final class CinemaModel: ObservableObject {
    let scene = SCNScene()
    let leftCamera = SCNNode()
    let rightCamera = SCNNode()
    private let screenMaterial = SCNMaterial()
    private var player: AVPlayer?
    private var initialOrientation: simd_quatf?
    @Published var movieTitle = "Escolha um filme MP4"
    @Published var playing = false
    @Published var errorMessage: String?
    @Published var showPicker = false

    init() { buildRoom() }

    func enter(camera: ARCamera?) {
        initialOrientation = camera.map { simd_quatf($0.transform) }
    }

    func updateHead(_ camera: ARCamera?) {
        guard let pose = camera else { return }
        let current = simd_quatf(pose.transform)
        if initialOrientation == nil { initialOrientation = current }
        guard let origin = initialOrientation else { return }
        let relative = simd_inverse(origin) * current
        leftCamera.simdOrientation = relative
        rightCamera.simdOrientation = relative
    }

    func loadMovie(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: dest)
            player?.pause()
            let movie = AVPlayer(url: dest)
            movie.actionAtItemEnd = .pause
            screenMaterial.diffuse.contents = movie
            player = movie
            movieTitle = url.deletingPathExtension().lastPathComponent
            errorMessage = nil
            playing = true
            movie.play()
        } catch {
            errorMessage = "Erro ao abrir vídeo: " + error.localizedDescription
        }
    }

    func togglePlayback() {
        guard let player = player else { showPicker = true; return }
        if playing { player.pause() } else { player.play() }
        playing.toggle()
    }

    func seek(_ delta: Double) {
        guard let player = player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, seconds + delta), preferredTimescale: 600))
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                     _ x: Float, _ y: Float, _ z: Float,
                     _ color: UIColor, glow: UIColor? = nil) {
        let node = SCNNode(geometry: SCNBox(width: w, height: h, length: d,
                                             chamferRadius: 0.04))
        let material = SCNMaterial()
        material.diffuse.contents = color
        if let glow = glow { material.emission.contents = glow }
        node.geometry?.firstMaterial = material
        node.position = SCNVector3(x, y, z)
        scene.rootNode.addChildNode(node)
    }

    private func buildRoom() {
        scene.background.contents = UIColor(red: 0.008, green: 0.01, blue: 0.022, alpha: 1)
        let wall = UIColor(red: 0.035, green: 0.042, blue: 0.07, alpha: 1)
        let gold = UIColor(red: 0.7, green: 0.44, blue: 0.16, alpha: 1)
        let red = UIColor(red: 0.3, green: 0.028, blue: 0.055, alpha: 1)
        let blue = UIColor(red: 0.15, green: 0.28, blue: 0.62, alpha: 1)
        box(29, 0.3, 33, 0, -0.3, 0, UIColor(red: 0.065, green: 0.04, blue: 0.06, alpha: 1))
        box(29, 0.25, 33, 0, 12.5, 0, wall)
        box(0.3, 13, 33, -14.5, 6, 0, wall)
        box(0.3, 13, 33, 14.5, 6, 0, wall)
        box(29, 13, 0.3, 0, 6, -16.2, wall)
        box(29, 13, 0.3, 0, 6, 16.2, wall)

        // Large illuminated cinema screen.
        let screen = SCNNode(geometry: SCNPlane(width: 20, height: 10.5))
        screenMaterial.diffuse.contents = UIColor(white: 0.018, alpha: 1)
        screenMaterial.lightingModel = .constant
        screenMaterial.isDoubleSided = true
        screen.geometry?.firstMaterial = screenMaterial
        screen.position = SCNVector3(0, 6.1, -15.6)
        scene.rootNode.addChildNode(screen)
        box(21, 0.18, 0.25, 0, 11.55, -15.55, gold)
        box(21, 0.18, 0.25, 0, 0.65, -15.55, gold)
        box(0.18, 11, 0.25, -10.5, 6.1, -15.55, gold)
        box(0.18, 11, 0.25, 10.5, 6.1, -15.55, gold)

        // Acoustic panels, glowing aisles and golden wall sconces.
        for side: Float in [-1, 1] {
            for i in 0..<8 {
                box(0.16, 7.2, 2.3, side * 14.15, 5,
                    Float(i) * 3.6 - 12.6,
                    UIColor(red: 0.085, green: 0.08, blue: 0.11, alpha: 1))
            }
            box(0.08, 0.08, 29, side * 12, 0.03, 0, blue, glow: blue)
            for z in stride(from: Float(-12), through: Float(12), by: 6) {
                box(0.20, 3, 0.18, side * 14.1, 3.1, z, gold, glow: gold)
            }
        }

        // Velvet seating flanks the viewer, preserving the central sightline.
        for row in 0..<6 {
            let z = Float(row) * 3.2 - 9.5
            for column in 0..<4 {
                for side: Float in [-1, 1] {
                    let x = side * (Float(column) * 1.9 + 4.5)
                    box(1.45, 0.5, 1.3, x, 0.65, z, red)
                    box(1.45, 1.55, 0.36, x, 1.45, z + 0.65, red)
                    box(0.22, 0.85, 1.5, x - 0.78, 0.8, z, wall)
                    box(0.22, 0.85, 1.5, x + 0.78, 0.8, z, wall)
                }
            }
        }
        for z in stride(from: Float(-11), through: Float(11), by: 5.5) {
            box(15, 0.06, 0.12, 0, 12.2, z, gold,
                glow: UIColor(red: 0.18, green: 0.10, blue: 0.03, alpha: 1))
        }
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.28, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        for (eye, x) in [(leftCamera, Float(-0.032)), (rightCamera, Float(0.032))] {
            eye.camera = SCNCamera()
            eye.camera?.fieldOfView = 80
            eye.camera?.zNear = 0.05
            eye.camera?.zFar = 80
            eye.position = SCNVector3(x, 1.65, 6.8)
            scene.rootNode.addChildNode(eye)
        }
    }
}

private struct CinemaSceneView: UIViewRepresentable {
    let cinema: CinemaModel
    let runtime: VRRuntime
    let rightEye: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = cinema.scene
        view.pointOfView = rightEye ? cinema.rightCamera : cinema.leftCamera
        view.backgroundColor = .black
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling2X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        cinema.updateHead(runtime.camera)
    }
}

struct CinemaEyeView: View {
    let rightEye: Bool
    @ObservedObject var runtime: VRRuntime
    @ObservedObject var cinema: CinemaModel
    let onExit: () -> Void
    @State private var lastPinch = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CinemaSceneView(cinema: cinema, runtime: runtime, rightEye: rightEye)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "film.fill")
                        Text("VR-OS CINEMA").tracking(1.1)
                        Spacer(minLength: 0)
                        Text("IMAX").foregroundStyle(.yellow.opacity(0.8))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(9)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    Spacer()
                    Text(cinema.movieTitle)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if let error = cinema.errorMessage {
                        Text(error).font(.system(size: 9)).foregroundStyle(.red).lineLimit(2)
                    }
                    HStack(spacing: 5) {
                        cinemaButton("folder.fill", "Filme") { cinema.showPicker = true }
                        cinemaButton("gobackward.10", "-10s") { cinema.seek(-10) }
                        cinemaButton(cinema.playing ? "pause.fill" : "play.fill",
                                     cinema.playing ? "Pausar" : "Play") {
                            cinema.togglePlayback()
                        }
                        cinemaButton("goforward.10", "+10s") { cinema.seek(10) }
                        cinemaButton("xmark", "Sair") { onExit() }
                    }
                    .padding(7)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 7)
                    .padding(.bottom, 16)
                }
                .foregroundStyle(.white)
                if runtime.hand.visible {
                    Circle()
                        .stroke(.white, lineWidth: runtime.hand.pinching ? 3 : 1.5)
                        .frame(width: runtime.hand.pinching ? 24 : 17,
                               height: runtime.hand.pinching ? 24 : 17)
                        .position(handPoint(size: geometry.size))
                        .allowsHitTesting(false)
                }
            }
            .onReceive(runtime.$hand) { hand in
                guard !rightEye else { return }
                if hand.visible && hand.pinching && !lastPinch {
                    let point = handPoint(size: geometry.size)
                    let bottom = geometry.size.height - 40
                    if abs(point.y - bottom) < 37 {
                        let slot = min(4, max(0, Int(point.x / max(1, geometry.size.width) * 5)))
                        switch slot {
                        case 0: cinema.showPicker = true
                        case 1: cinema.seek(-10)
                        case 2: cinema.togglePlayback()
                        case 3: cinema.seek(10)
                        default: onExit()
                        }
                    }
                }
                lastPinch = hand.visible && hand.pinching
            }
        }
        .fileImporter(isPresented: $cinema.showPicker,
                      allowedContentTypes: [.mpeg4Movie, .movie, .video],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { cinema.loadMovie(url) }
            case .failure(let error):
                cinema.errorMessage = error.localizedDescription
            }
        }
    }

    private func handPoint(size: CGSize) -> CGPoint {
        let raw = runtime.hand.point
        guard let image = runtime.cameraImage else {
            return CGPoint(x: raw.x * size.width, y: raw.y * size.height)
        }
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let scale = max(size.width / iw, size.height / ih)
        return CGPoint(x: raw.x * iw * scale - (iw * scale - size.width) / 2,
                       y: raw.y * ih * scale - (ih * scale - size.height) / 2)
    }

    private func cinemaButton(_ symbol: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
