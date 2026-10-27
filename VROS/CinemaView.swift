import ARKit
import AVFoundation
import Combine
import CoreMotion
import simd
import PhotosUI
import CoreTransferable
import SceneKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

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

/// Stable world-space position for a selectable reclining theater seat.
private struct CinemaSeat {
    let id: Int
    let row: Int
    let column: Int
    let position: SCNVector3

    var cameraPosition: SCNVector3 {
        SCNVector3(position.x, position.y + 1.70, position.z - 0.13)
    }

    var label: String { "F\(row + 1) · P\(column + 1)" }
}

final class CinemaModel: ObservableObject {
    let library = CinemaLibrary()
    private let roomAudio = VRCinemaAudio()
    private var presented = false
    private var periodicObserver: Any?
    private var audioInterruption: NSObjectProtocol?
    @Published private(set) var movieVolume: Float = 1
    @Published private(set) var movieMuted = false
    @Published private(set) var roomAmbience = false
    @Published private(set) var roomBrightness: CGFloat = 1
    @Published var toolsSelected = false
    private var libraryObservation: AnyCancellable?
    @Published var libraryVisible = false {
        didSet { if !libraryVisible { pendingLibraryDelete = nil } }
    }
    @Published var libraryPage = 0
    @Published private var pendingLibraryDelete: UUID?
    let scene = SCNScene()
    // One rotating head rig keeps the stereo 64-mm separation aligned with
    // the head direction. Previously each eye was rotated independently at
    // a fixed WORLD-space X offset, corrupting stereo when looking sideways.
    private let headRig = SCNNode()
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
    private var endPlaybackObserver: NSObjectProtocol?
    private var playbackStatusObservation: NSKeyValueObservation?
    private var importedMovieURL: URL?
    private var currentLibraryURL: URL?
    private var movieImportID = UUID()
    private var initialOrientation: simd_quatf?
    private let motion = CMMotionManager()
    private var motionReference: simd_quatf?
    private var lastARPose: ARCamera?
    @Published private(set) var headTrackingStatus = "Iniciando sensores…"
    // Hide the overlay five seconds after movie playback starts so it never
    // obstructs the screen; tapping the scene or Menu restores controls.
    @Published var showControlsAutomatically = true {
        didSet {
            UserDefaults.standard.set(showControlsAutomatically,
                                      forKey: "vros.cinema.autoControls.v1")
            revealControls()
        }
    }
    @Published private(set) var screenPitchDegrees: Float = 0
    @Published private(set) var screenYawDegrees: Float = 0
    @Published var invertTracking = false
    private var screenPitchOffset: Float = 0
    private var screenYawOffset: Float = 0
     private var screenAimOrientation = simd_quatf()
    private var lastMotionTimestamp: TimeInterval = 0
    private var roomLights: [SCNLight] = []
    private var ambientLight: SCNLight?
    private var screenBounceLight: SCNLight?
    private var accentNodes: [SCNNode] = []
    private var controlsTask: Task<Void, Never>?
    private var seats: [CinemaSeat] = []
    private var seatMarkers: [Int: SCNNode] = [:]
    weak var leftSceneView: SCNView?
    @Published private(set) var currentSeatID = 30
    @Published private(set) var currentSeatLabel = "F3 · P7"
    @Published var seatSelectionMode = false
    @Published var gazeProgress: CGFloat = 0
    @Published var movieTitle = "Escolha um filme MP4"
    @Published var playing = false
    @Published var selectedMode: CinemaVideoMode = .twoD
    @Published var immersiveScreen = true {
        didSet {
            UserDefaults.standard.set(immersiveScreen,
                                      forKey: "vros.cinema.immersive.v1")
        }
    }
    @Published var cinemaFovDegrees: CGFloat = 88
    @Published var swapEyes = false {
        didSet {
            UserDefaults.standard.set(swapEyes, forKey: "vros.cinema.swapEyes.v1")
        }
    }
    @Published var convergence: CGFloat = 0
    @Published var controlsVisible = true
    @Published var errorMessage: String?
    @Published var showPicker = false

    init() {
        libraryObservation = library.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Previous versions copied every imported movie into Documents
        // without deleting it. No release exposed these internal copies to
        // the picker; clear them, then use Caches for temporary playback.
        let fileManager = FileManager.default
        let oldFolder = fileManager.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cinema", isDirectory: true)
        try? fileManager.removeItem(at: oldFolder)
        let cacheFolder = fileManager.urls(
            for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cinema", isDirectory: true)
        try? fileManager.removeItem(at: cacheFolder)

        let preferences = UserDefaults.standard
        if preferences.object(forKey: "vros.cinema.volume.v1") != nil {
            movieVolume = min(1, max(0, preferences.float(forKey: "vros.cinema.volume.v1")))
        }
        movieMuted = preferences.bool(forKey: "vros.cinema.muted.v1")
        let brightness = preferences.double(forKey: "vros.cinema.brightness.v1")
        if brightness.isFinite && brightness >= 0.1 && brightness <= 1.5 { roomBrightness = brightness }
        audioInterruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ==
                AVAudioSession.InterruptionType.began.rawValue { self?.exit() }
        }
        if preferences.object(forKey: "vros.cinema.autoControls.v1") != nil {
            showControlsAutomatically =
                preferences.bool(forKey: "vros.cinema.autoControls.v1")
        }
        if preferences.object(forKey: "vros.cinema.immersive.v1") != nil {
            immersiveScreen = preferences.bool(forKey: "vros.cinema.immersive.v1")
        }
        if preferences.object(forKey: "vros.cinema.swapEyes.v1") != nil {
            swapEyes = preferences.bool(forKey: "vros.cinema.swapEyes.v1")
        }
        let savedFOV = preferences.double(forKey: "vros.cinema.fov.v1")
        if savedFOV >= 55 && savedFOV <= 115 {
            cinemaFovDegrees = CGFloat(savedFOV)
        }
        invertTracking = preferences.bool(forKey: "vros.cinema.invert.v1")
        screenPitchOffset = Float(preferences.double(forKey: "vros.cinema.pitch.v1"))
        screenYawOffset = Float(preferences.double(forKey: "vros.cinema.yaw.v1"))
        screenPitchOffset = max(-0.50, min(0.50, screenPitchOffset))
        screenYawOffset = max(-0.50, min(0.50, screenYawOffset))

        buildRoom()
        let savedSeat = preferences.integer(forKey: "vros.cinema.seat.v1")
        if preferences.object(forKey: "vros.cinema.seat.v1") != nil,
           let seat = seats.first(where: { $0.id == savedSeat }) {
            currentSeatID = seat.id
            currentSeatLabel = seat.label
            refreshSeatMarkerColors()
        }
        updateStereoMaterials()
        updateSeatPosition()
        refreshScreenAim()
        updateLighting(animated: false)
    }

