import XCTest
import MetalKit
@testable import VROS

@MainActor
final class MetalRenderingTests: XCTestCase {
    private func deviceAndLibrary() throws -> (MTLDevice, MTLLibrary) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal indisponível neste destino; executar em simulador com Metal ou iPhone físico")
        }
        // This is the app's bundle, not the XCTest bundle: Xcode compiles its .metal files here.
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: VRRenderer.self))
        return (device, library)
    }

    func testRealSceneAndLensPipelinesCompileAndVertexLayoutMatchesMetal() throws {
        let (device, library) = try deviceAndLibrary()
        XCTAssertEqual(MemoryLayout<SceneVertex>.size, 32)
        XCTAssertEqual(MemoryLayout<SceneVertex>.stride, 32)
        XCTAssertEqual(MemoryLayout<SceneVertex>.offset(of: \.position), 0)
        XCTAssertEqual(MemoryLayout<SceneVertex>.offset(of: \.color), 16)
        let scene = MTLRenderPipelineDescriptor()
        scene.vertexFunction = try XCTUnwrap(library.makeFunction(name: "sceneVertex"))
        scene.fragmentFunction = try XCTUnwrap(library.makeFunction(name: "sceneFragment"))
        scene.colorAttachments[0].pixelFormat = .bgra8Unorm
        scene.depthAttachmentPixelFormat = .depth32Float
        _ = try device.makeRenderPipelineState(descriptor: scene)
        _ = try LensDistortionRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
    }

    func testOffscreenCompositorPlacesLeftAndRightIntoPhysicalHalvesWithoutGap() throws {
        let (device, library) = try deviceAndLibrary()
        let renderer = try LensDistortionRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        let left = try texture(device: device, width: 4, height: 4,
                               pixels: Array(repeating: [UInt8](arrayLiteral: 0, 0, 255, 255), count: 16).flatMap { $0 })
        let right = try texture(device: device, width: 4, height: 4,
                                pixels: Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 16).flatMap { $0 })
        var profile = VRLensProfile.genericVRBox
        profile.distortionStrength = 0
        profile.leftScale = 1
        profile.rightScale = 1
        profile.leftCenterX = 0.5
        profile.rightCenterX = 0.5
        // Odd width exposes both an off-by-one split and any unpainted center column.
        let width = 65
        let height = 32
        let result = try composite(renderer: renderer, device: device, left: left, right: right,
                                   width: width, height: height, profile: profile)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let expected: [UInt8] = x < width / 2 ? [0, 0, 255, 255] : [255, 0, 0, 255]
                guard Array(result[index..<(index + 4)]) == expected else {
                    XCTFail("Composição SBS incorreta no pixel (\(x),\(y)): \(Array(result[index..<(index + 4)]))")
                    return
                }
            }
        }
    }

    func testNonzeroDistortionKeepsAsymmetricCentersAndEyeSources() throws {
        let (device, library) = try deviceAndLibrary()
        let renderer = try LensDistortionRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        let sourceSize = 64
        func coordinateTexture(eyeMarker: UInt8) throws -> MTLTexture {
            var pixels: [UInt8] = []
            for y in 0..<sourceSize {
                for x in 0..<sourceSize {
                    // B/G encode source Y/X; R identifies the eye even under interpolation.
                    pixels += [UInt8((255 * (Float(y) + 0.5) / Float(sourceSize)).rounded()),
                               UInt8((255 * (Float(x) + 0.5) / Float(sourceSize)).rounded()), eyeMarker, 255]
                }
            }
            return try texture(device: device, width: sourceSize, height: sourceSize, pixels: pixels)
        }
        let left = try coordinateTexture(eyeMarker: 220)
        let right = try coordinateTexture(eyeMarker: 40)
        let width = 83
        let height = 41
        var profile = VRLensProfile.genericVRBox
        // Pick centers at pixel centers, allowing an exact fixed-point check after rasterization.
        profile.leftCenterX = 14.5 / 41
        profile.rightCenterX = 26.5 / 42
        profile.leftScale = 0.82
        profile.rightScale = 1.12
        profile.distortionK1 = 0.45
        profile.distortionK2 = 0.2
        profile.distortionStrength = 0.9
        let pixels = try composite(renderer: renderer, device: device, left: left, right: right,
                                   width: width, height: height, profile: profile)
        for eye in StereoCamera.Eye.allCases {
            let range = StereoCamera.horizontalRange(eye, drawableWidth: width)
            let center = eye == .left ? profile.leftCenterX : profile.rightCenterX
            let scale = eye == .left ? profile.leftScale : profile.rightScale
            let marker: UInt8 = eye == .left ? 220 : 40
            let centerPixelX = range.lowerBound + (eye == .left ? 14 : 26)
            let centerIndex = ((height / 2) * width + centerPixelX) * 4
            XCTAssertEqual(Float(pixels[centerIndex]), 128, accuracy: 2)
            XCTAssertEqual(Float(pixels[centerIndex + 1]), center * 255, accuracy: 2)
            XCTAssertEqual(pixels[centerIndex + 2], marker)
            var maskedPixels = 0
            var visiblePixels = 0
            for y in 0..<height {
                for x in range {
                    let u = (Float(x - range.lowerBound) + 0.5) / Float(range.count)
                    let v = (Float(y) + 0.5) / Float(height)
                    let dx = u - center
                    let dy = v - 0.5
                    let radialX = 2 * dx * Float(range.count) / Float(height)
                    let radialY = 2 * dy
                    let radius2 = radialX * radialX + radialY * radialY
                    let factor = 1 + profile.distortionStrength *
                        (profile.distortionK1 * radius2 + profile.distortionK2 * radius2 * radius2)
                    let sourceU = center + dx * factor / scale
                    let sourceV = 0.5 + dy * factor / scale
                    let index = (y * width + x) * 4
                    if sourceU < 0 || sourceU > 1 || sourceV < 0 || sourceV > 1 {
                        maskedPixels += 1
                        guard Array(pixels[index..<(index + 4)]) == [0, 0, 0, 255] else {
                            XCTFail("Amostra fora da textura deve ficar preta em (\(x),\(y))")
                            return
                        }
                    } else {
                        visiblePixels += 1
                        // Linear texture sampling clamps to edge texel centers, not UV 0 and 1.
                        let lower = 0.5 / Float(sourceSize)
                        let upper = 1 - lower
                        let expectedX = 255 * min(max(sourceU, lower), upper)
                        let expectedY = 255 * min(max(sourceV, lower), upper)
                        guard pixels[index + 2] == marker,
                              abs(Float(pixels[index]) - expectedY) <= 2,
                              abs(Float(pixels[index + 1]) - expectedX) <= 2,
                              pixels[index + 3] == 255 else {
                            XCTFail("Distorção, eixo UV ou fonte de olho incorreto em (\(x),\(y))")
                            return
                        }
                    }
                }
            }
            XCTAssertGreaterThan(maskedPixels, 10)
            XCTAssertGreaterThan(visiblePixels, 10)
        }
    }

    private func texture(device: MTLDevice, width: Int, height: Int,
                         pixels: [UInt8]) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private func composite(renderer: LensDistortionRenderer, device: MTLDevice,
                           left: MTLTexture, right: MTLTexture, width: Int, height: Int,
                           profile: VRLensProfile) throws -> [UInt8] {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let destination = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Green would remain visible if either viewport left a gap.
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 0, 1)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        renderer.encode(encoder: encoder, eye: .left, texture: left,
                        drawableSize: CGSize(width: CGFloat(width), height: CGFloat(height)), profile: profile)
        renderer.encode(encoder: encoder, eye: .right, texture: right,
                        drawableSize: CGSize(width: CGFloat(width), height: CGFloat(height)), profile: profile)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, "\(String(describing: command.error))")
        var result = [UInt8](repeating: 0, count: width * height * 4)
        result.withUnsafeMutableBytes { bytes in
            destination.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return result
    }

    func testHostedAppDeclaresOnlyTheCalibratedLandscapeOrientation() {
        let orientations = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String]
        XCTAssertEqual(orientations, ["UIInterfaceOrientationLandscapeRight"])
    }
}
