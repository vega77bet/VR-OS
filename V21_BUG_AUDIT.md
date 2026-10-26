# V21 — revisão de bugs e validação

Branch de trabalho: `vr-os-21-native-settings-app`. Base auditada: `442415ce9171fba87704b15340880bd9b92add18`. PR: https://github.com/vega77bet/VR-OS/pull/29.

## Diagnóstico e mudanças

| Problema | Correção |
| --- | --- |
| Sessão de Ajustes não carregava tela inteira e três opções do Cinema; modo 0,5x não persistia | Carregamento completo, gravação usando as mesmas chaves dos componentes existentes, restauração do 0,5x no início quando há autorização |
| Preferências antigas/corrompidas podiam produzir números inválidos | Valores não finitos do visor e zoom usam padrões seguros; tema inválido usa Grafite |
| Tocar no texto de um stepper incrementava o valor | Incremento exige direção explícita; toque e pinça usam os botões +/- |
| Busca mantinha offset compartilhado anterior | Cada mudança de busca zera ambos os olhos e o offset da sessão |
| Pinça durante troca de página podia consultar a tabela anterior | Hit testing espera que o coordenador UIKit corresponda à página e à busca atuais |
| Cursor mudava quando Ajustes/tema ocultava os pixels da câmera | Mapeamento usa resolução do sensor, independente de existir CGImage de preview |
| ARKit e ultrawide usavam detectores ligeiramente diferentes | Ambos usam VRPinchDetector, com histerese, debounce, sensibilidade e rejeição de amostras inválidas |
| Arraste de slider para outra altura consultava outra linha | O trilho fica ligado à linha inicial; arraste no cabeçalho não rola a lista |
| Falha na configuração da saída 0,5x deixava entrada instalada | Remove a entrada antes de nova tentativa |
| Callback de início de câmera podia retomar captura depois de ir para segundo plano | Verificação da fase ativa nos callbacks de transição; intenção de início bloqueia resposta tardia de permissão ARKit |
| Copiar filmes grandes bloqueava a interface | Cópia em tarefa de segundo plano com acesso security-scoped durante a operação |
| Importação terminando após saída/segundo plano podia iniciar som | Identificador de importação invalida resultados antigos, incluindo transferência da Fototeca/iCloud |
| Vídeo incompatível podia parecer estar tocando | Observação de falha do AVPlayerItem mostra erro e restaura controles; reprodução não tenta reiniciar item que falhou |
| Novo filme podia herdar proporção do anterior | Proporção segura reiniciada antes dos metadados do novo arquivo |
| Transformação SBS combinava escala e translação por multiplicação | Componentes UV explícitos; testes verificam metades distintas e troca de olhos em SBS/OU |
| Desativar ocultação de controles não cancelava temporizador pendente | Mudança da preferência revela controles e atualiza/cancela o temporizador |
| Restauração geral deixava assento, convergência e fonte das notas anteriores | Restaura posicionamento do Cinema e fonte das notas, além das opções do Ajustes |

Tema, tela inteira e diversas opções do Cinema **já eram persistidos pelos componentes reais** na base auditada. O diagnóstico inicial de que todos esses valores eram perdidos foi amplo demais. Esta revisão corrige o carregamento da sessão, completa a preferência 0,5x e testa os dois lados do contrato, usando as chaves existentes.

## Validação automatizada

O workflow mantém os testes Swift de geometria do legado (launcher, 72 assentos, visor, projeção 3DoF, pinça e catálogo), compila Release para iPhone e executa XCTest no simulador.

O target VROSRegressionTests possui um aplicativo hospedeiro mínimo independente: fornece UIApplication, janelas e entrega de eventos UIKit sem iniciar a câmera, ARKit ou rede do app de produção. Os testes cobrem:

