import ARKit
import AVFoundation
import PhotosUI
import CoreTransferable
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

/// PhotosPicker's file representation is copied while its temporary access is
/// valid, avoiding loading gigabyte-sized movies into RAM as Data.
private struct CinemaPhotoMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let original = received.file
            let ext = original.pathExtension.isEmpty ? "mov" : original.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: original, to: destination)
            return CinemaPhotoMovie(url: destination)
        }
    }
}

/// Layout of the pixels in an imported stereoscopic movie.
/// H-SBS and full SBS have exactly the same left/right packing; only source
/// resolution differs. All three modes share one synchronized AVPlayer.
enum CinemaVideoMode: String, CaseIterable {
    case twoD = "2D"
    case sbs = "SBS"
    case halfSBS = "H-SBS"
    case overUnder = "OU"

    var subtitle: String {
        switch self {
        case .twoD: return "Filme normal"
        case .sbs: return "Lado a lado completo"
        case .halfSBS: return "Lado a lado meia resolução"
        case .overUnder: return "Cima e baixo"
        }
    }
}

final class CinemaModel: ObservableObject {
    let scene = SCNScene()
    let leftCamera = SCNNode()
    let rightCamera = SCNNode()
    // Both eyes sample different halves of the same AVPlayer frame. Using
    // one player keeps audio, seeking and left/right images synchronized.
    private let leftScreenMaterial = SCNMaterial()
    private let rightScreenMaterial = SCNMaterial()
    private let leftVideoPlane = SCNPlane(width: 23.8, height: 13.4)
    private let rightVideoPlane = SCNPlane(width: 23.8, height: 13.4)
    private var sourceAspect: CGFloat = 16.0 / 9.0
    private let screenWidth: CGFloat = 27.2
    private let screenHeight: CGFloat = 13.4
    private var player: AVPlayer?
    private var movieImportID = UUID()
    private var initialOrientation: simd_quatf?
    private var roomLights: [SCNLight] = []
    private var ambientLight: SCNLight?
    private var screenBounceLight: SCNLight?
    private var accentNodes: [SCNNode] = []
    private var controlsTask: Task<Void, Never>?
    @Published var movieTitle = "Escolha um filme MP4"
    @Published var playing = false
    @Published var selectedMode: CinemaVideoMode = .twoD
    @Published var immersiveScreen = true
    @Published var swapEyes = false
    @Published var convergence: CGFloat = 0
    @Published var controlsVisible = true
    @Published var errorMessage: String?
    @Published var showPicker = false

    init() {
        buildRoom()
        updateStereoMaterials()
        updateSeatPosition()
        updateLighting(animated: false)
    }

    func enter(camera: ARCamera?) {
        initialOrientation = camera.map { simd_quatf($0.transform) }
        revealControls()
    }

