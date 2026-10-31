# VR-OS 2.0 — Etapa 1

Fundação nativa iOS para iPhone 15 convencional (60 Hz) em VR Box: Swift, Metal/MetalKit, Core Motion e simd. Abre diretamente em uma cena geométrica binocular. Sem câmera, ARKit, LiDAR, realidade mista ou dependências de execução externas.

**A validação final exige um iPhone físico.** A implementação e os testes sintéticos não certificam conforto óptico, sinais dos sensores no aparelho ou 60 FPS. Consulte [o registro de validação](Docs/Validation.md) para os resultados efetivamente obtidos.

## Começar

Requisitos: macOS, Xcode 16.4 ou superior, XcodeGen (`brew install xcodegen`).

```sh
git clone --branch vr-os-2 https://github.com/vega77bet/VR-OS.git
cd VR-OS
xcodegen generate
open VROS.xcodeproj
```

No target VROS, selecione seu Team de assinatura e um iPhone com Developer Mode habilitado. O projeto anterior não tinha Team, certificados ou perfis de provisionamento; nenhum foi inventado. O identificador foi preservado da versão mais recente: `com.vega77bet.vros2`. Se o seu Team não possuir esse identificador, use um identificador de desenvolvimento disponível.

```sh
# Compilação para dispositivo, sem assinatura (não instalável):
xcodebuild -project VROS.xcodeproj -scheme VROS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build

# Testes, escolhendo um simulador instalado:
xcodebuild -project VROS.xcodeproj -scheme VROS \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

O projeto Xcode é gerado a partir de `project.yml`; código Swift e shaders Metal são compilados no target nativo. O workflow [ios.yml](.github/workflows/ios.yml) gera o projeto, compila para `iphoneos` e executa XCTest no simulador em `macos-15`. Os artefatos incluem `.app` sem assinatura, projeto Xcode e `.xcresult`. Um `.app` sem assinatura não é um IPA instalável. Não há empacotamento de IPA fictício.

## Uso

1. Abra o app em paisagem, **Dynamic Island / topo do iPhone à esquerda** (interface `landscapeRight`). Somente essa montagem é suportada nesta etapa.
2. Segure o visor na direção frontal desejada e toque **Recentralizar**. Repita sempre que necessário; apenas o rumo horizontal é redefinido, preservando inclinação e gravidade.
3. Em **Calibrar lentes**, ajuste IPD virtual, FOV, centros horizontais e escala por olho, intensidade/K1/K2 da distorção e resolução interna. Os ajustes ficam salvos localmente; **Restaurar padrões** desfaz todos.
4. Feche a calibração, recentralize se necessário e toque **Entrar no visor** para ocultar controles 2D e métricas antes de colocar o iPhone no VR Box. Um toque na tela volta a mostrá-los.
5. Faça os testes físicos de [DeviceTesting.md](Docs/DeviceTesting.md). Controles 2D são instrumentos de preparação, não uma interface binocular utilizável dentro do visor.

## Arquitetura

```text
VROS/
  App/                 Entrada SwiftUI, integração MTKView, ciclo de vida
  Core/Tracking/       Core Motion, conversão de bases, recenter
  Core/Rendering/      Câmeras, passes Metal, distorção, métricas
  Core/Calibration/    Perfil validado e persistência versionada
  Scenes/              Geometria estática da cena de teste
  Shaders/             Cena 3D e pós-processamento óptico
  UI/                  Calibração e diagnóstico antes do uso do visor
Tests/                 XCTest da matemática, estado e persistência
Docs/                  Coordenadas, validação e testes físicos
project.yml            Projeto nativo reproduzível via XcodeGen
```

### Binocular

Uma pose de cabeça é lida por frame. Cada olho recebe uma câmera independente, deslocada em ±IPD/2 no eixo X local da cabeça e rotacionada pela mesma pose. As câmeras são paralelas, sem convergência artificial: profundidade surge da disparidade das projeções da geometria. A projeção descentrada mantém o eixo óptico no centro ajustável de cada lente. A textura esquerda vai exclusivamente para a metade física esquerda; a direita para a direita. A derivação está em [Rendering.md](Docs/Rendering.md).

Dois alvos de cor/profundidade internos recebem a mesma malha estática com matrizes diferentes. Um segundo passe aplica distorção radial por fragment shader, escala óptica e recorte preto fora da imagem. A escala de resolução altera apenas dimensões das texturas, preservando geometria e IPD. Centros são normalizados **dentro de cada metade**, não na tela inteira. Consulte as fórmulas e testes no código de `StereoCamera` e `LensDistortionRenderer`.

Os valores iniciais (IPD 64 mm, FOV vertical 90°, centros 0,5, escala 1, K1 0,18, K2 0,04, intensidade 0,5) são provisórios. Não representam medições do seu VR Box. Distorção cromática e um perfil físico medido ainda não estão implementados.

### Rastreamento

Core Motion fornece atitude fundida por quaternion, sem depender das câmeras. A transformação explícita de bases está descrita em [Coordinates.md](Docs/Coordinates.md). Não há filtros pesados nem integração própria de giroscópio; o renderizador usa a amostra recente para ambos os olhos. Recentralização atua sobre um offset de rumo, com transição curta, sem alterar IPD. Pausas interrompem os sensores e a renderização; a retomada restabelece a referência para evitar saltos causados pela reinicialização do Core Motion.

É **3DoF**: translação da cabeça não é rastreada. A posição dos olhos inclui somente a separação binocular virtual em torno de uma cabeça fixa; não há rastreamento de sala, mãos ou controles Bluetooth implementados. O método de recenter está pronto para ser chamado por uma futura camada de entrada.

### Desempenho e recursos

`MTKView` sincroniza a renderização com o display, com alvo de 60 Hz. A cena usa buffers estáticos compartilhados entre os olhos e recursos de GPU privados. O número de frames em voo é limitado sem bloquear a thread principal. Métricas mostram frequência dos frames, tempo de submissão de CPU e tempo de GPU quando disponível; não medem latência sensor-fóton. A resolução pode ser reduzida manualmente e por limite térmico. O renderizador e as callbacks não mantêm ciclos fortes de retenção.

Não há timewarp, compositor assíncrono ou garantia de experiência equivalente a Quest 3. Limitações reais do painel, das lentes e do rastreamento inercial precisam ser avaliadas no aparelho. A Etapa 2 não foi iniciada.

## Preservação do projeto anterior

O ponto mais recente encontrado foi `vr-os-48-phonexr-rebuild`, commit `e1dc5e377f490f6580c0b9325c9c8e4369fd5e9f`. A branch `backup/vr-os-antigo` preserva esse projeto completo. A `main` e todas as demais branches anteriores permanecem intactas; o histórico foi mantido, sem force push. Veja [RebuildInventory.md](Docs/RebuildInventory.md) para a relação dos arquivos substituídos.
