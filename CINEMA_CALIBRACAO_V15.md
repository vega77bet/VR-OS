# VR-OS V15 — Cinema: calibração e testes reais

Esta versão é uma correção de código, **não uma confirmação de que os sensores foram validados num iPhone com VR Box**.

## Corrigido no código

- A direção inicial de cada poltrona passa a ser uma rotação em 3D que mira no **centro exato do telão**, levando em conta a posição horizontal e a altura da cadeira. A V14 calculava apenas a inclinação vertical.
- O delta do CoreMotion é referenciado à atitude de entrada/recentralização e convertido dos eixos do iPhone para os eixos do display, respeitando **Landscape Left** e **Landscape Right**.
- O padrão deixa de inverter arbitrariamente todos os eixos do quaternion. Há um botão reversível **Mov.: normal / Mov.: inverso**.
- Caso os sensores não estejam disponíveis ou parem de enviar amostras, a orientação relativa do ARKit é usada como fallback quando há tracking.
- Botões manuais **Tela ↑ / ↓ / ← / →**, **Mirar tela** (zera correções laterais/verticais) e **Centralizar** (redefine cabeça na direção atual).
- Ângulo de visão virtual do Cinema ajustável em 55°–105° por **FOV − / FOV +**. Valor inicial 78° no modo MAX; MAX desligado usa +12°.
- Com filme reproduzindo, controles desaparecem após aproximadamente 5 segundos. Toque no Cinema ou em Menu para exibi-los novamente.

## Como confirmar no iPhone

1. Instale uma versão **assinada** da V15. O artefato do GitHub Actions é propositalmente **unsigned**.
2. Com o iPhone na orientação horizontal que você usará no VR Box, abra **Cinema**, fique olhando para frente e toque **Centralizar**.
3. A imagem do Cinema deve mostrar o centro do telão. Se não mostrar, toque **Mirar tela**; use as setas para corrigir ângulo e direção.
4. Vire a cabeça para a direita: a visão deve acompanhar a cabeça e revelar o lado direito da sala (as imagens da sala movem-se para a esquerda na tela). Repita para a esquerda, para cima e para baixo. Se todos os eixos estiverem reversos, toque **Mov.: inverso**. Se apenas um eixo estiver errado, relate qual e em qual orientação do iPhone; não dá para concluir sem teste real.
5. Mude para uma poltrona lateral: depois da animação, a câmera deve mirar no centro do telão, não nas cadeiras.
6. Importe um MP4, reproduza, espere aproximadamente 5 segundos e verifique se os controles somem. Use Menu para reabrir.
7. Ajuste **FOV − / +** até o filme ficar confortável e visível pelas lentes, sem forçar os olhos.
8. Teste um vídeo de 10 minutos: observe latência do movimento, travamentos, aquecimento e bateria. Se houver tontura ou desconforto, interrompa o teste.

## Limites

- Alterar FOV virtual **não aumenta o campo óptico físico** das lentes do headset.
- Sem dispositivo físico não dá para garantir direção real dos eixos, latência, conforto ou posicionamento ótico.
- A pinça depende de a câmera traseira conseguir enxergar a mão; o suporte do VR Box pode obstruí-la.
- Os sites YouTube e Netflix continuam sujeitos a políticas de reprodução/DRM das plataformas.
