# VR-OS V37–V43 — Organização e continuidade

Branch `vr-os-37-43-productivity`, baseada na V36 (`982fe360376527deebbc29f832f58ad0845a08d4`). Versão 6.0.0, build 43. Sem merge na principal.

O detalhamento antigo destas versões não estava disponível nesta sessão. Foi adotado e informado o escopo funcional abaixo, continuando Arquivos, Fotos, leitura e navegador da V36.

| Versão | Entrega |
| --- | --- |
| V37 | Busca por nome sem distinção de acentos/maiúsculas, filtro por tipo e ordenação por importação, nome ou tamanho |
| V38 | Favoritos persistentes, filtro de favoritos, renomeação do título da cópia local, tamanho visível e tratamento de lista vazia |
| V39 | Fotos com zoom 1–4x, rotação, deslocamento por toque/pinça, restaurar enquadramento e anterior/próxima na seleção filtrada |
| V40 | Paginação de texto calculada com CoreText para a área do visor; tamanho 10–16; retomada por posição UTF-16 e página de PDF após reiniciar |
| V41 | URLs das abas e aba ativa restauradas por app, seleção direta na Central, reabrir última aba fechada durante a sessão e reuso da janela do mesmo app |
| V42 | Diagnóstico local com estado de câmera, rastreamento, mão/pinça, bateria, temperatura e contagem/tamanho dos arquivos; exportação em texto |
| V43 | Exportação/importação JSON dos ajustes com esquema versionado, validação integral, confirmação e aplicação/persistência; regressões e revisão de ciclo de vida |

## Uso

Abra Arquivos ou Fotos na Central. As primeiras páginas contêm busca, ordenação e filtros; as seguintes têm Abrir, Favoritar, Renomear e Excluir cópia para cada item. Renomear muda somente o título apresentado, mantendo o arquivo interno e o original externo. Favoritos e leitura ficam no índice local. Filtros são temporários e reiniciam ao abrir Arquivos/Fotos.

O teclado de busca/renomeação aparece em um único diálogo nativo. A lista e a prévia são binoculares. Toque e Vision usam os mesmos retângulos dos botões da prévia. Com zoom acima de 1x, segure e arraste a imagem. A rotação/zoom são de visualização; não modificam o original. A galeria percorre as imagens presentes no filtro e ordenação ao abri-la.

Textos preservam quebras de linha e Unicode. A posição é salva ao trocar página ou tamanho, com limites de 1 MB por arquivo e 10.000 páginas por texto no visor. PDFs continuam limitados a 40 MB. O botão Início reinicia a leitura; Restaurar reinicia zoom/enquadramento ou tamanho de fonte. A paginação se adapta ao tamanho da abertura.

Na Central, cada janela web oferece seleção de abas. Reabrir recupera a última URL fechada enquanto a sessão existe. As URLs e aba ativa são salvas separadamente para cada app web. Reabrir um app já aberto restaura a janela existente. Isso não conserva DOM, formulários, scroll ou a pilha voltar/avançar de cada aba e não resolve DRM nem sincronização de vídeos entre WebViews.

Salvar ajustes exporta visor/lentes, gestos, janelas, aparência, ambiente e preferências de câmera/Cinema presentes em Ajustes. Não exporta mídia, abas, histórico, contas/cookies, posição das janelas, volume/luz do Cinema ou conteúdo remoto. Restaurar backup valida todos os campos antes da alteração e exige confirmação. Os ajustes são aplicados ao estado compartilhado e salvos pelos mesmos mecanismos de Ajustes. Modos de câmera continuam sujeitos à disponibilidade/permissão física.

Diagnóstico é uma fotografia do estado ao abrir/exportar, não um monitor de FPS nem uma certificação automática. O arquivo não contém conteúdo de mídia, nomes de arquivos, histórico ou contas. A coleta/exportação é local e não envia dados a terceiros.

## Revisão e testes

- Compatibilidade com índice da V36 sem novos campos.
- Busca/filtros combinados, ordenação, renomeação/favorito e reabertura; original preservado.
- Falha ao gravar metadados reverte alterações em memória.
- Texto com muitas quebras de linha e emoji: reconstrução integral de páginas e retomada após reiniciar; PDF com retomada de página.
- Galeria, clamp de zoom/deslocamento, rotação/reset e abertura/exclusão por registro canônico.
- Fechar durante decodificação não reabre a prévia.
- Restauração de abas, URL ativa, isolamento por app, dados inválidos, duplicatas e limite de oito.
- Backup completo, persistência e rejeição de versão/campos/limites inválidos sem mudança parcial.
- Geometria dos botões sem sobreposição ao conteúdo e renderização em duas dimensões de lente, com imagens anexadas ao xcresult.
- Suíte anterior de Ajustes, Cinema, gestos, lentes e biblioteca permanece no Actions.

Referências de APIs: [FileExporter](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)) e [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).

## Validação física pendente

Testar num iPhone com VR Box: visibilidade e conforto nas lentes, pinça para todos os controles e deslocamento, câmera 0,5x e retorno ARKit, permissão negada e segundo plano, som/Bluetooth/interrupções, fotos HEIC grandes, arquivos do iCloud e pouco espaço, PDFs protegidos/corrompidos, restauração do backup com câmera indisponível, e streaming com conta/DRM.

Compilação e testes de simulador não demonstram ausência total de bugs nem validam o hardware acima.
