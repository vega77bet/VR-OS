# VR-OS Vision Calibration

O módulo `VR-OS Vision Calibration` ajusta a apresentação de cada metade do
frame SBS no compositor Metal existente. Ele não mede o IPD anatômico, a
posição das lentes ou a fusão cerebral: todos os valores são ajustes manuais e
reversíveis para compensar pequenos erros do conjunto iPhone/VR Box.

## Fluxo do frame

O tracking fornece uma pose tardia comum aos dois olhos. `StereoCamera` ainda
cria duas câmeras paralelas, deslocadas por `ipdMeters`; portanto a calibração
não copia uma imagem para o outro olho e não remove a disparidade 3D. Cada olho
é renderizado em sua própria textura de cor e profundidade, junto com o Home e
suas janelas espaciais. O compositor chama `LensDistortionRenderer.encode`
uma vez para cada metade física do drawable:

```
pose -> câmera esquerda/direita -> textura esquerda/direita
     -> UI espacial -> pré-distorção inversa por olho -> SBS
```

O viewport esquerdo é `0 .. width/2` e o direito é `width/2 .. width`, sem
textura ou amostra compartilhada entre eles.

## Coordenadas e ordem matemática

`horizontalOffset`, `verticalOffset` e `opticalCenterX/Y` usam UV normalizada da
textura de **um olho**. X cresce para a direita e Y para baixo. `imageScale` é
adimensional; rotação está em graus no perfil e em radianos no uniform. K1–K3,
P1/P2 e os fatores cromáticos são adimensionais. IPD está em metros e o centro
de projeção X usa UV da câmera, separado do centro óptico do pós-processamento.

Para cada pixel de destino o shader executa amostragem inversa, nesta ordem:

1. subtrai centro óptico e deslocamento da imagem;
2. aplica a rotação inversa;
3. normaliza pelo aspect ratio;
4. aplica `r² = x²+y²`, `1 + K1*r² + K2*r⁴ + K3*r⁶` multiplicado por
   `distortionStrength`;
5. aplica tangencial Brown–Conrady (`P1`, `P2`);
6. aplica o pequeno fator radial do canal vermelho ou azul, mantendo verde como
   referência;
7. reposiciona o resultado pela escala horizontal/vertical do olho;
8. amostra somente a textura do olho atual.

A escala é deliberadamente aplicada depois da pré-distorção. Essa ordem preserva
as calibrações legadas e mantém escala e correção da lente como operações
separadas; a referência CPU e o shader usam a mesma sequência.

Com `distortionStrength = 0`, deslocamentos, escalas, rotação neutra, centros
em 0,5 e cromática 1, o mapeamento é identidade. UVs fora de `[0,1]` tornam o
pixel preto; elas nunca atravessam para a textura do outro olho. A mesma
transformação está implementada em `VisionCalibrationMath.sourceUV` para
testes determinísticos.

## Assistente e interação

`VisionCalibrationSession` mantém um snapshot transacional, pilha de desfazer e
baseline por etapa. `VisionCalibrationView` fornece o assistente nativo para a
preparação e revisão fora do visor. O painel espacial `Calibração` usa a mesma
ação `SpatialAction` e pode ser operado pela mira de permanência ou por
GameController/Joy-Con dentro do VR Box. O alvo geométrico (cruz, círculos,
quadrado e grade) é desenhado pela `SpatialUIRenderer` e recebe as duas
projeções e o compositor real.

As etapas são: preparação, alinhamento esquerdo, alinhamento direito, fusão,
escala/rotação, centro óptico, distorção radial/tangencial, cromática,
legibilidade e validação. A sessão oferece preview imediato, comparar
antes/depois, desfazer, restaurar etapa, restaurar olho, restaurar tudo,
cancelar e salvar. No painel sem touchscreen, “menor/maior” altera escala
horizontal e vertical juntas; restaurar proporções retorna ambos os eixos a
1.0. Os controles separados horizontal/vertical continuam disponíveis no modo
avançado. `Y`/recenter e o botão nativo de recuperação continuam disponíveis;
o perfil genérico não pode ser excluído.

## Perfis e migração

`VRCalibrationManager` continua sendo a única fonte de verdade consumida pelo
renderer. O envelope persistido usa `UserDefaults`, Codable, versão de
persistência 3 e perfis nomeados (`VisionCalibrationProfile`). O perfil antigo
com `leftCenterX`, `rightCenterX`, `leftScale`, `rightScale`, `distortionK1`,
`distortionK2` e `distortionStrength` é lido por `VRLensProfile` e migrado para
os parâmetros independentes dos olhos. Dados inválidos são validados, finitos e
limitados antes de chegar à GPU. Falha de decodificação volta ao padrão seguro.

## Texto e cintilação

A correção binocular não é tratada como correção de texto. O atlas de glifos e
SF Symbols é imutável, usa células com margem UV de dois pixels, textura
mipmapped e filtragem mip linear, sem rasterização de strings por frame. O
sampler seleciona os níveis mip durante a minificação; criar os níveis sem
selecioná-los deixaria o texto preso ao nível base e sujeito a shimmer. O ajuste
de resolução é separado dos parâmetros ópticos. O comportamento final de
shimmer, foco físico e legibilidade deve ser avaliado no iPhone dentro do VR
Box; o CI não consegue medir essas propriedades.

## Limites físicos

Os limites conservadores corrigem pequenos desalinhamentos. Lente fora do foco,
inclinação grande, aberração severa, erro de montagem ou dificuldade de fusão
que persista após restaurar e ajustar não podem ser eliminados por software.
Não há detecção automática da fusão humana nem medição do IPD real.

## Testes e build

`Tests/VisionCalibrationTests.swift` cobre identidade, sinais, escala, rotação,
centro, radial/tangencial, cromática, valores inválidos, migração, undo,
cancelamento, commit, perfis e recuperação. `MetalRenderingTests` valida o ABI
dos uniforms e os passes SBS reais quando Metal está disponível. O workflow
`.github/workflows/ios.yml` executa os testes macOS/iOS e publica **somente**
`VROS-unsigned.ipa` como artefato. Sem certificado Apple, esse IPA é um pacote
não assinado e precisa ser assinado pelo Sideloadly/AltStore com uma conta
válida antes da instalação.

Validação CI registrada em 1 de novembro de 2026: [run 41280649952](https://github.com/vega77bet/VR-OS/actions/runs/41280649952). O run executou 94 testes macOS e 107 testes iOS no simulador, todos aprovados, além de gerar o IPA não assinado com o sampler mip linear ativo e escala proporcional operável no painel espacial.
O run compilou o target iOS para dispositivo sem assinatura. O resumo oficial do
Xcode registrou **94 testes macOS passados, 0 falhas, 0 ignorados** e **107 testes
iOS no simulador passados, 0 falhas, 0 ignorados**. O run exportou a captura GPU
e publicou `VROS-unsigned.ipa` como o único arquivo do artefato. Não houve teste
físico no iPhone 15 ou no VR Box neste ambiente.