    deinit {
        if let observer = periodicObserver { player?.removeTimeObserver(observer) }
        if let observer = audioInterruption { NotificationCenter.default.removeObserver(observer) }
        roomAudio.stop()
        motion.stopDeviceMotionUpdates()
        controlsTask?.cancel()
        if let observer = endPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let url = importedMovieURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func enter(camera: ARCamera?) {
        presented = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { errorMessage = "Áudio indisponível: " + error.localizedDescription }
        if roomAmbience { try? roomAudio.start() }
        setSeatSelectionMode(false)
        motion.stopDeviceMotionUpdates()
        lastARPose = camera
        initialOrientation = camera.map { simd_quatf($0.transform) }
        motionReference = nil
        lastMotionTimestamp = 0
        headTrackingStatus = "Calibrando movimento…"
        controlsVisible = true
        refreshScreenAim()
        startHeadTracking()
    }

    func exit() {
        savePlaybackProgress()
        presented = false
        roomAudio.stop()
        libraryVisible = false

        // A copy finishing after exit/background must never start audio.
        movieImportID = UUID()
        setSeatSelectionMode(false)
        motion.stopDeviceMotionUpdates()
        motionReference = nil
        lastMotionTimestamp = 0
        player?.pause()
        playing = false
        controlsTask?.cancel()
        controlsVisible = true
        updateLighting()
    }

    /// CoreMotion provides a stable reference even when a headset blocks the
    /// rear camera. Quaternions are calibrated at the user's current pose.
    /// The neutral view ALWAYS looks at the screen centre from the current seat.
    private func startHeadTracking() {
        guard motion.isDeviceMotionAvailable else {
            headTrackingStatus = "Sensores indisponíveis · usando ARKit"
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        lastMotionTimestamp = ProcessInfo.processInfo.systemUptime
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryZVertical)
            ? .xArbitraryZVertical : .xArbitraryCorrectedZVertical
        motion.startDeviceMotionUpdates(using: frame, to: .main) {
            [weak self] measurement, error in
            guard let self = self else { return }
            guard let measurement = measurement, error == nil else {
                self.headTrackingStatus = "Falha nos sensores · usando ARKit"
                self.initialOrientation = self.lastARPose.map {
                    simd_quatf($0.transform)
                }
                self.motion.stopDeviceMotionUpdates()
                return
            }
            self.lastMotionTimestamp = ProcessInfo.processInfo.systemUptime
            let q = measurement.attitude.quaternion
            let current = simd_normalize(simd_quatf(
                ix: Float(q.x), iy: Float(q.y),
                iz: Float(q.z), r: Float(q.w)
            ))
            if self.motionReference == nil {
                self.motionReference = current
                self.headTrackingStatus = "Cabeça: sensores ativos"
                self.applyHeadOrientation(simd_quatf())
            }
            guard let baseline = self.motionReference else { return }

            // The relative attitude is expressed in the INITIAL DEVICE frame.
            // Convert it to the actual landscape display axes before sending
            // it to SceneKit. Old versions hardcoded LandscapeRight even when
            // iOS showed the other landscape orientation.
            let deltaDevice = simd_inverse(baseline) * current
            let basis = self.screenToDeviceRotation()
            let deltaDisplay = simd_inverse(basis) * deltaDevice * basis
            self.applyHeadOrientation(simd_normalize(deltaDisplay))
        }
    }

    /// SceneKit camera axes: +X right, +Y up, -Z forward.
    /// Portrait phone axes are rotated a quarter turn in a landscape holder.
    /// The specific sign depends on the actual interface orientation.
    private func screenToDeviceRotation() -> simd_quatf {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .landscapeRight
        let turn: Float = orientation == .landscapeLeft ? -.pi / 2 : .pi / 2
        return simd_quatf(angle: turn, axis: SIMD3<Float>(0, 0, 1))
    }

    func recenterHead() {
        if motion.isDeviceMotionActive,
           let reading = motion.deviceMotion?.attitude.quaternion {
            motionReference = simd_normalize(simd_quatf(
                ix: Float(reading.x), iy: Float(reading.y),
                iz: Float(reading.z), r: Float(reading.w)))
        } else if let pose = lastARPose {
            initialOrientation = simd_quatf(pose.transform)
        }
        applyHeadOrientation(simd_quatf())
        revealControls()
    }

    func updateHead(_ camera: ARCamera?) {
        lastARPose = camera
        // If CoreMotion stops or ceases sending updates, don't freeze the
        // screen forever. Fall back to relative ARKit camera orientation.
        let recentMotion = motion.isDeviceMotionActive &&
            ProcessInfo.processInfo.systemUptime - lastMotionTimestamp < 0.6
        guard !recentMotion, let pose = camera else { return }
        let current = simd_quatf(pose.transform)
        if initialOrientation == nil { initialOrientation = current }
        guard let origin = initialOrientation else { return }
        let delta = simd_normalize(simd_inverse(origin) * current)
        applyHeadOrientation(delta)
    }

    /// A camera in the left or right section of the auditorium needs BOTH
    /// yaw and pitch to face the real screen centre. Pitch-only alignment
    /// leaves the movie off-centre and looking at chair backs.
    private func refreshScreenAim() {
        guard let seat = seats.first(where: { $0.id == currentSeatID }) else { return }
        let eye = SIMD3<Float>(seat.cameraPosition.x,
                               seat.cameraPosition.y,
                               seat.cameraPosition.z)
        let neutral = VRCinemaGeometry.lookRotation(from: eye)
        let extraYaw = simd_quatf(angle: screenYawOffset,
                                  axis: SIMD3<Float>(0, 1, 0))
        let extraPitch = simd_quatf(angle: screenPitchOffset,
                                    axis: SIMD3<Float>(1, 0, 0))
        screenAimOrientation = simd_normalize(neutral * extraYaw * extraPitch)
        screenPitchDegrees = VRCinemaGeometry.pitchDegrees(from: eye) +
                             screenPitchOffset * 180 / .pi
        screenYawDegrees = VRCinemaGeometry.yawDegrees(from: eye) +
                           screenYawOffset * 180 / .pi
        applyHeadOrientation(simd_quatf())
    }

    private func applyHeadOrientation(_ delta: simd_quatf) {
        let corrected = invertTracking ? simd_inverse(delta) : delta
        let finalOrientation = simd_normalize(screenAimOrientation * corrected)
        headRig.simdOrientation = finalOrientation
        if roomAudio.active { roomAudio.updateOrientation(finalOrientation) }
    }

    func adjustScreenHeight(_ direction: Float) {
        screenPitchOffset = max(-0.50, min(0.50,
                                         screenPitchOffset + direction * (.pi / 36)))
        UserDefaults.standard.set(Double(screenPitchOffset),
                                  forKey: "vros.cinema.pitch.v1")
        refreshScreenAim()
        recenterHead()
    }

    func adjustScreenHorizontal(_ direction: Float) {
        screenYawOffset = max(-0.50, min(0.50,
                                       screenYawOffset + direction * (.pi / 36)))
        UserDefaults.standard.set(Double(screenYawOffset),
                                  forKey: "vros.cinema.yaw.v1")
        refreshScreenAim()
        recenterHead()
    }

    func resetScreenAim() {
        screenPitchOffset = 0
        screenYawOffset = 0
        UserDefaults.standard.set(0.0, forKey: "vros.cinema.pitch.v1")
        UserDefaults.standard.set(0.0, forKey: "vros.cinema.yaw.v1")
        refreshScreenAim()
        recenterHead()
    }

    func resetPlacement() {
        convergence = 0
        updateStereoMaterials()
        _ = selectSeat(30)
        resetScreenAim()
    }

    // Covers the asynchronous Photos/iCloud download BEFORE file import starts.
    func beginPhotoImport() -> UUID {
        controlsTask?.cancel()
        controlsVisible = true
        movieImportID = UUID()
        return movieImportID
    }

    func acceptsPhotoImport(_ token: UUID) -> Bool {
        movieImportID == token
    }

    func toggleTrackingDirection() {
        invertTracking.toggle()
        UserDefaults.standard.set(invertTracking, forKey: "vros.cinema.invert.v1")
        recenterHead()
    }

    func loadMovie(_ url: URL, deleteSourceAfterImport: Bool = false, displayTitle: String? = nil) {
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
        let importID = UUID()
        movieImportID = importID
        controlsTask?.cancel()
        controlsVisible = true
        errorMessage = "Importando vídeo…"
        Task { @MainActor [weak self] in
            do {
                let dest = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer {
                        if access { url.stopAccessingSecurityScopedResource() }
                        if deleteSourceAfterImport { try? FileManager.default.removeItem(at: url) }
                    }
                    let folder = CinemaLibrary.folder
                    try FileManager.default.createDirectory(at: folder,
                                                            withIntermediateDirectories: true)
                    if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                        return url
                    }
                    let dest = folder.appendingPathComponent(
                        UUID().uuidString + "." + url.pathExtension.lowercased())
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                        return dest
                    } catch {
                        try? FileManager.default.removeItem(at: dest)
                        throw error
                    }
                }.value
                guard let self = self, self.movieImportID == importID else {
                    if dest != url { try? FileManager.default.removeItem(at: dest) }
                    return
                }
                self.installMovie(dest, sourceURL: url, importID: importID, displayTitle: displayTitle)
            } catch {
                guard let self = self, self.movieImportID == importID else { return }
                self.errorMessage = "Erro ao importar vídeo: " + error.localizedDescription
                self.revealControls()
            }
        }
    }

    private func installMovie(_ dest: URL, sourceURL url: URL, importID: UUID, displayTitle: String? = nil) {
        savePlaybackProgress()
        if let observer = periodicObserver { player?.removeTimeObserver(observer); periodicObserver = nil }
        player?.pause()
        playbackStatusObservation = nil
        sourceAspect = 16.0 / 9.0
        if let previousObserver = endPlaybackObserver {
            NotificationCenter.default.removeObserver(previousObserver)
            endPlaybackObserver = nil
        }
        if let previousFile = importedMovieURL {
            try? FileManager.default.removeItem(at: previousFile)
        }
        // Library owns retained imports. Player cleanup only owns cache files.
        importedMovieURL = nil
        currentLibraryURL = dest
        library.record(url: dest, title: displayTitle ?? url.deletingPathExtension().lastPathComponent)
        let movie = AVPlayer(url: dest)
        movie.actionAtItemEnd = .pause
        leftScreenMaterial.diffuse.contents = movie
        rightScreenMaterial.diffuse.contents = movie
        player = movie
        movie.volume = movieVolume
        movie.isMuted = movieMuted
        let savedEntry = library.entries.first { $0.filename == dest.lastPathComponent }
        convergence = CGFloat(savedEntry?.convergence ?? 0)
        if let seconds = savedEntry?.seconds, seconds.isFinite, seconds > 0 {
            movie.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        periodicObserver = movie.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
            self?.savePlaybackProgress()
        }
        playbackStatusObservation = movie.currentItem?.observe(
            \.status, options: [.initial, .new]) { [weak self, weak movie] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Formato de vídeo incompatível."
            DispatchQueue.main.async {
                guard let self = self, self.player === movie else { return }
                self.player?.pause()
                self.playing = false
                self.errorMessage = "Não foi possível reproduzir: " + message
                self.updateLighting()
                self.revealControls()
            }
        }
        endPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: movie.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.playing = false
            self.updateLighting()
            self.revealControls()
        }
        movieTitle = library.entries.first(where: { $0.filename == dest.lastPathComponent })?.title ??
            url.deletingPathExtension().lastPathComponent
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
        if let saved = library.entries.first(where: { $0.filename == dest.lastPathComponent })?.mode,
           let mode = CinemaVideoMode(rawValue: saved) {
            selectedMode = mode
        }
        library.saveMode(selectedMode.rawValue, for: dest)
        updateStereoMaterials()
        fitScreen()
        errorMessage = nil
        playing = true
        updateLighting()
        revealControls()
        movie.play()

        // Rotate-aware aspect ratio. The video plane fits INSIDE the
        // 27.2-by-13.4-metre screen instead of stretching 16:9 or 2.39:1.
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
        if let url = currentLibraryURL { library.saveMode(mode.rawValue, for: url) }
        updateStereoMaterials()
        fitScreen()
        revealControls()
    }

    func toggleImmersive() {
        immersiveScreen.toggle()
        updateSeatPosition()
        recenterHead()
        revealControls()
    }

    func adjustCinemaFOV(_ delta: CGFloat) {
        cinemaFovDegrees = min(115, max(55, cinemaFovDegrees + delta))
        UserDefaults.standard.set(Double(cinemaFovDegrees),
                                  forKey: "vros.cinema.fov.v1")
        updateSeatPosition()
        revealControls()
    }

    /// Move the STEREO HEAD RIG as one object; eye offsets stay in its
    /// local coordinates and therefore rotate correctly with head motion.
    private func updateSeatPosition(animated: Bool = false) {
        guard let selected = seats.first(where: { $0.id == currentSeatID }) else { return }
        for eye in [leftCamera, rightCamera] {
            // Each eye receives half the landscape display. SceneKit defaults
            // to VERTICAL FOV; the visible horizontal angle then depends on
            // the eye viewport aspect ratio. Explicit horizontal FOV makes the
            // cinema's left-right framing consistent across screen sizes.
            eye.camera?.projectionDirection = .horizontal
            eye.camera?.fieldOfView = immersiveScreen
                ? cinemaFovDegrees : min(125, cinemaFovDegrees + 12)
        }
        let target = selected.cameraPosition
        headRig.removeAction(forKey: "cinemaSeatTravel")
        if animated {
            let move = SCNAction.move(to: target, duration: 0.72)
            move.timingMode = .easeInEaseOut
            headRig.runAction(move, forKey: "cinemaSeatTravel")
        } else {
            headRig.position = target
        }
    }

    func setSeatSelectionMode(_ enabled: Bool) {
        seatSelectionMode = enabled
        gazeProgress = 0
        for marker in seatMarkers.values { marker.isHidden = !enabled }
        revealControls()
    }

    func toggleSeatSelection() {
        setSeatSelectionMode(!seatSelectionMode)
    }

    /// Raycast ignores the auditorium's chairs and finds only the glowing
    /// selection orbs. Used by touch, pinch, and the headset gaze dwell.
    private func targetedSeat(at point: CGPoint, in view: SCNView) -> Int? {
        let hit = view.hitTest(point, options: [
            .categoryBitMask: 8,
            .firstFoundOnly: true
        ]).first
        guard let name = hit?.node.name,
              name.hasPrefix("seat-indicator-") else { return nil }
        return Int(name.replacingOccurrences(of: "seat-indicator-", with: ""))
    }

    func seatAtGazeCenter() -> Int? {
        guard seatSelectionMode, let view = leftSceneView else { return nil }
        return targetedSeat(at: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                            in: view)
    }

    @discardableResult
    func chooseSeatByGaze(_ seatID: Int) -> Bool {
        guard seatSelectionMode else { return false }
        return selectSeat(seatID)
    }

    @discardableResult
    func chooseSeat(at viewportPoint: CGPoint, in view: SCNView? = nil,
                    tryGazeCenter: Bool = false) -> Bool {
        guard seatSelectionMode, let renderer = view ?? leftSceneView else { return false }
        let seatID = targetedSeat(at: viewportPoint, in: renderer) ??
            (tryGazeCenter ? seatAtGazeCenter() : nil)
        guard let seatID = seatID else { return false }
        return selectSeat(seatID)
    }

    @discardableResult
    private func selectSeat(_ seatID: Int) -> Bool {
        guard let seat = seats.first(where: { $0.id == seatID }) else { return false }
        currentSeatID = seatID
        currentSeatLabel = seat.label
        UserDefaults.standard.set(seatID, forKey: "vros.cinema.seat.v1")
        refreshSeatMarkerColors()
        // Lock the new chair position but reset the head's look direction
        // so the next camera frame faces the enormous screen naturally.
        if let q = motion.deviceMotion?.attitude.quaternion {
            motionReference = simd_normalize(simd_quatf(
                ix: Float(q.x), iy: Float(q.y),
                iz: Float(q.z), r: Float(q.w)))
        } else if let pose = lastARPose {
            initialOrientation = simd_quatf(pose.transform)
        }
        updateSeatPosition(animated: true)
        refreshScreenAim()
        recenterHead()
        setSeatSelectionMode(false)
        return true
    }

    private func refreshSeatMarkerColors() {
        for (id, marker) in seatMarkers {
            let selected = id == currentSeatID
            let tint = selected
                ? UIColor(red: 1, green: 0.78, blue: 0.28, alpha: 1)
                : UIColor(red: 0.24, green: 0.85, blue: 1, alpha: 1)
            marker.geometry?.firstMaterial?.diffuse.contents = tint
            marker.geometry?.firstMaterial?.emission.contents = tint
        }
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
        var scaleX: Float
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
        // Set UV scale and offset independently. Multiplying translation
        // by scale can halve the right-eye offset and sample the centre seam.
        var transform = SCNMatrix4Identity
        let margin: Float = selectedMode == .twoD ? 0 : abs(Float(convergence))
        scaleX = max(0.01, scaleX - 2 * margin)
        transform.m11 = scaleX
        transform.m22 = scaleY
        transform.m41 = translationX + margin + shift
        transform.m42 = translationY
        material.diffuse.contentsTransform = transform
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.lightingModel = .constant
        material.isDoubleSided = true
    }

    func togglePlayback() {
        guard let player = player else { showPicker = true; return }
        guard player.currentItem?.status != .failed else {
            errorMessage = player.currentItem?.error?.localizedDescription ??
                "Este vídeo não pode ser reproduzido."
            revealControls()
            return
        }
        if playing {
            player.pause()
            playing = false
        } else {
            let endTime = player.currentItem?.duration.seconds ?? .nan
            let current = player.currentTime().seconds
            if endTime.isFinite && endTime > 0 && current.isFinite &&
               current >= endTime - 0.2 {
                player.seek(to: .zero)
            }
            player.play()
            playing = true
        }
        updateLighting()
        revealControls()
    }

    func seek(_ delta: Double) {
        guard let player = player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let end = duration.isFinite && duration > 0
            ? duration : Double.greatestFiniteMagnitude
        player.seek(to: CMTime(seconds: min(end, max(0, seconds + delta)),
                              preferredTimescale: 600))
        revealControls()
    }

    func revealControls() {
        controlsTask?.cancel()
        controlsVisible = true
        guard playing && showControlsAutomatically else { return }
        controlsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self = self, self.playing else { return }
            self.controlsVisible = false
        }
    }

    func toggleMenu() {
        if controlsVisible {
            controlsTask?.cancel()
            controlsVisible = false
        } else {
            revealControls()
        }
    }


    private func savePlaybackProgress() {
        guard let url = currentLibraryURL, let player = player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let position = duration.isFinite && seconds >= duration - 2 ? 0 : seconds
        library.saveProgress(position, convergence: Double(convergence), for: url)
    }

    func setMovieVolume(_ raw: Float) {
        guard raw.isFinite else { return }
        movieVolume = max(0, min(1, raw))
        player?.volume = movieVolume
        UserDefaults.standard.set(movieVolume, forKey: "vros.cinema.volume.v1")
    }

    func setRoomBrightness(_ raw: CGFloat) {
        guard raw.isFinite else { return }
        roomBrightness = max(0.1, min(1.5, raw))
        UserDefaults.standard.set(Double(roomBrightness), forKey: "vros.cinema.brightness.v1")
        updateLighting()
    }

    var toolItems: [VRWorkspaceItem] {
        [
            ("mode", "Formato", selectedMode.rawValue, "rectangle.split.2x1"),
            ("eyes", "Trocar olhos", swapEyes ? "Invertidos" : "Normal", "eye"),
            ("conv-", "Convergência −", String(format: "%.3f", Double(convergence)), "minus"),
            ("conv+", "Convergência +", "Ajustar profundidade 3D", "plus"),
            ("seat-", "Assento anterior", currentSeatLabel, "chair.lounge"),
            ("seat+", "Próximo assento", currentSeatLabel, "chair.lounge.fill"),
            ("light-", "Menos luz", "\(Int(roomBrightness * 100))%", "sun.min"),
            ("light+", "Mais luz", "\(Int(roomBrightness * 100))%", "sun.max"),
            ("vol-", "Volume −", "\(Int(movieVolume * 100))%", "speaker.wave.1"),
            ("vol+", "Volume +", "\(Int(movieVolume * 100))%", "speaker.wave.3"),
            ("mute", "Mudo", movieMuted ? "Ativo" : "Desativado", "speaker.slash"),
            ("ambience", "Projetor espacial", roomAmbience ? "Ativo" : "Desativado", "hifispeaker.fill"),
            ("fov-", "Tela maior", "Aproximar campo visual", "plus.magnifyingglass"),
            ("fov+", "Tela menor", "Ampliar campo visual", "minus.magnifyingglass")
        ].map { VRWorkspaceItem(id: "tool." + $0.0, title: $0.1, detail: $0.2,
            symbol: $0.3, command: .cinemaTool($0.0)) }
    }

    var panelItems: [VRWorkspaceItem] { toolsSelected ? toolItems : libraryItems }

    func applyTool(_ key: String) {
        switch key {
        case "mode":
            let modes = CinemaVideoMode.allCases
            if let i = modes.firstIndex(of: selectedMode) { selectMode(modes[(i + 1) % modes.count]) }
        case "eyes": toggleEyeOrder()
        case "conv-": adjustConvergence(-1); savePlaybackProgress()
        case "conv+": adjustConvergence(1); savePlaybackProgress()
        case "seat-": _ = selectSeat((currentSeatID + 71) % 72)
        case "seat+": _ = selectSeat((currentSeatID + 1) % 72)
        case "light-": setRoomBrightness(roomBrightness - 0.1)
        case "light+": setRoomBrightness(roomBrightness + 0.1)
        case "vol-": setMovieVolume(movieVolume - 0.1)
        case "vol+": setMovieVolume(movieVolume + 0.1)
        case "mute":
            movieMuted.toggle(); player?.isMuted = movieMuted
            UserDefaults.standard.set(movieMuted, forKey: "vros.cinema.muted.v1")
        case "ambience":
            roomAmbience.toggle()
            do { if roomAmbience && presented { try roomAudio.start() } else { roomAudio.stop() } }
            catch { roomAmbience = false; errorMessage = error.localizedDescription }
        case "fov-": adjustCinemaFOV(-5)
        case "fov+": adjustCinemaFOV(5)
        default: break
        }
    }

    var libraryItems: [VRWorkspaceItem] {
        library.entries.flatMap { entry in [
            VRWorkspaceItem(id: entry.id.uuidString, title: entry.title,
                detail: "Reproduzir · histórico", symbol: "film.fill",
                command: .movie(entry.id), artwork: library.covers[entry.id]),
            VRWorkspaceItem(id: entry.id.uuidString + ".favorite", title: entry.favorite ? "Favorito" : "Favoritar",
                detail: entry.title, symbol: entry.favorite ? "star.fill" : "star",
                command: .favoriteMovie(entry.id)),
            VRWorkspaceItem(id: entry.id.uuidString + ".delete",
                title: pendingLibraryDelete == entry.id ? "Confirmar exclusão" : "Excluir cópia",
                detail: entry.title, symbol: "trash", command: .deleteMovie(entry.id))
        ]}
    }

    func selectLibrary(_ command: VRWorkspaceCommand) {
        switch command {
        case let .cinemaTool(key): applyTool(key)
        case let .movie(id):
            guard let entry = library.entries.first(where: { $0.id == id }) else { return }
            libraryVisible = false
            loadMovie(library.url(for: entry))
        case let .favoriteMovie(id):
            objectWillChange.send()
            library.toggleFavorite(id)
            pendingLibraryDelete = nil
        case let .deleteMovie(id):
            guard pendingLibraryDelete == id else {
                pendingLibraryDelete = id
                return
            }
            pendingLibraryDelete = nil
            if let entry = library.entries.first(where: { $0.id == id }),
               library.url(for: entry) == currentLibraryURL {
                exit()
                player?.replaceCurrentItem(with: nil)
                currentLibraryURL = nil
                movieTitle = "Escolha um filme MP4"
            }
            do {
                try library.remove(id)
                changeLibraryPage(0)
            } catch {
                libraryVisible = false
                errorMessage = "Não foi possível excluir a cópia: " + error.localizedDescription
                revealControls()
            }
        default: break
        }
    }

    func changeLibraryPage(_ delta: Int) {
        libraryPage = max(0, min(max(0, (panelItems.count - 1) / 6), libraryPage + delta))
    }

    func updateLighting(animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 1.5 : 0
        ambientLight?.intensity = (playing ? 75 : 230) * roomBrightness
        screenBounceLight?.intensity = (playing ? 210 : 95) * roomBrightness
        for light in roomLights {
            light.intensity = (playing ? 70 : 350) * roomBrightness
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

        // 72 recliners in six staggered, raised rows. The centre aisle is
        // intentionally wide enough to see and select the front chairs.
        // Shared prototype geometry and materials keep the stereo draw cost low.
        let chairPrototype = SCNNode()
        let fabric = UIColor(red: 0.40, green: 0.022, blue: 0.073, alpha: 1)
        let fabricHighlight = UIColor(red: 0.53, green: 0.07, blue: 0.11, alpha: 1)
        let shell = UIColor(red: 0.045, green: 0.036, blue: 0.053, alpha: 1)
        let armTop = UIColor(red: 0.145, green: 0.11, blue: 0.13, alpha: 1)
        let stitching = UIColor(red: 0.69, green: 0.31, blue: 0.31, alpha: 1)

        func chairBox(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                      x: Float, y: Float, z: Float,
                      tint: UIColor, radius: CGFloat = 0.09) {
            let geometry = SCNBox(width: w, height: h, length: d,
                                  chamferRadius: radius)
            geometry.firstMaterial?.diffuse.contents = tint
            let part = SCNNode(geometry: geometry)
            part.position = SCNVector3(x, y, z)
            chairPrototype.addChildNode(part)
        }

        // Raised armchairs: the rigid back shell frames two padded cushions.
        chairBox(1.79, 1.85, 0.26, x: 0, y: 1.56, z: 0.69,
                 tint: shell, radius: 0.13)
        chairBox(1.55, 1.35, 0.24, x: 0, y: 1.65, z: 0.48,
                 tint: fabric, radius: 0.17)
        chairBox(1.47, 0.35, 0.19, x: 0, y: 2.34, z: 0.46,
                 tint: fabricHighlight, radius: 0.12)
        chairBox(1.45, 0.34, 1.35, x: 0, y: 0.83, z: -0.17,
                 tint: fabricHighlight, radius: 0.16)
        chairBox(1.42, 0.30, 0.66, x: 0, y: 0.49, z: -0.75,
                 tint: fabric, radius: 0.12)  // folding foot rest
        chairBox(1.60, 0.28, 1.38, x: 0, y: 0.55, z: -0.10,
                 tint: shell, radius: 0.09)
        for side in [Float(-1), Float(1)] {
            chairBox(0.22, 0.78, 1.60, x: side * 0.90, y: 0.97, z: 0,
                     tint: shell, radius: 0.08)
            chairBox(0.23, 0.15, 1.30, x: side * 0.90, y: 1.37, z: -0.08,
                     tint: armTop, radius: 0.065)
            chairBox(0.11, 1.31, 0.055, x: side * 0.69, y: 1.65, z: 0.33,
                     tint: stitching, radius: 0.025)
            let metal = SCNCylinder(radius: 0.12, height: 0.016)
            metal.firstMaterial?.diffuse.contents = gold
            let cupRing = SCNNode(geometry: metal)
            cupRing.position = SCNVector3(side * 0.90, 1.46, -0.43)
            chairPrototype.addChildNode(cupRing)
            let insert = SCNCylinder(radius: 0.074, height: 0.021)
            insert.firstMaterial?.diffuse.contents = UIColor.black
            let hole = SCNNode(geometry: insert)
            hole.position = SCNVector3(side * 0.90, 1.472, -0.43)
            chairPrototype.addChildNode(hole)
        }
        chairBox(0.82, 0.45, 0.79, x: 0, y: 0.30, z: 0.15,
                 tint: shell, radius: 0.09)

        for row in 0..<6 {
            let rowZ = Float(row) * 4.2 - 11.7
            let rise = Float(row) * 0.33
            if row > 0 {
                box(27.9, CGFloat(rise), 4.02, 0, rise / 2 - 0.01,
                    rowZ, darkCarpet)
            }
            for sideIndex in 0..<2 {
                let side: Float = sideIndex == 0 ? -1 : 1
                for column in 0..<6 {
                    let seatID = row * 12 + sideIndex * 6 + column
                    let x = side * (2.45 + Float(column) * 2.08)
                    let seatOrigin = SCNVector3(x, rise, rowZ)
                    let seat = CinemaSeat(id: seatID, row: row,
                                          column: sideIndex * 6 + column,
                                          position: seatOrigin)
                    seats.append(seat)

                    let chair = chairPrototype.clone()
                    chair.position = seatOrigin
                    scene.rootNode.addChildNode(chair)

                    // Neon selection pin. No physics: only rendered when the
                    // seat picker is explicitly open, never during the movie.
                    let orb = SCNSphere(radius: 0.26)
                    orb.segmentCount = 12
                    let orbMaterial = SCNMaterial()
                    orbMaterial.lightingModel = .constant
                    orb.firstMaterial = orbMaterial
                    let marker = SCNNode(geometry: orb)
                    marker.name = "seat-indicator-\(seatID)"
                    marker.categoryBitMask = 8
                    marker.position = SCNVector3(x, rise + 2.93, rowZ - 0.10)
                    marker.isHidden = true
                    scene.rootNode.addChildNode(marker)
                    seatMarkers[seatID] = marker
                }
            }
        }
        refreshSeatMarkerColors()

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

        // One head rig with local ±32-mm eye offsets; unlike world-space
        // offsets, this preserves IPD direction when the user turns their head.
        scene.rootNode.addChildNode(headRig)
        for (index, eye) in [leftCamera, rightCamera].enumerated() {
            eye.camera = SCNCamera()
            eye.camera?.categoryBitMask = index == 0 ? (1 | 2 | 8) : (1 | 4 | 8)
            eye.camera?.projectionDirection = .horizontal
            eye.camera?.fieldOfView = cinemaFovDegrees
            eye.camera?.zNear = 0.05
            eye.camera?.zFar = 90
            eye.position = SCNVector3(index == 0 ? -0.032 : 0.032, 0, 0)
            headRig.addChildNode(eye)
        }
    }
}

