# VR OS — Spatial Shell

Aplicativo nativo iOS feito em SwiftUI, ARKit e SceneKit. Projeto experimental de janelas espaciais usando a câmera do iPhone.

## Branch de desenvolvimento
`feature/vros-spatial-shell`

A branch `main` mantém o protótipo 0.1. **A compilação e o teste no aparelho ficam para a próxima etapa.**

## O que está implementado no código
- Interface escura com painéis arredondados, material translúcido, launcher e dock.
- Janelas 3D ancoradas no ambiente com ARKit, com criação e remoção.
- Toque em janela para abrir o aplicativo correspondente.
- Arrastar uma janela no espaço e redimensionar com pinça.
- Recentralizar janelas, fechar todas e consultar janelas abertas.
- Notas salvas localmente via AppStorage.
- Relógio e cronômetro.
- Seleção de foto via PhotosPicker.
- Importação e listagem de documentos durante a sessão.
- Ajustes persistentes de cor, distância, escala, opacidade, vibração e animações.

## Limitações conhecidas
- O AR é exibido na tela do iPhone; não é um headset VR binocular.
- A interface interativa de cada aplicativo é SwiftUI sobre a câmera; o painel espacial 3D funciona como um atalho selecionável, não como uma interface 3D totalmente interativa.
- O estado das janelas não é persistido entre execuções; configurações e notas são.
- A compilação, a execução no iPhone e a qualidade dos gestos ainda precisam ser validadas.
- Os arquivos importados são listados apenas na sessão; não há visualizador de documentos.
- A galeria mostra uma imagem selecionada de cada vez.

## Próximo passo
Validar com XcodeGen e GitHub Actions em macOS, corrigir possíveis erros de compilação e testar no iPhone 15. A assinatura e a instalação do IPA dependem do fluxo de sideload que será resolvido separadamente.