    func exit() {
        player?.pause()
        playing = false
        controlsTask?.cancel()
        controlsVisible = true
        updateLighting()
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
        // AVFoundation cannot reliably demux Matroska. Do not claim the
        // import succeeded when the user picks a .mkv.
        if url.pathExtension.lowercased() == "mkv" {
            controlsTask?.cancel()
            player?.pause()
            playing = false
            updateLighting()
            errorMessage = "MKV ainda não é compatível com este player. Use MP4 SBS ou converta mantendo o 3D."
            controlsVisible = true
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // Security-scoped file access is temporary. Copy into our sandbox
            // before dismissing the document picker so offline viewing works.
            let movieFolder = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cinema", isDirectory: true)
            try FileManager.default.createDirectory(at: movieFolder,
                                                    withIntermediateDirectories: true)
            let dest = movieFolder.appendingPathComponent(
                UUID().uuidString + "." + url.pathExtension.lowercased())
            try FileManager.default.copyItem(at: url, to: dest)
            player?.pause()
            let movie = AVPlayer(url: dest)
            movie.actionAtItemEnd = .pause
            leftScreenMaterial.diffuse.contents = movie
            rightScreenMaterial.diffuse.contents = movie
            player = movie
            movieTitle = url.deletingPathExtension().lastPathComponent
            let name = movieTitle.lowercased()
            if name.contains("h-sbs") || name.contains("hsbs") ||
               name.contains("half-sbs") || name.contains("half_sbs") {
                selectedMode = .halfSBS
            } else if name.contains("sbs") || name.contains("side-by-side") ||
                      name.contains("side_by_side") {
                selectedMode = .sbs
            } else if name.contains("over-under") || name.contains("top-bottom") ||
                      name.contains("top_bottom") || name.contains("3d-ou") {
                selectedMode = .overUnder
            } else {
                selectedMode = .twoD
            }
            updateStereoMaterials()
            errorMessage = nil
            playing = true
            updateLighting()
            revealControls()
            movie.play()

            // Rotate-aware aspect ratio. The video plane fits INSIDE the
            // 27.2-by-13.4-metre screen instead of stretching 16:9 or 2.39:1.
            let importID = UUID()
            movieImportID = importID
            Task {
                let asset = AVURLAsset(url: dest)
                do {
                    guard let track = try await asset.loadTracks(withMediaType: .video).first
                    else { return }
                    let natural = try await track.load(.naturalSize)
                    let rotation = try await track.load(.preferredTransform)
                    let transformed = natural.applying(rotation)
                    let width = abs(transformed.width)
                    let height = abs(transformed.height)
                    guard width > 0, height > 0 else { return }
                    await MainActor.run {
                        guard self.movieImportID == importID else { return }
                        self.sourceAspect = width / height
                        // An ordinary 1920x1080 SBS is usually H-SBS;
                        // a 3840x1080 SBS is usually full-width SBS.
                        if self.selectedMode == .sbs && self.sourceAspect < 2.6 {
                            self.selectedMode = .halfSBS
                        }
                        self.fitScreen()
                    }
                } catch {
                    await MainActor.run {
                        guard self.movieImportID == importID else { return }
                        // Keep the safe 16:9 default if metadata is unavailable.
                        self.sourceAspect = 16.0 / 9.0
                        self.fitScreen()
                    }
                }
            }
        } catch {
            errorMessage = "Erro ao importar MP4: " + error.localizedDescription
        }
    }

    /// The movie's overall aspect ratio differs from one eye's aspect
    /// ratio in packed SBS or over/under movies.
    private func fitScreen() {
        var aspect = sourceAspect
        switch selectedMode {
        case .twoD, .halfSBS: break
        case .sbs: aspect /= 2
        case .overUnder:
            // Full OU has a tall packed frame (e.g. 1920×2160); half OU
            // is anamorphic (e.g. 1920×1080). Both should end up 16:9.
            if sourceAspect < 1.2 { aspect *= 2 }
        }
        guard aspect.isFinite, aspect > 0 else { return }
        let height = min(screenHeight, screenWidth / aspect)
        let width = height * aspect
        leftVideoPlane.height = height
        leftVideoPlane.width = width
        rightVideoPlane.height = height
        rightVideoPlane.width = width
    }

    func selectMode(_ mode: CinemaVideoMode) {
        selectedMode = mode
        updateStereoMaterials()
        fitScreen()
        revealControls()
    }

    func toggleImmersive() {
        immersiveScreen.toggle()
        updateSeatPosition()
        revealControls()
    }

    private func updateSeatPosition() {
        // The movie screen is at z=-15.66. In immersive mode the viewer is
        // about 13 m away, for a horizontal angular width around 90 degrees.
        let z: Float = immersiveScreen ? -2.6 : 3.25
        leftCamera.position = SCNVector3(-0.032, 1.68, z)
        rightCamera.position = SCNVector3(0.032, 1.68, z)
    }

    func toggleEyeOrder() {
        swapEyes.toggle()
        updateStereoMaterials()
        revealControls()
    }

    func adjustConvergence(_ direction: CGFloat) {
        convergence = max(-0.02, min(0.02, convergence + direction * 0.0025))
        updateStereoMaterials()
        revealControls()
    }

    private func updateStereoMaterials() {
        configureEyeMaterial(leftScreenMaterial, rightEye: false)
        configureEyeMaterial(rightScreenMaterial, rightEye: true)
    }

