# Renderização binocular da Etapa 1

A cena usa metros, vetores-coluna e um espaço destro: +X direita, +Y cima e -Z frente. O centro da cabeça fica em `(0, 1.65, 0)`; não há rastreamento de posição. O renderer lê uma única orientação imediatamente antes de codificar os dois olhos. Assim, a base estéreo não muda entre as duas passagens.

Para uma orientação `R` e um IPD `d`, os centros das câmeras são:

```
E_esquerdo = H + R * (-d/2, 0, 0)
E_direito  = H + R * (+d/2, 0, 0)
V_olho    = inversa(R) * translação(-E_olho)
```

As câmeras permanecem paralelas. O renderer usa perspectiva por olho, teste de profundidade e geometria de verdade; a disparidade diminui com a distância. Não existe convergência por inclinação das câmeras, que poderia introduzir disparidade vertical. O plano próximo é 5 cm e o distante 80 m. A matriz projeta profundidade no intervalo Metal `[0,1]`.

Cada olho tem uma textura privada de cor e uma de profundidade. Um único buffer imutável contém a geometria estática; somente a matriz de cada olho muda a cada frame. A resolução interna é a resolução de cada metade física multiplicada pela escala de renderização. O centro óptico horizontal controla o ponto principal da projeção e o centro da distorção, nas mesmas coordenadas normalizadas de cada olho.

A composição ocorre na resolução nativa do drawable, sem margens de safe area. `0..<width/2` pertence ao olho esquerdo e `width/2..<width` ao direito; até larguras ímpares ficam sem lacunas. Cada passagem de composição amostra apenas sua própria textura, evitando vazamento entre olhos.

O shader calcula um raio em coordenadas isotrópicas e usa amostragem inversa:

```
r² = dot(2*(uv-centro)*(aspect,1), 2*(uv-centro)*(aspect,1))
f  = 1 + intensidade*(k1*r² + k2*r⁴)
uv_fonte = centro + (uv-centro)*f/escala_óptica
```

Coordenadas fora da textura ficam pretas. Com coeficientes positivos, a imagem recebe uma pré-deformação tipo barril para compensar lentes com distorção tipo almofada. O perfil genérico é provisório, sem medição de um modelo específico. O modelo não corrige aberração cromática, distorção tangencial nem diferenças verticais de centros; precisa de avaliação física antes de se afirmar qualidade óptica.

O `MTKView` solicita 60 frames por segundo. Duas submissões podem ficar em voo; se ambas estiverem ocupadas, a nova submissão é descartada sem bloquear a thread principal ou acumular poses antigas. Texturas substituídas num resize permanecem válidas para comandos já enviados. O renderer não retém o `MTKView` e os handlers da GPU usam referência fraca ao renderer.

A escala configurada é limitada a `0.7` sob condição térmica `serious` e `0.5` sob `critical`. A recuperação espera 20 segundos após a saída da condição mais restritiva para evitar trocas frequentes de texturas. A escala efetiva aparece nas métricas.

FPS indica a taxa de frames submetidos; CPU indica o custo de codificação até a submissão, suavizado; GPU indica o intervalo `GPUEndTime-GPUStartTime` do último command buffer concluído quando disponível. Esses dados não medem a latência movimento-fóton, scanout ou conforto. Instrumentação física continua necessária.
