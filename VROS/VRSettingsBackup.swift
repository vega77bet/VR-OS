import SwiftUI
import UniformTypeIdentifiers

struct VRExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Explicit preference schema: no cookies, browsing history, media or paths.
struct VRSettingsBackup: Codable {
    var version = 1
    var numbers: [String: Double]
    var flags: [String: Bool]

    static let ranges: [String: ClosedRange<Double>] = [
        "profile": 0...2, "scale": 0.75...1.4, "spacing": -0.075...0.12,
        "vertical": -0.16...0.16, "cameraZoom": 0.8...1.3, "curvature": 0...1,
        "theme": 0...3, "webZoom": 0.65...1.55, "cinemaFOV": 55...115,
        "cursorSize": 0.7...1.6, "pinch": 0...1, "opacity": 0.42...1,
        "depth": 0.75...3.5, "scenery": 0...4
    ]
    static let flagKeys: Set<String> = [
        "cameraUltra", "fullFrame", "invertUltra", "cinemaInvert", "immersive",
        "swapEyes", "autoControls", "skeleton", "cursor", "reduceMotion", "largeText", "hud"
    ]

    @MainActor
    init(settings s: VRSettingsSession, scenery: Int) {
        numbers = [
            "profile": Double(s.lens.profile.rawValue), "scale": Double(s.lens.scale),
            "spacing": Double(s.lens.spacing), "vertical": Double(s.lens.verticalOffset),
            "cameraZoom": Double(s.lens.cameraZoom), "curvature": Double(s.lens.curvature),
            "theme": Double(s.themeIndex), "webZoom": Double(s.webZoom), "cinemaFOV": Double(s.cinemaFOV),
            "cursorSize": Double(s.cursorSize), "pinch": Double(s.pinchSensitivity),
            "opacity": Double(s.windowOpacity), "depth": Double(s.defaultDepth), "scenery": Double(scenery)
        ]
        flags = [
            "cameraUltra": s.cameraUltra, "fullFrame": s.fullCameraFrame,
            "invertUltra": s.invertUltraMotion, "cinemaInvert": s.cinemaInvert,
            "immersive": s.cinemaImmersive, "swapEyes": s.cinemaSwapEyes,
            "autoControls": s.cinemaAutoControls, "skeleton": s.showSkeleton,
            "cursor": s.showCursor, "reduceMotion": s.reduceMotion,
            "largeText": s.largeText, "hud": s.showHUD
        ]
    }

    func validate() throws {
        guard version == 1, Set(numbers.keys) == Set(Self.ranges.keys),
              Set(flags.keys) == Self.flagKeys else { throw BackupError.invalid }
        for (key, range) in Self.ranges {
            guard let value = numbers[key], value.isFinite, range.contains(value) else { throw BackupError.invalid }
        }
        for key in ["profile", "theme", "scenery"] {
            guard let value = numbers[key], value.rounded() == value else { throw BackupError.invalid }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> VRSettingsBackup {
        guard data.count <= 65_536 else { throw BackupError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    @MainActor
    @discardableResult
    func apply(to s: VRSettingsSession) throws -> Int {
        try validate() // Validate the ENTIRE document before any mutation.
        func n(_ key: String) -> CGFloat { CGFloat(numbers[key]!) }
        func b(_ key: String) -> Bool { flags[key]! }
        var lens = s.lens
        lens.profile = VRLensProfile(rawValue: Int(numbers["profile"]!))!
        lens.scale = n("scale"); lens.spacing = n("spacing"); lens.verticalOffset = n("vertical")
        lens.cameraZoom = n("cameraZoom"); lens.curvature = n("curvature"); s.lens = lens
        s.themeIndex = Int(numbers["theme"]!); s.webZoom = n("webZoom"); s.cinemaFOV = n("cinemaFOV")
        s.cursorSize = n("cursorSize"); s.pinchSensitivity = n("pinch")
        s.windowOpacity = n("opacity"); s.defaultDepth = n("depth")
        s.cameraUltra = b("cameraUltra"); s.fullCameraFrame = b("fullFrame")
        s.invertUltraMotion = b("invertUltra"); s.cinemaInvert = b("cinemaInvert")
        s.cinemaImmersive = b("immersive"); s.cinemaSwapEyes = b("swapEyes")
        s.cinemaAutoControls = b("autoControls"); s.showSkeleton = b("skeleton")
        s.showCursor = b("cursor"); s.reduceMotion = b("reduceMotion")
        s.largeText = b("largeText"); s.showHUD = b("hud")
        s.didRestoreBackup()
        return Int(numbers["scenery"]!)
    }

    enum BackupError: LocalizedError {
        case invalid
        var errorDescription: String? { "Backup incompatível ou inválido. Nenhum ajuste foi alterado." }
    }
}
