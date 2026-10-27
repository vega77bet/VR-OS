# Pacote V22–V29

Base: V21, commit 734ed1cc7cb74fa15e9c2c5d3e0ed3e33d7e653d.
Branch: vr-os-22-29-evolution. Nenhuma versão deste pacote autoriza merge na principal.

## Estado da implementação

| Etapa | Implementado nesta entrega | Ainda necessário |
| --- | --- | --- |
| V22 — interface | Ícones compostos com gradiente, iluminação e contorno; Central VR paginada; acesso a Ajustes, câmera, centralização, temas, HUD e atualizações | Ícones vetoriais exclusivos, refinamento da barra superior e animações |
| V23 — janelas | Estado binocular compartilhado; minimizar/restaurar sem destruir sessão, foco para qualquer janela, tamanho independente da profundidade e fechamento | Redimensionamento pelos cantos e arraste físico; validar pinça em todos os modos |
| V24 — cursor | Mantém o cursor e detector da V21 | Estados de alvo, progresso e feedback novos |
| V25 — mãos | Mantém Vision, sensibilidade e debounce testados da V21 | Calibração guiada e diagnóstico de detecção |
| V26 — Ajustes | Central abre Ajustes reais; preferências existentes preservadas | Novas categorias e acessibilidade |
| V27 — temas | Central acessa os quatro temas existentes | Refinamento visual dos quatro ambientes |
| V28 — ambientes | Não implementado | Novos ambientes procedurais e seleção binocular |
| V29 — Cinema | Mantém importação e reprodução da V21 | Biblioteca persistente, capas, favoritos e histórico |

Esta branch é uma entrega incremental. Não representa oito versões concluídas.

## Interação

O antigo botão Atualizações do Dock passa a se chamar Central. As atualizações continuam acessíveis no primeiro painel da Central. As páginas seguintes têm ações por janela, incluindo restaurar janelas minimizadas.

A apresentação da janela é independente de sua âncora AR e de sua profundidade. Minimizar preserva a sessão web/nota. Fechar remove também os estados da Central. Maximizar não altera a âncora, permitindo retornar ao local anterior.

O mesmo VRWorkspaceGeometry calcula a posição de cada botão SwiftUI e o alvo Vision. A lista é paginada para evitar scroll divergente entre olhos. Ações pelo toque e pela pinça usam o mesmo dispatcher.

## Testes

WorkspaceTests verifica limites de tamanho, minimizar/focar/restaurar/fechar e correspondência entre botões e alvos Vision em duas dimensões de visor. O workflow mantém todos os testes da V21, compila para iPhone e executa XCTest no simulador antes de empacotar a IPA.

Teste físico pendente: tamanho/legibilidade dos novos ícones, acesso à Central com VR Box, recuperar janela minimizada, alternar foco sem perder câmera, ajustar tamanho sem alterar profundidade, ARKit/0,5x e pinça em cada cartão.
