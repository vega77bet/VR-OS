# VR-OS V16 (4.2.0) — revisão de estabilidade e imersão

> Status: **compilação iOS** automatizada no GitHub Actions. O uso físico no iPhone 15/VR Box e a reprodução de Netflix/YouTube/Twitch **não foram garantidos nem testados aqui**.

## Problemas corrigidos no código

| Relato/risco | Mudança | Validação necessária |
| --- | --- | --- |
| Cinema baixo, apontando fora do telão | V15 calcula yaw e pitch para mirar o centro do telão a partir de cada uma das 72 cadeiras; V16 mantém o sistema | Olhar realmente para o centro depois de abrir e de trocar de cadeira |
| Direção invertida ao virar cabeça | V15 ajustou base de movimento no Landscape Left/Right e oferece opção *Mov.: normal/inverso* | Giro real à esquerda, direita, cima e baixo |
| Visão estreita/cortada | Câmeras SceneKit usam FOV **horizontal explícito** em vez de depender da projeção vertical padrão; valor MAX inicial 88°, ajustável entre 55°–115° | Ajustar FOV no headset, conferir conforto e se a tela cabe no campo visível |
| Estéreo desconfortável ao virar cabeça | As duas câmeras agora são filhas do **mesmo headRig**, com separação IPD local de 64 mm que gira junto com a cabeça | Conferir fusão das imagens e sensação de profundidade |
| Poltronas só com toque/pinça | Indicadores permitem **olhar por 1,5 s** para uma bolinha e selecionar, com progresso em anel sincronizado nos dois olhos | Testar no headset; olhar fixamente por 1,5 s |
| YouTube/sites minúsculos | Mantém janela maior e zoom da V13 e inclui **Modo Foco**, ocupando praticamente toda a viewport por olho | Conferir tamanho e legibilidade nos óculos |
| Sem clique/rolagem sem tocar no telefone | **Pinça curta** sobre página dispara clique DOM; **segurar pinça e mover verticalmente** rola página, espelhando ao segundo olho | Sites complexos podem exigir toque físico: eventos sintéticos de JS não são eventos de toque confiáveis |
| App errado escolhido pelo gesto | Corrigida geometria do menu de apps para a quantidade real de opções e slider | Abrir cada opção via gesto de pinça |
| Dock cobrindo janelas/alça | Dock minimiza em um **botão no canto inferior esquerdo**, aberto por toque ou pinça | Testar alcance e arraste da linha branca |
| Travamentos/aquecimento | Ao entrar no Cinema, conversão desnecessária de pixels da câmera AR para CGImage é suspensa; a pose e a mão continuam atualizadas; home reduz frequência da cópia da câmera; até 3 sites abertos ao mesmo tempo | Monitorar FPS, bateria, calor e memória num teste longo |

## Extras

- Novos apps web: **Twitch** e **Wikipedia** (além de YouTube, Netflix e Navegador).
- **Modo Foco** em janela web: ícone de expandir no cabeçalho; o mesmo ícone restaura o layout normal. Fecha outras janelas da visualização, não as sessões salvas.
- Zoom de janelas web **65–155%**, agora persistido nos ajustes do aparelho.
- O Cinema mantém os modos 2D, SBS, H-SBS, OU, importação da Fototeca, poltronas e vídeo MP4.
- Controles do Cinema desaparecem automaticamente após 5 s de reprodução e reaparecem ao tocar ou abrir Menu.
- Mensagem de limite de sessões para evitar abrir vários navegadores com dois WebKit por app.

## Teste mínimo no iPhone + VR Box

1. Assinar/instalar o **IPA unsigned**. Colocar o iPhone no VR Box na orientação horizontal.
2. Abrir **Cinema** e tocar **Centralizar** enquanto olha reto. O centro do telão deve estar à frente. Se preciso: **Mirar tela** e **Tela ↑ / ↓ / ← / →**.
3. Virar a cabeça nos quatro sentidos. A visão deve acompanhar o mundo, não mexer no sentido oposto. Se tudo estiver invertido, testar **Mov.: inverso**.
4. Pressionar **Assentos**. Olhar fixamente para uma bolinha por aproximadamente 1,5 s, observar o anel amarelo se completar e conferir que teletransportou ao lugar certo. Repetir por pinça/toque.
5. Iniciar MP4, confirmar que controles somem após ~5s, e ajustar **FOV − / +** sem desconforto.
6. Voltar ao Home, abrir **Apps > YouTube**. Expandir no cabeçalho e confirmar se o campo visual melhora. Tocar em links com pinça curta; rolar segurando pinça e movimentando a mão. Reabrir Dock no canto inferior esquerdo.
7. Testar Wikipedia/Navegador e Twitch. A reprodução de vídeo protegido pode falhar na WebView; neste caso, o botão Safari permanece como alternativa.
8. Abrir até três sites. Ao tentar o quarto, verificar se aparece aviso; fechar um e abrir outro.
9. Deixar em uso por 10–15 minutos, observando aquecimento, travamentos e atraso na cabeça. **Parar imediatamente se causar tontura, náusea ou desconforto visual.**

## Limites reais

- O projeto **não altera o campo de visão óptico** das lentes do VR Box, nem transforma a câmera traseira monocular em duas câmeras estéreo.
- CoreMotion, ARKit, foco binocular e compatibilidade com DRM exigem teste em aparelho real; compilar corretamente **não prova ausência de bugs**.
- WebKit em cada olho usa duas visualizações web independentes; vídeos e sites dinâmicos podem não ficar perfeitamente sincronizados. O Cinema nativo é recomendado para MP4 SBS.
- Pinça depende de a câmera traseira conseguir enxergar a mão. **Seleção de assentos por olhar** funciona sem pinça enquanto o modo Assentos estiver aberto.
- Sites com políticas rígidas de segurança podem rejeitar clicks sintéticos de JavaScript; botões e pesquisas por teclado podem exigir toque físico no telefone.
- O sistema é um aplicativo iOS com interface VR, não substitui o sistema operacional do iPhone.
