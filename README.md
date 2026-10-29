# VR-OS 7.0 · V48

Sistema VR experimental para **iPhone e VR Box**, com dois visores calibráveis, biblioteca de aplicativos, janelas espaciais e seleção pela orientação da cabeça. A reconstrução V48 segue o Home e a paleta descritos na auditoria do PhoneXR, com implementação nativa em SwiftUI/UIKit.

## O que mudou

- **Biblioteca espacial:** painel com categorias laterais, grade de seis itens por página, busca que ignora acentos, ordenação por nome ou uso recente e seção de janelas abertas/minimizadas.
- **Dock flutuante:** relógio, bateria quando disponível, centralização, busca, câmera opcional, quatro aplicativos fixados e Biblioteca. Os pins e o histórico de abertura são salvos no aparelho.
- **Janelas:** barra inferior com mover, diminuir, aumentar, expandir/restaurar, minimizar e fechar. Janelas minimizadas podem ser recuperadas na Biblioteca.
- **Teclado espacial:** letras, números, símbolos, apagar, limpar e espaço. Usa toque, pinça ou a mira para pesquisar apps, buscar nos Ajustes e digitar endereços/pesquisas no navegador.
- **Modo sem câmera por padrão:** Home, mira, navegador, mídia e Cinema podem ser usados sem iniciar ARKit nem solicitar permissão de câmera. Core Motion fornece orientação, nunca posição 6DoF nesse modo.
- **Tema escuro:** fundo `#14171C`, superfícies `#20242B`/`#252A31`, controles `#3A3F48`, texto `#F2F2F2` e painéis arredondados. Ícone original do VR-OS incluído no catálogo.

## Usar

1. Abra o VR-OS com o iPhone na horizontal. A Biblioteca aparece nos dois visores.
2. Mova a cabeça para posicionar a mira e mantenha o alvo sobre um botão por **1 segundo**. O anel mostra o progresso; o botão dispara uma vez até o alvo mudar. O tempo é configurável nos Ajustes. As setas na lateral inferior dos Ajustes permitem rolar sem tocar no iPhone.
3. Abra Cinema, Navegador, Arquivos, Fotos ou Ajustes. São recursos reais do próprio aplicativo. YouTube, Netflix, Twitch e Wikipedia abrem seus sites.
4. Use o pequeno pin em cada cartão para fixar/desafixar um aplicativo no dock. Há quatro lugares; fixar um quinto substitui o último.
5. Abra o relógio para os ajustes rápidos: brilho do iPhone, câmera, centralização, mira, visor e ambientes.
6. Na barra abaixo de uma janela, escolha **Mover**, olhe para outro ponto e mantenha a mira parada para colocar a janela ali. O aviso superior cancela a operação. Com câmera e mão válidas, a alça branca antiga também mantém a movimentação por pinça.
7. Use Biblioteca → Janelas para restaurar uma janela minimizada. O botão de expandir alterna o modo foco.
8. O ícone de câmera liga/desliga a captura opcional. O modo 0,5x continua nos Ajustes e depende de uma lente ultrawide funcional.

A mira acompanha o movimento do iPhone/cabeça; não é um sensor que detecta a direção dos olhos. A tela continua aceitando toque físico. Os seletores de importação e as autorizações do próprio iOS podem exigir toque; importe os arquivos antes de colocar o headset.

## Recursos preservados

Cinema com reprodução local via AVPlayer, modos 2D/SBS/H-SBS/OU, seleção de assentos, controles por mira, ajustes de FOV e áudio; importação e organização de documentos/imagens/vídeos; navegador WKWebView com favoritos, histórico e abas gerenciadas pela Central VR; Ajustes nativos com persistência; perfis dos dois visores; ambientes procedurais; ARKit/Vision e câmera 0,5x opcionais; atualizações de conteúdo HTTPS.

## Limites da versão iPhone

- **Não executa APK Android, jogos Quest/Gear VR ou binários OpenXR/Monado.** O runtime, o patcher Android e o AccessibilityService da auditoria não são componentes iOS.
- Não há integração WebXR imersiva, backend de contas/amigos/chamadas, assistente remota, streaming de desktop ou protocolo PhoneXR PH5/PH6 nesta versão.
- Vision continua detectando uma mão. A fusão MediaPipe/YOLO do Android não foi portada.
- A câmera é monocular, copiada para os dois olhos; não há passthrough estéreo real. A orientação sem câmera é 3DoF. Posição 6DoF depende do caminho ARKit e de câmera funcional.
- O navegador permite até três janelas web simultâneas e mantém duas WKWebViews por sessão; conteúdo dinâmico pode diferir entre os olhos. Vídeo com DRM ou interação que exige evento nativo pode precisar do Safari/toque físico.
- Janelas não sobrevivem ao encerramento do app. Pins, recentes e preferências sobrevivem.
- Uma falha física na câmera não é corrigida por software. O modo padrão evita depender dela.

A matriz completa está em [V48_IMPLEMENTACAO.md](V48_IMPLEMENTACAO.md).

## Compilação e testes

`project.yml` usa XcodeGen, formato **xcode15_0**, iOS 16+, Swift 5 e build 48. O fluxo `.github/workflows/build-ipa.yml` executa os testes de geometria, compila o aplicativo Release sem assinatura, executa os testes de regressão no simulador e produz prévias PNG e IPA unsigned.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project VROS.xcodeproj -scheme VROS -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project VROS.xcodeproj -scheme VROSRegression \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO test
```

Os resultados de uma execução precisam ser consultados no Actions; a existência do workflow ou dos testes não comprova aprovação. Um IPA unsigned exige assinatura com método compatível com o iPhone, como o método de sideload já utilizado pelo usuário. Não instala diretamente por um download OTA.

## Referência e procedência

Referência arquitetural/visual: [samrat1games/phonexr](https://github.com/samrat1games/phonexr), snapshot auditado `27c5bc469fb736fb0c00b7254a6dfc532fea7003`, especialmente `Theme.kt`, `HomePanel.kt` e `WindowChrome.kt`.

Os novos componentes Swift desta reconstrução e o ícone do VR-OS são implementações próprias. Não foram importados o código Kotlin, binários, chaves de assinatura, contas ou serviços Supabase do projeto de referência. A referência é creditada sem transformar o aplicativo em uma distribuição do PhoneXR.

A documentação histórica permanece nos arquivos V16–V47; quando houver divergência, este README e a matriz V48 descrevem a versão atual.
