# VR-OS V30–V36 — Cinema e mídia

Branch: vr-os-30-36-media-suite. Base: V22–V29, commit 7932e3851d00025087868160ec8701ce52bad60f. Versão nativa 5.0.0, build 36. Sem merge na principal.

| Área | Implementação |
| --- | --- |
| V30 | Painel binocular de formatos, troca de olhos, convergência e campo visual; convergência mantém a amostragem dentro da metade correta; modo, convergência e progresso por filme |
| V31 | Assentos anteriores/próximos, seleção existente por olhar/pinça e intensidade real das luzes da sala |
| V32 | Volume/mudo do filme, sessão de áudio para reprodução e som opcional de projetor com fonte espacial atrás do usuário |
| V33 | App Arquivos: importação por seletor do iOS, índice persistente, cópias locais, texto UTF-8 e PDF paginados, exclusão confirmada de cópias |
| V34 | App Fotos: importação pelo PhotosPicker, imagens locais e visualização binocular com decodificação reduzida |
| V35 | Abas por janela, limite de oito, histórico de URLs, limpeza de histórico, foco e favoritos existentes, recuperação após encerramento do processo WebKit |
| V36 | Atalhos reais para YouTube/Netflix/Twitch e navegação HTTPS, saída existente para Safari; preserva as limitações de DRM e do WebView |

## Como acessar

Arquivos e Fotos aparecem na Central de Apps e na Central VR. Os seletores do iOS aparecem uma única vez no display inteiro. Depois da importação, listas e pré-visualizações voltam a ser binoculares. Arquivos copia apenas o item escolhido; não acessa diretórios privados do iOS nem altera o original.

Arquivos aceita imagem, PDF, texto simples e vídeo. Limites: 40 MB para imagem/PDF e 1 MB para texto; vídeos são copiados por arquivo em segundo plano. O texto precisa estar em UTF-8. PDFs protegidos são recusados. Imagens são reduzidas para visualização, preservando a cópia original importada. A exclusão exige duas ativações e remove somente a cópia do app.

Vídeos de Arquivos podem abrir no Cinema quando o modo ARKit está ativo. O Cinema mantém sua própria cópia persistente. Excluir em Arquivos não exclui a cópia do Cinema, nem o original externo.

No Cinema, a barra superior tem Controles, Filmes, Menu, Assentos e Sair. Toque e pinça compartilham os retângulos reais dessa barra. Controles é paginado e oferece formatos, olhos, convergência, assentos, luz, volume, mudo, projetor e tamanho visual.

O progresso é salvo a cada cinco segundos, ao trocar filme e ao sair. Um filme terminado volta ao início. As preferências antigas da biblioteca continuam decodificáveis porque os novos campos são opcionais.

O projetor é um som sintetizado opcional, com fonte posicionada no fundo da sala e orientação acompanhando a cabeça. Não transforma a trilha do filme em Dolby Atmos ou multicanal. Interrupções de áudio pausam o Cinema; saída e segundo plano interrompem o ambiente.

Abas e histórico são controlados pela Central VR, nas ações de cada janela web. Trocar de aba recria as superfícies WebKit e reabre sua URL: a sessão de login compartilhada permanece, mas o DOM, a posição de scroll e o histórico voltar/avançar da aba não são conservados. O histórico persiste até cinquenta URLs; a Central oferece os seis mais recentes.

## Validação

O Actions compila iPhone Release e executa a suíte anterior mais testes de importação/reabertura/exclusão preservando o original, imagens, formato inválido, validação de nomes, parser HTTPS, abas/limites, convergência em ambas as metades, volume/luz e geometria da barra do Cinema.

## Exige teste físico

- Lente 0,5x, retorno ao ARKit, orientação e Vision com a mão real.
- Abrir/fechar Controles e Sair no VR Box por toque e pinça.
- Percepção 3D, convergência, campo visual, cadeiras e conforto.
- Som, mudo, fones/Bluetooth, interrupções, áudio espacial do projetor e segundo plano.
- Importação do iCloud, filmes grandes, falta de espaço, PDFs reais e arquivos corrompidos.
- Fototeca, memória/temperatura, troca de abas com vídeo e reprodução em cada serviço.

Os sites podem exigir conta/assinatura e podem bloquear reprodução incorporada. Dois WebViews independentes não garantem sincronização de vídeo ou DOM. A alternativa Safari é externa ao ambiente binocular. A suíte automatizada não certifica ausência de bugs nem substitui essas verificações.
