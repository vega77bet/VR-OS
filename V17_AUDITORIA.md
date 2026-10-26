# VR-OS V17 — auditoria integral (4.3.0 / build 17)

Auditoria baseada na base V16 do repositório e na revisão de **todos os arquivos Swift da aplicação**, inclusive Cinema, ARKit/Vision, WebKit, notas, temas, manifestos e HUD. Os testes de código/compilação **não substituem** validação física no iPhone com headset.

## Correções efetivamente aplicadas

| Área | Problema que existia | Correção V17 |
| --- | --- | --- |
| Janelas normais | `Text(...).lineLimit(4)` escondia o restante do texto, sem scroll | Novo `VRNoteScrollSurface` baseado em `UITextView`; scroll por toque, pinça e botões, espelhado nos dois olhos |
| Legibilidade | Texto de notas fixo e pequeno | Fonte ajustável A− / A+ (11 a 22 pontos), salva em UserDefaults |
| Treinamento | Botão Janela criava texto curto sem permitir conferir scroll | Agora cria guia longo que demonstra todas as formas de rolagem |
| Sites | Não havia zoom independente da página nem botão de rolagem | Zoom WebKit 75 a 250%, setas ↑/↓ e pinch-scroll; valores maiores que 100% no slider do launcher aumentam zoom interno, sem cortar janela |
| Janelas grandes | Zoom/distância podiam colocar o fechar e a alça fora da viewport de um olho | Dimensões limitadas ao campo renderizável; Modo Foco usa viewport quase inteira sem alça |
| Estéreo WebKit | Voltar/Avançar nos dois navegadores podia desencontrar o histórico | Só o olho primário controla o histórico; o secundário recebe a URL resultante e offset de scroll limitado ao conteúdo |
| Scroll WebKit | Offset do olho principal era copiado mesmo além do conteúdo do olho direito | Offset horizontal/vertical limitado ao tamanho real do navegador secundário |
| Erros da web | Cancelar carregamento por redirecionamento podia exibir erro falso | Ignora `NSURLErrorCancelled` nas transições |
| Favoritos | Navegador não tinha acesso rápido a páginas | Estrela para salvar/remover até 4 URLs HTTPS persistentes; botões de acesso rápido por olho |
| Pinça no launcher | Áreas dependiam de medidas hardcoded e da quantidade de apps | `VRGestureGeometry` compartilha geometria do menu e acerto de gesto para 3/5/7 opções; testes automatizados |
| Cinema | Filmes importados eram copiados para Documents e acumulavam no app | Imports temporários em Caches/Cinema, limpeza ao substituir e ao iniciar, remoção de cache legado |
| Cinema | Ao acabar o filme, o estado `playing` podia continuar em reprodução; Play não reiniciava | Observador de fim de item, controle volta ao estado correto e Play reinicia do início |
| Cinema | Buscar/avançar 10 s podia posicionar além do fim | Busca limita posição à duração válida do item |
| Cinema | Escolha de cadeira, FOV, direção e ajuste da mira eram esquecidos ao reabrir | Salvos localmente, com botão Mirar tela para zerar as correções manuais |
| Cinema | Quaternion aim embutido difícil de auditar e sujeito a regressão | `VRCinemaGeometry` puro; testes do vetor de frente de todas as 72 poltronas com tolerância de 0,01% |
| Desempenho | Temas procedurais geravam `CGImage` da câmera mesmo sem exibi-la | Conversão de frames desativada em Cosmos/Aurora/Synthwave e no Cinema; pose AR e mãos mantidas |
| Mão no Cinema | Otimizar a prévia poderia estragar o mapeamento do dedo | O ponto da mão usa resolução fornecida pelo ARKit mesmo com `cameraImage == nil` |
| Segundo plano | Retornar de outro app podia reiniciar ARKit apagando referências das janelas | Pausa no background e `resume()` sem `.resetTracking`/`.removeExistingAnchors`; o Cinema pausa o filme e recalibra o movimento |
| HUD | Título podia mostrar VR OS 3.1 mesmo com versão nova instalada | HUD usa `CFBundleShortVersionString` real, além de relógio e bateria |
| Documentação | README descrevia V3, controles antigos e atualização de Apps não suportada | README atualizado com os comandos reais, limitações e build V17 |
| Compilação | Aviso Swift de referência de `self` capturada em contexto concorrente no controle de cinema | Timer de esconder controles usa Task `@MainActor` explícito; removidos valores Swift não usados |

## Novidades de usabilidade

- Ajuste do zoom **da página** separado de tamanho do quadro VR.
- Quatro favoritos visíveis rapidamente no navegador; salvos localmente.
- Um novo cartão **guia de uso** com texto longo para treinar scroll pelo gesto.
- Relógio e bateria no topo do headset.
- FOV e mira do Cinema mantidos entre aberturas.

