import SwiftUI

/// Guided calibration UI. The same draft is sent to the live Metal compositor
/// on every edit, while the transaction keeps cancel/undo/emergency recovery.
@MainActor
struct VisionCalibrationView: View {
    @ObservedObject var manager: VRCalibrationManager
    @StateObject private var session: VisionCalibrationSession
    @Environment(\.dismiss) private var dismiss
    @State private var showingProfiles = false
    @State private var showingAdvanced = false

    init(manager: VRCalibrationManager) {
        self.manager = manager
        _session = StateObject(wrappedValue: VisionCalibrationSession(manager: manager))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Calibração visual")
                        .font(.title2.weight(.semibold))
                    Text(session.progressText + " · " + session.stage.title)
                        .font(.headline).foregroundStyle(.blue)
                    Text(explanation)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("A imagem de cada olho continua sendo renderizada separadamente. O ajuste é manual, reversível e não mede o IPD ou a fusão cerebral automaticamente.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Navegação") {
                    HStack {
                        Button("Anterior") { session.previousStage() }.disabled(session.stage == .preparation)
                        Spacer()
                        Button(session.stage == .validation ? "Salvar" : "Próxima etapa") {
                            if session.stage == .validation { save() } else { session.nextStage() }
                        }.buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button("Desfazer") { session.undo() }.disabled(!canUndo)
                        Button("Restaurar etapa") { session.restoreStage() }
                        Button("Comparar antes/depois") { session.toggleCompare() }
                    }.font(.caption)
                }

                stageContent

                Section("Recuperação") {
                    Button("Restaurar olho selecionado") { session.restoreSelectedEye() }
                    Button("Restaurar tudo ao padrão seguro", role: .destructive) { session.restoreAll() }
                    Text("Se a imagem ficar inutilizável, este botão e a opção Restaurar padrões continuam disponíveis fora do headset.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Perfis") {
                    Text("Perfil atual: \(session.draft.name)")
                    Button("Gerenciar perfis") { showingProfiles = true }
                    Button("Duplicar perfil atual") {
                        _ = manager.duplicateActiveProfile()
                    }
                }

                Section {
                    DisclosureGroup("Ajustes avançados", isExpanded: $showingAdvanced) {
                        Text("Tangencial, K3 e cromática usam limites conservadores. Lentes fisicamente fora do foco ou inclinadas além desses limites não podem ser corrigidas por software.")
                            .font(.footnote).foregroundStyle(.secondary)
                        parameterRow(.radialK3, step: 0.005)
                        parameterRow(.tangentialP1, step: 0.002)
                        parameterRow(.tangentialP2, step: 0.002)
                        parameterRow(.chromaticRedScale, step: 0.001)
                        parameterRow(.chromaticBlueScale, step: 0.001)
                    }
                }
            }
            .navigationTitle("VR-OS Vision Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingProfiles, onDismiss: { session.reloadFromManager() }) {
            VisionProfileListView(manager: manager)
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var stageContent: some View {
        switch session.stage {
        case .preparation:
            Section("Preparar visão") {
                Text("Posicione o iPhone horizontalmente, confirme que as duas lentes estão firmes e ajuste primeiro a distância física entre elas. Use a mira central ou um controle; a calibração pode ser cancelada a qualquer momento.")
                Button("Continuar com calibração atual") { session.nextStage() }.buttonStyle(.borderedProminent)
                Button("Restaurar padrão e começar") { session.restoreAll(); session.nextStage() }
            }
        case .leftAlignment, .rightAlignment:
            Section("\(session.selectedEye.title)") {
                eyePicker
                Text("Use a cruz, o círculo e as marcas de referência da cena VR. Ajuste somente a imagem deste olho até que o alvo fique centrado e inteiro.")
                    .font(.footnote).foregroundStyle(.secondary)
                parameterRow(.horizontalOffset, step: 0.002)
                parameterRow(.verticalOffset, step: 0.002)
                parameterRow(.opticalCenterX, step: 0.002)
                parameterRow(.opticalCenterY, step: 0.002)
            }
        case .fusion:
            Section("Fusão binocular") {
                Text("O alvo de fusão usa formas diferentes em cada olho. Procure uma única figura. Não force convergência excessiva: uma disparidade 3D legítima deve permanecer na cena.")
                eyePicker
                parameterRow(.horizontalOffset, step: 0.001)
                parameterRow(.verticalOffset, step: 0.001)
                projectionCenterRow
                HStack {
                    Button("IPD −") { session.adjustIPD(-0.0005) }
                    Text(String(format: "IPD %.1f mm", session.draft.ipdMeters * 1000)).monospacedDigit()
                    Button("IPD +") { session.adjustIPD(0.0005) }
                }
                HStack {
                    assessment("Ainda vejo separado")
                    assessment("Melhorou")
                    assessment("Confortável")
                }
                Text("Avaliação: \(session.userAssessment)").font(.caption).foregroundStyle(.secondary)
            }
        case .scale:
            Section("Escala e rotação") {
                eyePicker
                parameterRow(.horizontalScale, step: 0.002)
                parameterRow(.verticalScale, step: 0.002)
                parameterRow(.rotationDegrees, step: 0.05)
                HStack {
                    Button("Proporção −") { session.adjustProportionalScale(-0.002) }
                    Button("Proporção +") { session.adjustProportionalScale(0.002) }
                    Button("Restaurar proporções") { session.restoreProportions() }
                }
                Text("Escala uniforme é preferível. Diferenças grandes entre os olhos podem piorar o conforto.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .opticalCenter:
            Section("Centro óptico") {
                eyePicker
                parameterRow(.opticalCenterX, step: 0.002)
                parameterRow(.opticalCenterY, step: 0.002)
                projectionCenterRow
                Text("O centro de correção pode não coincidir com o centro geométrico da metade do display.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .distortion:
            Section("Grade de linhas e círculos") {
                eyePicker
                parameterRow(.distortionStrength, step: 0.02)
                parameterRow(.radialK1, step: 0.005)
                parameterRow(.radialK2, step: 0.002)
                Text("Amostragem inversa radial/tangencial é aplicada no compositor real por olho. Regiões fora da textura ficam pretas e nunca cruzam para o outro olho.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .chromatic:
            Section("Correção de cores nas bordas") {
                eyePicker
                parameterRow(.chromaticRedScale, step: 0.001)
                parameterRow(.chromaticBlueScale, step: 0.001)
                Text("O verde é a referência. Ajuste níveis pequenos apenas se observar contornos coloridos; a correção não elimina defeitos físicos da lente.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .readability:
            Section("Teste de legibilidade") {
                Text("Confira no centro e nas bordas: VR-OS · CALIBRAÇÃO · INÍCIO · AJUSTES · CINEMA · ARQUIVOS · 0123456789 · ÁÉÍÓÚ çãõ")
                    .font(.body.weight(.semibold))
                Text("Se o texto estiver ruim em todas as posições, revise a resolução interna e o renderizador de texto; não tente resolver tudo com distorção óptica.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Resolução −") { session.setRenderScale(session.draftRenderScale - 0.05) }
                    Text(String(format: "%.0f%%", session.draftRenderScale * 100)).monospacedDigit()
                    Button("Resolução +") { session.setRenderScale(session.draftRenderScale + 0.05) }
                }
            }
        case .validation:
            Section("Validação final") {
                Text("Volte ao Home e observe uma janela central, uma janela lateral, ícones, textos e profundidade. A comparação antes/depois usa o mesmo conteúdo e não inventa uma pontuação.")
                Button("Estou confortável") { session.setAssessment("Confortável") }
                Button("Não consegui alinhar as imagens") { session.setAssessment("Não consegui alinhar") }
                    .foregroundStyle(.orange)
                Button("Salvar calibração") { save() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var eyePicker: some View {
        Picker("Olho", selection: Binding(get: { session.selectedEye }, set: { session.selectEye($0) })) {
            ForEach(VisionCalibrationEye.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var projectionCenterRow: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Centro de projeção")
                Text(String(format: "%.4f", session.selectedEye == .left
                            ? session.draft.leftProjectionCenterX
                            : session.draft.rightProjectionCenterX))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button("−") { session.adjustProjectionCenter(eye: session.selectedEye, delta: -0.002) }
            Button("+") { session.adjustProjectionCenter(eye: session.selectedEye, delta: 0.002) }
        }
        .buttonStyle(.bordered)
    }

    private func parameterRow(_ parameter: VisionCalibrationParameter, step: Float) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(parameter.title)
                Text(valueText(parameter)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button("−") { session.adjust(parameter, delta: -step) }
            Button("+") { session.adjust(parameter, delta: step) }
        }
        .buttonStyle(.bordered)
    }

    private func valueText(_ parameter: VisionCalibrationParameter) -> String {
        let eye = session.eye
        let value: Float
        switch parameter {
        case .horizontalOffset: value = eye.horizontalOffset
        case .verticalOffset: value = eye.verticalOffset
        case .horizontalScale: value = eye.horizontalScale
        case .verticalScale: value = eye.verticalScale
        case .rotationDegrees: value = eye.rotationDegrees
        case .opticalCenterX: value = eye.opticalCenterX
        case .opticalCenterY: value = eye.opticalCenterY
        case .radialK1: value = eye.radialK1
        case .radialK2: value = eye.radialK2
        case .radialK3: value = eye.radialK3
        case .tangentialP1: value = eye.tangentialP1
        case .tangentialP2: value = eye.tangentialP2
        case .chromaticRedScale: value = eye.chromaticRedScale
        case .chromaticBlueScale: value = eye.chromaticBlueScale
        case .distortionStrength: value = eye.distortionStrength
        }
        return String(format: "%.4f", value)
    }

    private func assessment(_ title: String) -> some View {
        Button(title) { session.setAssessment(title) }.font(.caption)
    }
    private var explanation: String {
        switch session.stage {
        case .preparation: return "Prepare o visor antes de iniciar."
        case .leftAlignment, .rightAlignment: return "Ajuste uma metade do display por vez."
        case .fusion: return "Junte as formas sem remover a profundidade real."
        case .scale: return "Corrija tamanho e inclinação em passos pequenos."
        case .opticalCenter: return "Mova o centro da correção até as linhas ficarem mais retas."
        case .distortion: return "Use a grade e os círculos nas bordas."
        case .chromatic: return "Reduza contornos vermelhos ou azuis."
        case .readability: return "Valide o texto real do sistema."
        case .validation: return "Confirme visualmente e salve ou descarte."
        }
    }
    private var canUndo: Bool { session.canUndo }
    private func save() { session.save(); dismiss() }
    private func cancel() { session.cancel(); dismiss() }
}

@MainActor
private struct VisionProfileListView: View {
    @ObservedObject var manager: VRCalibrationManager
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(manager.profiles) { profile in
                    Button { manager.selectProfile(id: profile.id); dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(profile.name); Text(profile.id).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); if profile.id == manager.activeProfileID { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                }
                Section("Novo perfil") {
                    TextField("Nome", text: $newName)
                    Button("Criar a partir do perfil atual") {
                        _ = manager.createProfile(name: newName.isEmpty ? "Minha calibração" : newName)
                        newName = ""
                    }
                }
                Button("Restaurar padrão seguro", role: .destructive) { manager.resetDefaults() }
            }
            .navigationTitle("Perfis de visão")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