- Alteração e releitura de todos os controles do catálogo numa nova sessão com UserDefaults isolado.
- Confirmação em duas ativações e persistência da restauração.
- Preferências inválidas e limites de slider.
- Texto do stepper sem incremento acidental.
- Scroll originado no olho direito, espelhamento, busca e navegação.
- Eventos reais de UISwitch e UISlider registrados nas células.
- Duas tabelas SwiftUI/UIKit montadas, seguindo busca e navegação.
- Cancelamento de pinça com amostra inválida.
- Transformações SBS/OU, troca de olhos e modo 2D.
- Importação de MP4 H-SBS real e saída do Cinema.
- Importação tardia e transferência da Fototeca invalidadas ao sair.

O primeiro ciclo de testes teve falhas na entrega dos eventos UIKit por ausência de aplicativo hospedeiro. O teste foi mantido e o ambiente corrigido. O resultado final deve ser conferido na execução associada ao commit atual do PR; os artefatos incluem o resultado XCTest e a IPA quando todas as etapas passam.

O ambiente local desta revisão não contém Xcode/Swift. Compilação e XCTest são executados no macOS do GitHub Actions. Isso não equivale a teste no iPhone.

## Vídeo de teste próprio

`RegressionTests/Fixtures/VR-OS-demo-H-SBS.mp4`: MP4 H.264, 1280×720, 30 fps, oito segundos, sem áudio. É um padrão estático com disparidade pequena para testar divisão e profundidade, não um filme nem um teste de sincronização de movimento. Gerador reproduzível: `bash Tools/generate-stereo-demo.sh caminho.mp4` (requer ffmpeg).

No iPhone, salve em Arquivos, abra Cinema e escolha pelo seletor **Arquivos**. O nome identifica H-SBS automaticamente; também é possível selecionar H-SBS manualmente. O olho esquerdo deve mostrar somente a borda azul; o direito, somente a vermelha. Trocar olhos deve inverter as bordas. Use convergência zero para esta verificação.

## Validação física ainda necessária

| Área | Procedimento e aprovação |
| --- | --- |
| Óptica/estéreo | Usar iPhone no VR Box; ajustar perfil/IPD visual; confirmar conforto, alinhamento e ausência de metade errada usando o clipe |
| Vision | Testar cada mão separadamente, luz variada, pinças rápidas/lentas e perda da mão; verificar ausência de cliques repetidos |
| Dois olhos | Rolar devagar e com inércia em ambos; mudar busca/categoria; arrastar controles; verificar ausência de diferença visível |
| Câmera | Alternar ARKit↔0,5x repetidamente, bloquear/desbloquear e negar/reautorizar câmera; confirmar liberação do hardware e recuperação de falhas |
| Orientação | Conferir ambos os sentidos de paisagem; a captura/projeção usa convenção landscapeRight, portanto o alinhamento com rotação física precisa ser medido |
| Janelas/profundidade | Mover sem deslocamento involuntário; testar profundidade e recentralização. A estimativa monocular não fornece precisão de sensor de profundidade |
| Cinema | Fotos e Arquivos, vídeo longo, H-SBS/SBS/OU, sair durante cópia e download iCloud, pausa/fim/retorno do segundo plano; não deixar som após saída |
| Persistência | Alterar cada categoria, encerrar o processo e reabrir; comparar valores e efeito real; repetir depois de restaurar ajustes |
| Desempenho | Sessão de pelo menos 15–20 minutos; observar aquecimento, bateria, fluidez e memória |
| WebKit | Navegar, rolar e reproduzir em sites reais. Dois WebViews independentes não garantem sincronização de vídeo/DOM; DRM e eventos confiáveis dependem do provedor |

## Limites da conclusão

Não é possível afirmar “zero bugs”, conforto óptico ou rastreamento perfeito com testes de matemática e simulador. ARKit 6DoF permanece separado da captura física ultrawide, que utiliza Vision e CoreMotion 3DoF. O Cinema continua com um AVPlayer compartilhado e duas câmeras virtuais. Não houve merge na branch principal.
