# VR-OS Cinema 3D — testes no iPhone e VR Box

Esta versão experimental foi implementada sobre a sala Cinema V2. As duas câmeras continuam compartilhando a sala SceneKit, mas cada olho agora possui sua própria tela de filme e material. Um único AVPlayer abastece as duas telas com tempo de reprodução sincronizado.

## Formatos de vídeo

- **2D**: ambas as lentes recebem o mesmo quadro.
- **SBS**: dois quadros lado a lado, cada quadro com resolução horizontal completa (por exemplo, arquivo 3840 × 1080 para dois quadros de 1920 × 1080).
- **H-SBS**: dois quadros lado a lado com metade da resolução horizontal (por exemplo, arquivo 1920 × 1080 com duas imagens comprimidas de 960 × 1080). O cinema estica visualmente cada olho ao aspecto original.
- **OU**: quadros empilhados verticalmente; aceita aspecto alto de Full OU (1920 × 2160) e aspecto normal de Half OU (1920 × 1080).
- Os recortes de vídeo são feitos com transformações de coordenadas UV; não exigem dois reprodutores e podem ter sua ordem invertida.

## Passo a passo

1. Assine e instale o IPA sem assinatura baixado do GitHub Actions.
2. Abra o Cinema e importe um MP4/M4V/MOV local pelo botão **Filme**.
3. Escolha o modo **H-SBS** para o vídeo de teste sintético fornecido em separado. O player também tenta detectar H-SBS/SBS pelo nome do arquivo.
4. Ative **MAX ON** para aproximar o assento da tela e ocupar mais do campo de visão.
5. Se a profundidade parecer invertida, use **Trocar olhos**. Para suavizar desconforto, use **3D −/3D +** com ajustes pequenos.
6. Confira a imagem nas duas lentes, a sincronização, as bordas da tela, possíveis travamentos e o consumo de bateria.
7. Teste um filme 2D para garantir que a reprodução convencional permaneceu intacta.

## Limites de compatibilidade

**MKV ainda não é suportado** pelo AVPlayer utilizado nesta versão. Não basta aceitar a extensão no app Arquivos: é necessário incorporar um demuxer/decodificador independente (por exemplo, libVLC) ou converter legalmente o arquivo para MP4 mantendo os dois quadros estereoscópicos. A próxima etapa será avaliar libVLC antes de prometer MKV como funcional.

O efeito de algo sair da tela já é codificado nas diferenças entre os dois olhos do arquivo 3D, não é gerado pelo VR-OS. Ainda não houve teste físico no iPhone 15 + VR Box. Compilar com sucesso não comprova que o material com AVPlayer será renderizado nas duas telas sem problemas. Interrompa o uso se provocar cansaço visual ou tontura.

Este modo reproduz filmes estereoscópicos em uma tela 3D virtual, não vídeos VR 180/360 esféricos.
