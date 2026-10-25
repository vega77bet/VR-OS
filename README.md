# VR-OS 3.0 — ancoragem espacial + estimativa monocular de profundidade

Protótipo **experimental** de realidade mista para iPhone 15 (não Pro) + VR Box.

## O que mudou nesta branch
- Uma única **ARSession** fornece os quadros da câmera. O mesmo CGImage é mostrado nos dois olhos: evita a dupla camada de prévia que podia deixar o olho esquerdo preto.
- **ARKit World Tracking** fornece a pose 6DoF do telefone; cada janela guarda um ponto no **sistema de coordenadas do ARKit** e se mantém naquela posição enquanto a sessão rastreia bem.
- **Vision** detecta 21 pontos em 2D: pulso e articulações dos cinco dedos. Esqueleto desenhado em ambas as metades.
- Estimativa **aproximada** de Z da mão usando tamanho aparente da palma e intrínsecos da câmera; filtrada e limitada a 0,30–3,50 m. A largura real da palma é presumida em 8,5 cm, por isso não é medida confiável.
- Pinça seleciona e move janela em X/Y. Movimento aproximado da mão em Z desloca a janela ao segurar pinça.
- Barra inferior em cada janela com controle de distância (0,65–4 m). Visual em cinza/grafite, sem azul.
- A dock cria janelas e recentraliza as existentes diante da pose atual.

## Limitações importantes
- O iPhone 15 padrão **não possui LiDAR**. A mão e dedos **não** têm coordenadas 3D individuais reais: há 21 articulações 2D mais **um único Z estimado para a mão**; dedos apontados/rotacionados podem distorcer a estimativa.
- A câmera traseira é **monocular**. Ambos os olhos veem a mesma imagem real; apenas as janelas têm disparidade estimada para criar profundidade.
- Os pontos das janelas são locais à sessão, não anchors persistentes em mapa de ambiente; **reiniciar perde as posições**. ARKit pode derivar ou perder tracking em locais sem textura/pouca luz.
- ARKit e imagem de câmera são assumidos na orientação paisagem-direita; alinhamento e rotação podem precisar de calibração para modelos de iPhone e VR Box.
- Decodificar frames de ARKit em CGImage e processar Vision pode aumentar consumo de bateria e latência.
- O IPA produzido pelo Actions é **sem assinatura**. É preciso assinar/instalar via AltStore ou ferramenta apropriada. **Não é atualização OTA automática**.
- Não executa aplicativos iOS em janelas.
- Compilação CI **não substitui validação real no aparelho**. O alinhamento e gestos precisam de testes.
- Utilize sentado/parado e em local sem obstáculos.

## Build
XcodeGen e GitHub Actions em macOS constroem o app iOS e publicam o IPA sem assinatura nos artifacts da execução.
Bundle ID preservado da versão anterior para facilitar atualização via assinatura com o mesmo identificador.

## Segurança / privacidade
Os quadros de câmera e hand tracking são processados localmente; este protótipo não os envia a servidores.
