# VR OS Spatial 2 (Web)

Versão experimental para navegador, preparada para **iPhone na horizontal**.
A interface é um ambiente de janelas 3D angularmente ancoradas por **orientação do telefone** (DeviceOrientation), com câmera traseira ocupando a tela inteira. É **passthrough experimental**, não ARKit.

## Funções implementadas

- Janela espacial com projeção em perspectiva, direção fixa relativa ao movimento do telefone, foco, arrastar por toque, redimensionar, minimizar, expandir, fechar, recentralizar e restaurar parte da sessão.
- Dock espacial com acesso alternativo aos apps no topo caso ele saia do campo de visão.
- Seleção 0,5x por nome do dispositivo, tentando zoom mínimo quando suportado; retorno automático à traseira se a troca falhar.
- Controle de até duas mãos com MediaPipe Tasks Vision 1.1.1: cursor estável, pinça com histerese, clicar, arrastar, duas mãos para redimensionar; sem máscara de silhueta artificial. A câmera é compartilhada com o ambiente.
- Notas autossalvas; calculadora com parser sem `eval`; relógio e cronômetro; calendário e eventos; arquivos binários, imagens e áudios guardados em IndexedDB com fallback temporário em memória; captura de fotos; configurações; gerenciador de janelas; diagnóstico e PWA.
- Tema premium minimalista, confortável em orientação paisagem, controles com alvos maiores e suporte a retrato/desktop.

## Como testar

Abra a URL **HTTPS no Safari**, na horizontal. Toque em **Iniciar câmera e espaço**, aceite câmera e movimento. Para recente­ralizar, use o ícone de foco no topo. Se a lente 0,5x não estiver disponível, alterne pelo ícone de câmera ou em Ajustes.

### Desenvolvimento local

Na pasta `web`, execute `python3 -m http.server 8000` e abra `http://localhost:8000` no computador (o acesso remoto à câmera exige HTTPS).

### Smoke tests

Instale Playwright e o Chromium correspondente, depois execute `python tests/test_suite.py`.
Os testes usam câmera sintética e cobrem paisagem/retrato/desktop, criação/fechamento/minimização de janelas, calculadora, notas, orientação/recentralização, câmera, calendário, foto, gerenciamento de janelas e pinça simulada.

## Limitações importantes

- O Safari oferece câmera e `DeviceOrientation` conforme permissões, **não ARKit para ancoragem física de pontos na sala**. As janelas ficam fixas em **direções**, mas não sabem se o telefone andou 1 metro.
- A oclusão real entre mão e janela e a profundidade física não estão disponíveis na versão web; o recorte artificial foi removido por causar distorções.
- A câmera 0,5x depende de Safari/iOS exporem a lente ou capacidades de zoom; selecionar a opção não garante lente ultrawide em todo dispositivo.
- O controle por mãos depende de baixar inicialmente a biblioteca e o modelo MediaPipe; a performance e os gestos precisam ser validados no iPhone real.
- Ao perder permissão de câmera ou mudar de dispositivo, o usuário pode precisar reativar os gestos. Alguns arquivos são mantidos apenas em memória quando IndexedDB não está disponível.
- A PWA pode funcionar offline para a interface previamente carregada, mas o rastreamento das mãos precisa do modelo em cache ou de conexão.

## Privacidade

A imagem da câmera é analisada localmente no navegador para visualização e gestos. A biblioteca MediaPipe é carregada de CDN. Não há backend para upload automático de fotos, arquivos ou transmissão da câmera.
