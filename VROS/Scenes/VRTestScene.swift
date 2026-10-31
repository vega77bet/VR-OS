import simd

/// Packed identically to the Metal `SceneVertex` (two float4 values).
struct SceneVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
}

/// Static, metre-scale geometry. No cameras, panorama, textures or per-frame rebuilds.
/// The observer starts at (0, 1.65, 0), with front along -Z and gravity along -Y.
struct VRTestScene {
    static func vertices() -> [SceneVertex] {
        var mesh = Builder()
        let blue = SIMD3<Float>(0.20, 0.58, 0.95)
        let amber = SIMD3<Float>(1.0, 0.57, 0.18)
        let teal = SIMD3<Float>(0.12, 0.81, 0.68)

        // Every square is one metre. Small gaps expose the darker base plane.
        mesh.quad(SIMD3(-8, -0.003, 8), SIMD3(8, -0.003, 8),
                  SIMD3(8, -0.003, -8), SIMD3(-8, -0.003, -8), color: SIMD3(0.025, 0.04, 0.065))
        for x in -8..<8 {
            for z in -8..<8 {
                let c: Float = (x + z).isMultiple(of: 2) ? 0.15 : 0.095
                let a = Float(x) + 0.012
                let b = Float(z) + 0.012
                mesh.quad(SIMD3(a, 0, b), SIMD3(a + 0.976, 0, b),
                          SIMD3(a + 0.976, 0, b + 0.976), SIMD3(a, 0, b + 0.976),
                          color: SIMD3(c * 0.72, c * 0.91, c))
            }
        }

        // An enclosed reference volume keeps all rotations visually testable.
        mesh.box(center: SIMD3(0, 2.5, -8.05), size: SIMD3(16.2, 5, 0.1), color: SIMD3(0.075, 0.11, 0.17))
        mesh.box(center: SIMD3(0, 2.5, 8.05), size: SIMD3(16.2, 5, 0.1), color: SIMD3(0.065, 0.085, 0.13))
        mesh.box(center: SIMD3(-8.05, 2.5, 0), size: SIMD3(0.1, 5, 16), color: SIMD3(0.12, 0.10, 0.09))
        mesh.box(center: SIMD3(8.05, 2.5, 0), size: SIMD3(0.1, 5, 16), color: SIMD3(0.07, 0.115, 0.12))
        mesh.box(center: SIMD3(0, 5.05, 0), size: SIMD3(16.2, 0.1, 16.2), color: SIMD3(0.04, 0.055, 0.085))

        // True horizontal references at the neutral eye height; they roll with the view.
        mesh.box(center: SIMD3(0, 1.65, -7.985), size: SIMD3(16, 0.025, 0.015), color: blue)
        mesh.box(center: SIMD3(0, 1.65, 7.985), size: SIMD3(16, 0.025, 0.015), color: blue * 0.65)
        mesh.box(center: SIMD3(-7.985, 1.65, 0), size: SIMD3(0.015, 0.025, 16), color: amber)
        mesh.box(center: SIMD3(7.985, 1.65, 0), size: SIMD3(0.015, 0.025, 16), color: teal)
        for x in stride(from: -6, through: 6, by: 2) {
            mesh.box(center: SIMD3(Float(x), 2.5, -7.97), size: SIMD3(0.018, 5, 0.018), color: blue * 0.28)
        }

        mesh.text("FRONT", center: SIMD3(0, 3.15, -7.95), right: SIMD3(1, 0, 0), pixel: 0.095, color: blue)
        mesh.text("LEFT", center: SIMD3(-7.95, 3.15, 0), right: SIMD3(0, 0, -1), pixel: 0.095, color: amber)
        mesh.text("RIGHT", center: SIMD3(7.95, 3.15, 0), right: SIMD3(0, 0, 1), pixel: 0.095, color: teal)
        mesh.text("BACK", center: SIMD3(0, 3.15, 7.95), right: SIMD3(-1, 0, 0), pixel: 0.095, color: blue * 0.65)

        // Cubes at several distances, supported by pedestals for an obvious scale.
        mesh.box(center: SIMD3(-1.0, 0.45, -2), size: SIMD3(0.55, 0.9, 0.55), color: SIMD3(0.11, 0.15, 0.21))
        mesh.box(center: SIMD3(-1.0, 1.13, -2), size: SIMD3(0.46, 0.46, 0.46), color: amber)
        mesh.box(center: SIMD3(1.35, 0.55, -4), size: SIMD3(0.65, 1.1, 0.65), color: SIMD3(0.11, 0.15, 0.21))
        mesh.box(center: SIMD3(1.35, 1.43, -4), size: SIMD3(0.65, 0.65, 0.65), color: teal)
        mesh.box(center: SIMD3(-2.25, 0.55, -6), size: SIMD3(0.85, 1.1, 0.85), color: SIMD3(0.11, 0.15, 0.21))
        mesh.box(center: SIMD3(-2.25, 1.55, -6), size: SIMD3(0.85, 0.85, 0.85), color: blue)

        // Central near cube and distant reticle give easily compared binocular disparity.
        mesh.box(center: SIMD3(0, 0.7, -1.5), size: SIMD3(0.025, 1.4, 0.025), color: SIMD3(0.33, 0.4, 0.5))
        mesh.box(center: SIMD3(0, 1.5, -1.5), size: SIMD3(0.2, 0.2, 0.2), color: SIMD3(0.96, 0.82, 0.37))
        mesh.box(center: SIMD3(0, 1.65, -6.9), size: SIMD3(0.55, 0.025, 0.025), color: SIMD3(repeating: 0.9))
        mesh.box(center: SIMD3(0, 1.65, -6.9), size: SIMD3(0.025, 0.55, 0.025), color: SIMD3(repeating: 0.9))

        // Upper geometry proves positive pitch reveals the upper world.
        for (index, x) in [Float(-2.2), 0, 2.2].enumerated() {
            let z: Float = -3.5 - Float(index) * 0.6
            mesh.box(center: SIMD3(x, 4.16, z), size: SIMD3(0.018, 1.65, 0.018), color: SIMD3(0.3, 0.36, 0.45))
            mesh.box(center: SIMD3(x, 3.15, z), size: SIMD3(0.4, 0.4, 0.4), color: [amber, blue, teal][index])
        }
        return mesh.vertices
    }

