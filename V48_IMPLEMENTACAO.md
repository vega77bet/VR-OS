# V48 — reconstrução orientada pela auditoria PhoneXR

## Escopo e fonte

Pedido: refazer o VR-OS seguindo a auditoria fornecida, mantendo o nome VR-OS e o alvo de seleção de um segundo, para uso em iPhone/VR Box. Base: branch `vr-os-frontend-rebuild`, commit `0a196acbbe23483f8322d2260b8a52721ee48507` (V47). Referência PhoneXR: commit `27c5bc469fb736fb0c00b7254a6dfc532fea7003`.

O material de referência foi lido no código: árvore recursiva, `Theme.kt`, `HomePanel.kt` e `WindowChrome.kt`. A auditoria enviada pelo usuário fornece o contexto dos outros módulos; esta implementação não é uma nova auditoria completa do Android. Não se afirma reprodução visual pixel a pixel a partir de screenshots do PhoneXR, que não foram fornecidas.

## Matriz de implementação

| Área da auditoria | VR-OS V48 iPhone | Evidência e limite |
| --- | --- | --- |
| Home com biblioteca lateral e dock | Implementação nativa nova | `VRHomeLibrary.swift`, `VRHomeShell.swift`; desenho e hit-testing compartilham `VRHomeLayout`. |
| Paleta Horizon escura | Cores principais reproduzidas | `VRDesignSystem.swift`; cinzas `14171C`, `20242B`, `252A31`, `3A3F48`, texto `F2F2F2`, verde `7BD88F`, erro `FF6B6B`, laranja `FF9544`. |
| Biblioteca, recentes e pins | Implementados localmente | `VRHomeLibrary.entries`, `opened`, `togglePin`; IDs conhecidos, sem duplicados; persistência UserDefaults; quatro pins. |
| Busca e teclado espacial | Implementados | `VRSpatialKeyboard.swift`, `performKeyboardKey` em `VROSApp.swift`; busca de biblioteca, busca dos Ajustes e navegação web. Ajustes também tem setas de rolagem com hit-testing dedicado. |
| Quick settings | Implementados para funções do app | Brilho real via UIScreen; câmera, centralizar, mira, visor, ambientes e Ajustes. Não simula controles de Wi-Fi/Bluetooth do iOS. |
| Janelas espaciais | Preservadas e ampliadas | `VRWindowChrome.swift`, `VRWorkspace.swift`, `VROSApp.swift`; minimizar/restaurar, foco, escala e reposicionamento pelo olhar. |
| Seleção por olhar | Implementada com Core Motion | `VRDwellController.swift`; quaternion relativo em eixos de paisagem, anel de progresso, um disparo por alvo; padrão 1 s. Não é eye-tracking. |
| Uso sem câmera | Padrão desta versão | `vros.camera.enabled.v48` começa falso. Inicialização do Home evita `runtime.start()` e `ultraWide.start()` enquanto a câmera está desligada. |
| Orientação 3DoF | Implementada | Core Motion + `VRUltraWideWindowProjection`; âncoras direcionais e ambientes com orientação sem câmera, sem posição métrica real. |
| ARKit 6DoF | Caminho existente, opcional | `VRRuntime.swift`; exige câmera autorizada/funcional e suporte do aparelho. Sem validação física nesta reconstrução. |
| Mãos | Vision existente, uma mão | `VRRuntime.swift`, `VRUltraWideCamera.swift`; sem MediaPipe/YOLO, sem garantia de funcionar com câmera danificada. |
| Cinema e mídia estéreo | Recursos existentes mantidos | `CinemaView.swift`, `CinemaLibrary.swift`, `VRMediaStore.swift`; AVPlayer local, SBS/OU; a mira acessa os controles, a biblioteca e a saída. Não equivale a testes de todos os formatos/DRMs. |
| Navegador | WKWebView existente + teclado espacial | `VRWebApps.swift`, `VRBrowserState.swift`; ambas as superfícies pertencem a uma sessão, mas páginas dinâmicas podem divergir. |
| Abas e histórico | Existentes na Central VR | `VRWebSession`, comandos em `VRWorkspaceCommand`; não se promete equivalência completa da UI de abas do Android. |
| WebXR imersivo | Não integrado | Não há bridge JS/OpenXR nova nesta versão. |
| OpenXR/Monado, APK patcher, VrApi/Gear VR | Não executáveis nesta versão iOS | Recompilar um shell iOS não executa binários Android. Nenhum botão de instalação/execução falsa foi adicionado. |
| Joy-Con/Accessibility Android | Não portado | Nenhuma promessa de eventos em background equivalente ao Android. |
| Conta, amigos, chamadas e watch together | Não conectados | Exigiriam backend e autenticação próprios; não se usa o Supabase de outro autor. |
| Elix/assistente | Não conectada | Nenhuma chave ou endpoint externo foi importado. |
| Desktop, screen share, clipboard de LAN | Não implementados nesta versão | Nenhum listener TCP/UDP ou broadcast foi criado para imitar serviços sem backend. |
| SDK PH5/PH6 | Não portado | A arquitetura de entrada do VR-OS permanece nativa e interna ao processo. |

