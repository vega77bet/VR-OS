import SwiftUI

struct CalibrationView: View {
    @ObservedObject var manager: VRCalibrationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ajuste antes de colocar o iPhone no visor. Os valores iniciais são provisórios: o VR Box não possui uma especificação óptica única.")
                        .font(.footnote)
                    Text(manager.profile.name)
                }

                Section("Geometria binocular") {
                    adjustment("IPD virtual", value: $manager.profile.ipdMeters, range: 0.05...0.075,
                               display: String(format: "%.1f mm", manager.profile.ipdMeters * 1000))
                    adjustment("Campo de visão vertical", value: $manager.profile.verticalFOVDegrees, range: 60...110,
                               display: String(format: "%.0f°", manager.profile.verticalFOVDegrees))
                }

                Section("Olho esquerdo · metade esquerda") {
                    adjustment("Centro horizontal E", value: $manager.profile.leftCenterX, range: 0.35...0.65,
                               display: percent(manager.profile.leftCenterX))
                    adjustment("Escala óptica E", value: $manager.profile.leftScale, range: 0.7...1.3,
                               display: percent(manager.profile.leftScale))
                }

                Section("Olho direito · metade direita") {
                    adjustment("Centro horizontal D", value: $manager.profile.rightCenterX, range: 0.35...0.65,
                               display: percent(manager.profile.rightCenterX))
                    adjustment("Escala óptica D", value: $manager.profile.rightScale, range: 0.7...1.3,
                               display: percent(manager.profile.rightScale))
                }

                Section("Distorção radial") {
                    adjustment("Intensidade", value: $manager.profile.distortionStrength, range: 0...1,
                               display: percent(manager.profile.distortionStrength))
                    adjustment("Coeficiente K1", value: $manager.profile.distortionK1, range: 0...0.5,
                               display: String(format: "%.3f", manager.profile.distortionK1))
                    adjustment("Coeficiente K2", value: $manager.profile.distortionK2, range: 0...0.25,
                               display: String(format: "%.3f", manager.profile.distortionK2))
                    Text("Intensidade zero desativa a distorção. Use o piso e o horizonte para observar a curvatura através das lentes.")
                        .font(.footnote)
                }

                Section("Resolução interna") {
                    adjustment("Escala de renderização", value: $manager.renderScale, range: 0.5...1,
                               display: percent(manager.renderScale))
                    Text("A escala reduz as dimensões em pixels de cada olho. O ajuste não altera o IPD nem a geometria virtual.")
                        .font(.footnote)
                }

                Section {
                    Button("Restaurar padrões") { manager.resetDefaults() }
                    Text("As alterações são salvas automaticamente neste iPhone.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Calibração óptica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func percent(_ value: Float) -> String { String(format: "%.0f%%", value * 100) }

    private func adjustment(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(display)
        }
    }
}
