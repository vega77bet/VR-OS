# Validação da Etapa 2

Branch `vr-os-2-stage-2`, derivada de `8f518573e4c1f57dcaea085ee1fb3d6d9832501b`. [Pull request #35](https://github.com/vega77bet/VR-OS/pull/35), sem merge. Ambiente local Linux sem Xcode, iPhone ou Joy-Con; compilação e XCTest foram executados no runner macOS do GitHub Actions em 2026-10-31 UTC.

## Verificações locais

- `git diff --check`: aprovado.
- YAML e existência dos fontes dos targets: aprovado.
- Revisão da fonte única de geometria visual/interativa e da arbitragem de entrada.
- Regressões incluídas: distância não abre janelas fechadas; biblioteca não fica oculta pelo destino anterior; ausência de seleção em controle preserva acesso pela cabeça; direcional remapeado não rola adicionalmente; recenter não reinicia repetidamente o dwell; navegação cancela arrasto.

## Resultado remoto

**Execução final aprovada:** [CI 41251810645](https://github.com/vega77bet/VR-OS/actions/runs/41251810645), código-fonte `b987b36f3e8656de8c5a2ec0247789313087ca72`. O commit posterior deste registro altera somente documentação, sem modificar o código validado.

Runner `macos-15-intel`, macOS 15.7.9, Xcode 16.4. Simulador iPhone 16 Pro, iOS 18.6, arquitetura x86_64. Esse destino não é um iPhone 15 físico.

| Verificação | Resultado observado |
| --- | --- |
| Geração XcodeGen | Aprovada |
| Release `iphoneos`, destino genérico, sem assinatura | `BUILD SUCCEEDED` |
| XCTest nativo `VROSMath` | 83 executados, 83 aprovados, 0 falhas, 0 pulados |
| XCTest iOS `VROS` | 96 executados, 96 aprovados, 0 falhas, 0 pulados |
| Pipelines Metal e ABI Swift/shader | Aprovados na GPU do simulador |
| SBS, lentes, disparidade das janelas e cantos | Aprovados com leitura de pixels reais |
| Atlas de texto e SF Symbols | Pixels reais aprovados e captura inspecionada |
| Janelas sobrepostas/rotacionadas | Superfície visível mais próxima coincide com raycast |
| Interrupção do tracking da cabeça | Dwell cancelado; exige duração nova completa após retomada |
| Encerramento dos simuladores após exportar evidências | Aprovado |

Os 83 testes nativos são parte dos 96 casos da suíte iOS, recompilados a partir dos mesmos arquivos de produção. Não são 179 casos distintos. Nenhum teste Metal foi pulado na execução final.

Distribuição iOS: 6 calibração, 12 entrada/preferências, 31 interação, 21 workspace, 4 renderização espacial, 1 captura Home, 6 estéreo, 11 tracking/lifecycle e 4 Metal/lentes/layout da Etapa 1.

## Cobertura das interações

| Requisito | Evidência automatizada |
| --- | --- |
| Posição e projeção dos painéis | Workspace, matrizes estéreo e disparidade GPU |
| Correspondência visual/interativa | Transformação compartilhada, cantos e oclusão GPU |
| Interseção do laser | Raios sobre planos e janelas rotacionadas, oclusão e área vazia |
| Seleção/cancelamento | Duração, progresso, latch, afastamento e perda do sensor |
| Botões e disponibilidade | Mapeamento customizado, fallback, aliases e entradas inexistentes |
| Conexão/desconexão | Registro simulado, mudança de fonte e quarentena de botões mantidos |
| Cabeça/controle | Automático, fonte explícita e ausência de ativação dupla |
| Arrasto | Captura, movimento, soltura, limites, chão e cancelamento por navegação/desconexão |
| Recenter | Continuidade, relação entre painéis, caso vertical e cursor estacionário com giro da cabeça |
| Persistência | Round-trip, corrupção, valores inválidos e restauração |
| Foco e ciclo das janelas | Exclusividade, fechar/recuperar, biblioteca, paginação e fade do dock |

## Artefatos e inspeção visual

[VROS-stage2-native-build-evidence](https://github.com/vega77bet/VR-OS/actions/runs/41251810645/artifacts/13062010782) contém `.app` de dispositivo não assinado, projeto Xcode, ambos os `.xcresult`, `ios-summary.json`, `math-summary.json` e captura SBS anexada ao XCTest. Retenção até 2026-11-14.

SHA-256 do ZIP informado pelo GitHub: `139b520ef2c68068887b7c13b5b176d0e1a388ef4406db25e241930ff978575c`.

A captura foi produzida pelos shaders e malhas de produção, em 1280×590 SBS antes da correção óptica, com pose fixa e textos de teste identificados. Foi inspecionada para leitura, cortes, painel, dock e referências espaciais. Não é um mockup nem uma captura de iPhone/VR Box real. A revisão visual levou ao aumento da tipografia/contraste e à adição de referências laterais discretas.

## Correções e avisos

O primeiro CI encontrou recursão nos observadores `@Published` de preferências. Os setters passaram a reatribuir somente valores que precisem de normalização, e a suíte de persistência foi aprovada na execução final. A revisão também corrigiu abertura indevida de janelas fechadas ao mudar distância, foco exclusivo, aliases/direcional com ação duplicada, cancelamento de arrasto, estabilidade do cursor com cabeça em movimento, oclusão de painéis e proteção de dwell contra pose congelada.

Os logs mantêm o aviso de extração App Intents sem dependência `AppIntents.framework`, que não é utilizada. As actions v4 emitem aviso de migração de Node.js 20 para 24 na infraestrutura do GitHub. Não houve erro Swift/Metal ou teste reprovado na execução final. Execuções substituídas e a falha inicial não foram contabilizadas como aprovadas.

## Preservação e implementação

21 arquivos adicionados, 7 modificados, nenhum removido em relação à Etapa 1. No `Core/`, somente `VRRenderer.swift` recebe a integração do cenário/UI. Tracking, conversor de coordenadas, câmera estéreo, lentes e calibração da Etapa 1 não foram reescritos. `main`, `vr-os-2` e `backup/vr-os-antigo` permaneceram nos commits originais.

## Limites da validação

Sensores reais, eixos físicos dos Joy-Cons, lentes/VR Box, legibilidade, conforto, 60 FPS sustentados, latência movimento-fóton, autonomia e vazamentos no iPhone 15 permanecem dependentes de teste físico. Simulador não comprova esses resultados.

O CI produz `.app` de dispositivo sem assinatura, projeto Xcode, relatórios e capturas GPU. Sem certificado/Team real não há IPA instalável.

Compatibilidade e mapeamento efetivo de Joy-Con esquerdo, direito e par permanecem pendentes de teste físico, assim como atitude de `GCMotion`. Analógico/botões usam apenas capacidades anunciadas; movimento relativo é opt-in experimental. A origem do laser é virtual e o tracking da cabeça é 3DoF. Conteúdo interno de Cinema, Navegador, Arquivos e Fotos continua identificado como em desenvolvimento. A transparência é aproximada para UI de alta opacidade, não transmissão física completa entre janelas.

O roteiro de instalação, pareamento e uso está no [README](../README.md), na [tabela de controles](Controllers.md) e no [checklist físico](Stage2DeviceTesting.md). A etapa está pronta para avaliação no aparelho; conforto e compatibilidade física não estão certificados.
