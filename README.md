# VR-OS 4.6 — visor curvo para VR Box + câmera 0,5x com rastreamento

Aplicativo **experimental de realidade mista** para iPhone em modo paisagem, pensado para uso sentado com um headset simples tipo VR Box. **Não substitui o iOS** e não instala aplicativos iOS dentro das janelas.

## Destaque V20 — dois visores curvos como na imagem de referência

- **Novas aberturas ópticas:** em vez de duas metades retangulares ocupando toda a tela, dois blocos curvos sobre fundo preto, com centros mais próximos e tamanho/calibração independentes do tamanho da tela. O mesmo layout vale para Home ARKit, ultrawide 0,5x e Cinema.
- **Perfil Referência (padrão):** cada olho usa 28,5% da largura e 60% da altura da tela; centros em 35% e 65% da largura, altura do centro em 62,5%, aproximadamente como na imagem enviada.
- **Perfis VR Box + / Compacto:** alternativa com área maior ou visor menor, conforme o headset.
- **Botão Visor no dock:** ajuste por toque ou pinça de tamanho, separação visual/IPD, altura, zoom digital e curvatura. Configuração persistente no iPhone. Não representa calibração óptica física.
- **Central de Apps paginada:** todos os sete atalhos continuam acessíveis mesmo em visores compactos; menu Temas reduz o tamanho dos cartões.
- **Limitações:** a máscara não aumenta FOV óptico nem altera a lente 0,5x, e o zoom digital acima de 100% **recorta** parte da câmera. A imagem de ambas as câmeras permanece monocular, copiada para os dois olhos. Consulte [V20_VISOR_LENTES.md](V20_VISOR_LENTES.md) para medidas e testes.

## Destaque V19 — ultrawide real com mãos e cabeça

- O botão **0,5x** abre a câmera ultrawide física do iPhone. A V19 mantém **Vision** lendo a mesma captura para reconhecer mão, cursor, esqueleto e pinça.
- O **Core Motion** oferece orientação da cabeça em **3DoF**, para movimentar a perspectiva das janelas em direções angulares aproximadas; o modo 0,5x **não oferece posição espacial 6DoF/SLAM do ARKit**.
- A mão pode clicar em menus, rolar textos/sites e arrastar janelas em 2D/ângulo usando a pinça. Precisa que a lente traseira realmente enxergue a mão.
- O cabeçalho da câmera 0,5x inclui **Mira** (recentralizar janelas), **Tela toda / Preencher** (mostrar sensor inteiro com barras pretas ou ampliar/cortar), **Mov./Inv.** (inverter direção de rotação) e **ARKit** (voltar ao rastreamento espacial completo).
- Ao abrir 0,5x, ARKit é pausado para liberar câmera traseira; ao voltar, a ultrawide é desligada antes da retomada do ARKit. Cinema usa o modo ARKit.
- Detalhes, limitações e testes em [V19_RASTREAMENTO_05X.md](V19_RASTREAMENTO_05X.md).

## Recursos anteriores (V17–V18)

- **Cinema virtual** com 72 poltronas, telão para arquivos locais MP4/MOV, modos 2D, SBS, H-SBS e OU, um AVPlayer para manter o vídeo dos dois olhos sincronizado, seleção de cadeira por toque, pinça ou **olhar fixamente por 1,5 s** para a bolinha.
- **Ajustes de Cinema**: Centralizar, Mirar tela, Tela ↑/↓/←/→, FOV horizontal 55°–115°, MAX, inverter direção do movimento e trocar lados 3D. FOV, cadeira e calibração são persistidos localmente.
- **Home espacial**: janelas em âncoras ARKit com movimento por pinça na linha branca; quatro temas (Grafite, Cosmos, Aurora e Synthwave). Dock minimizável no canto para não obstruir as alças das janelas.
- **Textos legíveis**: as janelas de notas agora rolam verticalmente por toque, botões ou pinça; A− / A+ ajustam o tamanho da fonte.
- **Central de Apps**: YouTube, Netflix, Navegador, Wikipedia e Twitch como sites em **WKWebView**, uma página por olho. Suporta Modo Foco, página Zoom +/−, rolagem por setas e pinça, favoritos de até quatro URLs, navegação HTTPS, recarregar, voltar e abrir no Safari.
- **HUD** com versão instalada, relógio, bateria (quando disponível) e estado da câmera. Conteúdo remoto de janelas é buscado por HTTPS e fica em cache.
- **Melhorias de desempenho**: ARKit e Vision processam localmente; previews CGImage ficam suspensos em Cinema e temas procedurais; há limite de três apps web abertos ao mesmo tempo.

