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
        let queue = try XCTUnwrap(device.makeCommandQueue())
        func solidTexture(bgra: [UInt8]) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let pixels = Array(repeating: bgra, count: 16).flatMap { $0 }
            pixels.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                                withBytes: bytes.baseAddress!, bytesPerRow: 16)
            }
            return texture
        }
        let left = try solidTexture(bgra: [0, 0, 255, 255])
        let right = try solidTexture(bgra: [255, 0, 0, 255])
        var profile = VRLensProfile.genericVRBox
        profile.distortionStrength = 0
        profile.leftScale = 1
        profile.rightScale = 1
        profile.leftCenterX = 0.5
        profile.rightCenterX = 0.5
        // Odd width exposes both an off-by-one split and any unpainted center column.
        let width = 65
        let height = 32
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
                        drawableSize: CGSize(width: width, height: height), profile: profile)
        renderer.encode(encoder: encoder, eye: .right, texture: right,
                        drawableSize: CGSize(width: width, height: height), profile: profile)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, "\(String(describing: command.error))")
        var result = [UInt8](repeating: 0, count: width * height * 4)
        result.withUnsafeMutableBytes { bytes in
            destination.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
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

    func testHostedAppDeclaresOnlyTheCalibratedLandscapeOrientation() {
        let orientations = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String]
        XCTAssertEqual(orientations, ["UIInterfaceOrientationLandscapeRight"])
    }
}