## Automação no GitHub Actions

O workflow `.github/workflows/build-ipa.yml` realiza, nesta ordem:

1. Checkout em macOS, instala XcodeGen e gera o Xcode project.
2. Compila e executa `Tests/main.swift` junto com `VRGestureGeometry.swift` e `VRCinemaGeometry.swift`.
3. Testa **os cliques em todos os menus de 3/5/7 apps, com/sem aviso**, controle de zoom, sete ícones da barra do site, favoritos, foco e clamp das janelas.
4. Testa que **as 72 câmeras das poltronas**, com seus deslocamentos e elevações reais, apontam para o centro do telão, com produto escalar acima de 0,9999.
5. Compila target iPhone Release e empacota o IPA **unsigned**.

Testes não têm acesso a lente, sensor, vídeo DRM ou interação tátil de um VR Box real.

## Roteiro de validação no iPhone

- [ ] **Home:** abrir a V17 e verificar "VR OS 4.3.0", relógio, bateria. Alternar Grafite/Cosmos/Aurora/Synthwave sem travar; confirmar rastreamento.
- [ ] **Notas:** Dock → Janela; usar ↑/↓, rolagem por toque e pinça segurada; A−/A+; fechar e criar outra (o tamanho escolhido da letra deve persistir).
- [ ] **Janela:** selecionar uma janela pelo cabo branco, mover X/Y/Z; confirmar que sua alça e X não desaparecem atrás da borda, até quando a janela fica próxima.
- [ ] **Apps:** abrir YouTube, Wikipedia, Navegador, Netflix e Twitch por toque e pinça. Conferir se o toque em um app não abre outro.
- [ ] **Sites:** rolar usando ↑/↓ e pinça; ajustar zoom −/+; salvar uma URL na estrela e voltar a ela; avançar/voltar entre 3 páginas e comparar os dois olhos.
- [ ] **Foco:** expandir/restaurar janela web, usar os botões ainda acessíveis.
- [ ] **Limite:** tentar abrir mais de 3 apps web, conferir aviso e recuperação após fechar um.
- [ ] **Cinema:** olhar para frente e tocar Centralizar/Mirar tela; mover a cabeça em quatro eixos; escolher várias poltronas por toque/pinça/olhar 1,5s; confirmar centro do telão.
- [ ] **Vídeo:** abrir MP4, assistir até terminar; conferir se vira "Play" e volta ao começo ao apertar; testar busca e 2D/SBS/OU.
- [ ] **Persistência:** ajustar FOV, mira e poltrona; sair e reabrir o Cinema para conferir se manteve.
- [ ] **Background:** com uma janela ancorada e um filme pausado, mudar de aplicativo e retornar; verificar se o mundo virtual não teletransporta e os sensores voltam.
- [ ] **Desempenho:** usar 10–15 min; observar bateria, aquecimento, latência e FPS. Parar imediatamente se causar tontura.

## Limitações reconhecidas / não considerar corrigidas sem teste físico

1. **Direção real de CoreMotion e fusão dos olhos:** só teste com iPhone montado verifica o sentido e o conforto. A direção pode variar pela orientação e encaixe; existe controle manual.
2. **FOV óptico físico:** depende da distância das lentes, regulagem e design do VR Box. FOV virtual 55–115° não altera as lentes.
3. **Apps web protegidos:** Netflix DRM e alguns players YouTube/Twitch podem não funcionar no WKWebView. São sites, não apps nativos.
4. **Sincronia exata entre webviews estéreo:** o código minimiza histórico/scroll divergentes, mas vídeos, logins e conteúdo dinâmico ainda podem variar entre os dois WebKit; cliques disparados via JS podem ser rejeitados por segurança dos sites.
5. **Câmera e mãos:** iPhone sem LiDAR mede apenas pose + 21 joints 2D, estimando Z da mão; VR Box pode bloquear a câmera traseira. Seleção das poltronas por olhar é o fallback do Cinema.
6. **FPS/temperatura/oclusão de mão:** sem métricas coletadas no dispositivo real, não há comprovação de estabilidade em sessões longas.
7. **ARKit relocalizando:** ao voltar do background, o app evita resetar as âncoras, mas ARKit pode perder o mundo dependendo da iluminação e movimento. Recentrar permanece disponível.
8. **IPA unsigned:** não instala diretamente sem assinatura e não atualiza código automaticamente.

**Status correto:** correções implementadas e verificações de build/lógica automatizadas; aprovação final da experiência VR depende dos testes do usuário com o headset.
