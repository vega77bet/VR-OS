import simd

/// A static, metre-scale observatory surrounding the user in every direction.
/// Vertex colours approximate soft ambient light; shadows are baked floor geometry,
/// not real-time shadow maps. No panorama or camera image is used.
enum HomeEnvironment {
    static func vertices() -> [SceneVertex] {
        var mesh = Builder()
        mesh.vertices.reserveCapacity(20_000)

        // A continuous hemisphere supplies a quiet horizon without a stretched image.
        // Its radius stays inside the stereo camera's 80 m far plane.
        let sectors = 64
        let bands = 14
        let skyRadius: Float = 44
        for band in 0..<bands {
            let a = Float(band) / Float(bands) * .pi / 2
            let b = Float(band + 1) / Float(bands) * .pi / 2
            let ca = skyColour(elevation: Float(band) / Float(bands))
            let cb = skyColour(elevation: Float(band + 1) / Float(bands))
            for sector in 0..<sectors {
                let t = Float(sector) / Float(sectors) * 2 * .pi
                let u = Float(sector + 1) / Float(sectors) * 2 * .pi
                func point(_ azimuth: Float, _ elevation: Float) -> SIMD3<Float> {
                    SIMD3(skyRadius * cos(elevation) * sin(azimuth),
                          -0.7 + skyRadius * sin(elevation),
                          skyRadius * cos(elevation) * cos(azimuth))
                }
                mesh.quad(point(t, a), point(u, a), point(u, b), point(t, b),
                          colours: (ca, ca, cb, cb))
            }
        }

        // Low-contrast terrain ridges at different distances make a true 360° skyline.
        for layer in 0..<3 {
            let radius = Float(21 + layer * 7)
            let colour = SIMD3<Float>(0.075, 0.105, 0.15) + SIMD3(repeating: Float(layer) * 0.012)
            for sector in 0..<sectors {
                let t = Float(sector) / Float(sectors) * 2 * .pi
                let u = Float(sector + 1) / Float(sectors) * 2 * .pi
                func ridge(_ angle: Float) -> SIMD3<Float> {
                    let height = 1.7 + Float(layer) * 0.35
                        + 1.15 * sin(angle * 3 + Float(layer))
                        + 0.55 * sin(angle * 7 - Float(layer) * 0.6)
                    return SIMD3(radius * sin(angle), height, radius * cos(angle))
                }
                let p = ridge(t)
                let q = ridge(u)
                mesh.quad(SIMD3(p.x, -1, p.z), SIMD3(q.x, -1, q.z), q, p,
                          colour: colour * (0.88 + 0.12 * cos(t)))
            }
        }

        // Broad floor, then three shallow concentric levels of a circular plaza.
        mesh.disc(center: SIMD3(0, -0.26, 0), radius: 43,
                  colour: SIMD3(0.035, 0.048, 0.065), segments: 96)
        mesh.disc(center: SIMD3(0, -0.16, 0), radius: 10.6,
                  colour: SIMD3(0.055, 0.069, 0.088), segments: 96)
        mesh.disc(center: SIMD3(0, -0.08, 0), radius: 9.8,
                  colour: SIMD3(0.066, 0.080, 0.100), segments: 96)
        mesh.disc(center: .zero, radius: 8.9,
                  colour: SIMD3(0.078, 0.092, 0.114), segments: 96)
        mesh.ring(center: SIMD3(0, 0.002, 0), inner: 8.67, outer: 8.70,
                  colour: SIMD3(0.17, 0.28, 0.40), segments: 96)
        mesh.ring(center: SIMD3(0, -0.078, 0), inner: 9.56, outer: 9.59,
                  colour: SIMD3(0.10, 0.16, 0.23), segments: 96)

        // Quiet floor seams establish scale and vanishing lines without a bright grid.
        let seam = SIMD3<Float>(0.061, 0.074, 0.094)
        for step in -4...4 {
            let p = Float(step) * 1.6
            let halfLength = sqrt(max(0, 8.5 * 8.5 - p * p))
            mesh.quad(SIMD3(p - 0.006, 0.003, -halfLength),
                      SIMD3(p + 0.006, 0.003, -halfLength),
                      SIMD3(p + 0.006, 0.003, halfLength),
                      SIMD3(p - 0.006, 0.003, halfLength), colour: seam)
            mesh.quad(SIMD3(-halfLength, 0.003, p - 0.006),
                      SIMD3(halfLength, 0.003, p - 0.006),
                      SIMD3(halfLength, 0.003, p + 0.006),
                      SIMD3(-halfLength, 0.003, p + 0.006), colour: seam)
        }

        // Tangential open pavilions sit beyond the usable interface volume.
        // Their surfaces receive fixed face shading rather than expensive dynamic lights.
        for index in 0..<5 {
            let angle = Float(index) / 5 * 2 * .pi + .pi / 5
            let center = SIMD3<Float>(sin(angle) * 14.5, -0.24, cos(angle) * 14.5)
            let right = SIMD3<Float>(cos(angle), 0, -sin(angle))
            let forward = SIMD3<Float>(sin(angle), 0, cos(angle))
            mesh.orientedBox(center: center + SIMD3(0, 0.10, 0),
                             size: SIMD3(5.9, 0.2, 2.2), right: right, forward: forward,
                             colour: SIMD3(0.083, 0.10, 0.125))
            for side: Float in [-1, 1] {
                mesh.orientedBox(center: center + right * (side * 2.62) + SIMD3(0, 1.95, 0),
                                 size: SIMD3(0.28, 3.9, 0.42), right: right, forward: forward,
                                 colour: SIMD3(0.13, 0.155, 0.19))
            }
            mesh.orientedBox(center: center + SIMD3(0, 3.88, 0),
                             size: SIMD3(5.55, 0.22, 0.52), right: right, forward: forward,
                             colour: SIMD3(0.17, 0.19, 0.22))
            mesh.orientedBox(center: center + SIMD3(0, 3.72, 0) - forward * 0.22,
                             size: SIMD3(4.7, 0.035, 0.025), right: right, forward: forward,
                             colour: SIMD3(0.26, 0.43, 0.61))
        }

        // A few low sculptures punctuate the near/middle ground. The entire frontal
        // ±2.5 m corridor remains clear for panels and pointer interaction.
        let sculptures: [SIMD3<Float>] = [
            SIMD3(-5.5, 0, -4.8), SIMD3(5.5, 0, -4.8),
            SIMD3(-6.3, 0, 2.8), SIMD3(6.3, 0, 2.8), SIMD3(0, 0, 7.4)
        ]
        for (index, center) in sculptures.enumerated() {
            mesh.shadow(center: center + SIMD3(0, 0.004, 0), radius: 0.94)
            mesh.cylinder(center: center + SIMD3(0, 0.12, 0), radius: 0.62, height: 0.24,
                          colour: SIMD3(0.10, 0.12, 0.15), segments: 24)
            let height: Float = index.isMultiple(of: 2) ? 1.30 : 1.05
            mesh.cylinder(center: center + SIMD3(0, 0.24 + height / 2, 0),
                          radius: 0.18, height: height,
                          colour: SIMD3(0.20, 0.235, 0.28), segments: 12)
            mesh.cylinder(center: center + SIMD3(0, 0.24 + height, 0),
                          radius: 0.195, height: 0.045,
                          colour: SIMD3(0.35, 0.51, 0.66), segments: 24)
        }
        return mesh.vertices
    }