## Como controlar

1. Coloque o iPhone na horizontal; execute o app e permita câmera/movimento.
2. **Dock**: Janela, Apps, Cinema, Atualizar, Temas, Centro, 0,5x/ARKit e Visor. Em Visor, selecione Referência, VR Box + ou Compacto e ajuste IPD visual e tamanho dos dois olhos. Depois de selecionar, o Dock pode virar um botão pequeno no canto inferior esquerdo; toque ou faça pinça nesse botão para reabri-lo.
3. **Mover janela**: segure a pinça na **linha branca abaixo** do cartão e arraste a mão. A distância usa estimativa monocular e pode variar.
4. **Nota longa**: role tocando, use ↑/↓ ou segure a pinça sobre o texto e mova a mão. A−/A+ mudam o tamanho da letra.
5. **Site**: abra Apps, selecione a plataforma; expanda pelo ícone no cabeçalho para Modo Foco. Use setas de scroll, zoom de página, estrelinha para salvar favorito, ou pinça curta em links e pinça prolongada para rolar. Alguns sites exigem toque físico.
6. **Cinema**: ajuste a mira com Centralizar/Mirar tela, escolha uma poltrona com a mira, toque ou pinça. Teste direção e FOV antes de colocar um vídeo grande; pare se sentir tontura.

## Limites reais

- O iPhone padrão não tem LiDAR; o Z da mão é **estimado pela largura aparente da palma**, não medido com sensor 3D.
- A câmera real é **monocular** e projetada para os dois olhos; não é passthrough estéreo verdadeiro.
- O FOV configurável altera a câmera **virtual**, nunca o campo óptico do headset.
- Netflix e outros provedores podem bloquear vídeo DRM em WKWebView. YouTube, Twitch e conteúdo dinâmico podem apresentar diferenças entre as duas páginas web independentes por olho; clicar por JavaScript não produz toque nativo confiável.
- A captura da mão pela câmera traseira pode ser bloqueada pelo próprio VR Box. O Cinema oferece seleção de assento por **olhar**, mas Home/apps ainda usam toque ou mão.
- As posições espaciais não são âncoras persistentes; reiniciar o aplicativo remove as janelas. O tracking do ARKit pode derivar em ambientes escuros.
- **A compilação e os testes de geometria passam no macOS, mas não garantem calibração, latência, legibilidade, conforto ou compatibilidade de sites no iPhone real.**
- Use sentado e sem obstáculos. Pare imediatamente em caso de náusea ou desconforto visual.

## Compilar e instalar

`project.yml` define o target iOS 16+; o CI executa:
```sh
brew install xcodegen
xcodegen generate
swiftc VROS/VRGestureGeometry.swift VROS/VRCinemaGeometry.swift VROS/VRUltraWideWindowProjection.swift VROS/VRPinchDetector.swift VROS/VRLensGeometry.swift Tests/main.swift -o /tmp/vros-tests
/tmp/vros-tests
xcodebuild -project VROS.xcodeproj -scheme VROS -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

O workflow `.github/workflows/build-ipa.yml` faz build e publica um **IPA unsigned** em Artifacts. Para instalar, **assine** esse IPA com credenciais e um método compatível com o iPhone. Um IPA unsigned não instala diretamente nem se atualiza por download OTA.

## Conteúdo remoto

O manifesto público `https://vr-os-content-updates.vercel.app/manifest.json` fornece apenas **textos, templates de janelas, algumas cores e metadados de versão**. É validado, mantido em cache local e **não executa Swift nem atualiza recursos nativos**. Novos apps web/gestos/correções de código exigem outra IPA assinada. Os frames de câmera e pontos da mão são processados localmente.

Para testes de visor e perfis, veja [V20_VISOR_LENTES.md](V20_VISOR_LENTES.md). Para as melhorias anteriores, consulte [V19_RASTREAMENTO_05X.md](V19_RASTREAMENTO_05X.md) e `V17_AUDITORIA.md`.
