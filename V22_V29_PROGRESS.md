# Pacote V22–V29 — implementação experimental
Base V21: 734ed1cc7cb74fa15e9c2c5d3e0ed3e33d7e653d.
Branch: vr-os-22-29-evolution. PR #30. Sem merge na principal.

| Etapa | Implementado | Refinamentos pendentes |
| --- | --- | --- |
| V22 | Dock com ícones compostos, gradiente, iluminação e contorno; Central paginada com ações reais | Ícones vetoriais exclusivos e barra superior renovada |
| V23 | Estado binocular de janelas; minimizar/restaurar sem destruir sessão; maximizar com saída sempre disponível; escala independente da profundidade; fechar | Arraste de redimensionamento pelos cantos e validação física |
| V24 | Cursor com estado visual de pinça, contraste e animação opcional | Hover por alvo e anel de progresso contextual |
| V25 | Diagnóstico de pontos da mão; acesso direto à sensibilidade; calibração por amostra da pinça fechada | Calibração guiada em múltiplos passos e avaliação com mãos reais |
| V26 | Texto maior nas células de Ajustes e redução de animações, ambos persistidos e restauráveis | Novas categorias completas de acessibilidade e desempenho |
| V27 | Chrome e ícones seguem cores dos quatro temas existentes | Renovação completa dos quatro cenários originais |
| V28 | Oceano, Floresta, Nebulosa e Cyberpunk procedurais com resposta à pose ARKit; seleção persistida | Texturas refinadas e teste de conforto 360° |
| V29 | Biblioteca persistente de filmes, miniaturas reais, favoritos, histórico e restauração do modo estéreo | Busca, filtros, gestão de espaço e retomada por tempo |

O pacote reúne primeiras implementações funcionais das oito áreas. Não significa que oito versões completas e sem bugs foram certificadas. A versão instalada continua identificada como build 22 experimental.

## Uso
O antigo botão Atualizações do Dock passa a se chamar Central. Atualizações continuam no primeiro painel; páginas seguintes oferecem mãos, acessibilidade, ambientes e ações por janela. Cada olho usa a mesma página e os mesmos alvos de pinça.

Minimizar mantém a sessão. A Central restaura janelas minimizadas. Maximizar preserva a âncora e oferece Restaurar no alto, por toque ou pinça. Escala de tamanho não altera profundidade. Redimensionamento é incremental pelos comandos Aumentar/Diminuir da Central.

Para calibrar a mão, mantenha uma pinça fechada sobre Calibrar na Central com boa luz. A amostra ajusta o limiar do detector; confira o resultado em Mãos e gestos. É uma estimativa por amostra, não uma medição física.

Ambientes procedurais usam a pose do ARKit. Selecionar um deles durante o passthrough 0,5x retorna ao ARKit. Escolher Tema original restaura o tema anterior. Os desenhos são cenários estilizados, não fotografias panorâmicas.

No Cinema, o botão de livros no alto abre a biblioteca binocular. Importe via Arquivos/Fotos. **Os vídeos passam a ser guardados em Documentos/VRMovieLibrary para persistir entre execuções**, em vez de somente no cache temporário. A biblioteca gera miniaturas, mantém favoritos e ordena por última abertura. O arquivo é copiado em segundo plano. O original não é alterado. A biblioteca ainda não possui interface de exclusão; considere o espaço disponível antes de importar filmes grandes.

## Validação
O Actions mantém os testes V21, compila iPhone Release e executa XCTest antes da IPA. WorkspaceTests cobre minimizar/foco/restauração/fechamento, limites de escala, alvos Vision em visores pequenos e persistência de biblioteca/favoritos/modo estéreo. Os testes de preferências percorrem também os novos controles.

Validar no iPhone/VR Box: legibilidade, pinça real, calibração, troca ARKit/0,5x, sincronização percebida, ambientes durante movimento, importação de arquivos grandes/iCloud, miniaturas, reabertura de favoritos, aquecimento e espaço livre. A compilação não comprova esses comportamentos.

## Limites
Dois WebViews podem divergir em sites dinâmicos/DRM. Ultrawide continua Vision + CoreMotion 3DoF; ARKit oferece o modo separado 6DoF. Estes recursos não alteram as limitações físicas da câmera ou do headset.
