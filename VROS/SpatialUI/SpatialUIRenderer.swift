import MetalKit
import UIKit
import simd

/// World-space geometry, not a screen overlay. Its pose and eye projection are provided
/// by the same camera pipeline as the environment. The atlas is immutable after init.
@MainActor
final class SpatialUIRenderer {
    struct Vertex {
        var position: SIMD4<Float>
        var color: SIMD4<Float>
        var uv: SIMD2<Float>
        var padding: SIMD2<Float> = .zero
    }
    private struct Camera { var viewProjection: simd_float4x4 }
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let atlas: SpatialGlyphAtlas
    private var buffers: [MTLBuffer?] = [nil, nil, nil]
    private var capacities = [0, 0, 0]
    private var bufferIndex = 0
    private var vertices: [Vertex] = []
    private var focusLevels: [String: Float] = [:]
    private var previousTime: TimeInterval?
    private var feedbackStep: Float = 0.2
    private(set) var vertexCount = 0

    init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        atlas = try SpatialGlyphAtlas(device: device)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Spatial windows, glyphs and ray"
        descriptor.vertexFunction = library.makeFunction(name: "spatialVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "spatialFragment")
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw VRRenderer.RenderError.unavailable("profundidade da interface espacial")
        }
        depthState = state
        vertices.reserveCapacity(24000)
    }

    /// Three reusable buffers are safe with the renderer's maximum of two frames in flight.
    /// Text strings never allocate textures: individual glyphs and symbols share one atlas.
    func prepare(_ frame: SpatialRenderFrame) {
        let dt = Float(min(max(frame.time - (previousTime ?? frame.time - 1 / 60), 0), 0.05))
        previousTime = frame.time
        feedbackStep = 1 - exp(-dt / 0.075)
        if focusLevels.count > 256 { focusLevels.removeAll(keepingCapacity: true) }
        vertices.removeAll(keepingCapacity: true)
        let windows = frame.windows.filter { $0.isOpen && $0.opacity > 0.002 }.sorted {
            let a = simd_length_squared($0.position - StereoCamera.headPosition)
            let b = simd_length_squared($1.position - StereoCamera.headPosition)
            return a == b ? $0.id < $1.id : a > b
        }
        for window in windows { append(window: window, frame: frame) }
        appendPointer(frame.pointer)
        vertexCount = vertices.count
        bufferIndex = (bufferIndex + 1) % buffers.count
        let bytes = vertexCount * MemoryLayout<Vertex>.stride
        if bytes > capacities[bufferIndex] {
            let capacity = max(bytes * 2, 65536)
            buffers[bufferIndex] = device.makeBuffer(length: capacity, options: .storageModeShared)
            capacities[bufferIndex] = buffers[bufferIndex] == nil ? 0 : capacity
            buffers[bufferIndex]?.label = "Reusable spatial vertices \(bufferIndex)"
        }
        guard bytes > 0, let buffer = buffers[bufferIndex] else { vertexCount = 0; return }
        vertices.withUnsafeBytes { source in
            buffer.contents().copyMemory(from: source.baseAddress!, byteCount: bytes)
        }
    }

    func encode(encoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4) {
        guard vertexCount > 0, let buffer = buffers[bufferIndex] else { return }
        var camera = Camera(viewProjection: viewProjection)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&camera, length: MemoryLayout<Camera>.stride, index: 1)
        encoder.setFragmentTexture(atlas.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }

    private func append(window: SpatialWindow, frame: SpatialRenderFrame) {
        let alpha = min(max(window.opacity, 0), 1)
        let grabbed = frame.grabbedWindowID == window.id
        let border = grabbed ? SIMD4<Float>(0.42, 0.72, 1, alpha * 0.95)
            : SIMD4<Float>(0.30, 0.40, 0.54, alpha * 0.60)
        // A small layered offset gives a restrained soft shadow without a blur pass.
        rounded(center: SIMD2(0.015, -0.025), size: window.size + SIMD2(repeating: 0.025),
                radius: window.cornerRadius + 0.012, z: -0.006,
                color: SIMD4(0, 0, 0, alpha * 0.12), window: window)
        rounded(center: .zero, size: window.size, radius: window.cornerRadius, z: 0,
                color: border, window: window)
        rounded(center: .zero, size: window.size - SIMD2(repeating: 0.006),
                radius: max(0, window.cornerRadius - 0.003), z: 0.0005,
                color: SIMD4(0.028, 0.038, 0.055, alpha * 0.94), window: window)
        if !window.title.isEmpty {
            text(window.title, center: SIMD2(0, window.size.y / 2 - 0.105),
                 maxSize: SIMD2(max(0.1, window.size.x - 0.35), 0.09), height: 0.062,
                 color: SIMD4(0.93, 0.96, 1, alpha), z: 0.010, window: window)
        }
        for element in window.elements {
            let focused = frame.focusedElementID == element.id
            let target: Float = element.selected || focused ? 1 : 0
            let amount = (focusLevels[element.id] ?? 0) + (target - (focusLevels[element.id] ?? 0)) * feedbackStep
            focusLevels[element.id] = amount
            if element.style == .button || element.style == .appIcon {
                let pulse = focused ? frame.pointer.selectionPulse : 0
                let idle = SIMD4<Float>(0.075, 0.095, 0.13, alpha * 0.94)
                let highlighted = SIMD4<Float>(0.15 + pulse * 0.12, 0.31 + pulse * 0.14, 0.48 + pulse * 0.15, alpha * 0.96)
                let base = idle + (highlighted - idle) * amount
                let outline = SIMD4<Float>(0.18, 0.23, 0.30, alpha * 0.65)
                let activeOutline = SIMD4<Float>(0.49, 0.72, 0.95, alpha * 0.85)
                rounded(center: element.center, size: element.size, radius: element.cornerRadius,
                        z: 0.008, color: outline + (activeOutline - outline) * amount,
                        window: window)
                rounded(center: element.center, size: element.size - SIMD2(repeating: 0.005),
                        radius: max(0, element.cornerRadius - 0.0025), z: 0.0085,
                        color: base, window: window)
            }
            let tint: SIMD4<Float> = element.style == .caption
                ? SIMD4(0.63, 0.70, 0.81, alpha) : SIMD4(0.94, 0.97, 1, alpha)
            if element.style == .appIcon, let symbol = element.symbol {
                let side = min(min(element.size.y * 0.45, element.size.x * 0.48), 0.13)
                icon(symbol, center: element.center + SIMD2(0, element.size.y * 0.13),
                     side: side, color: tint, z: 0.011, window: window)
                text(element.title, center: element.center - SIMD2(0, element.size.y * 0.29),
                     maxSize: SIMD2(element.size.x - 0.018, element.size.y * 0.25), height: 0.044,
                     color: tint, z: 0.011, window: window)
            } else if let symbol = element.symbol, element.style == .button {
                if element.size.x < 0.25 {
                    icon(symbol, center: element.center, side: min(element.size.x, element.size.y) * 0.48,
                         color: tint, z: 0.011, window: window)
                } else {
                    let side = min(element.size.y * 0.45, 0.065)
                    icon(symbol, center: element.center - SIMD2(element.size.x * 0.38, 0), side: side,
                         color: tint, z: 0.011, window: window)
                    text(element.title, center: element.center + SIMD2(side * 0.38, 0),
                         maxSize: SIMD2(element.size.x - side * 2.0 - 0.025, element.size.y * 0.75),
                         height: 0.048, color: tint, z: 0.011, window: window)
                }
            } else if let symbol = element.symbol, element.title.isEmpty {
                icon(symbol, center: element.center, side: min(element.size.x, element.size.y) * 0.78,
                     color: tint, z: 0.011, window: window)
            } else {
                text(element.title, center: element.center, maxSize: element.size - SIMD2(repeating: 0.012),
                     height: element.style == .label ? 0.070 : element.style == .caption ? 0.041 : 0.049,
                     color: tint, z: 0.011, window: window)
            }
        }
    }

    private func rounded(center: SIMD2<Float>, size: SIMD2<Float>, radius: Float,
                         z: Float, color: SIMD4<Float>, window: SpatialWindow) {
        guard size.x > 0, size.y > 0 else { return }
        let r = min(max(radius, 0), min(size.x, size.y) * 0.5)
        let half = size * 0.5
        let c = world(SIMD3(center.x, center.y, z), window)
        var previous: SIMD3<Float>?
        var first: SIMD3<Float>?
        for corner in 0..<4 {
            let sign: SIMD2<Float>
            switch corner {
            case 0: sign = SIMD2(1, 1)
            case 1: sign = SIMD2(-1, 1)
            case 2: sign = SIMD2(-1, -1)
            default: sign = SIMD2(1, -1)
            }
            let arcCenter = center + sign * (half - SIMD2(repeating: r))
            for step in 0...16 {
                let angle = Float(corner) * .pi / 2 + Float(step) * .pi / 32
                let point = world(SIMD3(arcCenter.x + cos(angle) * r,
                                        arcCenter.y + sin(angle) * r, z), window)
                if let last = previous { triangle(c, last, point, color: color) }
                else { first = point }
                previous = point
            }
        }
        if let last = previous, let first { triangle(c, last, first, color: color) }
    }

    private func text(_ string: String, center: SIMD2<Float>, maxSize: SIMD2<Float>, height: Float,
                      color: SIMD4<Float>, z: Float, window: SpatialWindow) {
        guard maxSize.x > 0, maxSize.y > 0 else { return }
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        var fontHeight = min(height, maxSize.y / Float(max(1, lines.count)) * 0.9)
        let widest = lines.map { $0.reduce(Float(0)) { $0 + atlas.glyph($1).advance } }.max() ?? 0
        if widest * fontHeight > maxSize.x { fontHeight = maxSize.x / max(widest, 0.001) }
        for (lineIndex, line) in lines.enumerated() {
            let width = line.reduce(Float(0)) { $0 + atlas.glyph($1).advance } * fontHeight
            var x = center.x - width * 0.5
            let y = center.y + (Float(lines.count - 1) * 0.5 - Float(lineIndex)) * fontHeight
            for character in line {
                let glyph = atlas.glyph(character)
                let side = fontHeight * SpatialGlyphAtlas.cellToFontRatio
                let glyphCenter = SIMD2(x + side * 0.5, y)
                texturedQuad(center: glyphCenter, size: SIMD2(repeating: side), z: z,
                             uv: glyph.uv, color: color, window: window)
                x += glyph.advance * fontHeight
            }
        }
    }

    private func icon(_ symbol: String, center: SIMD2<Float>, side: Float,
                      color: SIMD4<Float>, z: Float, window: SpatialWindow) {
        texturedQuad(center: center, size: SIMD2(repeating: side), z: z,
                     uv: atlas.symbol(symbol), color: color, window: window)
    }

    private func texturedQuad(center: SIMD2<Float>, size: SIMD2<Float>, z: Float,
                              uv: SIMD4<Float>, color: SIMD4<Float>, window: SpatialWindow) {
        let half = size * 0.5
        let a = world(SIMD3(center.x - half.x, center.y - half.y, z), window)
        let b = world(SIMD3(center.x + half.x, center.y - half.y, z), window)
        let c = world(SIMD3(center.x + half.x, center.y + half.y, z), window)
        let d = world(SIMD3(center.x - half.x, center.y + half.y, z), window)
        quad(a, b, c, d, color: color, uv: uv)
    }

    private func appendPointer(_ pointer: SpatialPointerVisual) {
        let ray = pointer.ray
        let distance = simd_distance(ray.origin, pointer.end)
        guard distance.isFinite, distance > 0.01 else { return }
        let direction = simd_normalize(ray.direction)
        let candidate = abs(direction.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(direction, candidate))
        let up = simd_normalize(simd_cross(right, direction))
        // Pull back a few millimetres so the indicator never z-fights with its hit plane.
        let end = pointer.end - direction * 0.012
        if pointer.isLaser {
            let glow = right * 0.004
            quad(ray.origin - glow, ray.origin + glow, end + glow, end - glow,
                 color: SIMD4(0.8, 0.9, 1, 0.12))
            let width = right * 0.0012
            quad(ray.origin - width, ray.origin + width, end + width, end - width,
                 color: SIMD4(1, 1, 1, 0.85))
        }
        let radius = max(0.006, distance * (pointer.isLaser ? 0.003 : 0.004))
        let pulse = max(0, min(pointer.selectionPulse, 1))
        let color = pointer.isHit ? SIMD4<Float>(0.80 + pulse * 0.2, 0.91 + pulse * 0.09, 1, 0.95)
            : SIMD4<Float>(0.86, 0.90, 0.96, 0.65)
        ring(center: end, right: right, up: up, radius: radius, width: radius * 0.26,
             fraction: 1, color: color)
        if pointer.isLaser {
            disc(center: end, right: right, up: up, radius: radius * 0.38, color: SIMD4(1, 1, 1, 0.95))
        }
        if pointer.dwellProgress > 0 {
            ring(center: end, right: right, up: up, radius: radius * 1.8, width: radius * 0.3,
                 fraction: min(pointer.dwellProgress, 1), color: SIMD4(0.55, 0.80, 1, 0.98))
        }
    }

    private func disc(center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
                      radius: Float, color: SIMD4<Float>) {
        for step in 0..<32 {
            let a = Float(step) * 2 * .pi / 32
            let b = Float(step + 1) * 2 * .pi / 32
            triangle(center, center + (right * cos(a) + up * sin(a)) * radius,
                     center + (right * cos(b) + up * sin(b)) * radius, color: color)
        }
    }

    private func ring(center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
                      radius: Float, width: Float, fraction: Float, color: SIMD4<Float>) {
        let segments = max(1, Int(ceil(fraction * 48)))
        for step in 0..<segments {
            let a = Float(step) / Float(segments) * fraction * 2 * .pi + .pi / 2
            let b = Float(step + 1) / Float(segments) * fraction * 2 * .pi + .pi / 2
            let first = right * cos(a) + up * sin(a)
            let second = right * cos(b) + up * sin(b)
            quad(center + first * (radius - width * 0.5), center + first * (radius + width * 0.5),
                 center + second * (radius + width * 0.5), center + second * (radius - width * 0.5), color: color)
        }
    }

    private func world(_ local: SIMD3<Float>, _ window: SpatialWindow) -> SIMD3<Float> {
        SpatialGeometry.worldPoint(local: local, window: window)
    }
    private func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, color: SIMD4<Float>) {
        append(a, color, atlas.whiteUV)
        append(b, color, atlas.whiteUV)
        append(c, color, atlas.whiteUV)
    }
    private func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                      color: SIMD4<Float>, uv: SIMD4<Float>? = nil) {
        let bounds = uv ?? SIMD4(atlas.whiteUV.x, atlas.whiteUV.y, atlas.whiteUV.x, atlas.whiteUV.y)
        append(a, color, SIMD2(bounds.x, bounds.w))
        append(b, color, SIMD2(bounds.z, bounds.w))
        append(c, color, SIMD2(bounds.z, bounds.y))
        append(a, color, SIMD2(bounds.x, bounds.w))
        append(c, color, SIMD2(bounds.z, bounds.y))
        append(d, color, SIMD2(bounds.x, bounds.y))
    }
    private func append(_ position: SIMD3<Float>, _ color: SIMD4<Float>, _ uv: SIMD2<Float>) {
        vertices.append(Vertex(position: SIMD4(position, 1), color: color, uv: uv))
    }
}