## Organização do fonte novo

- `VROS/VRHomeLibrary.swift`: catálogo local, filtros, estado compartilhado, persistência de pins/recentes, canvas lógico 640×420 e alvos interativos.
- `VROS/VRHomeShell.swift`: biblioteca, cards, navegação lateral, dock, relógio/bateria e ajustes rápidos. A geometria vem do modelo, inclusive em visores pequenos.
- `VROS/VRSpatialKeyboard.swift`: sessão e destino do teclado, entrada limitada a 512 caracteres, teclas e hit-testing com o mesmo canvas do Home.
- `VROS/VRWindowChrome.swift`: ações e retângulos da cápsula inferior das janelas.
- `VROS/VRDwellController.swift`: mantém o tempo e rearmamento do alvo e acrescenta orientação relativa em quaternion para ambos os sentidos de paisagem.
- `VROS/VROSApp.swift`: coordena as ações com os recursos reais já existentes. `performHomeAction`, `performKeyboardKey`, `performWindowAction`, `placeMovingWindow`, `setCameraEnabled` são os pontos principais.
- `VROS/VRWebApps.swift`: campo de endereço abre o teclado espacial da sessão; navegação continua sendo validada por `VRBrowserURL`.
- `RegressionTests/HomeShellTests.swift`: busca, persistência, filtros, alvos nas dimensões dos visores, restauração de janelas, teclado e prévias nativas.
- `Tools/generate-app-icon.py` e `AppIcon.appiconset`: ícone geométrico original, com tamanhos necessários para iPhone/Xcode 15.

## Build corrigido

O log da V47 mostrou que `xcodeVersion: 15.0` sozinho não muda o formato do projeto gerado. O Xcode recebeu `objectVersion = 77` e recusou abrir o projeto. A V48 define explicitamente `projectFormat: xcode15_0`, conforme a especificação do XcodeGen.

Após essa correção, o build revelou outro erro anterior: o catálogo não tinha `AppIcon`, embora o target exigisse esse conjunto. A V48 fornece o conjunto e os PNGs correspondentes.

O host de testes e o bundle de testes também herdam número de versão válido, evitando a falha de instalação por ausência de CFBundleVersion encontrada na primeira execução do simulador.

O workflow testa antes de empacotar a IPA, exporta prévias criadas por UIKit no simulador e não depende do subcomando `xcresulttool export attachments` de outra versão do Xcode. A configuração compila em Release com `CODE_SIGNING_ALLOWED=NO`; isso não é uma assinatura de distribuição.

## Verificação e limites

Os testes automatizados da reconstrução cobrem estado e geometria, com renderização nativa de biblioteca, ajustes rápidos, teclado e visão binocular. O CI também executa as suítes de regressão anteriores. Os resultados efetivos da execução são registrados no PR, sem inferir aprovação apenas pela presença dos testes.

Ainda dependem do iPhone/VR Box: direção física da mira nos dois sentidos de paisagem, conforto/IPD, legibilidade nas lentes, latência, deriva dos sensores, falha real da câmera, pinça, aquecimento, bateria e compatibilidade de sites/vídeos reais. Capturas do simulador não comprovam essas propriedades.