    private static func skyColour(elevation: Float) -> SIMD3<Float> {
        let horizon = SIMD3<Float>(0.23, 0.31, 0.43)
        let zenith = SIMD3<Float>(0.035, 0.047, 0.076)
        let t = min(1, elevation * 1.8)
        return horizon * (1 - t) + zenith * t
    }

    private struct Builder {
        var vertices: [SceneVertex] = []

        mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                               colours: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) {
            vertices.append(SceneVertex(position: SIMD4(a, 1), color: SIMD4(colours.0, 1)))
            vertices.append(SceneVertex(position: SIMD4(b, 1), color: SIMD4(colours.1, 1)))
            vertices.append(SceneVertex(position: SIMD4(c, 1), color: SIMD4(colours.2, 1)))
        }

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                          colours: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) {
            triangle(a, b, c, colours: (colours.0, colours.1, colours.2))
            triangle(a, c, d, colours: (colours.0, colours.2, colours.3))
        }

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                          colour: SIMD3<Float>) {
            quad(a, b, c, d, colours: (colour, colour, colour, colour))
        }

        mutating func disc(center: SIMD3<Float>, radius: Float, colour: SIMD3<Float>, segments: Int) {
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                let b = Float(i + 1) / Float(segments) * 2 * .pi
                triangle(center, center + SIMD3(radius * sin(a), 0, radius * cos(a)),
                         center + SIMD3(radius * sin(b), 0, radius * cos(b)),
                         colours: (colour, colour * 0.95, colour * 0.95))
            }
        }

        mutating func ring(center: SIMD3<Float>, inner: Float, outer: Float,
                           colour: SIMD3<Float>, segments: Int) {
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                let b = Float(i + 1) / Float(segments) * 2 * .pi
                quad(center + SIMD3(inner * sin(a), 0, inner * cos(a)),
                     center + SIMD3(outer * sin(a), 0, outer * cos(a)),
                     center + SIMD3(outer * sin(b), 0, outer * cos(b)),
                     center + SIMD3(inner * sin(b), 0, inner * cos(b)), colour: colour)
            }
        }

        mutating func shadow(center: SIMD3<Float>, radius: Float) {
            // Nested opaque gradients approximate a soft contact shadow on the plaza.
            disc(center: center, radius: radius, colour: SIMD3(0.067, 0.081, 0.103), segments: 32)
            disc(center: center + SIMD3(0, 0.001, 0), radius: radius * 0.78,
                 colour: SIMD3(0.054, 0.066, 0.086), segments: 32)
            disc(center: center + SIMD3(0, 0.002, 0), radius: radius * 0.56,
                 colour: SIMD3(0.037, 0.048, 0.067), segments: 32)
        }

        mutating func cylinder(center: SIMD3<Float>, radius: Float, height: Float,
                               colour: SIMD3<Float>, segments: Int) {
            let bottom = center - SIMD3<Float>(0, height / 2, 0)
            let top = center + SIMD3<Float>(0, height / 2, 0)
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                let b = Float(i + 1) / Float(segments) * 2 * .pi
                let da = SIMD3<Float>(radius * sin(a), 0, radius * cos(a))
                let db = SIMD3<Float>(radius * sin(b), 0, radius * cos(b))
                quad(bottom + da, bottom + db, top + db, top + da,
                     colour: colour * (0.76 + 0.20 * cos(a - 0.7)))
                triangle(top, top + da, top + db, colours: (colour * 1.1, colour * 1.1, colour * 1.1))
            }
        }

        mutating func orientedBox(center: SIMD3<Float>, size: SIMD3<Float>,
                                  right: SIMD3<Float>, forward: SIMD3<Float>, colour: SIMD3<Float>) {
            let x = right * size.x / 2
            let y = SIMD3<Float>(0, size.y / 2, 0)
            let z = forward * size.z / 2
            quad(center - x - y + z, center + x - y + z, center + x + y + z, center - x + y + z,
                 colour: colour * 0.86)
            quad(center + x - y - z, center - x - y - z, center - x + y - z, center + x + y - z,
                 colour: colour * 0.73)
            quad(center - x - y - z, center - x - y + z, center - x + y + z, center - x + y - z,
                 colour: colour * 0.66)
            quad(center + x - y + z, center + x - y - z, center + x + y - z, center + x + y + z,
                 colour: colour * 0.93)
            quad(center - x + y + z, center + x + y + z, center + x + y - z, center - x + y - z,
                 colour: colour * 1.08)
        }
    }
}