    private func configureEyeMaterial(_ material: SCNMaterial, rightEye: Bool) {
        let useRightHalf = swapEyes ? !rightEye : rightEye
        let scaleX: Float
        let scaleY: Float
        let translationX: Float
        let translationY: Float
        switch selectedMode {
        case .twoD:
            scaleX = 1
            scaleY = 1
            translationX = 0
            translationY = 0
        case .sbs, .halfSBS:
            scaleX = 0.5
            scaleY = 1
            translationX = useRightHalf ? 0.5 : 0
            translationY = 0
        case .overUnder:
            scaleX = 1
            scaleY = 0.5
            translationX = 0
            // Texture v=1 corresponds to the top. Left eye gets top.
            translationY = useRightHalf ? 0 : 0.5
        }
        // The convergence adjustment shifts sampling only slightly, and is
        // limited to the 3D modes. This does NOT alter the source movie.
        let shift: Float = selectedMode == .twoD ? 0 :
            Float(convergence) * (rightEye ? 1 : -1)
        let transform = SCNMatrix4Mult(
            SCNMatrix4MakeTranslation(translationX + shift, translationY, 0),
            SCNMatrix4MakeScale(scaleX, scaleY, 1))
        material.diffuse.contentsTransform = transform
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.lightingModel = .constant
        material.isDoubleSided = true
    }

    func togglePlayback() {
        guard let player = player else { showPicker = true; return }
        if playing { player.pause() } else { player.play() }
        playing.toggle()
        updateLighting()
        revealControls()
    }

