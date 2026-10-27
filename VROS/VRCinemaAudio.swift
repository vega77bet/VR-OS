import AVFoundation
import simd

/// Optional mono projector source rendered at the rear of the virtual room.
/// This does not convert the film's soundtrack into multichannel audio.
final class VRCinemaAudio {
    private let engine = AVAudioEngine()
    private let source = AVAudioPlayerNode()
    private let environment = AVAudioEnvironmentNode()
    private var configured = false
    private(set) var active = false

    func start() throws {
        if active { return }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        if !configured {
            engine.attach(source)
            engine.attach(environment)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                throw NSError(domain: "VROSAudio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Formato de áudio indisponível"])
            }
            engine.connect(source, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            source.position = AVAudio3DPoint(x: 0, y: 1, z: 5)
            source.renderingAlgorithm = .equalPowerPanning
            source.volume = 0.04
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100),
                  let samples = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = 44100
            for i in 0..<44100 {
                let t = Double(i) / 44100
                samples[i] = Float(sin(t * 2 * .pi * 60) * 0.5 + sin(t * 2 * .pi * 120) * 0.15)
            }
            source.scheduleBuffer(buffer, options: .loops)
            configured = true
        }
        try engine.start()
        source.play()
        active = true
    }

    func updateOrientation(_ rotation: simd_quatf) {
        let forward = rotation.act(SIMD3<Float>(0, 0, -1))
        let up = rotation.act(SIMD3<Float>(0, 1, 0))
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
    }

    func stop() {
        guard configured else { active = false; return }
        source.pause()
        engine.pause()
        active = false
    }
    deinit { engine.stop() }
}