private struct CinemaSceneView: UIViewRepresentable {
    let cinema: CinemaModel
    let runtime: VRRuntime
    let rightEye: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(cinema: cinema)
    }

    final class Coordinator: NSObject {
        let cinema: CinemaModel

        init(cinema: CinemaModel) { self.cinema = cinema }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view as? SCNView else { return }
            if cinema.seatSelectionMode &&
               cinema.chooseSeat(at: recognizer.location(in: view), in: view) {
                return
            }
            if !cinema.controlsVisible { cinema.revealControls() }
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = cinema.scene
        view.pointOfView = rightEye ? cinema.rightCamera : cinema.leftCamera
        view.backgroundColor = .black
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling2X
        if !rightEye { cinema.leftSceneView = view }
        view.addGestureRecognizer(UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
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
    @State private var gazeSeatID: Int?
    @State private var gazeBeganAt = Date()
    private let gazeTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tapping empty cinema space always restores options.
                        if !cinema.controlsVisible { cinema.revealControls() }
                    }
                // Persistent access: controls can ALWAYS be reopened without
                // requiring rear-camera hand tracking inside the VR headset.
                VStack {
                    VRCinemaToolbar(viewport: geometry.size, action: headerAction)
                    Spacer()
                }
                if cinema.seatSelectionMode {
                    ZStack {
                        Circle()
                            .strokeBorder(.cyan.opacity(0.88), lineWidth: 1.7)
                            .frame(width: 29, height: 29)
                        Circle()
                            .trim(from: 0, to: cinema.gazeProgress)
                            .stroke(.yellow, style: StrokeStyle(lineWidth: 3,
                                                               lineCap: .round))
                            .frame(width: 37, height: 37)
                            .rotationEffect(.degrees(-90))
                    }
                    .position(x: geometry.size.width / 2,
                              y: geometry.size.height / 2)
                    .allowsHitTesting(false)
                    VStack {
                        Spacer()
                        Text("Olhe 1,5 s para a bolinha, faça pinça ou toque")
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.78),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 10)
                            .padding(.bottom, 101)
                    }
                    .allowsHitTesting(false)
                }
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
                        cinemaOption("Centralizar") { cinema.recenterHead() }
                        cinemaOption(cinema.immersiveScreen ? "MAX ON" : "MAX OFF") {
                            cinema.toggleImmersive()
                        }
                        cinemaOption("Trocar olhos") { cinema.toggleEyeOrder() }
                        cinemaOption("3D −") { cinema.adjustConvergence(-1) }
                        cinemaOption("3D +") { cinema.adjustConvergence(1) }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 4)
                    HStack(spacing: 4) {
                        cinemaOption("Tela ↑") { cinema.adjustScreenHeight(1) }
                        cinemaOption("Tela ↓") { cinema.adjustScreenHeight(-1) }
                        cinemaOption("Tela ←") { cinema.adjustScreenHorizontal(-1) }
                        cinemaOption("Tela →") { cinema.adjustScreenHorizontal(1) }
                        cinemaOption("Mirar tela") { cinema.resetScreenAim() }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 3)
                    HStack(spacing: 5) {
                        cinemaOption("FOV −") { cinema.adjustCinemaFOV(-5) }
                        cinemaOption("FOV +") { cinema.adjustCinemaFOV(5) }
                        cinemaOption(cinema.invertTracking ? "Mov.: inverso" : "Mov.: normal") {
                            cinema.toggleTrackingDirection()
                        }
                        Text(String(format: "%.0f°", cinema.cinemaFovDegrees))
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 27)
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 3)
                    Text(String(format: "%@ · %@ · Mira ↑%.0f° ↔%.0f°",
                                cinema.headTrackingStatus, cinema.currentSeatLabel,
                                cinema.screenPitchDegrees, cinema.screenYawDegrees))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green.opacity(0.95))
                        .padding(.top, 3)
                    Spacer()
                    Text(cinema.movieTitle)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if let error = cinema.errorMessage {
                        Text(error).font(.system(size: 9)).foregroundStyle(.red).lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        cinemaButton("folder.fill", "Arquivos") { cinema.showPicker = true }
                        cinemaButton("photo.on.rectangle.angled", "Fototeca") {
                            guard !rightEye else { return }
                            pickingPhotoMovie = true
                        }
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
            .onReceive(gazeTimer) { _ in
                // Only left eye runs the gaze timer; the model publishes
                // progress so both headset eyes display one synchronized ring.
                guard !rightEye else { return }
                guard cinema.seatSelectionMode else {
                    gazeSeatID = nil
                    if cinema.gazeProgress != 0 { cinema.gazeProgress = 0 }
                    return
                }
                guard let target = cinema.seatAtGazeCenter() else {
                    gazeSeatID = nil
                    cinema.gazeProgress = 0
                    return
                }
                if gazeSeatID != target {
                    gazeSeatID = target
                    gazeBeganAt = Date()
                    cinema.gazeProgress = 0
                }
                let elapsed = Date().timeIntervalSince(gazeBeganAt)
                cinema.gazeProgress = CGFloat(min(1, max(0, elapsed / 1.5)))
                if elapsed >= 1.5 {
                    _ = cinema.chooseSeatByGaze(target)
                    gazeSeatID = nil
                    cinema.gazeProgress = 0
                }
            }
            .onChange(of: pickedMovie) { nextItem in
                guard !rightEye, let nextItem = nextItem else { return }
                let token = cinema.beginPhotoImport()
                Task {
                    do {
                        guard let movie = try await nextItem.loadTransferable(
                            type: CinemaPhotoMovie.self) else {
                            guard cinema.acceptsPhotoImport(token) else { return }
                            cinema.errorMessage = "Não foi possível importar esse vídeo da Fototeca."
                            cinema.revealControls()
                            return
                        }
                        guard cinema.acceptsPhotoImport(token) else {
                            try? FileManager.default.removeItem(at: movie.url)
                            return
                        }
                        cinema.loadMovie(movie.url, deleteSourceAfterImport: true)
                    } catch {
                        guard cinema.acceptsPhotoImport(token) else { return }
                        cinema.errorMessage = "Erro na Fototeca: " + error.localizedDescription
                        cinema.revealControls()
                    }
                }
            }
            .onReceive(runtime.$hand) { hand in
                guard !rightEye else { return }
                if cinema.libraryVisible {
                    if hand.visible && hand.pinching && !lastPinch {
                        let point = handPoint(size: geometry.size)
                        let box = VRWorkspaceGeometry.bounds(geometry.size)
                        if point.y < box.minY + 36 && point.x > box.maxX - 45 {
                            cinema.libraryVisible = false
                        } else if point.y > box.maxY - 28 {
                            if point.x < box.midX - box.width / 6 { cinema.changeLibraryPage(-1) }
                            if point.x > box.midX + box.width / 6 { cinema.changeLibraryPage(1) }
                        } else if let slot = VRWorkspaceGeometry.item(at: point, in: geometry.size) {
                            let index = cinema.libraryPage * 6 + slot
                            if cinema.panelItems.indices.contains(index) {
                                cinema.selectLibrary(cinema.panelItems[index].command)
                            }
                        }
                    }
                    lastPinch = hand.visible && hand.pinching
                    return
                }
                if hand.visible && hand.pinching && !lastPinch {
                    if let slot = VRCinemaToolbarGeometry.slot(
                        at: handPoint(size: geometry.size), viewport: geometry.size) {
                        headerAction(slot)
                        lastPinch = true
                        return
                    }
                    if cinema.seatSelectionMode {
                        // First try the fingertip; aim at a seat marker with
                        // the centre reticle as a fallback for the VR Box.
                        _ = cinema.chooseSeat(at: handPoint(size: geometry.size),
                                              tryGazeCenter: true)
                    } else if !cinema.controlsVisible {
                        // First pinch brings the controls back without
                        // accidentally pausing or exiting the movie.
                        cinema.revealControls()
                    } else {
                    let point = handPoint(size: geometry.size)
                    let bottom = geometry.size.height - 40
                    if point.y < 42 {
                        // Only exact toolbar targets can activate a header action.
                    } else if point.y >= 44 && point.y <= 88 {
                        let slot = min(3, max(0, Int(point.x / max(1, geometry.size.width) * 4)))
                        cinema.selectMode(CinemaVideoMode.allCases[slot])
                    } else if point.y > 88 && point.y <= 133 {
                        let slot = min(4, max(0, Int(point.x / max(1, geometry.size.width) * 5)))
                        switch slot {
                        case 0: cinema.recenterHead()
                        case 1: cinema.toggleImmersive()
                        case 2: cinema.toggleEyeOrder()
                        case 3: cinema.adjustConvergence(-1)
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
        .overlay {
            if cinema.libraryVisible {
                GeometryReader { geometry in
                    VRWorkspaceView(items: cinema.panelItems, page: cinema.libraryPage,
                        viewport: geometry.size, title: cinema.toolsSelected ? "CONTROLES" : "BIBLIOTECA", onSelect: cinema.selectLibrary,
                        onPage: cinema.changeLibraryPage,
                        onClose: { cinema.libraryVisible = false })
                    if cinema.panelItems.isEmpty {
                        Text("Importe um vídeo por Arquivos ou Fotos para iniciar a biblioteca.")
                            .font(.system(size: 11)).foregroundStyle(.white)
                            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .photosPicker(isPresented: rightEye ? .constant(false) : $pickingPhotoMovie,
                      selection: rightEye ? .constant(nil) : $pickedMovie,
                      matching: .videos)
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

    private func headerAction(_ slot: Int) {
        switch slot {
        case 0:
            cinema.toolsSelected = true
            cinema.libraryPage = 0
            cinema.libraryVisible = true
        case 1:
            cinema.toolsSelected = false
            cinema.libraryPage = 0
            cinema.libraryVisible = true
        case 2: cinema.toggleMenu()
        case 3: cinema.toggleSeatSelection()
        default: onExit()
        }
    }

    private func handPoint(size: CGSize) -> CGPoint {
        let raw = runtime.hand.point
        // Cinema skips CGImage generation for performance, so use ARKit's
        // native image resolution to preserve the correct fingertip crop.
        let iw = runtime.camera?.imageResolution.width ??
                 CGFloat(runtime.cameraImage?.width ?? 0)
        let ih = runtime.camera?.imageResolution.height ??
                 CGFloat(runtime.cameraImage?.height ?? 0)
        guard iw > 0, ih > 0 else {
            return CGPoint(x: raw.x * size.width, y: raw.y * size.height)
        }
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

