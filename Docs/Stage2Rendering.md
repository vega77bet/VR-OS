# Home espacial e renderização

O renderizador da Etapa 1 mantém as duas câmeras, a leitura única de pose por frame e a correção óptica. A cena inicial passa a usar `HomeEnvironment`: praça circular, céu em degradê de vértices, horizonte e relevo em 360°, pavilhões e esculturas discretas em várias distâncias. São 13.830 vértices imutáveis; não há imagem panorâmica esticada. Iluminação ambiente, faces e sombras de contato são aproximações por cores/geometria, sem shadow maps ou iluminação global.

`SpatialUIRenderer` recebe um `SpatialRenderFrame` depois da atualização de entrada. Gera uma malha em coordenadas de mundo, reutilizada pelos dois olhos com suas respectivas matrizes de vista/projeção. Janelas usam posição, quaternion, dimensões e raio de canto do mesmo modelo usado pelo raycaster. O fundo está no plano local Z=0; as superfícies de botões estão em Z=0,008 m e o texto em Z=0,011 m. Os cantos são tesselações de círculos com 16 segmentos por quadrante.

Painéis escuros e elementos têm alpha premultiplicado e são desenhados do mais distante ao mais próximo, com teste de profundidade contra o cenário e sem gravação de profundidade transparente. O feedback de foco interpola em 75 ms; abertura/fechamento e posição são controlados pelo modelo espacial. Não há uma camada UIKit duplicada para os olhos.

Texto Latin e símbolos SF Symbols são rasterizados uma vez em um atlas imutável de 2048×2048, em formato padrão de 8 bits. Cada string é composta de quads de glifos desse atlas. Horário, bateria e nomes não criam texturas novas. O atlas tem capacidade fixa de 256 células; caracteres não representados usam `?` e símbolos desconhecidos usam um quadrado. SF Symbols são recursos públicos do sistema Apple, não elementos copiados de interfaces Meta.

O laser branco é geometria 3D: núcleo fino, halo discreto e ponto na interseção. A mira de cabeça usa anéis geométricos na profundidade do ponto atingido, incluindo o progresso de permanência. Os dois são projetados pelas câmeras reais de cada olho. A origem do controle é virtual e não representa posição física 6DoF.

Há um passe de cenário e um draw de UI por olho, seguido pelo compositor óptico existente. Três buffers de vértices são reutilizados com no máximo dois frames em voo. A malha CPU mantém capacidade entre frames; o atlas e o ambiente não são reconstruídos durante a renderização. O custo de transparência, geometria dinâmica e as fontes precisam ser medidos no iPhone 15; esses mecanismos não constituem garantia de 60 FPS.

`SpatialMetalTests` verifica o shader real, o ABI dos vértices, a disparidade de um painel em renderização offscreen, os cantos arredondados e pixels de texto/símbolos. Testes de GPU são explicitamente pulados quando Metal não está disponível; aprovação de conforto e leitura através do VR Box depende do aparelho.
