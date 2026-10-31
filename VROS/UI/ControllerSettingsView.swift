import SwiftUI

/// Preparation UI: pairing remains in iOS Settings; no private Bluetooth APIs.
@MainActor
struct ControllerSettingsView: View {
    @ObservedObject var manager: GameControllerManager
    @ObservedObject var preferences: InteractionPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Pareamento no iPhone") {
                    Text("Abra Ajustes → Bluetooth no iPhone. Mantenha pressionado o botão SYNC do Joy-Con até os LEDs piscarem e selecione o controle na lista. Volte ao VR-OS. Repita para o segundo Joy-Con, se desejado.")
                    Text("O iOS decide se apresenta cada Joy-Con ou um par como um controle. Apenas entradas realmente anunciadas pela API são utilizadas.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Controle ativo") {
                    if manager.devices.isEmpty {
                        Text("Nenhum controle GameController conectado. A mira da cabeça continua disponível.")
                    }
                    ForEach(manager.devices) { device in
                        Button { manager.select(id: device.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(capabilities(device)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if manager.activeID == device.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                    }
                }
                Section("Interação") {
                    Picker("Entrada", selection: $preferences.inputMode) {
                        ForEach(InteractionInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Ponteiro do controle", selection: $preferences.pointerMode) {
                        ForEach(ControllerPointerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text(String(format: "Sensibilidade %.1f", preferences.sensitivity))
                    Slider(value: $preferences.sensitivity, in: 0.2...2.5)
                    Text(String(format: "Permanência %.1f segundos", preferences.dwellDuration))
                    Slider(value: $preferences.dwellDuration, in: 0.6...2)
                    Text("Com dois analógicos: direito aponta, esquerdo rola e ajusta profundidade ao agarrar. Com um: aponta; o direcional permite rolar. Sem eixos: mira da cabeça com confirmação por botão.")
                        .font(.footnote)
                }
                Section("Movimento experimental") {
                    Text("Disponível somente se o iOS anunciar atitude do controle. Os eixos variam com o controle e a forma de segurá-lo. Calibre o laser no painel espacial de Controles e teste cada eixo. Na ausência de dados, o modo por analógico assume automaticamente.")
                        .font(.footnote)
                    Toggle("Inverter direção horizontal", isOn: $preferences.motionInvertX)
                    Toggle("Inverter direção vertical", isOn: $preferences.motionInvertY)
                    Toggle("Trocar eixos de inclinação", isOn: $preferences.motionSwapAxes)
                }
                if let device = manager.activeDescriptor {
                    Section("Botões realmente disponíveis") {
                        Text("Os nomes A/B/X/Y abaixo são posições lógicas da Apple e podem diferir das letras impressas no Joy-Con. Pressione e confira no aparelho; remapeie conforme necessário.")
                            .font(.footnote)
                        ForEach(ControllerButton.allCases.filter { device.availableButtons.contains($0) }, id: \.self) { button in
                            Picker(button.title, selection: binding(button)) {
                                Text("Sem ação").tag(ControllerAction?.none)
                                ForEach(ControllerAction.allCases, id: \.self) { action in
                                    Text(action.title).tag(Optional(action))
                                }
                            }
                        }
                        Text("Uma entrada disponível será reservada como alternativa de seleção se nenhum botão estiver associado a Selecionar. A + ZR não geram cliques duplicados.")
                            .font(.footnote)
                        Button("Restaurar mapeamento") { preferences.mapping = .defaults }
                    }
                }
                Section {
                    Button("Restaurar interação") { preferences.resetDefaults() }
                }
            }
            .navigationTitle("Controles e interação").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            _ = manager.sample()
        }
    }

    private func binding(_ button: ControllerButton) -> Binding<ControllerAction?> {
        Binding(get: { preferences.mapping.bindings[button] },
                set: { preferences.mapping.bindings[button] = $0 })
    }

    private func capabilities(_ device: ControllerDescriptor) -> String {
        var parts = ["\(device.availableButtons.count) botões"]
        if device.hasLeftStick { parts.append("analógico E") }
        if device.hasRightStick { parts.append("analógico D") }
        if device.hasMotion { parts.append("atitude anunciada") }
        if let level = device.batteryLevel { parts.append("\(Int(level * 100))%") }
        return parts.joined(separator: " • ")
    }
}
