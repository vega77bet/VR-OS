import UIKit
import AVFoundation
import ARKit

enum VRDiagnostics {
    static func thermalDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Aquecendo"
        case .serious: return "Quente"
        case .critical: return "Crítico"
        @unknown default: return "Desconhecido"
        }
    }

    @MainActor
    static func report(camera: String, tracking: String, handPoints: Int, pinching: Bool,
                       mediaCount: Int, mediaBytes: Int64, webCount: Int) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
        let battery = UIDevice.current.batteryLevel
        return """
        VR-OS · diagnóstico local
        Versão: \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Data: \(ISO8601DateFormatter().string(from: Date()))
        Temperatura: \(thermalDescription(ProcessInfo.processInfo.thermalState))
        Economia de energia: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "Sim" : "Não")
        Bateria: \(battery >= 0 ? "\(Int(battery * 100))%" : "Indisponível")
        ARKit suportado: \(ARWorldTrackingConfiguration.isSupported ? "Sim" : "Não")
        Lente 0,5x disponível: \(ultra ? "Sim" : "Não")
        Permissão da câmera: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)
        Câmera: \(camera)
        Rastreamento: \(tracking)
        Mão: \(max(0, min(21, handPoints)))/21 pontos · pinça \(pinching ? "fechada" : "aberta")
        Arquivos locais: \(mediaCount) · \(ByteCountFormatter.string(fromByteCount: mediaBytes, countStyle: .file))
        Janelas web abertas: \(webCount)

        Este relatório é uma fotografia do estado atual; não certifica ausência de bugs.
        Teste físico: 0,5x, ARKit, Vision, conforto óptico, áudio e serviços com DRM.
        Não inclui fotos, vídeos, nomes de arquivos, histórico, cookies ou contas.
        """
    }
}
