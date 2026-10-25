# VR-OS Cinema 3D — versão 8 experimental

Esta branch parte da sala VR-OS Cinema V2, preservando luzes, assentos,
AVPlayer local, ARKit e o visor VR Box lado a lado.

## Como testar

1. Gere e assine o IPA de teste, instale no iPhone 15 e coloque-o no VR Box.
2. Abra **Cinema > Filme** e importe um MP4, M4V ou MOV compatível.
3. Selecione o modo da fonte: **2D**, **SBS** (duas imagens completas lado a lado),
   **H-SBS** (duas imagens com meia largura, lado a lado), ou **OU** (imagem superior
   para o olho esquerdo e inferior para o direito).
4. Teste usando um vídeo de referência estereoscópico licenciado ou criado por você
   para verificar qual olho recebe qual imagem. Confirme profundidade e proporção.
5. Use pausar, voltar/avançar 10 segundos e sair como na versão anterior.

## Implementação

Um único AVPlayer fornece o vídeo aos materiais das duas telas SceneKit. Cada
tela possui máscara de categoria própria; as câmeras esquerda e direita mostram
somente sua respectiva tela. O recorte de textura escolhe a metade correspondente
do filme; no H-SBS o filme é expandido para sua proporção original.

## Limitações ainda não verificadas

- **Não há confirmação de funcionamento no dispositivo real**; o desempenho e
  compartilhamento de textura AVPlayer entre materiais exigem teste físico.
- **MKV não está implementado**: a versão atual precisa de contêiner compatível
  com AVPlayer ou de uma integração futura com decodificador apropriado.
- A intensidade de objetos “saindo da tela” depende da disparidade do filme, da
  distância virtual da tela e do ajuste óptico do VR Box.
- A versão inicial não ajusta separadamente a convergência/disparidade do filme.
  O modo estéreo da sala virtual usa separação das câmeras de 64 mm.
