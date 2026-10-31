import XCTest
import MetalKit
import simd
@testable import VROS

@MainActor
final class SpatialMetalTests: XCTestCase {
    private func renderer() throws -> (MTLDevice, SpatialUIRenderer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal indisponível; executar esta suíte em destino com GPU")
        }
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: VRRenderer.self))
        let renderer = try SpatialUIRenderer(device: device, library: library, pixelFormat: .bgra8Unorm)
        XCTAssertEqual(MemoryLayout<SpatialUIRenderer.Vertex>.stride, 48)
        XCTAssertEqual(MemoryLayout<SpatialUIRenderer.Vertex>.offset(of: \.uv), 32)
        return (device, renderer)
    }

    func testActualSpatialPanelHasDifferentEyeProjectionsAndRoundedBounds() throws {
        let (device, renderer) = try renderer()
        let window = SpatialWindow(id: "panel", position: SIMD3(0, 1.65, -2),
                                   size: SIMD2(1, 0.8), cornerRadius: 0.1, title: "")
        let frame = SpatialRenderFrame(windows: [window], focusedElementID: nil, grabbedWindowID: nil,
                                       pointer: hiddenPointer(), time: 0)
        renderer.prepare(frame)
        let left = try render(renderer, device: device, eye: .left)
        let right = try render(renderer, device: device, eye: .right)
        func centroid(_ bytes: [UInt8]) -> Float {
            var sum: Float = 0
            var count: Float = 0
            for y in 0..<256 {
                for x in 0..<256 where bytes[(y * 256 + x) * 4] > 4 {
                    sum += Float(x); count += 1
                }
            }
            XCTAssertGreaterThan(count, 100)
            return sum / max(count, 1)
        }
        // A near central object moves right in the left eye and left in the right eye.
        XCTAssertGreaterThan(centroid(left) - centroid(right), 2)
        XCTAssertGreaterThan(left[(128 * 256 + 128) * 4], 4, "Real atlas solid texel must paint the panel")
        XCTAssertEqual(left[(30 * 256 + 30) * 4], 0, "Empty space stays empty")
        // At y=103 the rounded upper-left corner is outside the left-eye panel polygon.
        XCTAssertEqual(left[(103 * 256 + 98) * 4], 0)
    }

    func testActualAtlasRendersLatinTextAndSystemSymbolInWorldSpace() throws {
        let (device, renderer) = try renderer()
        let elements = [
            SpatialElement(id: "text", windowID: "panel", center: SIMD2(0.15, 0),
                           size: SIMD2(0.55, 0.22), title: "VR-OS", style: .label),
            SpatialElement(id: "icon", windowID: "panel", center: SIMD2(-0.3, 0),
                           size: SIMD2(0.28, 0.30), title: "Início", symbol: "house.fill", style: .appIcon)
        ]
        let window = SpatialWindow(id: "panel", position: SIMD3(0, 1.65, -1.7),
                                   size: SIMD2(1.2, 0.6), title: "", elements: elements)
        renderer.prepare(SpatialRenderFrame(windows: [window], focusedElementID: "icon", grabbedWindowID: nil,
                                            pointer: hiddenPointer(), time: 1))
        let bytes = try render(renderer, device: device, eye: .left)
        var bright = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[index] > 140 && bytes[index + 1] > 140 && bytes[index + 2] > 140 { bright += 1 }
        }
        XCTAssertGreaterThan(bright, 8, "Text/SF Symbol atlas must render actual bright glyph pixels")
    }

    func testHomeEnvironmentIsBoundedAndCoversEveryHorizontalDirection() {
        let vertices = HomeEnvironment.vertices()
        XCTAssertGreaterThan(vertices.count, 1000)
        XCTAssertLessThan(vertices.count, 40000)
        XCTAssertEqual(vertices.count % 3, 0)
        for point in vertices.map(\.position) {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
        }
        XCTAssertTrue(vertices.contains { $0.position.x > 15 })
        XCTAssertTrue(vertices.contains { $0.position.x < -15 })
        XCTAssertTrue(vertices.contains { $0.position.z > 15 })
        XCTAssertTrue(vertices.contains { $0.position.z < -15 })
        XCTAssertTrue(vertices.contains { $0.position.y > 20 })
    }

    private func hiddenPointer() -> SpatialPointerVisual {
        SpatialPointerVisual(ray: SpatialRay(origin: .zero, direction: SIMD3(0, 0, -1)),
                             end: .zero, isLaser: false, isHit: false, dwellProgress: 0, selectionPulse: 0)
    }

    private func render(_ renderer: SpatialUIRenderer, device: MTLDevice,
                        eye: StereoCamera.Eye) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                   width: 256, height: 256, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let color = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                        width: 256, height: 256, mipmapped: false)
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = .renderTarget
        let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        let projection = StereoCamera.projection(verticalFOVDegrees: 90, aspect: 1, centerX: 0.5)
        let view = StereoCamera.viewMatrix(eye, orientation: simd_quatf(real: 1, imag: .zero), ipdMeters: 0.064)
        renderer.encode(encoder: encoder, viewProjection: projection * view)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, "\(String(describing: command.error))")
        var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
        bytes.withUnsafeMutableBytes { storage in
            color.getBytes(storage.baseAddress!, bytesPerRow: 256 * 4,
                           from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
        }
        return bytes
    }
}