    private struct Builder {
        var vertices: [SceneVertex] = []

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, color: SIMD3<Float>) {
            let rgba = SIMD4<Float>(color, 1)
            for p in [a, b, c, a, c, d] {
                vertices.append(SceneVertex(position: SIMD4<Float>(p, 1), color: rgba))
            }
        }

        mutating func box(center: SIMD3<Float>, size: SIMD3<Float>, color: SIMD3<Float>) {
            let a = center - size / 2
            let b = center + size / 2
            quad(SIMD3(a.x, a.y, b.z), SIMD3(b.x, a.y, b.z), SIMD3(b.x, b.y, b.z), SIMD3(a.x, b.y, b.z), color: color)
            quad(SIMD3(b.x, a.y, a.z), SIMD3(a.x, a.y, a.z), SIMD3(a.x, b.y, a.z), SIMD3(b.x, b.y, a.z), color: color * 0.58)
            quad(SIMD3(a.x, a.y, a.z), SIMD3(a.x, a.y, b.z), SIMD3(a.x, b.y, b.z), SIMD3(a.x, b.y, a.z), color: color * 0.68)
            quad(SIMD3(b.x, a.y, b.z), SIMD3(b.x, a.y, a.z), SIMD3(b.x, b.y, a.z), SIMD3(b.x, b.y, b.z), color: color * 0.78)
            quad(SIMD3(a.x, b.y, b.z), SIMD3(b.x, b.y, b.z), SIMD3(b.x, b.y, a.z), SIMD3(a.x, b.y, a.z), color: color * 1.08)
            quad(SIMD3(a.x, a.y, a.z), SIMD3(b.x, a.y, a.z), SIMD3(b.x, a.y, b.z), SIMD3(a.x, a.y, b.z), color: color * 0.4)
        }

        mutating func text(_ string: String, center: SIMD3<Float>, right: SIMD3<Float>, pixel: Float, color: SIMD3<Float>) {
            let glyphs: [Character: [String]] = [
                "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
                "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
                "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
                "N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
                "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
                "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
                "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
                "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
                "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
                "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
                "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
                "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
                "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
                "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"]
            ]
            let width = Float(string.count * 6 - 1) * pixel
            let up = SIMD3<Float>(0, 1, 0)
            for (letter, character) in string.enumerated() {
                guard let rows = glyphs[character] else { continue }
                for (row, contents) in rows.enumerated() {
                    for (column, value) in contents.enumerated() where value == "1" {
                        let x = Float(letter * 6 + column) * pixel - width / 2
                        let y = (3 - Float(row)) * pixel
                        let p = center + right * x + up * y
                        quad(p, p + right * pixel * 0.86,
                             p + (right + up) * pixel * 0.86, p + up * pixel * 0.86, color: color)
                    }
                }
            }
        }
    }
}