    func seek(_ delta: Double) {
        guard let player = player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, seconds + delta),
                              preferredTimescale: 600))
        revealControls()
    }

    func revealControls() {
        controlsTask?.cancel()
        controlsVisible = true
        guard playing else { return }
        controlsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self, self.playing else { return }
                self.controlsVisible = false
            }
        }
    }

    func updateLighting(animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.5 : 0
        ambientLight?.intensity = playing ? 75 : 230
        screenBounceLight?.intensity = playing ? 210 : 95
        for light in roomLights {
            light.intensity = playing ? 70 : 350
        }
        for node in accentNodes {
            node.opacity = playing ? 0.38 : 0.9
        }
        SCNTransaction.commit()
    }

    @discardableResult
    private func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                     _ x: Float, _ y: Float, _ z: Float,
                     _ color: UIColor, glow: UIColor? = nil) -> SCNNode {
        let node = SCNNode(geometry: SCNBox(width: w, height: h, length: d,
                                             chamferRadius: 0.04))
        let material = SCNMaterial()
        material.diffuse.contents = color
        if let glow = glow { material.emission.contents = glow }
        node.geometry?.firstMaterial = material
        node.position = SCNVector3(x, y, z)
        scene.rootNode.addChildNode(node)
        return node
    }

    /// All measurements are in virtual metres; the display fills nearly the
    /// entire 29 m front wall while keeping a comfortable 75° camera FOV.
    private func buildRoom() {
        scene.background.contents = UIColor(red: 0.006, green: 0.008, blue: 0.017, alpha: 1)
        let wall = UIColor(red: 0.028, green: 0.030, blue: 0.048, alpha: 1)
        let acoustic = UIColor(red: 0.067, green: 0.069, blue: 0.084, alpha: 1)
        let darkCarpet = UIColor(red: 0.060, green: 0.023, blue: 0.038, alpha: 1)
        let velvet = UIColor(red: 0.32, green: 0.022, blue: 0.058, alpha: 1)
        let velvetHighlight = UIColor(red: 0.43, green: 0.060, blue: 0.088, alpha: 1)
        let blackLeather = UIColor(red: 0.045, green: 0.039, blue: 0.050, alpha: 1)
        let gold = UIColor(red: 0.68, green: 0.43, blue: 0.17, alpha: 1)
        let amber = UIColor(red: 0.90, green: 0.53, blue: 0.20, alpha: 1)
        let aisleBlue = UIColor(red: 0.09, green: 0.26, blue: 0.74, alpha: 1)

        // Architectural shell, upholstered stage face and dark acoustic roof.
        box(29, 0.3, 33, 0, -0.30, 0, darkCarpet)
        box(29, 0.24, 33, 0, 14.3, 0, wall)
        box(0.30, 14.4, 33, -14.5, 7, 0, wall)
        box(0.30, 14.4, 33, 14.5, 7, 0, wall)
        box(29, 14.4, 0.3, 0, 7, -16.2, wall)
        box(29, 14.4, 0.3, 0, 7, 16.2, wall)

        // Matte screen backing fills the whole front wall. The AVPlayer is
        // on a fitted inner plane so ultrawide films never get stretched.
        box(27.8, 13.9, 0.20, 0, 7.05, -15.91,
            UIColor(red: 0.11, green: 0.095, blue: 0.083, alpha: 1))
        let backing = SCNNode(geometry: SCNPlane(width: screenWidth,
                                                  height: screenHeight))
        backing.geometry?.firstMaterial?.diffuse.contents = UIColor.black
        backing.position = SCNVector3(0, 7.05, -15.76)
        scene.rootNode.addChildNode(backing)

        // SceneKit category masks ensure each physical eye can see ONLY
        // its own movie texture; the rest of the room remains shared.
        leftScreenMaterial.diffuse.contents = UIColor(white: 0.018, alpha: 1)
        rightScreenMaterial.diffuse.contents = UIColor(white: 0.018, alpha: 1)
        leftVideoPlane.firstMaterial = leftScreenMaterial
        rightVideoPlane.firstMaterial = rightScreenMaterial
        let leftScreen = SCNNode(geometry: leftVideoPlane)
        leftScreen.position = SCNVector3(0, 7.05, -15.66)
        leftScreen.categoryBitMask = 2
        scene.rootNode.addChildNode(leftScreen)
        let rightScreen = SCNNode(geometry: rightVideoPlane)
        rightScreen.position = SCNVector3(0, 7.05, -15.66)
        rightScreen.categoryBitMask = 4
        scene.rootNode.addChildNode(rightScreen)
        box(27.8, 0.12, 0.22, 0, 13.94, -15.7, gold)
        box(27.8, 0.12, 0.22, 0, 0.16, -15.7, gold)
        box(0.12, 13.7, 0.22, -13.92, 7.05, -15.7, gold)
        box(0.12, 13.7, 0.22, 13.92, 7.05, -15.7, gold)

        // Floor aisles and staggered, individually lit stair noses.
        for side: Float in [-1, 1] {
            accentNodes.append(box(0.11, 0.055, 29, side * 12.35,
                                   0.02, 0, aisleBlue, glow: aisleBlue))
            accentNodes.append(box(0.08, 0.055, 29, side * 3.0,
                                   0.02, 0, aisleBlue, glow: aisleBlue))
            for row in 0..<6 {
                let z = Float(row) * 4.2 - 11.5
                accentNodes.append(box(8.65, 0.035, 0.07, side * 7.6,
                                       0.025, z,
                                       UIColor(red: 0.20, green: 0.36, blue: 0.70, alpha: 1),
                                       glow: aisleBlue))
            }

            // Acoustic fabric columns, golden vertical fins and sconces.
            for i in 0..<9 {
                let z = Float(i) * 3.6 - 14.4
                box(0.13, 9.7, 2.9, side * 14.18, 6.5, z, acoustic)
                box(0.17, 10.7, 0.12, side * 14.03, 6.55,
                    z + 1.43, gold)
                box(0.12, 3.5, 0.14, side * 13.98, 3.5,
                    z, amber, glow: amber)
            }
        }

        // Ceiling ribs, inset light slots and perimeter cove lighting.
        for z in stride(from: Float(-13.5), through: Float(13.5), by: 4.5) {
            box(27.5, 0.18, 0.18, 0, 13.75, z, acoustic)
            accentNodes.append(box(19.5, 0.045, 0.11, 0, 13.62, z,
                                   gold, glow: amber))
        }
        for side: Float in [-1, 1] {
            accentNodes.append(box(0.12, 0.10, 30, side * 12.9,
                                   13.55, 0, gold, glow: amber))
        }

        // Seat prototype: fabric cushion, highlighted back, curved-feeling
        // chamfered arms, back shell, foot and cupholder. SceneKit shares the
        // prototype geometry across each clone for a small rendering cost.
        let seatPrototype = SCNNode()
        func seatPart(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                      _ x: Float, _ y: Float, _ z: Float, _ color: UIColor,
                      chamfer: CGFloat = 0.07) {
            let node = SCNNode(geometry: SCNBox(width: w, height: h, length: d,
                                                 chamferRadius: chamfer))
            node.geometry?.firstMaterial?.diffuse.contents = color
            node.position = SCNVector3(x, y, z)
            seatPrototype.addChildNode(node)
        }
        seatPart(1.65, 0.31, 1.42, 0, 0.81, -0.12, velvetHighlight)
        seatPart(1.64, 1.68, 0.32, 0, 1.64, 0.54, velvet)
        seatPart(1.39, 0.30, 0.08, 0, 2.33, 0.34, velvetHighlight)
        seatPart(1.76, 1.86, 0.14, 0, 1.55, 0.77, blackLeather)
        seatPart(0.21, 0.78, 1.65, -0.93, 0.96, -0.10, blackLeather)
        seatPart(0.21, 0.78, 1.65, 0.93, 0.96, -0.10, blackLeather)
        seatPart(0.98, 0.42, 0.75, 0, 0.39, 0.15, blackLeather)
        for row in 0..<5 {
            let z = Float(row) * 4.2 - 11.7
            for column in 0..<4 {
                for side: Float in [-1, 1] {
                    let instance = seatPrototype.clone()
                    instance.position = SCNVector3(side * (4.2 + Float(column) * 2.15),
                                                   0, z)
                    scene.rootNode.addChildNode(instance)
                }
            }
        }

        // Four pooled dynamic lights: emissive strips provide decorative glow
        // without dozens of costly per-pixel light sources.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.78, alpha: 1)
        ambientLight = ambient.light
        scene.rootNode.addChildNode(ambient)
        for side: Float in [-1, 1] {
            for z in [Float(-8), Float(7)] {
                let lamp = SCNNode()
                let light = SCNLight()
                light.type = .omni
                light.color = UIColor(red: 1, green: 0.69, blue: 0.37, alpha: 1)
                light.attenuationStartDistance = 2
                light.attenuationEndDistance = 17
                lamp.light = light
                lamp.position = SCNVector3(side * 10.2, 4.7, z)
                scene.rootNode.addChildNode(lamp)
                roomLights.append(light)
            }
        }
        let screenLight = SCNNode()
        screenLight.light = SCNLight()
        screenLight.light?.type = .omni
        screenLight.light?.color = UIColor(red: 0.64, green: 0.75, blue: 1, alpha: 1)
        screenLight.light?.attenuationEndDistance = 21
        screenLight.position = SCNVector3(0, 9, -13.8)
        screenBounceLight = screenLight.light
        scene.rootNode.addChildNode(screenLight)

        // Two independent eyes, 64-mm interpupillary separation.
        for (index, eye) in [leftCamera, rightCamera].enumerated() {
            eye.camera = SCNCamera()
            eye.camera?.categoryBitMask = index == 0 ? (1 | 2) : (1 | 4)
            eye.camera?.fieldOfView = 75
            eye.camera?.zNear = 0.05
            eye.camera?.zFar = 90
            eye.position = SCNVector3(index == 0 ? -0.032 : 0.032, 1.68, 3.25)
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
    @ObservedObject var updates: LiveUpdateManager
    let onExit: () -> Void
    @State private var lastPinch = false
    @State private var pickedMovie: PhotosPickerItem?
    @State private var pickingPhotoMovie = false

    private var newerAppAvailable: Bool {
        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return updates.manifest.latestNativeVersion.compare(installed, options: .numeric) == .orderedDescending
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CinemaSceneView(cinema: cinema, runtime: runtime, rightEye: rightEye)
                    .ignoresSafeArea()
                if cinema.controlsVisible {
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
                    HStack(spacing: 4) {
                        ForEach(CinemaVideoMode.allCases, id: \.rawValue) { mode in
                            Button {
                                cinema.selectMode(mode)
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)
                                    .background(
                                        cinema.selectedMode == mode
                                          ? Color.blue.opacity(0.75)
                                          : Color.white.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 5)
                    HStack(spacing: 4) {
                        cinemaOption(cinema.immersiveScreen ? "MAX ON" : "MAX OFF") {
                            cinema.toggleImmersive()
                        }
                        cinemaOption("Trocar olhos") { cinema.toggleEyeOrder() }
                        cinemaOption("3D −") { cinema.adjustConvergence(-1) }
                        cinemaOption("3D +") { cinema.adjustConvergence(1) }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 4)
                    Spacer()
                    Text(cinema.movieTitle)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if let error = cinema.errorMessage {
                        Text(error).font(.system(size: 9)).foregroundStyle(.red).lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        cinemaButton("folder.fill", "Arquivos") { cinema.showPicker = true }
                        PhotosPicker(selection: rightEye ? .constant(nil) : $pickedMovie,
                                     matching: .videos,
                                     photoLibrary: .shared()) {
                            VStack(spacing: 3) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 15))
                                Text("Fototeca").font(.system(size: 9, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(.white.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        cinemaButton("gobackward.10", "-10s") { cinema.seek(-10) }
                        cinemaButton(cinema.playing ? "pause.fill" : "play.fill",
                                     cinema.playing ? "Pausar" : "Play") {
                            cinema.togglePlayback()
                        }
                        cinemaButton("goforward.10", "+10s") { cinema.seek(10) }
                        cinemaButton("arrow.down.circle", "Internet") {
                            Task { await updates.check(); cinema.revealControls() }
                        }
                        cinemaButton("xmark", "Sair") { onExit() }
                    }
                    .padding(5)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 7)
                    .padding(.bottom, 5)
                    if updates.isChecking {
                        Text("Buscando atualizações pela internet…")
                            .font(.system(size: 9))
                    } else {
                        Text(updates.statusMessage)
                            .font(.system(size: 9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    if newerAppAvailable,
                       let url = URL(string: updates.manifest.nativeReleaseURL) {
                        Link(destination: url) {
                            Text("Nova versão do app · instalar externamente")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                    }
                    Text("Conteúdo online atualiza aqui. Código/IPA exige instalar versão assinada.")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, 9)
                }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                }
                if cinema.controlsVisible && runtime.hand.visible {
                    Circle()
                        .stroke(.white, lineWidth: runtime.hand.pinching ? 3 : 1.5)
                        .frame(width: runtime.hand.pinching ? 24 : 17,
                               height: runtime.hand.pinching ? 24 : 17)
                        .position(handPoint(size: geometry.size))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: cinema.controlsVisible)
            .onChange(of: pickedMovie) { nextItem in
                guard !rightEye, let nextItem = nextItem else { return }
                Task {
                    do {
                        guard let movie = try await nextItem.loadTransferable(
                            type: CinemaPhotoMovie.self) else {
                            cinema.errorMessage = "Não foi possível importar esse vídeo da Fototeca."
                            cinema.revealControls()
                            return
                        }
                        cinema.loadMovie(movie.url)
                        try? FileManager.default.removeItem(at: movie.url)
                    } catch {
                        cinema.errorMessage = "Erro na Fototeca: " + error.localizedDescription
                        cinema.revealControls()
                    }
                }
            }
            .onReceive(runtime.$hand) { hand in
                guard !rightEye else { return }
                if hand.visible && hand.pinching && !lastPinch {
                    if !cinema.controlsVisible {
                        // First pinch brings the controls back without
                        // accidentally pausing or exiting the movie.
                        cinema.revealControls()
                    } else {
                    let point = handPoint(size: geometry.size)
                    let bottom = geometry.size.height - 40
                    if point.y >= 44 && point.y <= 88 {
                        let slot = min(3, max(0, Int(point.x / max(1, geometry.size.width) * 4)))
                        cinema.selectMode(CinemaVideoMode.allCases[slot])
                    } else if point.y > 88 && point.y <= 133 {
                        let slot = min(3, max(0, Int(point.x / max(1, geometry.size.width) * 4)))
                        switch slot {
                        case 0: cinema.toggleImmersive()
                        case 1: cinema.toggleEyeOrder()
                        case 2: cinema.adjustConvergence(-1)
                        default: cinema.adjustConvergence(1)
                        }
                    } else if abs(point.y - bottom) < 65 {
                        let slot = min(6, max(0, Int(point.x / max(1, geometry.size.width) * 7)))
                        switch slot {
                        case 0: cinema.showPicker = true
                        case 1: pickingPhotoMovie = true
                        case 2: cinema.seek(-10)
                        case 3: cinema.togglePlayback()
                        case 4: cinema.seek(10)
                        case 5: Task { await updates.check(); cinema.revealControls() }
                        default: onExit()
                        }
                    }
                    }
                }
                lastPinch = hand.visible && hand.pinching
            }
        }
        .onChange(of: pickingPhotoMovie) { shouldOpen in
            guard shouldOpen && !rightEye else { return }
            // SwiftUI PhotosPicker is a presentation controller, not a
            // supported programmatic open from hand pinch. Indicate users
            // should tap the visible picker (unlike a non-functional shortcut).
            cinema.errorMessage = "Para abrir a Fototeca, toque em Fototeca na tela."
            cinema.revealControls()
            pickingPhotoMovie = false
        }
        .fileImporter(isPresented: rightEye ? .constant(false) : $cinema.showPicker,
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

    private func cinemaOption(_ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
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
