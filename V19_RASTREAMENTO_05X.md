# VR-OS V19 — rastreamento real em 0,5x (iPhone 15)

Versão nativa **4.5.0 / build 19**.

## É tecnicamente possível?

**Sim, parcialmente.** A ultrawide continua sendo o dispositivo físico
\`AVCaptureDevice.DeviceType.builtInUltraWideCamera\`. Os **mesmos buffers de vídeo**
que exibimos no VR Box agora são encaminhados a
\`VNDetectHumanHandPoseRequest\` (Vision). O giroscópio e acelerômetro integrados
são lidos por \`CMMotionManager\` para orientação relativa (**3DoF**).

O resultado **não é 6DoF ARKit**: não há SLAM, posição 3D da câmera em metros,
profundidade real da mão, detecção de planos nem persistência espacial.

## O que foi implementado

1. **0,5x real**: vídeo de câmera traseira \`builtInUltraWideCamera\` via
   \`AVCaptureSession\`, exibido em duas metades VR.
2. **Rastreamento Vision em 0,5x**: detectar 21 articulações quando visíveis,
   cursor de dedo indicador e esqueleto desenhados em ambos os olhos.
3. **Pinça em 0,5x**: cálculo de distância normalizada entre polegar/indicador
   com histerese (ativar ~0,43 palma, soltar ~0,64) e confirmação em dois
   quadros; quando mão desaparece, gesto e arraste são liberados.
4. **Interação com janelas**: pinça nos botões dos menus, scroll de textos,
   zoom do navegador, clique/scroll nos sites (cliques DOM sujeitos a limites
   de WebKit) e movimento das janelas na alça branca. Em 0,5x a janela se move
   em **2D/angular**, não em distância física real.
5. **Orientação da cabeça 3DoF**: CoreMotion atualiza quaternion relativo ao
   enquadramento original; painéis mantêm direções angulares aproximadas e
   saem do centro da tela quando o usuário vira a cabeça.
6. **Controle de calibração**: barra do topo "Mira" recentraliza orientação e
   janelas; "Mov."/"Inv." inverte o sentido do giro (preferência persistente).
7. **Campo de visão**: "Tela toda" usa imagem \`scaledToFit\` para mostrar toda
   a captura ultrawide, podendo deixar barras pretas grandes por olho.
   "Preencher" usa \`scaledToFill\` e amplia a imagem, mas CORTA laterais:
   por isso o padrão V19 é mostrar a imagem completa.
8. **Troca de câmera segura**: ao voltar ao ARKit, desliga a
   \`AVCaptureSession\` e só então retoma o rastreamento 6DoF.
9. **Cinema**: mantém modo nativo baseado em ARKit. Se "Cinema" for acionado
   enquanto 0,5x está ativo, a tela explica que é necessário voltar ao ARKit.
10. **Bateria e CPU**: Vision roda em fila separada (~10 fps) com descarte
    de solicitações quando está ocupada. CoreMotion ~30 Hz. Não gera frames
    adicionais somente para rastrear a mão.

## Testes automatizados

GitHub Actions compila target iPhone Release e testa, em Swift/macOS:
- 3DoF: ray/project bijetivos nos pontos do visor, gira com cabeça, painel
  não aparece atrás da câmera.
- Pinça Vision: debounce de dois quadros, histerese, soltura e reset.
- Demais testes de janelas, botões, Cinema e 72 cadeiras da V17.

**Não confundir teste lógico com teste físico**: a Vision só funciona quando
a ultrawide pode VER a mão no enquadramento. O próprio VR Box pode tapar a
lente traseira, o campo pequeno por olho dificulta selecionar alvos e baixa
luz pode reduzir a precisão. É possível haver inversão em orientação física:
a opção "Mov./Inv." facilita o ajuste.

## Roteiro físico

- [ ] Instalar IPA V19 assinado no iPhone 15.
- [ ] Entrar no VR-OS e acionar 0,5x no dock (sétimo botão); verificar que é
      a lente ultrawide verdadeira. A tela começa em "Tela toda".
- [ ] Mostrar a mão em frente à **lente traseira descoberta**; confirmar que
      aparecem 21 juntas/contorno e o cursor em ambas as telas.
- [ ] Juntar polegar e indicador duas vezes de modo deliberado; confirmar que
      o cursor aumenta e consegue acionar um item de menu.
- [ ] Usar pinça sobre a linha branca de uma janela e movê-la; depois testar
      scroll de texto e botões WebKit.
- [ ] Virar a cabeça esquerda/direita/cima/baixo, observando se as janelas
      parecem fixas em DIREÇÃO. Ajustar Mov./Inv. se necessário.
- [ ] Apertar "Mira" e confirmar que volta a centralizar os painéis.
- [ ] Testar "Preencher"/"Tela toda"; confirmar trade-off de campo vs tamanho.
- [ ] Voltar ao ARKit e confirmar reaparecimento de janelas com rastreamento
      espacial. Cinema precisa desse modo.
- [ ] Testar temperatura, bateria, latência e estabilidade 10–15 minutos.
      Pare imediatamente se houver tontura ou desconforto visual.

## Limites que permanecem

- **Não há ARKit simultâneo com ultrawide** na arquitetura atual: a câmera
  traseira é entregue à captura ultrawide e o rastreamento 6DoF fica pausado.
- Janelas ficam estáveis apenas em **3DoF angular**, não posicionadas com
  precisão num ambiente real ao andar para os lados.
- Coordenadas angulares são aproximadas (FOV de projeção virtual 82°,
  sem calibração ótica); a sensação binocular depende das lentes do headset.
- Video web protegidos por DRM podem falhar em \`WKWebView\`.
- O IPA fornecido é **sem assinatura** e exige assinatura para instalação.


### Mapeamento do cursor quando mostrar todo o vídeo

A imagem real 0,5x é **letterboxed** por olho ao selecionar "Tela toda".
A posição dos 21 pontos da mão desenhados mantém as coordenadas da
imagem. Já o **cursor de interação** é expandido proporcionalmente à
viewport inteira do olho, para permitir alcançar botões no topo e dock
embaixo que de outra forma ficariam fora do quadro letterboxed. Portanto,
nesse modo a posição do cursor **não corresponde exatamente ao dedo na
imagem**: é um controle por gesto normalizado, não sobreposição calibrada.
"Preencher" volta ao mapeamento do cursor correspondente à imagem cortada.
