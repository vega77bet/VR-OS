# VR-OS 2.0 — Etapa 2: Home espacial

Aplicativo nativo para iPhone 15, iOS 17+, em VR Box. Swift, Metal/MetalKit, Core Motion, GameController e simd. Home, janelas, ícones, laser e mira são geometria no mundo, renderizada pelas câmeras binoculares da Etapa 1. Sem câmera, página web ou elementos proprietários de outros headsets.

Branch `vr-os-2-stage-2`, baseada em `vr-os-2` no commit `8f518573e4c1f57dcaea085ee1fb3d6d9832501b`. A Etapa 1 e `backup/vr-os-antigo` foram preservadas. Consulte [validação da Etapa 1](Docs/Validation.md) e [coordenadas](Docs/Coordinates.md).

## Compilar e instalar

macOS, Xcode 16.4+ e XcodeGen (`brew install xcodegen`).

```sh
git clone --branch vr-os-2-stage-2 https://github.com/vega77bet/VR-OS.git
cd VR-OS
xcodegen generate
open VROS.xcodeproj
```

Selecione seu Team no target VROS e execute num iPhone com Developer Mode. Bundle ID preservado: `com.vega77bet.vros2`. Não existem certificados, Team ou perfis inventados. O `.app` sem assinatura do CI não é diretamente instalável.

```sh
xcodebuild -project VROS.xcodeproj -scheme VROS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build

# Estado espacial e entrada simulada, sem simulador:
xcodebuild -project VROS.xcodeproj -scheme VROSMath -destination 'platform=macOS' test

# Suíte completa; escolha um simulador instalado:
xcodebuild -project VROS.xcodeproj -scheme VROS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

O [workflow](.github/workflows/ios.yml) usa `macos-15-intel`, compila para iPhone e executa ambas as suítes. Preserva `.xcresult`, projeto Xcode, `.app` sem assinatura e anexos dos testes. Capturas GPU são renderizações reais anteriores à correção das lentes; não avaliam conforto óptico. [Resultados efetivamente executados](Docs/Stage2Validation.md).

## Usar

1. Monte com **topo / Dynamic Island à esquerda**, interface `landscapeRight`.
2. O app abre no Home. Toque na tela para mostrar a preparação nativa; **Entrar no visor** oculta os controles. A seleção espacial fica suspensa durante a preparação.
3. Sem controle, aponte a mira e permaneça aproximadamente um segundo. O anel indica progresso; afastar cancela. Para repetir uma seleção, saia do botão antes de voltar.
4. O dock oferece Início, Aplicativos, Cinema, Navegador, Arquivos, Fotos, Ajustes e Biblioteca. A biblioteca possui paginação por botões e rolagem. Conteúdo incompleto abre uma janela **Recurso em desenvolvimento**, sem fingir reprodução, navegação ou acesso a arquivos.
5. **Menu** no Home ou Menu/+ equivalente abre o menu rápido: Home, aplicativos, recenter, controles, calibração, informações e saída do visor.
6. Ajustes → Controles e Calibração são painéis espaciais operáveis no visor. Remapeamento completo e lentes avançadas ficam na preparação nativa.
7. O alvo de cada janela recupera a posição; X fecha. **Restaurar layout** recupera o conjunto. Recenter traz a interface para a direção atual sem girar o cenário ou modificar o tracking.

## Joy-Cons

Pareie em **Ajustes → Bluetooth do iPhone**, usando SYNC. O VR-OS enumera somente dispositivos reconhecidos por GameController. [Pareamento, tabela de botões e compatibilidade](Docs/Controllers.md).

- Analógico direito aponta; se só houver um, ele aponta. Com dois, o esquerdo rola e ajusta profundidade ao agarrar. Direcional não associado a outra ação também rola.
- A lógico ou gatilho direito seleciona; gatilho esquerdo agarra enquanto mantido. B volta; X abre aplicativos; Y recentraliza interface e laser; Menu/+ abre menu rápido; Opções/− volta ao Home. São nomes **lógicos da Apple**, que podem diferir das letras Nintendo. Entradas disponíveis são remapeáveis.
- Sem eixos, use mira da cabeça com confirmação por botão. Sem entrada de seleção utilizável, há fallback para permanência.
- Movimento é **experimental, opt-in e dependente de `GCMotion.hasAttitude`**. Há calibração relativa e inversão/troca de eixos. Sem atitude, o analógico assume. Nenhum Joy-Con foi validado fisicamente neste ambiente. A origem do laser é virtual, sem rastreamento posicional 6DoF.

## Módulos

| Pasta | Responsabilidade |
| --- | --- |
| `App/`, `Core/` | Ciclo de vida, tracking, estéreo, lentes e métricas |
| `Environment/` | Observatório procedural 360°, horizonte, piso e decoração |
| `SpatialUI/` | Geometria compartilhada, janelas, workspace e UI Metal |
| `Home/` | Ações, relógio, bateria, status e frame único para os olhos |
| `Controllers/`, `Input/` | Adaptador GameController, registro testável e mapeamento |
| `Interaction/` | Raycast, permanência, arbitragem e arrasto |
| `Settings/`, `UI/` | Preferências persistentes e preparação nativa |
| `Tests/` | Fundação, workspace, entrada simulada e shaders reais |

`SpatialWindow`/`SpatialElement` são a fonte única da geometria visual e interativa. O raycast usa coordenadas locais, cantos arredondados e oclusão pela janela mais próxima. O atlas de glifos/SF Symbols é imutável; buffers são reutilizados. [Detalhes do renderizador](Docs/Stage2Rendering.md).

## Limitações

Cabeça em 3DoF, sem translação ou câmera. Iluminação/sombras são aproximações por geometria e cores. Parâmetros ópticos provisórios. Transparência ordenada por janela, sem interpenetração arbitrária como num compositor completo. Cinema, navegador, arquivos e fotos são destinos em desenvolvimento.

O objetivo é 60 Hz, sem garantia de 60 FPS sustentados. Conforto, legibilidade nas lentes, latência, memória e capacidades reais dos Joy-Cons exigem aparelho. [Checklist físico da Etapa 2](Docs/Stage2DeviceTesting.md).