/// Fixed Latin glyph/SF Symbol atlas: clock, battery and FPS strings reuse glyphs forever.
/// No cache eviction, string rasterization or texture mutation occurs during rendering.
@MainActor
private final class SpatialGlyphAtlas {
    struct Glyph { var uv: SIMD4<Float>; var advance: Float }
    static let cellToFontRatio: Float = 128 / 80
    let texture: MTLTexture
    let whiteUV = SIMD2<Float>(1.5 / 2048, 1.5 / 2048)
    private var glyphs: [Character: Glyph] = [:]
    private var symbols: [String: SIMD4<Float>] = [:]

    init(device: MTLDevice) throws {
        let side = 2048
        let cell = 128
        let font = UIFont.systemFont(ofSize: 80, weight: .medium)
        var characters: [Character] = (32...126).compactMap { UnicodeScalar($0).map { Character(String($0)) } }
        characters += (160...255).compactMap { UnicodeScalar($0).map { Character(String($0)) } }
        characters += Array("—–•…→←↑↓✓−")
        let names = Array(Set(AppDestination.allCases.map(\.symbol) + [
            "square", "xmark", "arrow.uturn.backward", "arrow.counterclockwise", "gamecontroller.fill",
            "slider.horizontal.3", "arrow.up", "arrow.down", "minus", "plus", "ellipsis", "viewfinder",
            "power", "battery.100", "clock", "chevron.left", "chevron.right", "arrow.left", "arrow.right",
            "arrow.up.left.and.arrow.down.right", "rectangle.3.group", "checkmark", "arrow.clockwise",
            "scope", "eye.fill", "chevron.up", "chevron.down", "minus.magnifyingglass", "plus.magnifyingglass",
            "rectangle.portrait.and.arrow.right", "cursorarrow.rays"
        ])).sorted()
        var glyphMap: [Character: Glyph] = [:]
        var symbolMap: [String: SIMD4<Float>] = [:]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            var index = 1
            for character in characters {
                let x = (index % 16) * cell
                let y = (index / 16) * cell
                let string = String(character) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                // Fixed cell, natural glyph advance. Baselines are shared across the atlas.
                string.draw(at: CGPoint(x: x, y: y + 15), withAttributes: attributes)
                let advance = Float(string.size(withAttributes: attributes).width) / 80
                glyphMap[character] = Glyph(uv: SIMD4(Float(x) / 2048, Float(y) / 2048,
                                                    Float(x + cell) / 2048, Float(y + cell) / 2048), advance: advance)
                index += 1
            }
            for name in names {
                let x = (index % 16) * cell
                let y = (index / 16) * cell
                let configuration = UIImage.SymbolConfiguration(pointSize: 88, weight: .regular)
                if let symbol = (UIImage(systemName: name, withConfiguration: configuration)
                                 ?? UIImage(systemName: "square", withConfiguration: configuration))?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let scale = min(100 / symbol.size.width, 100 / symbol.size.height)
                    let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                    symbol.draw(in: CGRect(x: CGFloat(x) + (128 - size.width) / 2,
                                           y: CGFloat(y) + (128 - size.height) / 2,
                                           width: size.width, height: size.height))
                }
                symbolMap[name] = SIMD4(Float(x) / 2048, Float(y) / 2048,
                                       Float(x + cell) / 2048, Float(y + cell) / 2048)
                index += 1
            }
            assert(index <= 256, "Fixed atlas must remain bounded")
        }
        guard let cgImage = image.cgImage else { throw VRRenderer.RenderError.unavailable("atlas de texto") }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let didDraw = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side,
                                                                   height: side, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard didDraw, let texture = device.makeTexture(descriptor: descriptor) else {
            throw VRRenderer.RenderError.unavailable("textura do atlas")
        }
        bytes.withUnsafeBytes { pointer in
            texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                            withBytes: pointer.baseAddress!, bytesPerRow: side * 4)
        }
        texture.label = "Immutable Latin glyphs and SF Symbols"
        self.texture = texture
        glyphs = glyphMap
        symbols = symbolMap
    }
    func glyph(_ character: Character) -> Glyph { glyphs[character] ?? glyphs["?"]! }
    func symbol(_ name: String) -> SIMD4<Float> { symbols[name] ?? symbols["square"]! }
}
